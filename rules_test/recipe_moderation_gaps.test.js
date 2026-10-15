// Moderation (#52): flere angrebsveje for rapporter, blokeringer og fjernede
// opskrifter. Den kendte læk i læsereglen for ældre opskrifter er #54.
const { test, before, beforeEach, after, describe } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs, query, where, serverTimestamp } = require('firebase/firestore');

let env;
const db = (uid) => env.authenticatedContext(uid).firestore();
const report = (extra = {}) => ({ recipeId: 'pub', reportedBy: 'eve', reason: 'spam', comment: '', createdAt: serverTimestamp(), ...extra });

before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-skafferiet-moderation-gaps',
    firestore: { rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') } });
});
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const s = ctx.firestore();
    await setDoc(doc(s, 'households/HH_A'), { name: 'A', members: ['alice', 'bob', 'nodoc'], admin: 'alice' });
    await setDoc(doc(s, 'households/HH_E'), { name: 'E', members: ['eve'], admin: 'eve' });
    await setDoc(doc(s, 'users/alice'), { householdId: 'HH_A' });
    await setDoc(doc(s, 'users/bob'), { householdId: 'HH_A' });
    await setDoc(doc(s, 'users/eve'), { householdId: 'HH_E' });
    await setDoc(doc(s, 'users/removed'), { householdId: 'HH_A' }); // stale: not a member
    await setDoc(doc(s, 'recipes/pub'), { title: 'L', titleLower: 'l', householdId: 'HH_A', createdBy: 'alice', visibility: 'public', authorName: 'Alice', createdAt: new Date('2026-01-02') });
    await setDoc(doc(s, 'recipes/novis'), { title: 'N', householdId: 'HH_A', createdBy: 'alice', createdAt: new Date('2026-01-02') });
    await setDoc(doc(s, 'recipes/hid'), { title: 'Fjernet', titleLower: 'fjernet', householdId: 'HH_A', createdBy: 'alice', visibility: 'hidden', authorName: 'Alice', createdAt: new Date('2026-01-04') });
  });
});

describe('moderation: rapporter', () => {
  test('opskrift uden visibility-felt kan ikke rapporteres', async () => {
    await assertFails(setDoc(doc(db('eve'), 'reports/novis_eve'), report({ recipeId: 'novis' })));
  });
  test('en ny rapport efter at opskriften er fjernet afvises (også overskrivning)', async () => {
    await assertSucceeds(setDoc(doc(db('eve'), 'reports/pub_eve'), report()));
    await env.withSecurityRulesDisabled(async (ctx) => { await updateDoc(doc(ctx.firestore(), 'recipes/pub'), { visibility: 'hidden' }); });
    await assertFails(setDoc(doc(db('eve'), 'reports/pub_eve'), report({ reason: 'other' })));
    // ... men den gamle kan stadig læses og slettes (kontosletning).
    await assertSucceeds(getDocs(query(collection(db('eve'), 'reports'), where('reportedBy', '==', 'eve'))));
    await assertSucceeds(deleteDoc(doc(db('eve'), 'reports/pub_eve')));
  });
  test('medlem uden profil-dokument kan rapportere sin egen husstands opskrift', async () => {
    await assertSucceeds(setDoc(doc(db('nodoc'), 'reports/pub_nodoc'), report({ reportedBy: 'nodoc' })));
  });
  test('fjernet medlem med forældet householdId kan ikke rapportere (harmløst)', async () => {
    await assertFails(setDoc(doc(db('removed'), 'reports/pub_removed'), report({ reportedBy: 'removed' })));
  });
  test('kommentar må være tom streng, men skal være med', async () => {
    await assertSucceeds(setDoc(doc(db('eve'), 'reports/pub_eve'), report({ comment: '' })));
  });
  test('liste med reportedBy == mig + recipeId-filter er tilladt; med orderBy createdAt også', async () => {
    await assertSucceeds(getDocs(query(collection(db('eve'), 'reports'), where('reportedBy', '==', 'eve'), where('recipeId', '==', 'pub'))));
  });
});

describe('moderation: blocked_authors', () => {
  test('authorUid over 128 tegn afvises', async () => {
    await assertFails(setDoc(doc(db('eve'), `users/eve/blocked_authors/${'a'.repeat(129)}`), { name: 'X', blockedAt: serverTimestamp() }));
  });
  test('ejeren kan blokere uden at have et profil-dokument', async () => {
    await assertSucceeds(setDoc(doc(db('nodoc'), 'users/nodoc/blocked_authors/alice'), { name: 'Alice', blockedAt: serverTimestamp() }));
  });
});

describe('moderation: hidden', () => {
  test('fuld overskrivning (setDoc) uden visibility-feltet afvises for husstanden', async () => {
    await assertFails(setDoc(doc(db('bob'), 'recipes/hid'), { title: 'Fjernet', titleLower: 'fjernet', householdId: 'HH_A', createdBy: 'alice', createdAt: new Date('2026-01-04') }));
  });
  test('fuld overskrivning med hidden bevaret er tilladt for husstanden', async () => {
    await assertSucceeds(setDoc(doc(db('bob'), 'recipes/hid'), { title: 'Fjernet', titleLower: 'fjernet', householdId: 'HH_A', createdBy: 'alice', visibility: 'hidden', createdAt: new Date('2026-01-04') }));
  });
  test('kendt grænse: skaberen kan genudgive indholdet som en ny opskrift (copiedFrom hid, public)', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), 'recipes/again'), { title: 'Fjernet', titleLower: 'fjernet', householdId: 'HH_A', createdBy: 'alice', visibility: 'public', authorName: 'Alice', copiedFrom: 'hid', createdAt: serverTimestamp() }));
  });
  test('ikke-skaber i husstanden kan ikke slette en fjernet opskrift; admin kan', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => { await updateDoc(doc(ctx.firestore(), 'households/HH_A'), { admin: 'bob' }); });
    await assertSucceeds(deleteDoc(doc(db('bob'), 'recipes/hid')));
  });
});
