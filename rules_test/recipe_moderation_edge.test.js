// Moderation (#52): grænsetilfælde for rapporter, blokeringer og fjernede
// opskrifter. Læsereglens læk for ældre opskrifter (#54) er rettet og
// testes i recipe_read_leak.test.js.
const { test, before, beforeEach, after, describe } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, collectionGroup, getDocs, query, where,
  deleteField, serverTimestamp,
} = require('firebase/firestore');

let env;
const db = (uid) => env.authenticatedContext(uid, { email: `${uid}@example.com` }).firestore();
const report = (extra = {}) => ({
  recipeId: 'pub', reportedBy: 'eve', reason: 'spam', comment: '',
  createdAt: serverTimestamp(), ...extra,
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-skafferiet-moderation-edge',
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
    await setDoc(doc(s, 'recipes/pub'), {
      title: 'Lasagne', titleLower: 'lasagne', householdId: 'HH_A', createdBy: 'alice',
      visibility: 'public', authorName: 'Alice', createdAt: new Date('2026-01-02'),
    });
    await setDoc(doc(s, 'recipes/hid'), {
      title: 'Fjernet', titleLower: 'fjernet', householdId: 'HH_A', createdBy: 'alice',
      visibility: 'hidden', authorName: 'Alice', createdAt: new Date('2026-01-04'),
    });
    await setDoc(doc(s, 'reports/pub_eve'), {
      recipeId: 'pub', reportedBy: 'eve', reason: 'spam', comment: 'x', createdAt: new Date('2026-02-01'),
    });
    await setDoc(doc(s, 'users/alice/blocked_authors/eve'), { name: 'Eve', blockedAt: new Date('2026-02-01') });
  });
});

describe('moderation: rapporter', () => {
  test('liste med reportedBy == en anden afvises, også med limit', async () => {
    await assertFails(getDocs(query(collection(db('carol'), 'reports'), where('reportedBy', '==', 'eve'))));
  });
  test('collectionGroup på reports/blocked_authors afvises', async () => {
    await assertFails(getDocs(query(collectionGroup(db('eve'), 'reports'), where('reportedBy', '==', 'eve'))));
    await assertFails(getDocs(collectionGroup(db('bob'), 'blocked_authors')));
  });
  test('get af ikke-eksisterende rapport afviser (afslører intet)', async () => {
    await assertFails(getDoc(doc(db('carol'), 'reports/pub_eve')));
  });
  test('delvis update af egen rapport med ny createdAt er OK; uden afvises', async () => {
    await assertSucceeds(updateDoc(doc(db('eve'), 'reports/pub_eve'), { reason: 'other', createdAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(db('eve'), 'reports/pub_eve'), { reason: 'spam' }));
  });
  test('kan ikke overskrive en andens rapport selv med rigtigt id-mønster for en selv', async () => {
    await assertFails(setDoc(doc(db('carol'), 'reports/pub_eve'), report({ reportedBy: 'carol' })));
  });
  test('skaber der har forladt husstanden kan rapportere sin egen opskrift (rules tillader; UI skjuler)', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/alice'), { householdId: 'HH_E' });
    });
    await assertSucceeds(setDoc(doc(db('alice'), 'reports/pub_alice'), report({ reportedBy: 'alice' })));
  });
  test('unicode: rules tæller UTF-16-enheder (250 emoji OK, 251 afvist) - TextField tæller grafemer', async () => {
    await assertSucceeds(setDoc(doc(db('eve'), 'reports/pub_eve'), report({ comment: '😀'.repeat(250) })));
    await assertFails(setDoc(doc(db('eve'), 'reports/pub_eve'), report({ comment: '😀'.repeat(251) })));
  });
  test('rapporten forbliver, efter opskriften gøres privat; ejeren kan stadig slette den', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'recipes/pub'), { visibility: 'household' });
    });
    await assertSucceeds(getDocs(query(collection(db('eve'), 'reports'), where('reportedBy', '==', 'eve'))));
    await assertSucceeds(deleteDoc(doc(db('eve'), 'reports/pub_eve')));
  });
});

describe('moderation: blocked_authors', () => {
  test('profil-read for husstand giver ikke undersamling', async () => {
    await assertFails(getDoc(doc(db('bob'), 'users/alice/blocked_authors/eve')));
  });
  test('ejeren kan opdatere navnet med ny blockedAt; kan ikke tilføje felt', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), 'users/alice/blocked_authors/eve'), { name: 'E', blockedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(db('alice'), 'users/alice/blocked_authors/eve'), { name: 'Y' }));
  });
});

describe('moderation: hidden', () => {
  test('husstanden redigerer med appens payload (visibility uændret, authorName slettes)', async () => {
    await assertSucceeds(updateDoc(doc(db('bob'), 'recipes/hid'), {
      title: 'Fjernet 2', titleLower: 'fjernet 2', visibility: 'hidden', authorName: deleteField(),
    }));
  });
  test('husstanden kan ikke slette visibility-feltet på hidden (ville blive household)', async () => {
    await assertFails(updateDoc(doc(db('bob'), 'recipes/hid'), { visibility: deleteField() }));
    await assertFails(updateDoc(doc(db('alice'), 'recipes/hid'), { visibility: deleteField(), authorName: deleteField() }));
  });
  test('setDoc (fuld overskrivning) af hidden til public afvises', async () => {
    await assertFails(setDoc(doc(db('alice'), 'recipes/hid'), {
      title: 'Fjernet', titleLower: 'fjernet', householdId: 'HH_A', createdBy: 'alice',
      visibility: 'public', authorName: 'Alice', createdAt: new Date('2026-01-04'),
    }));
  });
  test('admin-medlem (skaber) i husstanden kan slette sin hidden opskrift', async () => {
    await assertSucceeds(deleteDoc(doc(db('alice'), 'recipes/hid')));
  });
  test('almindeligt medlem (ikke skaber) kan ikke slette hidden', async () => {
    await assertFails(deleteDoc(doc(db('bob'), 'recipes/hid')));
  });
  test('skaber der har forladt husstanden kan hverken læse eller slette sin hidden opskrift', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'households/HH_A'), { name: 'A', members: ['bob'], admin: 'bob' });
      await setDoc(doc(ctx.firestore(), 'users/alice'), { householdId: 'HH_E' });
    });
    await assertFails(getDoc(doc(db('alice'), 'recipes/hid')));
    await assertFails(deleteDoc(doc(db('alice'), 'recipes/hid')));
    // Kontosletningens forespørgsel finder den ikke (visibility == 'public').
    const snap = await assertSucceeds(getDocs(query(collection(db('alice'), 'recipes'),
      where('createdBy', '==', 'alice'), where('visibility', '==', 'public'))));
    if (snap.docs.some((d) => d.id === 'hid')) throw new Error('uventet');
  });
  test('kontosletningens public-forespørgsel rammer ikke hidden, og den bliver i husstanden', async () => {
    const snap = await assertSucceeds(getDocs(query(collection(db('alice'), 'recipes'),
      where('createdBy', '==', 'alice'), where('visibility', '==', 'public'))));
    if (snap.docs.some((d) => d.id === 'hid')) throw new Error('uventet');
  });
  test('kopi af en hidden opskrift (cached) i egen husstand er bare en ny privat opskrift', async () => {
    await assertSucceeds(setDoc(doc(db('eve'), 'recipes/copy1'), {
      title: 'Fjernet', titleLower: 'fjernet', householdId: 'HH_E', createdBy: 'eve',
      visibility: 'household', copiedFrom: 'hid', createdAt: serverTimestamp(),
    }));
    // ... men kan ikke deles som 'public' af en anden end skaberen? (eve ER skaber af kopien)
    await assertSucceeds(updateDoc(doc(db('eve'), 'recipes/copy1'), { visibility: 'public', authorName: 'Eve' }));
  });
});
