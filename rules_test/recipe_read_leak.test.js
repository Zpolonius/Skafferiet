// Læsereglen for opskrifter (#54): en liste-forespørgsel uden filter på
// householdId må aldrig returnere en anden husstands private opskrifter.
// Før rettelsen tillod `!('householdId' in resource.data)` alle forespørgsler.
//
// Testdata: Familien A (alice), Eves hus (eve). HH_A har private opskrifter
// med visibility 'household', uden visibility (ældre) og 'hidden'.
//
// De positive forespørgsler appen selv sender er dækket i forvejen:
//   Filter.or(householdId == egen, householdId == null) ... firestore.rules.test.js
//   Fællesskab (public + createdAt / titleLower) .......... recipe_sharing.test.js
//   dedupe på copiedFrom, kontosletning ................... recipe_sharing.test.js, firestore.rules.test.js
const { test, before, beforeEach, after, describe } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, collection, getDocs, query, where, orderBy, limit, or,
} = require('firebase/firestore');

let env;
const db = (uid) => env.authenticatedContext(uid, { email: `${uid}@example.com` }).firestore();
const recipes = (uid) => collection(db(uid), 'recipes');

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-skafferiet-recipe-read',
    firestore: { rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') },
  });
});
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const s = ctx.firestore();
    await setDoc(doc(s, 'households/HH_A'), { name: 'A', members: ['alice'], admin: 'alice' });
    await setDoc(doc(s, 'households/HH_E'), { name: 'E', members: ['eve'], admin: 'eve' });
    await setDoc(doc(s, 'users/alice'), { householdId: 'HH_A' });
    await setDoc(doc(s, 'users/eve'), { householdId: 'HH_E' });
    await setDoc(doc(s, 'recipes/priv'), {
      title: 'Hemmelig', titleLower: 'hemmelig', householdId: 'HH_A', createdBy: 'alice',
      visibility: 'household', createdAt: new Date('2026-01-01'),
    });
    await setDoc(doc(s, 'recipes/old'), {
      title: 'Ældre privat', titleLower: 'ældre privat', householdId: 'HH_A', createdBy: 'alice',
      createdAt: new Date('2026-01-02'),
    });
    await setDoc(doc(s, 'recipes/hid'), {
      title: 'Fjernet', titleLower: 'fjernet', householdId: 'HH_A', createdBy: 'alice',
      visibility: 'hidden', createdAt: new Date('2026-01-03'),
    });
    await setDoc(doc(s, 'recipes/pub'), {
      title: 'Lasagne', titleLower: 'lasagne', householdId: 'HH_A', createdBy: 'alice',
      visibility: 'public', authorName: 'Alice', createdAt: new Date('2026-01-04'),
    });
    await setDoc(doc(s, 'recipes/global'), {
      title: 'Fælles ret', householdId: null, createdBy: 'admin', createdAt: new Date('2026-01-05'),
    });
    // Skrevet før householdId blev obligatorisk; appen skriver det altid nu.
    await setDoc(doc(s, 'recipes/noField'), { title: 'Uden felt', createdBy: 'alice' });
  });
});

describe('læk: andre husstandes private opskrifter via liste-forespørgsler', () => {
  test('where visibility == household afvises', async () => {
    await assertFails(getDocs(query(recipes('eve'), where('visibility', '==', 'household'))));
  });
  test('where visibility == hidden afvises', async () => {
    await assertFails(getDocs(query(recipes('eve'), where('visibility', '==', 'hidden'))));
  });
  test('ufiltreret forespørgsel (med limit) afvises', async () => {
    await assertFails(getDocs(query(recipes('eve'), limit(20))));
  });
  test('ufiltreret forespørgsel uden limit afvises', async () => {
    await assertFails(getDocs(recipes('eve')));
  });
  test("where title >= '' afvises", async () => {
    await assertFails(getDocs(query(recipes('eve'), where('title', '>=', ''))));
  });
  test('orderBy createdAt uden filter afvises', async () => {
    await assertFails(getDocs(query(recipes('eve'), orderBy('createdAt'))));
  });
  test('filter på en andens householdId afvises', async () => {
    await assertFails(getDocs(query(recipes('eve'), where('householdId', '==', 'HH_A'))));
  });
  test('or(egen, null) lækker ikke: kun Eves egne og globale kommer tilbage', async () => {
    const snap = await assertSucceeds(getDocs(query(recipes('eve'),
      or(where('householdId', '==', 'HH_E'), where('householdId', '==', null)))));
    const ids = snap.docs.map((d) => d.id);
    if (ids.length !== 1 || ids[0] !== 'global') throw new Error(`Uventet: ${ids}`);
  });
});

describe('get og de forespørgsler appen sender', () => {
  test('eve kan ikke hente HH_As private, ældre eller fjernede opskrift', async () => {
    for (const id of ['priv', 'old', 'hid']) {
      await assertFails(getDoc(doc(db('eve'), `recipes/${id}`)));
    }
  });
  test('en opskrift UDEN householdId kan ikke længere læses (heller ikke af en ukendt)', async () => {
    await assertFails(getDoc(doc(db('eve'), 'recipes/noField')));
    await assertFails(getDoc(doc(db('alice'), 'recipes/noField')));
  });
  test('en global opskrift (householdId: null) kan læses med get', async () => {
    await assertSucceeds(getDoc(doc(db('eve'), 'recipes/global')));
  });
  test('en offentlig opskrift kan læses med get', async () => {
    await assertSucceeds(getDoc(doc(db('eve'), 'recipes/pub')));
  });
  test('appens or-forespørgsel (egen husstand + globale) er tilladt for alice', async () => {
    const snap = await assertSucceeds(getDocs(query(recipes('alice'),
      or(where('householdId', '==', 'HH_A'), where('householdId', '==', null)))));
    const ids = snap.docs.map((d) => d.id).sort();
    if (ids.join() !== 'global,hid,old,priv,pub') throw new Error(`Uventet: ${ids}`);
  });
  test('alice kan liste sin egen husstands opskrifter', async () => {
    const snap = await assertSucceeds(getDocs(query(recipes('alice'), where('householdId', '==', 'HH_A'))));
    if (snap.size !== 4) throw new Error(`Forventede 4, fik ${snap.size}`);
  });
  test('Fællesskab-forespørgslen returnerer kun offentlige opskrifter til eve', async () => {
    const snap = await assertSucceeds(getDocs(query(recipes('eve'),
      where('visibility', '==', 'public'), orderBy('createdAt', 'desc'))));
    if (snap.size !== 1 || snap.docs[0].id !== 'pub') throw new Error('Forkert resultat');
  });
});
