// Fremgangsmåde-reglen (#25) mod det appen faktisk sender
// (RecipesNotifier._recipeFields ved add/update) og mod ældre data.
const { test, before, beforeEach, after, describe } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, setDoc, updateDoc, addDoc, collection, serverTimestamp } = require('firebase/firestore');

let env;
const db = (uid) => env.authenticatedContext(uid).firestore();
const steps = (n) => Array.from({ length: n }, (_, i) => `Trin ${i + 1}`);
// Det _recipeFields sender.
const fields = (extra = {}) => ({
  title: 'Suppe', imageUrl: null, calories: 0, time: '', category: 'RecipeCategory.aftensmad',
  ingredients: [], instructions: [], servings: null, protein: null, carbs: null, fat: null,
  nutritionFromIngredients: false, ...extra,
});
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-skafferiet-recipe-steps',
    firestore: { rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') },
  });
});
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const s = ctx.firestore();
    await setDoc(doc(s, 'households/HH'), { name: 'H', members: ['bob'], admin: 'bob' });
    await setDoc(doc(s, 'users/bob'), { householdId: 'HH' });
    await setDoc(doc(s, 'recipes/legacyNull'), { title: 'x', householdId: 'HH', createdBy: 'bob', instructions: null });
    await setDoc(doc(s, 'recipes/legacyMissing'), { title: 'x', householdId: 'HH', createdBy: 'bob' });
    await setDoc(doc(s, 'recipes/legacy60'), { title: 'x', householdId: 'HH', createdBy: 'bob', instructions: steps(60) });
  });
});

describe('fremgangsmåde: appens egne skrivninger', () => {
  test('addRecipe med 50 trin à 1000 tegn', async () => {
    await assertSucceeds(addDoc(collection(db('bob'), 'recipes'), {
      ...fields({ instructions: Array.from({ length: 50 }, () => 'æ'.repeat(1000)) }),
      createdAt: serverTimestamp(), householdId: 'HH', createdBy: 'bob',
    }));
  });
  test('starter-opskrift (4 trin) via addRecipe-formen', async () => {
    await assertSucceeds(addDoc(collection(db('bob'), 'recipes'), {
      ...fields({ instructions: steps(4) }), createdAt: serverTimestamp(), householdId: 'HH', createdBy: 'bob',
    }));
  });
  test('updateRecipe på gammel opskrift med instructions: null (app sender [])', async () => {
    await assertSucceeds(updateDoc(doc(db('bob'), 'recipes/legacyNull'), fields()));
  });
  test('updateRecipe på gammel opskrift uden feltet', async () => {
    await assertSucceeds(updateDoc(doc(db('bob'), 'recipes/legacyMissing'), fields()));
  });
});

describe('fremgangsmåde: ældre data blokerer ikke andre rettelser', () => {
  test('null-legacy: delvis opdatering af titel blokeres ikke af gamle trin', async () => {
    await assertSucceeds(updateDoc(doc(db('bob'), 'recipes/legacyNull'), { title: 'Ny' }));
  });
  test('60-trins legacy: titel-rettelse med uændrede trin blokeres ikke', async () => {
    await assertSucceeds(updateDoc(doc(db('bob'), 'recipes/legacy60'), { title: 'Ny' }));
  });
  test('60-trins legacy: at ændre trinene til stadig over 50 afvises', async () => {
    await assertFails(updateDoc(doc(db('bob'), 'recipes/legacy60'), fields({ instructions: steps(51) })));
  });
  test('60-trins legacy: skåret ned til 50 accepteres', async () => {
    await assertSucceeds(updateDoc(doc(db('bob'), 'recipes/legacy60'), fields({ instructions: steps(50) })));
  });
});
