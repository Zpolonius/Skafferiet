// Læsereglen for opskrifter (#54), flere forespørgselsformer: ingen
// liste-forespørgsel uden filter på householdId (eller visibility == 'public')
// må give Eve adgang til Familien A's private eller fjernede opskrifter. Før
// rettelsen returnerede de fleste former (og count()) HH_A's private opskrifter;
// householdId-formerne og collectionGroup var allerede afvist og er med som værn.
const { test, before, beforeEach, after, describe } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const {
  doc, setDoc, collection, collectionGroup, getDocs, query, where, orderBy, limitToLast,
  startAt, startAfter, endAt, or, getCountFromServer,
} = require('firebase/firestore');

let env;
const db = (uid) => env.authenticatedContext(uid, { email: `${uid}@example.com` }).firestore();
const recipes = (uid) => collection(db(uid), 'recipes');

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-skafferiet-recipe-read-shapes',
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
      visibility: 'household', createdAt: new Date('2026-01-01'), copiedFrom: 'pub', tags: ['x'],
    });
    await setDoc(doc(s, 'recipes/hid'), {
      title: 'Fjernet', titleLower: 'fjernet', householdId: 'HH_A', createdBy: 'alice',
      visibility: 'hidden', createdAt: new Date('2026-01-03'), tags: ['x'],
    });
    await setDoc(doc(s, 'recipes/pub'), {
      title: 'Lasagne', titleLower: 'lasagne', householdId: 'HH_A', createdBy: 'alice',
      visibility: 'public', authorName: 'Alice', createdAt: new Date('2026-01-04'),
    });
    await setDoc(doc(s, 'recipes/global'), {
      title: 'Fælles ret', householdId: null, createdBy: 'admin', createdAt: new Date('2026-01-05'),
    });
  });
});

describe('læk: flere forespørgselsformer afvises for en anden husstand', () => {
  const shapes = {
    "visibility != 'household' (ville give fjernede)": (c) => query(c, where('visibility', '!=', 'household')),
    "visibility in ['public', 'hidden']": (c) => query(c, where('visibility', 'in', ['public', 'hidden'])),
    "visibility not-in ['public']": (c) => query(c, where('visibility', 'not-in', ['public'])),
    'array-contains på et andet felt': (c) => query(c, where('tags', 'array-contains', 'x')),
    'orderBy titleLower uden filter': (c) => query(c, orderBy('titleLower')),
    'limitToLast': (c) => query(c, orderBy('createdAt'), limitToLast(5)),
    'cursor (startAfter)': (c) => query(c, orderBy('title'), startAfter('A')),
    'titleLower-interval uden visibility': (c) => query(c, orderBy('titleLower'), startAt('h'), endAt('h')),
    "createdBy == 'alice' uden visibility": (c) => query(c, where('createdBy', '==', 'alice')),
    'copiedFrom == id uden householdId': (c) => query(c, where('copiedFrom', '==', 'pub')),
    "householdId != 'HH_E'": (c) => query(c, where('householdId', '!=', 'HH_E')),
    "householdId in ['HH_A', null]": (c) => query(c, where('householdId', 'in', ['HH_A', null])),
    "householdId not-in ['HH_E']": (c) => query(c, where('householdId', 'not-in', ['HH_E'])),
    "or(visibility == 'public', householdId == 'HH_A')": (c) =>
      query(c, or(where('visibility', '==', 'public'), where('householdId', '==', 'HH_A'))),
  };
  for (const [name, q] of Object.entries(shapes)) {
    test(name, async () => { await assertFails(getDocs(q(recipes('eve')))); });
  }
  test('count() over hele samlingen afvises', async () => {
    await assertFails(getCountFromServer(recipes('eve')));
  });
  test('collectionGroup(recipes) afvises (ingen {path=**}-regel)', async () => {
    await assertFails(getDocs(collectionGroup(db('eve'), 'recipes')));
  });
});

describe('tilladte former giver kun offentlige og globale', () => {
  test("or(visibility == 'public', householdId == null)", async () => {
    const snap = await assertSucceeds(getDocs(query(recipes('eve'),
      or(where('visibility', '==', 'public'), where('householdId', '==', null)))));
    const ids = snap.docs.map((d) => d.id).sort().join();
    if (ids !== 'global,pub') throw new Error(`Uventet: ${ids}`);
  });
  test('householdId == null', async () => {
    const snap = await assertSucceeds(getDocs(query(recipes('eve'), where('householdId', '==', null))));
    if (snap.docs.map((d) => d.id).join() !== 'global') throw new Error('Forkert resultat');
  });
  test("Fællesskab-søgning (visibility == 'public' + titleLower-interval)", async () => {
    const snap = await assertSucceeds(getDocs(query(recipes('eve'), where('visibility', '==', 'public'),
      orderBy('titleLower'), startAt('l'), endAt('l'))));
    if (snap.docs.map((d) => d.id).join() !== 'pub') throw new Error('Forkert resultat');
  });
  test("kontosletning: createdBy == uid && visibility == 'public' (alice uden husstand)", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/alice'), { householdId: 'HH_E2' });
    });
    const snap = await assertSucceeds(getDocs(query(recipes('alice'),
      where('createdBy', '==', 'alice'), where('visibility', '==', 'public'))));
    if (snap.docs.map((d) => d.id).join() !== 'pub') throw new Error('Forkert resultat');
  });
});
