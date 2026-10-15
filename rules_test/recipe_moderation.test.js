// Rapportering, blokering og skjulning af delte opskrifter (#52).
//
// Testdata: Familien A (alice = ejer, bob = medlem), Eves hus (eve) og carol
// uden husstand. Alice har delt 'pub'; eve og carol er andre brugere, der
// rapporterer og blokerer. 'hid' er en opskrift en moderator har fjernet.
const { test, before, beforeEach, after, describe } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs, query, where,
  orderBy, deleteField, serverTimestamp,
} = require('firebase/firestore');

let env;
const db = (uid) => env.authenticatedContext(uid, { email: `${uid}@example.com` }).firestore();

// Det ModerationService sender.
const report = (extra = {}) => ({
  recipeId: 'pub', reportedBy: 'eve', reason: 'spam', comment: '',
  createdAt: serverTimestamp(), ...extra,
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-skafferiet-recipe-moderation',
    firestore: { rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') },
  });
});
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const s = ctx.firestore();
    await setDoc(doc(s, 'households/HH_A'), { name: 'A', members: ['alice', 'bob'], admin: 'alice' });
    await setDoc(doc(s, 'households/HH_E'), { name: 'E', members: ['eve'], admin: 'eve' });
    await setDoc(doc(s, 'users/alice'), { householdId: 'HH_A' });
    await setDoc(doc(s, 'users/bob'), { householdId: 'HH_A' });
    await setDoc(doc(s, 'users/eve'), { householdId: 'HH_E' });
    await setDoc(doc(s, 'users/carol'), {});
    await setDoc(doc(s, 'recipes/pub'), {
      title: 'Lasagne', titleLower: 'lasagne', householdId: 'HH_A', createdBy: 'alice',
      visibility: 'public', authorName: 'Alice', createdAt: new Date('2026-01-02'),
    });
    await setDoc(doc(s, 'recipes/pub2'), {
      title: 'Suppe', titleLower: 'suppe', householdId: 'HH_A', createdBy: 'alice',
      visibility: 'public', authorName: 'Alice', createdAt: new Date('2026-01-03'),
    });
    await setDoc(doc(s, 'recipes/priv'), {
      title: 'Hemmelig', titleLower: 'hemmelig', householdId: 'HH_A', createdBy: 'alice',
      visibility: 'household', createdAt: new Date('2026-01-01'),
    });
    await setDoc(doc(s, 'recipes/hid'), {
      title: 'Fjernet', titleLower: 'fjernet', householdId: 'HH_A', createdBy: 'alice',
      visibility: 'hidden', authorName: 'Alice', createdAt: new Date('2026-01-04'),
    });
    await setDoc(doc(s, 'recipes/evePub'), {
      title: 'Eves suppe', titleLower: 'eves suppe', householdId: 'HH_E', createdBy: 'eve',
      visibility: 'public', authorName: 'Eve', createdAt: new Date('2026-01-05'),
    });
  });
});

async function seedReport(id = 'pub_eve', data = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `reports/${id}`), {
      recipeId: 'pub', reportedBy: 'eve', reason: 'spam', comment: 'x',
      createdAt: new Date('2026-02-01'), ...data,
    });
  });
}

describe('rapporter: oprette og overskrive', () => {
  test('en bruger fra en anden husstand kan rapportere en delt opskrift', async () => {
    await assertSucceeds(setDoc(doc(db('eve'), 'reports/pub_eve'), report()));
  });
  test('en bruger uden husstand kan rapportere', async () => {
    await assertSucceeds(setDoc(doc(db('carol'), 'reports/pub_carol'), report({ reportedBy: 'carol' })));
  });
  test('alle fem årsager og en kommentar på 500 tegn er tilladt', async () => {
    for (const reason of ['offensive', 'spam', 'wrong_info', 'copyright', 'other']) {
      await assertSucceeds(setDoc(doc(db('eve'), 'reports/pub_eve'),
        report({ reason, comment: 'x'.repeat(500) })));
    }
  });
  test('en ny rapport overskriver den gamle (samme dokument)', async () => {
    await seedReport();
    await assertSucceeds(setDoc(doc(db('eve'), 'reports/pub_eve'),
      report({ reason: 'copyright', comment: 'Ny' })));
    await env.withSecurityRulesDisabled(async (ctx) => {
      const d = (await getDoc(doc(ctx.firestore(), 'reports/pub_eve'))).data();
      if (d.reason !== 'copyright' || d.comment !== 'Ny') throw new Error('Ikke overskrevet');
    });
  });
  test('dokument-id skal være recipeId_uid', async () => {
    await assertFails(setDoc(doc(db('eve'), 'reports/anything'), report()));
    await assertFails(setDoc(doc(db('eve'), 'reports/pub'), report()));
    await assertFails(setDoc(doc(db('eve'), 'reports/pub_carol'), report()));
  });
  test('reportedBy skal være en selv', async () => {
    await assertFails(setDoc(doc(db('eve'), 'reports/pub_eve'), report({ reportedBy: 'carol' })));
  });
  test('man kan ikke rapportere i en andens navn', async () => {
    await assertFails(setDoc(doc(db('eve'), 'reports/pub_carol'), report({ reportedBy: 'carol' })));
  });
  test('recipeId i dokumentet skal passe til id\'et', async () => {
    await assertFails(setDoc(doc(db('eve'), 'reports/pub_eve'), report({ recipeId: 'pub2' })));
  });
  test('ugyldig årsag afvises', async () => {
    await assertFails(setDoc(doc(db('eve'), 'reports/pub_eve'), report({ reason: 'hate' })));
    await assertFails(setDoc(doc(db('eve'), 'reports/pub_eve'), report({ reason: '' })));
    await assertFails(setDoc(doc(db('eve'), 'reports/pub_eve'), report({ reason: 3 })));
    await assertFails(setDoc(doc(db('eve'), 'reports/pub_eve'), report({ reason: 'Spam' })));
  });
  test('kommentar på 501 tegn eller ikke-tekst afvises', async () => {
    await assertFails(setDoc(doc(db('eve'), 'reports/pub_eve'), report({ comment: 'x'.repeat(501) })));
    await assertFails(setDoc(doc(db('eve'), 'reports/pub_eve'), report({ comment: 5 })));
    await assertFails(setDoc(doc(db('eve'), 'reports/pub_eve'), report({ comment: null })));
  });
  test('ekstra felter og manglende felter afvises', async () => {
    await assertFails(setDoc(doc(db('eve'), 'reports/pub_eve'), report({ status: 'open' })));
    const { comment, ...noComment } = report();
    await assertFails(setDoc(doc(db('eve'), 'reports/pub_eve'), noComment));
    const { reason, ...noReason } = report();
    await assertFails(setDoc(doc(db('eve'), 'reports/pub_eve'), noReason));
  });
  test('createdAt skal være serverens tid', async () => {
    await assertFails(setDoc(doc(db('eve'), 'reports/pub_eve'), report({ createdAt: new Date('2020-01-01') })));
    await assertFails(setDoc(doc(db('eve'), 'reports/pub_eve'), report({ createdAt: 'nu' })));
  });
  test('man kan ikke overskrive med ændret createdAt (opdatering)', async () => {
    await seedReport();
    await assertFails(setDoc(doc(db('eve'), 'reports/pub_eve'), report({ createdAt: new Date('2020-01-01') })));
  });
  test('man kan ikke rapportere sin egen husstands opskrift', async () => {
    await assertFails(setDoc(doc(db('bob'), 'reports/pub_bob'), report({ reportedBy: 'bob' })));
    await assertFails(setDoc(doc(db('alice'), 'reports/pub_alice'), report({ reportedBy: 'alice' })));
    await assertFails(setDoc(doc(db('eve'), 'reports/evePub_eve'), report({ recipeId: 'evePub' })));
  });
  test('man kan ikke rapportere en privat, fjernet eller ikke-eksisterende opskrift', async () => {
    await assertFails(setDoc(doc(db('eve'), 'reports/priv_eve'), report({ recipeId: 'priv' })));
    await assertFails(setDoc(doc(db('eve'), 'reports/hid_eve'), report({ recipeId: 'hid' })));
    await assertFails(setDoc(doc(db('eve'), 'reports/nope_eve'), report({ recipeId: 'nope' })));
  });
  test('uden login kan man ikke rapportere', async () => {
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(setDoc(doc(anon, 'reports/pub_eve'), report()));
  });
});

describe('rapporter: læsning og sletning', () => {
  beforeEach(async () => { await seedReport(); });

  test('man kan læse sin egen rapport', async () => {
    await assertSucceeds(getDoc(doc(db('eve'), 'reports/pub_eve')));
  });
  test('man kan liste sine egne rapporter (reportedBy == uid)', async () => {
    const snap = await assertSucceeds(getDocs(query(collection(db('eve'), 'reports'),
      where('reportedBy', '==', 'eve'))));
    if (snap.size !== 1) throw new Error('Forventede 1 rapport');
  });
  test('andre kan IKKE læse min rapport - hverken forfatteren, medlemmer eller fremmede', async () => {
    await assertFails(getDoc(doc(db('alice'), 'reports/pub_eve')));
    await assertFails(getDoc(doc(db('bob'), 'reports/pub_eve')));
    await assertFails(getDoc(doc(db('carol'), 'reports/pub_eve')));
  });
  test('andre kan IKKE liste rapporter', async () => {
    await assertFails(getDocs(collection(db('alice'), 'reports')));
    await assertFails(getDocs(collection(db('eve'), 'reports')));
    await assertFails(getDocs(query(collection(db('alice'), 'reports'), where('reportedBy', '==', 'eve'))));
    await assertFails(getDocs(query(collection(db('alice'), 'reports'), where('recipeId', '==', 'pub'))));
  });
  test('andre kan IKKE opdatere eller slette min rapport', async () => {
    await assertFails(updateDoc(doc(db('carol'), 'reports/pub_eve'), { reason: 'other' }));
    await assertFails(setDoc(doc(db('carol'), 'reports/pub_eve'), report()));
    await assertFails(deleteDoc(doc(db('carol'), 'reports/pub_eve')));
    await assertFails(deleteDoc(doc(db('alice'), 'reports/pub_eve')));
  });
  test('man kan slette sin egen rapport (kontosletning)', async () => {
    await assertSucceeds(deleteDoc(doc(db('eve'), 'reports/pub_eve')));
  });
  test('opdatering af en eksisterende rapport kan ikke ændre ejer eller opskrift', async () => {
    await assertFails(updateDoc(doc(db('eve'), 'reports/pub_eve'), { reportedBy: 'carol' }));
    await assertFails(updateDoc(doc(db('eve'), 'reports/pub_eve'), { recipeId: 'pub2' }));
  });
  test('slet konto: egne rapporter kan slås op og slettes med reportedBy == uid', async () => {
    await seedReport('pub2_eve', { recipeId: 'pub2' });
    await seedReport('pub_carol', { reportedBy: 'carol' });
    const s = db('eve');
    const snap = await assertSucceeds(getDocs(query(collection(s, 'reports'), where('reportedBy', '==', 'eve'))));
    for (const d of snap.docs) await assertSucceeds(deleteDoc(d.ref));
    await env.withSecurityRulesDisabled(async (ctx) => {
      const left = await getDocs(collection(ctx.firestore(), 'reports'));
      if (left.size !== 1 || left.docs[0].id !== 'pub_carol') throw new Error('Forkerte rapporter tilbage');
    });
  });
});

describe('blokerede forfattere: kun ejeren', () => {
  const block = (extra = {}) => ({ name: 'Alice', blockedAt: serverTimestamp(), ...extra });

  test('ejeren kan blokere, læse, liste og fjerne blokeringen', async () => {
    const s = db('eve');
    await assertSucceeds(setDoc(doc(s, 'users/eve/blocked_authors/alice'), block()));
    await assertSucceeds(getDoc(doc(s, 'users/eve/blocked_authors/alice')));
    const snap = await assertSucceeds(getDocs(collection(s, 'users/eve/blocked_authors')));
    if (snap.size !== 1) throw new Error('Forventede 1 blokering');
    await assertSucceeds(deleteDoc(doc(s, 'users/eve/blocked_authors/alice')));
  });
  test('ingen andre kan læse, liste, skrive eller slette - heller ikke husstandsmedlemmer', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/alice/blocked_authors/eve'),
        { name: 'Eve', blockedAt: new Date('2026-02-01') });
    });
    // bob bor i samme husstand som alice og må læse alices profil - men ikke blokeringerne.
    await assertSucceeds(getDoc(doc(db('bob'), 'users/alice')));
    await assertFails(getDoc(doc(db('bob'), 'users/alice/blocked_authors/eve')));
    await assertFails(getDocs(collection(db('bob'), 'users/alice/blocked_authors')));
    await assertFails(setDoc(doc(db('bob'), 'users/alice/blocked_authors/carol'), block()));
    await assertFails(deleteDoc(doc(db('bob'), 'users/alice/blocked_authors/eve')));
    await assertFails(getDocs(collection(db('eve'), 'users/alice/blocked_authors')));
    await assertFails(setDoc(doc(db('eve'), 'users/alice/blocked_authors/carol'), block()));
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDocs(collection(anon, 'users/alice/blocked_authors')));
  });
  test('felter valideres: kun name og blockedAt', async () => {
    const s = db('eve');
    await assertFails(setDoc(doc(s, 'users/eve/blocked_authors/alice'), block({ extra: 1 })));
    await assertFails(setDoc(doc(s, 'users/eve/blocked_authors/alice'), { name: 'Alice' }));
    await assertFails(setDoc(doc(s, 'users/eve/blocked_authors/alice'), { blockedAt: serverTimestamp() }));
  });
  test('name er tekst på 1-40 tegn', async () => {
    const s = db('eve');
    await assertSucceeds(setDoc(doc(s, 'users/eve/blocked_authors/alice'), block({ name: 'x'.repeat(40) })));
    await assertFails(setDoc(doc(s, 'users/eve/blocked_authors/alice'), block({ name: 'x'.repeat(41) })));
    await assertFails(setDoc(doc(s, 'users/eve/blocked_authors/alice'), block({ name: '' })));
    await assertFails(setDoc(doc(s, 'users/eve/blocked_authors/alice'), block({ name: 7 })));
  });
  test('blockedAt skal være serverens tid', async () => {
    const s = db('eve');
    await assertFails(setDoc(doc(s, 'users/eve/blocked_authors/alice'), block({ blockedAt: new Date('2020-01-01') })));
    await assertFails(setDoc(doc(s, 'users/eve/blocked_authors/alice'), block({ blockedAt: 'nu' })));
  });
  test('man kan ikke blokere sig selv', async () => {
    await assertFails(setDoc(doc(db('eve'), 'users/eve/blocked_authors/eve'), block()));
  });
  test('slet konto: hele samlingen kan listes og slettes af ejeren', async () => {
    const s = db('eve');
    await assertSucceeds(setDoc(doc(s, 'users/eve/blocked_authors/alice'), block()));
    await assertSucceeds(setDoc(doc(s, 'users/eve/blocked_authors/carol'), block({ name: 'Carol' })));
    const snap = await assertSucceeds(getDocs(collection(s, 'users/eve/blocked_authors')));
    for (const d of snap.docs) await assertSucceeds(deleteDoc(d.ref));
    const after = await getDocs(collection(s, 'users/eve/blocked_authors'));
    if (!after.empty) throw new Error('Blokeringer blev ikke slettet');
  });
  test('profilens øvrige regler er uændrede (blocked_authors er ikke et profilfelt)', async () => {
    await assertFails(updateDoc(doc(db('eve'), 'users/eve'), { blockedUsers: ['alice'] }));
  });
});

describe('fjernede opskrifter (visibility: hidden)', () => {
  test('klienter kan ikke oprette en opskrift som hidden', async () => {
    await assertFails(setDoc(doc(db('alice'), 'recipes/new'), {
      title: 'X', visibility: 'hidden', householdId: 'HH_A', createdBy: 'alice',
      createdAt: serverTimestamp(),
    }));
  });
  test('klienter kan ikke sætte hidden på en eksisterende opskrift - heller ikke skaberen', async () => {
    await assertFails(updateDoc(doc(db('alice'), 'recipes/pub'), { visibility: 'hidden', authorName: deleteField() }));
    await assertFails(updateDoc(doc(db('alice'), 'recipes/pub'), { visibility: 'hidden' }));
    await assertFails(updateDoc(doc(db('alice'), 'recipes/priv'), { visibility: 'hidden' }));
    await assertFails(updateDoc(doc(db('bob'), 'recipes/pub'), { visibility: 'hidden' }));
  });
  test('husstanden kan ikke ændre hidden til noget andet', async () => {
    await assertFails(updateDoc(doc(db('bob'), 'recipes/hid'), { visibility: 'household', authorName: deleteField() }));
    await assertFails(updateDoc(doc(db('bob'), 'recipes/hid'), { visibility: 'household' }));
    await assertFails(updateDoc(doc(db('bob'), 'recipes/hid'), { visibility: 'public' }));
  });
  test('skaberen kan ikke dele en fjernet opskrift igen', async () => {
    await assertFails(updateDoc(doc(db('alice'), 'recipes/hid'), { visibility: 'public' }));
    await assertFails(updateDoc(doc(db('alice'), 'recipes/hid'), { visibility: 'household', authorName: deleteField() }));
  });
  test('en skaber, der har forladt husstanden, kan ikke bruge "stop deling" til at ændre hidden', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'households/HH_A'), { name: 'A', members: ['bob'], admin: 'bob' });
    });
    await assertFails(updateDoc(doc(db('alice'), 'recipes/hid'),
      { visibility: 'household', authorName: deleteField() }));
    // ... mens "stop deling" af en almindeligt delt opskrift stadig virker.
    await assertSucceeds(updateDoc(doc(db('alice'), 'recipes/pub'),
      { visibility: 'household', authorName: deleteField() }));
  });
  test('husstanden kan stadig læse og redigere indholdet af en fjernet opskrift', async () => {
    await assertSucceeds(getDoc(doc(db('bob'), 'recipes/hid')));
    await assertSucceeds(getDoc(doc(db('alice'), 'recipes/hid')));
    await assertSucceeds(updateDoc(doc(db('bob'), 'recipes/hid'), { title: 'Ny titel', titleLower: 'ny titel' }));
    // visibility sendt uændret (som appen gør) er ikke en ændring.
    await assertSucceeds(updateDoc(doc(db('bob'), 'recipes/hid'),
      { visibility: 'hidden', authorName: deleteField(), calories: 5 }));
  });
  test('andre kan ikke læse en fjernet opskrift - hverken andre husstande eller brugere uden husstand', async () => {
    await assertFails(getDoc(doc(db('eve'), 'recipes/hid')));
    await assertFails(getDoc(doc(db('carol'), 'recipes/hid')));
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, 'recipes/hid')));
  });
  test('andre kan ikke redigere eller slette en fjernet opskrift', async () => {
    await assertFails(updateDoc(doc(db('eve'), 'recipes/hid'), { title: 'X' }));
    await assertFails(deleteDoc(doc(db('eve'), 'recipes/hid')));
  });
  test('Fællesskab-forespørgslen er stadig tilladt og indeholder ikke fjernede opskrifter', async () => {
    const snap = await assertSucceeds(getDocs(query(collection(db('eve'), 'recipes'),
      where('visibility', '==', 'public'), orderBy('createdAt', 'desc'))));
    const ids = snap.docs.map((d) => d.id);
    if (ids.includes('hid')) throw new Error('Fjernet opskrift i Fællesskab');
    if (!ids.includes('pub') || !ids.includes('pub2')) throw new Error('Delte opskrifter mangler');
  });
  test('titel-søgningen i Fællesskab er stadig tilladt', async () => {
    await assertSucceeds(getDocs(query(collection(db('eve'), 'recipes'),
      where('visibility', '==', 'public'), orderBy('titleLower'))));
  });
  test('husstandens egen liste (householdId == X) kan stadig hentes med en fjernet opskrift', async () => {
    const snap = await assertSucceeds(getDocs(query(collection(db('bob'), 'recipes'),
      where('householdId', '==', 'HH_A'))));
    if (!snap.docs.some((d) => d.id === 'hid')) throw new Error('Fjernet opskrift mangler hos husstanden');
  });
  test('en anden husstand kan ikke hente en fjernet opskrift via husstandsforespørgslen', async () => {
    await assertFails(getDocs(query(collection(db('eve'), 'recipes'),
      where('householdId', '==', 'HH_A'))));
  });
});
