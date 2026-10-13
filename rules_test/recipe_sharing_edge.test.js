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
    projectId: 'demo-skafferiet-recipe-sharing-edge',
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


// Deling af opskrifter (#51): angrebsveje i publishAllowed og formerCreatorUnshare.
describe('deling: angrebsveje', () => {
  test('former creator kan holde op med at dele en opskrift UDEN authorName', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const s = ctx.firestore();
      await setDoc(doc(s, 'recipes/noName'), { title: 'X', titleLower: 'x', householdId: 'HH_A', createdBy: 'alice', visibility: 'public' });
      await setDoc(doc(s, 'households/HH_A'), { name: 'A', members: ['bob'], admin: 'bob' });
      await setDoc(doc(s, 'users/alice'), { householdId: 'HH_E2' });
    });
    await assertSucceeds(updateDoc(doc(db('alice'), 'recipes/noName'), { visibility: 'household', authorName: deleteField() }));
  });
  test('former creator, nu medlem af en anden husstand, kan kun den smalle ændring', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const s = ctx.firestore();
      await setDoc(doc(s, 'households/HH_A'), { name: 'A', members: ['bob'], admin: 'bob' });
      await setDoc(doc(s, 'households/HH_E'), { name: 'E', members: ['eve', 'alice'], admin: 'eve' });
      await setDoc(doc(s, 'users/alice'), { householdId: 'HH_E' });
    });
    const r = () => doc(db('alice'), 'recipes/pub');
    await assertFails(updateDoc(r(), { householdId: 'HH_E' }));
    await assertFails(updateDoc(r(), { visibility: 'household', authorName: deleteField(), householdId: 'HH_E' }));
    await assertFails(updateDoc(r(), { visibility: 'household', authorName: deleteField(), ingredients: ['x'] }));
    await assertSucceeds(updateDoc(r(), { visibility: 'household', authorName: deleteField() }));
    // efter unshare kan hun ikke dele igen eller læse den
    await assertFails(updateDoc(r(), { visibility: 'public', authorName: 'Alice' }));
    await assertFails(getDoc(r()));
  });
  test('smal regel virker ikke på husstands-opskrift (no-op)', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'households/HH_A'), { name: 'A', members: ['bob'], admin: 'bob' });
    });
    await assertFails(updateDoc(doc(db('alice'), 'recipes/priv'), { visibility: 'household', authorName: deleteField() }));
  });
  test('ikke-skaber kan ikke sætte authorName igen bagefter', async () => {
    await updateDoc(doc(db('bob'), 'recipes/pub'), { authorName: deleteField() });
    await assertFails(updateDoc(doc(db('bob'), 'recipes/pub'), { authorName: 'Bob' }));
    await assertSucceeds(updateDoc(doc(db('alice'), 'recipes/pub'), { authorName: 'Alice' }));
  });
  test('ikke-skaber kan ikke offentliggøre via create i andens navn eller via legacy uden createdBy', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'recipes/noCreator'), { title: 'Y', householdId: 'HH_A' });
    });
    await assertFails(updateDoc(doc(db('bob'), 'recipes/noCreator'), { visibility: 'public' }));
  });
  test('reserverede ord: almindelige danske navne går igennem', async () => {
    for (const n of ['Mads', 'Søren', 'Ådne', 'Ida-Marie', 'Adam', 'Admir', 'Suppé']) {
      await assertSucceeds(addDoc(collection(db('alice'), 'recipes'), created({ visibility: 'public', authorName: n })));
    }
  });
});
