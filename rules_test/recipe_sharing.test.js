// Deling af opskrifter (#51): visibility 'household' | 'public', forfatterens
// fornavn (authorName) og kopier (copiedFrom) mod det appen faktisk sender.
//
// Testdata: Familien A (alice = ejer, bob = medlem), Eves hus (eve) og carol
// uden husstand. Eve spiller en anden husstand, der kan se men ikke ændre.
const { test, before, beforeEach, after, describe } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, updateDoc, deleteDoc, addDoc, collection, getDocs, query,
  where, orderBy, limit, startAfter, startAt, endAt, deleteField, serverTimestamp,
} = require('firebase/firestore');

let env;
const db = (uid) => env.authenticatedContext(uid, { email: `${uid}@example.com` }).firestore();
const anon = () => env.unauthenticatedContext().firestore();

// Det RecipesNotifier sender (recipeToFields + createdAt/householdId/createdBy).
const fields = (extra = {}) => ({
  title: 'Suppe', titleLower: 'suppe', imageUrl: null, calories: 0, time: '',
  category: 'RecipeCategory.aftensmad', ingredients: [], instructions: [],
  servings: null, protein: null, carbs: null, fat: null,
  nutritionFromIngredients: false, visibility: 'household', ...extra,
});
const created = (extra = {}) => ({
  ...fields(extra), createdAt: serverTimestamp(), householdId: 'HH_A', createdBy: 'alice',
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-skafferiet-recipe-sharing',
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
    await setDoc(doc(s, 'recipes/priv'), {
      title: 'Hemmelig', titleLower: 'hemmelig', householdId: 'HH_A', createdBy: 'alice',
      visibility: 'household', createdAt: new Date('2026-01-01'),
    });
    await setDoc(doc(s, 'recipes/legacy'), { title: 'Gammel', householdId: 'HH_A', createdBy: 'alice' });
    await setDoc(doc(s, 'recipes/legacyWeird'), {
      title: 'Mærkelig', householdId: 'HH_A', createdBy: 'alice', visibility: 'weird',
    });
    await setDoc(doc(s, 'recipes/evePub'), {
      title: 'Eves suppe', titleLower: 'eves suppe', householdId: 'HH_E', createdBy: 'eve',
      visibility: 'public', authorName: 'Eve', createdAt: new Date('2026-01-03'),
    });
  });
});

describe('deling af opskrifter: læsning', () => {
  test('en anden husstand kan læse en offentlig opskrift', async () => {
    await assertSucceeds(getDoc(doc(db('eve'), 'recipes/pub')));
  });
  test('en bruger uden husstand kan læse en offentlig opskrift', async () => {
    await assertSucceeds(getDoc(doc(db('carol'), 'recipes/pub')));
  });
  test('en anden husstand kan IKKE læse en husstands-opskrift', async () => {
    await assertFails(getDoc(doc(db('eve'), 'recipes/priv')));
  });
  test('en anden husstand kan IKKE læse en opskrift uden visibility', async () => {
    await assertFails(getDoc(doc(db('eve'), 'recipes/legacy')));
  });
  test('en ukendt visibility giver ingen læseadgang udefra', async () => {
    await assertFails(getDoc(doc(db('eve'), 'recipes/legacyWeird')));
  });
  test('ikke-loggede brugere kan ikke læse en offentlig opskrift', async () => {
    await assertFails(getDoc(doc(anon(), 'recipes/pub')));
  });
  test('husstanden læser stadig sine egne private opskrifter', async () => {
    await assertSucceeds(getDoc(doc(db('bob'), 'recipes/priv')));
  });
});

// OBS: Emulatoren kan ikke bevise, at ET HELT UFILTRERET list-kald afvises
// (read-reglen har den ældre gren `!('householdId' in resource.data)`, som
// emulatoren vurderer mod forespørgslens filtre). Testene her viser derfor
// kun, at Fællesskab-forespørgslerne er TILLADT, og at forespørgsler, der
// peger på en fremmed husstand via householdId, afvises. De beviser IKKE, at
// andre ufiltrerede forespørgsler er sikre (opfølgende sag).
describe('deling af opskrifter: Fællesskab-forespørgsler', () => {
  test('liste: visibility == public + orderBy createdAt + limit', async () => {
    const snap = await assertSucceeds(getDocs(query(collection(db('eve'), 'recipes'),
      where('visibility', '==', 'public'), orderBy('createdAt', 'desc'), limit(20))));
    if (snap.size !== 2) throw new Error(`Forventede 2 offentlige, fik ${snap.size}`);
  });
  test('næste side med startAfter', async () => {
    const first = await getDocs(query(collection(db('eve'), 'recipes'),
      where('visibility', '==', 'public'), orderBy('createdAt', 'desc'), limit(1)));
    await assertSucceeds(getDocs(query(collection(db('eve'), 'recipes'),
      where('visibility', '==', 'public'), orderBy('createdAt', 'desc'),
      startAfter(first.docs[0]), limit(1))));
  });
  test('søgning: titleLower-præfiks', async () => {
    const snap = await assertSucceeds(getDocs(query(collection(db('eve'), 'recipes'),
      where('visibility', '==', 'public'), orderBy('titleLower'),
      startAt('las'), endAt('las'), limit(20))));
    if (snap.size !== 1) throw new Error(`Forventede 1 træffer, fik ${snap.size}`);
  });
  // Bemærk: emulatoren afviser ikke helt ufiltrerede forespørgsler (den vurderer
  // 'householdId' in resource.data mod forespørgslens filtre), så her testes de
  // forespørgsler, der faktisk peger på en fremmed husstands data.
  test('uden visibility-filteret afvises forespørgsler på en fremmed husstands opskrifter', async () => {
    await assertFails(getDocs(query(collection(db('eve'), 'recipes'),
      where('householdId', '==', 'HH_A'), orderBy('createdAt', 'desc'), limit(20))));
  });
  test('offentlige opskrifter fra en bestemt husstand kan hentes med visibility-filteret', async () => {
    const snap = await assertSucceeds(getDocs(query(collection(db('eve'), 'recipes'),
      where('visibility', '==', 'public'), where('householdId', '==', 'HH_A'))));
    if (snap.size !== 1) throw new Error(`Forventede 1, fik ${snap.size}`);
  });
  test('"Vores"-forespørgslen (egen husstand eller global) virker stadig', async () => {
    const { or } = require('firebase/firestore');
    await assertSucceeds(getDocs(query(collection(db('eve'), 'recipes'),
      or(where('householdId', '==', 'HH_E'), where('householdId', '==', null)))));
  });
  test('ikke-loggede kan ikke liste offentlige opskrifter', async () => {
    await assertFails(getDocs(query(collection(anon(), 'recipes'),
      where('visibility', '==', 'public'), limit(20))));
  });
});

describe('deling af opskrifter: oprettelse', () => {
  test('husstands-opskrift og offentlig opskrift med fornavn', async () => {
    await assertSucceeds(addDoc(collection(db('alice'), 'recipes'), created()));
    await assertSucceeds(addDoc(collection(db('alice'), 'recipes'),
      created({ visibility: 'public', authorName: 'Alice' })));
  });
  test('uden visibility (ældre klient) accepteres stadig', async () => {
    const { visibility, ...rest } = created();
    await assertSucceeds(addDoc(collection(db('alice'), 'recipes'), rest));
  });
  test('ugyldig visibility afvises', async () => {
    await assertFails(addDoc(collection(db('alice'), 'recipes'), created({ visibility: 'secret' })));
    await assertFails(addDoc(collection(db('alice'), 'recipes'), created({ visibility: 'Public' })));
    await assertFails(addDoc(collection(db('alice'), 'recipes'), created({ visibility: true })));
    await assertFails(addDoc(collection(db('alice'), 'recipes'), created({ visibility: null })));
  });
  test('authorName: 1-40 tegn, tekst', async () => {
    await assertSucceeds(addDoc(collection(db('alice'), 'recipes'),
      created({ visibility: 'public', authorName: 'x'.repeat(40) })));
    await assertFails(addDoc(collection(db('alice'), 'recipes'),
      created({ visibility: 'public', authorName: 'x'.repeat(41) })));
    await assertFails(addDoc(collection(db('alice'), 'recipes'),
      created({ visibility: 'public', authorName: '' })));
    await assertFails(addDoc(collection(db('alice'), 'recipes'),
      created({ visibility: 'public', authorName: 42 })));
  });
  test('copiedFrom: tekst på højst 128 tegn', async () => {
    await assertSucceeds(addDoc(collection(db('alice'), 'recipes'), created({ copiedFrom: 'x'.repeat(128) })));
    await assertFails(addDoc(collection(db('alice'), 'recipes'), created({ copiedFrom: 'x'.repeat(129) })));
    await assertFails(addDoc(collection(db('alice'), 'recipes'), created({ copiedFrom: 7 })));
  });
  test('en kopi i egen husstand af en andens opskrift kan oprettes', async () => {
    await assertSucceeds(addDoc(collection(db('eve'), 'recipes'), {
      ...fields({ copiedFrom: 'pub' }), createdAt: serverTimestamp(), householdId: 'HH_E', createdBy: 'eve',
    }));
  });
  test('man kan ikke oprette en offentlig opskrift i en andens husstand', async () => {
    await assertFails(addDoc(collection(db('eve'), 'recipes'),
      { ...created({ visibility: 'public', authorName: 'Eve' }) }));
  });
  test('dedupe-forespørgslen (egen husstand + copiedFrom) er tilladt', async () => {
    await assertSucceeds(getDocs(query(collection(db('eve'), 'recipes'),
      where('householdId', '==', 'HH_E'), where('copiedFrom', '==', 'pub'), limit(1))));
  });
});

describe('deling af opskrifter: ændring', () => {
  test('skaberen kan dele, og et andet medlem kan holde op med at dele (som appen sender det)', async () => {
    await assertSucceeds(updateDoc(doc(db('alice'), 'recipes/priv'), fields({
      title: 'Hemmelig', titleLower: 'hemmelig', visibility: 'public', authorName: 'Alice',
    })));
    await assertSucceeds(updateDoc(doc(db('bob'), 'recipes/priv'), fields({
      title: 'Hemmelig', titleLower: 'hemmelig', visibility: 'household', authorName: deleteField(),
    })));
  });
  test('ugyldig visibility eller authorName ved ændring afvises', async () => {
    await assertFails(updateDoc(doc(db('alice'), 'recipes/priv'), { visibility: 'secret' }));
    await assertFails(updateDoc(doc(db('alice'), 'recipes/priv'), { authorName: '' }));
    await assertFails(updateDoc(doc(db('alice'), 'recipes/priv'), { authorName: 'x'.repeat(41) }));
    await assertFails(updateDoc(doc(db('alice'), 'recipes/priv'), { copiedFrom: 'x'.repeat(129) }));
  });
  test('en ældre opskrift med ukendt visibility kan stadig rettes uden at røre feltet', async () => {
    await assertSucceeds(updateDoc(doc(db('alice'), 'recipes/legacyWeird'), { title: 'Ny' }));
    await assertFails(updateDoc(doc(db('alice'), 'recipes/legacyWeird'), { visibility: 'weird2' }));
    await assertSucceeds(updateDoc(doc(db('alice'), 'recipes/legacyWeird'), { visibility: 'household' }));
  });
  test('en opskrift uden visibility kan få feltet sat med appens fulde opdatering', async () => {
    await assertSucceeds(updateDoc(doc(db('alice'), 'recipes/legacy'), fields({ title: 'Gammel', titleLower: 'gammel' })));
  });
  test('anden husstand kan IKKE ændre en offentlig opskrift', async () => {
    await assertFails(updateDoc(doc(db('eve'), 'recipes/pub'), { title: 'Hacket' }));
  });
  test('anden husstand kan IKKE vende visibility eller flytte opskriften', async () => {
    await assertFails(updateDoc(doc(db('eve'), 'recipes/pub'), { visibility: 'household' }));
    await assertFails(updateDoc(doc(db('eve'), 'recipes/priv'), { visibility: 'public' }));
    await assertFails(updateDoc(doc(db('eve'), 'recipes/pub'), { householdId: 'HH_E' }));
    await assertFails(updateDoc(doc(db('eve'), 'recipes/pub'), { authorName: 'Eve' }));
  });
  test('anden husstand kan IKKE ændre søgenøgle, kopi-henvisning eller indhold', async () => {
    for (const [k, v] of [['copiedFrom', 'y'], ['titleLower', 'zzz'], ['ingredients', []], ['createdAt', new Date()]]) {
      await assertFails(updateDoc(doc(db('eve'), 'recipes/pub'), { [k]: v }));
    }
  });
  test('ejerskab kan stadig ikke ændres', async () => {
    await assertFails(updateDoc(doc(db('alice'), 'recipes/pub'), { createdBy: 'bob' }));
    await assertFails(updateDoc(doc(db('alice'), 'recipes/pub'), { householdId: 'HH_E' }));
  });
});

describe('deling af opskrifter: sletning', () => {
  test('anden husstand kan IKKE slette en offentlig opskrift', async () => {
    await assertFails(deleteDoc(doc(db('eve'), 'recipes/pub')));
  });
  test('en bruger uden husstand kan IKKE slette en offentlig opskrift', async () => {
    await assertFails(deleteDoc(doc(db('carol'), 'recipes/pub')));
  });
  test('ikke-loggede kan ikke slette', async () => {
    await assertFails(deleteDoc(doc(anon(), 'recipes/pub')));
  });
  test('skaberen kan slette sin offentlige opskrift', async () => {
    await assertSucceeds(deleteDoc(doc(db('alice'), 'recipes/pub')));
  });
  test('et andet medlem kan stadig ikke slette (som i dag)', async () => {
    await assertFails(deleteDoc(doc(db('bob'), 'recipes/pub')));
  });
  test('skaberen kan slette sin offentlige opskrift, selv efter at have forladt husstanden', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'households/HH_A'),
        { name: 'A', members: ['bob'], admin: 'bob' });
    });
    await assertSucceeds(deleteDoc(doc(db('alice'), 'recipes/pub')));
    // ... men en husstands-opskrift kræver stadig medlemskab.
    await assertFails(deleteDoc(doc(db('alice'), 'recipes/priv')));
  });
});

describe('deling af opskrifter: slet konto', () => {
  // Spejler AccountDeletionService: egne offentlige opskrifter slettes først.
  const ownPublic = (s, uid) => query(collection(s, 'recipes'),
    where('createdBy', '==', uid), where('visibility', '==', 'public'));
  async function deleteMatching(s, q) {
    const snap = await getDocs(q);
    for (const d of snap.docs) await deleteDoc(d.ref);
    return snap.size;
  }
  async function exists(id) {
    let found = false;
    await env.withSecurityRulesDisabled(async (ctx) => {
      found = (await getDoc(doc(ctx.firestore(), `recipes/${id}`))).exists();
    });
    return found;
  }

  test('med andre i husstanden: egne offentlige slettes, private bliver', async () => {
    const s = db('alice');
    if (await deleteMatching(s, ownPublic(s, 'alice')) !== 1) throw new Error('Forventede 1 sletning');
    if (await exists('pub')) throw new Error('Offentlig opskrift blev ikke slettet');
    if (!(await exists('priv'))) throw new Error('Privat opskrift forsvandt');
  });
  test('en andens kopi af opskriften er et separat dokument og bliver', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'recipes/copy'), {
        title: 'Lasagne', householdId: 'HH_E', createdBy: 'eve', visibility: 'household', copiedFrom: 'pub',
      });
    });
    const s = db('alice');
    await deleteMatching(s, ownPublic(s, 'alice'));
    if (!(await exists('copy'))) throw new Error('Kopien blev slettet');
  });
  test('eneste medlem: forespørgslen virker, og husstandens opskrifter kan derefter slettes', async () => {
    const s = db('eve');
    await assertSucceeds(deleteMatching(s, ownPublic(s, 'eve')));
    await assertSucceeds(deleteMatching(s, query(collection(s, 'recipes'), where('householdId', '==', 'HH_E'))));
  });
  test('forespørgslen afviser at slette en andens offentlige opskrifter', async () => {
    const s = db('eve');
    await assertFails(deleteDoc(doc(s, 'recipes/pub')));
  });
});

describe('deling af opskrifter: kun skaberen må dele (fund 2)', () => {
  test('et andet medlem kan IKKE gøre en andens opskrift offentlig', async () => {
    await assertFails(updateDoc(doc(db('bob'), 'recipes/priv'), { visibility: 'public', authorName: 'Alice' }));
    await assertFails(updateDoc(doc(db('bob'), 'recipes/priv'), { visibility: 'public' }));
    await assertFails(updateDoc(doc(db('bob'), 'recipes/priv'), fields({
      title: 'Hemmelig', titleLower: 'hemmelig', visibility: 'public', authorName: 'Bob',
    })));
  });
  test('et andet medlem kan stadig rette en delt opskrift uden at røre deling og navn', async () => {
    await assertSucceeds(updateDoc(doc(db('bob'), 'recipes/pub'), fields({
      title: 'Lasagne 2', titleLower: 'lasagne 2', visibility: 'public', authorName: 'Alice',
    })));
  });
  test('et andet medlem kan IKKE ændre forfatternavnet på en delt opskrift', async () => {
    await assertFails(updateDoc(doc(db('bob'), 'recipes/pub'), { authorName: 'Bob' }));
  });
  test('et andet medlem kan altid holde op med at dele', async () => {
    await assertSucceeds(updateDoc(doc(db('bob'), 'recipes/pub'),
      { visibility: 'household', authorName: deleteField() }));
  });
  test('skaberen kan dele sin egen opskrift', async () => {
    await assertSucceeds(updateDoc(doc(db('alice'), 'recipes/priv'),
      { visibility: 'public', authorName: 'Alice' }));
  });
  test('et medlem kan ikke oprette en opskrift i en andens navn', async () => {
    await assertFails(addDoc(collection(db('bob'), 'recipes'),
      { ...created({ visibility: 'public', authorName: 'Alice' }), createdBy: 'alice' }));
  });
  test('admin kan stadig slette en offentlig opskrift lavet af et andet medlem', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'recipes/bobPub'), {
        title: 'B', householdId: 'HH_A', createdBy: 'bob', visibility: 'public', authorName: 'Bob',
      });
    });
    await assertSucceeds(deleteDoc(doc(db('alice'), 'recipes/bobPub')));
  });
});

describe('deling af opskrifter: skaber der har forladt husstanden (fund 1)', () => {
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'households/HH_A'), { name: 'A', members: ['bob'], admin: 'bob' });
      await setDoc(doc(ctx.firestore(), 'users/alice'), { householdId: 'HH_NEW' });
    });
  });
  test('kan holde op med at dele (præcis visibility + authorName fjernet)', async () => {
    await assertSucceeds(updateDoc(doc(db('alice'), 'recipes/pub'),
      { visibility: 'household', authorName: deleteField() }));
  });
  test('alt andet fra den tidligere skaber afvises', async () => {
    const ref = () => doc(db('alice'), 'recipes/pub');
    await assertFails(updateDoc(ref(), { visibility: 'household' }));            // navnet bliver stående
    await assertFails(updateDoc(ref(), { authorName: deleteField() }));          // stadig delt
    await assertFails(updateDoc(ref(), { title: 'Ny' }));
    await assertFails(updateDoc(ref(), { visibility: 'household', authorName: deleteField(), title: 'Ny' }));
    await assertFails(updateDoc(ref(), { visibility: 'household', authorName: 'Alice' }));
    await assertFails(updateDoc(ref(), { visibility: 'public', authorName: 'Alice2' }));
  });
  test('kan ikke gøre en husstands-opskrift offentlig eller røre den', async () => {
    await assertFails(updateDoc(doc(db('alice'), 'recipes/priv'), { visibility: 'public', authorName: 'Alice' }));
    await assertFails(updateDoc(doc(db('alice'), 'recipes/priv'), { title: 'Ny' }));
    await assertFails(deleteDoc(doc(db('alice'), 'recipes/priv')));
    await assertFails(getDoc(doc(db('alice'), 'recipes/priv')));
  });
  test('kan stadig slette sin offentlige opskrift', async () => {
    await assertSucceeds(deleteDoc(doc(db('alice'), 'recipes/pub')));
  });
  test('andre kan ikke bruge den smalle regel (anden husstand, andet medlem)', async () => {
    await assertFails(updateDoc(doc(db('eve'), 'recipes/pub'),
      { visibility: 'household', authorName: deleteField() }));
    await assertSucceeds(updateDoc(doc(db('bob'), 'recipes/pub'),
      { visibility: 'household', authorName: deleteField() }));
  });
});

describe('deling af opskrifter: forfatternavn og søgenøgle (fund 4, 5)', () => {
  const make = (extra) => addDoc(collection(db('alice'), 'recipes'), created(extra));
  test('reserverede navne afvises, uanset store/små bogstaver', async () => {
    for (const name of ['Skafferiet Support', 'SUPPORT', 'Admin', 'administrator', 'Moderator', 'skafferiet', 'Mr.Admin']) {
      await assertFails(make({ visibility: 'public', authorName: name }));
    }
    await assertSucceeds(make({ visibility: 'public', authorName: 'Anne-Marie' }));
  });
  test('reserverede navne afvises også ved ændring', async () => {
    await assertFails(updateDoc(doc(db('alice'), 'recipes/pub'), { authorName: 'Support' }));
  });
  // Reglernes lower() ændrer kun ASCII (testet: 'Æ'.lower() forbliver 'Æ'), mens
  // Darts toLowerCase() også ændrer æ/ø/å. Derfor kræves præcis lighed kun for
  // ren ASCII; ellers samme længde. Appen filtrerer søgetræf på titlen selv.
  test('titleLower skal være titlen med små bogstaver (også æ/ø/å, som Dart skriver dem)', async () => {
    await assertSucceeds(make({ title: 'Æblegrød', titleLower: 'æblegrød' }));
    await assertSucceeds(make({ title: 'ØLLEBRØD', titleLower: 'øllebrød' }));
    await assertSucceeds(make({ title: 'Åkande', titleLower: 'åkande' }));
    await assertSucceeds(make({ title: 'Pasta Carbonara', titleLower: 'pasta carbonara' }));
  });
  test('en afvigende titleLower afvises', async () => {
    await assertFails(make({ title: 'Suppe', titleLower: 'lasagne', visibility: 'public', authorName: 'Eve' }));
    await assertFails(make({ title: 'Suppe', titleLower: 'Suppe' }));
    await assertFails(make({ title: 'Køb billige piller', titleLower: 'lasagne', visibility: 'public', authorName: 'Eve' }));
    await assertFails(make({ title: 'Suppe', titleLower: 5 }));
  });
  test('ved ændring: titel eller titleLower skal stadig passe sammen', async () => {
    await assertSucceeds(updateDoc(doc(db('alice'), 'recipes/pub'), { title: 'Ny', titleLower: 'ny' }));
    await assertFails(updateDoc(doc(db('alice'), 'recipes/pub'), { titleLower: 'spam' }));
    await assertFails(updateDoc(doc(db('alice'), 'recipes/pub'), { title: 'Nyt' })); // titleLower er stadig 'lasagne'
  });
  test('ældre opskrift uden titleLower kan rettes delvist', async () => {
    await assertSucceeds(updateDoc(doc(db('bob'), 'recipes/legacy'), { title: 'Ny titel' }));
  });
  test('40 UTF-16-enheder: 20 emoji er fint, 21 afvises', async () => {
    await assertSucceeds(make({ visibility: 'public', authorName: '😀'.repeat(20) }));
    await assertFails(make({ visibility: 'public', authorName: '😀'.repeat(21) }));
  });
  test('authorName kan sættes på en privat opskrift (har ingen virkning, kun længde tjekkes)', async () => {
    await assertSucceeds(make({ authorName: 'Alice' }));
  });
  test('offentlig opskrift uden husstand afvises', async () => {
    await assertFails(addDoc(collection(db('eve'), 'recipes'), {
      ...fields({ visibility: 'public', authorName: 'Eve' }), createdAt: serverTimestamp(),
      householdId: null, createdBy: 'eve',
    }));
  });
  test('ikke-medlem kan ikke oprette med en andens createdBy i egen husstand', async () => {
    await assertFails(addDoc(collection(db('eve'), 'recipes'), {
      ...fields({ visibility: 'public', authorName: 'Alice' }), createdAt: serverTimestamp(),
      householdId: 'HH_E', createdBy: 'alice',
    }));
  });
});
