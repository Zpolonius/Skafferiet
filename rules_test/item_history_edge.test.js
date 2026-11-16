// Varehistorik (#28): historikken skrives i samme batch som varen, så intet
// input som ItemHistoryWriter accepterer må få reglerne til at afvise den –
// ellers forsvinder selve varen også.
const { test, before, beforeEach, after, describe } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, updateDoc, writeBatch, serverTimestamp, increment, Timestamp } = require('firebase/firestore');

let env;
const db = (uid) => env.authenticatedContext(uid).firestore();
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-skafferiet-history-edge',
    firestore: { rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') },
  });
});
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'households/HH'), { name: 'H', members: ['bob'], admin: 'bob' });
    await setDoc(doc(ctx.firestore(), 'users/bob'), { householdId: 'HH' });
  });
});
// Det ItemHistoryWriter.entry sender (mirror).
const w = (name, category, unit = null, quantity = null) => ({
  name, category, unit, quantity, useCount: increment(1), lastUsed: serverTimestamp(),
});
async function commitWithGrocery(key, data) {
  const s = db('bob');
  const b = writeBatch(s);
  b.set(doc(s, 'households/HH/grocery_list/x' + Math.random()), { name: data.name });
  b.set(doc(s, `households/HH/item_history/${key}`), data, { merge: true });
  return b.commit();
}

describe('probe: tegnlængder (Dart .length = UTF-16)', () => {
  test('80 x æ (160 UTF-8-bytes) accepteres', async () => {
    const n = 'æ'.repeat(80); if (n.length !== 80) throw 1;
    await assertSucceeds(commitWithGrocery('k1', w(n, 'ø'.repeat(40), 'å'.repeat(20), 'ø'.repeat(10))));
  });
  test('40 emoji (80 UTF-16-enheder) accepteres', async () => {
    const n = '🥩'.repeat(40); if (n.length !== 80) throw 1;
    await assertSucceeds(commitWithGrocery('k2', w(n, '🥩'.repeat(20), '🥩'.repeat(10), '🥩'.repeat(5))));
  });
  test('kombinerende tegn (e + U+0301) x 40 = 80 UTF-16', async () => {
    const n = 'é'.repeat(40); if (n.length !== 80) throw 1;
    await assertSucceeds(commitWithGrocery('k3', w(n, 'Kød')));
  });
});

describe('probe: nøgler', () => {
  for (const key of ['1∕2 liter mælk', '~.', '~..', '~__x__', '🥩 kød', 'a.b', 'æble#1', 'x?y', '[a]', ' ', 'a\\b']) {
    test(`id "${key}"`, async () => { await assertSucceeds(commitWithGrocery(key, w('X', 'Kød'))); });
  }
});

describe('probe: merge og increment', () => {
  test('samme vare to gange i ét batch (to opskrifter med løg) -> useCount 2', async () => {
    const s = db('bob');
    const b = writeBatch(s);
    b.set(doc(s, 'households/HH/grocery_list/a'), { name: 'Løg' });
    b.set(doc(s, 'households/HH/item_history/løg'), w('Løg', 'Grønt', 'stk', '2'), { merge: true });
    b.set(doc(s, 'households/HH/grocery_list/b'), { name: 'løg' });
    b.set(doc(s, 'households/HH/item_history/løg'), w('løg', 'Grønt', null, '1.0'), { merge: true });
    await assertSucceeds(b.commit());
    await env.withSecurityRulesDisabled(async (ctx) => {
      const d = (await getDoc(doc(ctx.firestore(), 'households/HH/item_history/løg'))).data();
      if (d.useCount !== 2 || d.unit !== null || d.name !== 'løg') throw new Error(JSON.stringify(d));
    });
  });
  test('stale enhed: senere uden enhed nulstiller unit', async () => {
    await assertSucceeds(commitWithGrocery('salt', w('Salt', 'Krydderier', 'g', '100')));
    await assertSucceeds(commitWithGrocery('salt', w('Salt', 'Krydderier')));
    await env.withSecurityRulesDisabled(async (ctx) => {
      const d = (await getDoc(doc(ctx.firestore(), 'households/HH/item_history/salt'))).data();
      if (d.unit !== null || d.quantity !== null || d.useCount !== 2) throw new Error(JSON.stringify(d));
    });
  });
  test('en ældre post med et ekstra felt blokerer ikke for at tilføje varen', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'households/HH/item_history/legacy'), { name: 'L', category: 'K', useCount: 1, extra: 1 });
    });
    await assertSucceeds(commitWithGrocery('legacy', w('L', 'K')));
  });
  test('et medlem kan ikke tilføje et nyt ukendt felt ved update', async () => {
    await assertSucceeds(commitWithGrocery('ny', w('N', 'K')));
    await assertFails(commitWithGrocery('ny', { ...w('N', 'K'), extra: 1 }));
  });
  test('en meget høj useCount vælter ikke batchet med varen', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'households/HH/item_history/max'), { name: 'M', category: 'K', useCount: 1000000, lastUsed: new Date() });
    });
    await assertSucceeds(commitWithGrocery('max', w('M', 'K')));
  });
  test('negativ useCount afvises', async () => {
    const s = db('bob');
    await assertFails(setDoc(doc(s, 'households/HH/item_history/neg'), { name: 'N', category: 'K', useCount: -1, lastUsed: serverTimestamp() }));
  });
});

// Fortryd af "Fjern forslag" (#47): ItemHistoryRepository.restore skriver
// posten tilbage med den ORIGINALE lastUsed (et klient-tidsstempel).
describe('Fortryd: genskab en fjernet historikpost', () => {
  const orig = new Date('2026-05-01T12:00:00Z');
  test('create med de seks felter, null unit/quantity og originalt tidsstempel', async () => {
    const s = db('bob');
    await assertSucceeds(setDoc(doc(s, 'households/HH/item_history/kaffe'), {
      name: 'Kaffe', category: 'Kolonial', unit: null, quantity: null, useCount: 7, lastUsed: Timestamp.fromDate(orig),
    }));
    const d = (await getDoc(doc(s, 'households/HH/item_history/kaffe'))).data();
    if (d.useCount !== 7 || d.lastUsed.toMillis() !== orig.getTime()) throw new Error('forkert indhold');
  });
  test('create med ekstra gammelt felt afvises (derfor skrives kun de seks felter)', async () => {
    await assertFails(setDoc(doc(db('bob'), 'households/HH/item_history/kaffe'), {
      name: 'Kaffe', category: 'Kolonial', unit: null, quantity: null, useCount: 7, lastUsed: Timestamp.fromDate(orig), legacy: 'x',
    }));
  });
  test('update af en nyere post: kun useCount tælles op (increment) accepteres', async () => {
    const s = db('bob');
    await setDoc(doc(s, 'households/HH/item_history/kaffe'), {
      name: 'Kaffe', category: 'Kolonial', unit: 'g', quantity: '500', useCount: 1, lastUsed: Timestamp.fromDate(new Date('2026-06-01')),
    });
    await assertSucceeds(updateDoc(doc(s, 'households/HH/item_history/kaffe'), { useCount: increment(7) }));
    const d = (await getDoc(doc(s, 'households/HH/item_history/kaffe'))).data();
    if (d.useCount !== 8 || d.lastUsed.toMillis() !== new Date('2026-06-01').getTime()) throw new Error('forkert indhold');
  });
  test('en ikke-medlem kan ikke genskabe', async () => {
    await assertFails(setDoc(doc(db('eve'), 'households/HH/item_history/kaffe'), {
      name: 'Kaffe', category: 'Kolonial', unit: null, quantity: null, useCount: 7, lastUsed: Timestamp.fromDate(orig),
    }));
  });
});
