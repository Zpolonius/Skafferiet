// Tester sikkerhedsreglerne i ../firestore.rules mod Firestore-emulatoren.
//
// Kør:  cd rules_test && npm install && npm test
//
// Testdata: "Familien A" (alice = ejer, bob = medlem) og "Eves hus" (eve).
// carol har ingen husstand men har en invitation til Familien A.
// Eve spiller angriberen: hun må aldrig kunne se eller ændre Familien A's data.

const { test, before, beforeEach, after, describe } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs, query,
  where, or, writeBatch, arrayUnion, arrayRemove, deleteField, serverTimestamp,
  Timestamp,
} = require('firebase/firestore');

let env;

const DAY_MS = 24 * 60 * 60 * 1000;
const VALID_CODE = 'ABCDEFGHJK';
const EXPIRED_CODE = 'ZZZZZZZZZZ';

function db(uid) {
  return env.authenticatedContext(uid, { email: `${uid}@example.com` }).firestore();
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-skafferiet',
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8'),
    },
  });
});

after(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const s = ctx.firestore();
    await setDoc(doc(s, 'households/HH_A'), {
      name: 'Familien A', members: ['alice', 'bob'], admin: 'alice',
      adultsCount: 2, childrenCount: 2, preferences: [],
    });
    await setDoc(doc(s, 'households/HH_E'), {
      name: 'Eves hus', members: ['eve'], admin: 'eve',
    });
    await setDoc(doc(s, 'users/alice'), { householdId: 'HH_A', displayName: 'Alice', email: 'alice@example.com' });
    await setDoc(doc(s, 'users/bob'), { householdId: 'HH_A', displayName: 'Bob', email: 'bob@example.com' });
    await setDoc(doc(s, 'users/eve'), { householdId: 'HH_E', displayName: 'Eve', email: 'eve@example.com' });
    await setDoc(doc(s, 'users/carol'), { displayName: 'Carol', email: 'carol@example.com' });
    await setDoc(doc(s, 'recipes/r1'), {
      title: 'Lasagne', householdId: 'HH_A', createdBy: 'alice', calories: 500,
    });
    await setDoc(doc(s, 'recipes/global'), {
      title: 'Fælles ret', householdId: null, createdBy: 'admin', calories: 300,
    });
    await setDoc(doc(s, 'households/HH_A/grocery_list/g1'), { name: 'Mælk' });
    await setDoc(doc(s, 'invitations/inv1'), {
      fromHouseholdId: 'HH_A', fromHouseholdName: 'Familien A', fromUserName: 'Alice',
      toUserEmail: 'carol@example.com', status: 'pending',
    });
    await setDoc(doc(s, `join_codes/${VALID_CODE}`), {
      householdId: 'HH_A', createdBy: 'alice',
      expiresAt: Timestamp.fromMillis(Date.now() + DAY_MS),
    });
    await setDoc(doc(s, `join_codes/${EXPIRED_CODE}`), {
      householdId: 'HH_A', createdBy: 'alice',
      expiresAt: Timestamp.fromMillis(Date.now() - DAY_MS),
    });
  });
});

// ── Angreb der SKAL blokeres ──────────────────────────────────────────────────

describe('angreb: brugerprofiler', () => {
  test('eve kan ikke liste alle brugere (e-mails og husstands-ID)', async () => {
    await assertFails(getDocs(collection(db('eve'), 'users')));
  });

  test('eve kan ikke læse en fremmed brugers profil', async () => {
    await assertFails(getDoc(doc(db('eve'), 'users/alice')));
  });

  test('eve kan ikke pege sin profil på en fremmed husstand', async () => {
    await assertFails(updateDoc(doc(db('eve'), 'users/eve'), { householdId: 'HH_A' }));
  });

  test('ny bruger kan ikke oprette profil med fremmed husstand', async () => {
    await assertFails(setDoc(doc(db('mallory'), 'users/mallory'), { householdId: 'HH_A' }));
  });

  test('ukendte felter i profilen afvises', async () => {
    await assertFails(updateDoc(doc(db('alice'), 'users/alice'), { isAdmin: true }));
  });
});

describe('angreb: husstande', () => {
  test('eve kan ikke læse en fremmed husstand', async () => {
    await assertFails(getDoc(doc(db('eve'), 'households/HH_A')));
  });

  test('eve kan ikke melde sig ind uden bevis', async () => {
    await assertFails(updateDoc(doc(db('eve'), 'households/HH_A'), {
      members: arrayUnion('eve'),
    }));
  });

  test('eve kan ikke melde sig ind med en opdigtet kode', async () => {
    await assertFails(updateDoc(doc(db('eve'), 'households/HH_A'), {
      members: arrayUnion('eve'), joinedWith: { type: 'code', id: 'QQQQQQQQQQ' },
    }));
  });

  test('eve kan ikke melde sig ind med en udløbet kode', async () => {
    await assertFails(updateDoc(doc(db('eve'), 'households/HH_A'), {
      members: arrayUnion('eve'), joinedWith: { type: 'code', id: EXPIRED_CODE },
    }));
  });

  test('eve kan ikke bruge carols invitation', async () => {
    await assertFails(updateDoc(doc(db('eve'), 'households/HH_A'), {
      members: arrayUnion('eve'), joinedWith: { type: 'invite', id: 'inv1' },
    }));
  });

  test('eve kan ikke bruge en gyldig kode til at tilføje andre end sig selv', async () => {
    await assertFails(updateDoc(doc(db('eve'), 'households/HH_A'), {
      members: arrayUnion('eve', 'mallory'), joinedWith: { type: 'code', id: VALID_CODE },
    }));
  });

  test('eve kan ikke tage ejerskab samtidig med at hun melder sig ind', async () => {
    await assertFails(updateDoc(doc(db('eve'), 'households/HH_A'), {
      members: arrayUnion('eve'), admin: 'eve', joinedWith: { type: 'code', id: VALID_CODE },
    }));
  });

  test('bob (ikke ejer) kan ikke gøre sig selv til ejer', async () => {
    await assertFails(updateDoc(doc(db('bob'), 'households/HH_A'), { admin: 'bob' }));
  });

  test('bob (ikke ejer) kan ikke smide alice ud', async () => {
    await assertFails(updateDoc(doc(db('bob'), 'households/HH_A'), {
      members: arrayRemove('alice'),
    }));
  });

  test('bob (ikke ejer) kan ikke slette husstanden', async () => {
    await assertFails(deleteDoc(doc(db('bob'), 'households/HH_A')));
  });

  test('ejeren kan ikke tilføje andre brugere uden deres samtykke', async () => {
    await assertFails(updateDoc(doc(db('alice'), 'households/HH_A'), {
      members: arrayUnion('eve'),
    }));
  });

  test('ejeren kan ikke forlade husstanden uden at give ejerskabet videre', async () => {
    await assertFails(updateDoc(doc(db('alice'), 'households/HH_A'), {
      members: arrayRemove('alice'),
    }));
  });

  test('man kan ikke oprette en husstand med andre medlemmer end sig selv', async () => {
    await assertFails(setDoc(doc(db('eve'), 'households/HH_NEW'), {
      name: 'Fælde', members: ['eve', 'alice'], admin: 'eve',
    }));
  });

  test('husstandsnavn over 100 tegn afvises', async () => {
    await assertFails(updateDoc(doc(db('alice'), 'households/HH_A'), {
      name: 'x'.repeat(101),
    }));
  });

  test('eve kan ikke læse Familien A\'s indkøbsliste', async () => {
    await assertFails(getDocs(collection(db('eve'), 'households/HH_A/grocery_list')));
  });
});

describe('angreb: opskrifter', () => {
  test('eve kan ikke hente Familien A\'s opskrifter', async () => {
    await assertFails(getDocs(query(
      collection(db('eve'), 'recipes'), where('householdId', '==', 'HH_A'),
    )));
  });

  test('eve kan ikke publicere en "global" opskrift alle brugere ser', async () => {
    await assertFails(setDoc(doc(db('eve'), 'recipes/spam'), {
      title: 'Spam', householdId: null, createdBy: 'eve', calories: 1,
    }));
  });

  test('bob kan ikke overtage alice\'s opskrift ved at skifte createdBy', async () => {
    await assertFails(updateDoc(doc(db('bob'), 'recipes/r1'), { createdBy: 'bob' }));
  });

  test('bob kan ikke flytte en opskrift til en anden husstand', async () => {
    await assertFails(updateDoc(doc(db('bob'), 'recipes/r1'), { householdId: 'HH_E' }));
  });

  test('et tidligere medlem kan ikke længere læse opskrifterne', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'households/HH_A'), { members: ['alice'] });
    });
    // bob's profil peger stadig på HH_A, men han er ikke medlem længere.
    await assertFails(getDoc(doc(db('bob'), 'recipes/r1')));
  });
});

describe('angreb: invitationer og koder', () => {
  test('carol kan ikke ændre andet end status på sin invitation', async () => {
    await assertFails(updateDoc(doc(db('carol'), 'invitations/inv1'), {
      status: 'accepted', fromHouseholdId: 'HH_E',
    }));
  });

  test('en afvist invitation kan ikke genbruges', async () => {
    await assertSucceeds(updateDoc(doc(db('carol'), 'invitations/inv1'), { status: 'declined' }));
    await assertFails(updateDoc(doc(db('carol'), 'invitations/inv1'), { status: 'accepted' }));
  });

  test('eve kan ikke lave invitationer på vegne af Familien A', async () => {
    await assertFails(setDoc(doc(db('eve'), 'invitations/x'), {
      fromHouseholdId: 'HH_A', toUserEmail: 'mallory@example.com', status: 'pending',
    }));
  });

  test('eve kan ikke lave en invitationskode til Familien A', async () => {
    await assertFails(setDoc(doc(db('eve'), 'join_codes/EEEEEEEEEE'), {
      householdId: 'HH_A', createdBy: 'eve',
      expiresAt: Timestamp.fromMillis(Date.now() + DAY_MS),
    }));
  });

  test('ingen kan liste alle invitationskoder', async () => {
    await assertFails(getDocs(collection(db('eve'), 'join_codes')));
  });

  test('en kode kan ikke gøres gyldig i mere end 8 dage', async () => {
    await assertFails(setDoc(doc(db('alice'), 'join_codes/LLLLLLLLLL'), {
      householdId: 'HH_A', createdBy: 'alice',
      expiresAt: Timestamp.fromMillis(Date.now() + 30 * DAY_MS),
    }));
  });

  test('en kode med forkert format afvises (for kort til at være sikker)', async () => {
    await assertFails(setDoc(doc(db('alice'), 'join_codes/ABC'), {
      householdId: 'HH_A', createdBy: 'alice',
      expiresAt: Timestamp.fromMillis(Date.now() + DAY_MS),
    }));
  });
});

// ── Normale handlinger der SKAL virke ─────────────────────────────────────────

describe('normal brug', () => {
  test('alice kan læse sin egen og bob\'s profil (samme husstand)', async () => {
    await assertSucceeds(getDoc(doc(db('alice'), 'users/alice')));
    await assertSucceeds(getDoc(doc(db('alice'), 'users/bob')));
  });

  test('en ny bruger kan læse sin egen (endnu ikke oprettede) profil', async () => {
    await assertSucceeds(getDoc(doc(db('newbie'), 'users/newbie')));
  });

  test('alice kan opdatere sit profilbillede', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), 'users/alice'),
      { photoURL: 'https://example.com/a.jpg' }, { merge: true }));
  });

  test('profilbillede kan opdateres selvom brugeren er fjernet fra husstanden', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'households/HH_A'), { members: ['alice'] });
    });
    await assertSucceeds(updateDoc(doc(db('bob'), 'users/bob'), { photoURL: 'x' }));
  });

  test('ny bruger opretter husstand og peger sin profil på den', async () => {
    const s = db('newbie');
    await assertSucceeds(setDoc(doc(s, 'users/newbie'), {
      displayName: 'Ny', email: 'newbie@example.com', hasCompletedOnboarding: false,
    }, { merge: true }));
    await assertSucceeds(setDoc(doc(s, 'households/SK-NEWBIE1'), {
      name: 'Nyt Skafferi', members: ['newbie'], admin: 'newbie',
      adultsCount: 2, childrenCount: 2, preferences: [], createdAt: serverTimestamp(),
    }));
    await assertSucceeds(setDoc(doc(s, 'users/newbie'), { householdId: 'SK-NEWBIE1' }, { merge: true }));
  });

  test('medlemmer kan læse husstanden og ændre navn og præferencer', async () => {
    await assertSucceeds(getDoc(doc(db('bob'), 'households/HH_A')));
    await assertSucceeds(updateDoc(doc(db('bob'), 'households/HH_A'), { name: 'Nyt navn' }));
    await assertSucceeds(setDoc(doc(db('bob'), 'households/HH_A'), {
      name: 'Familien A', adultsCount: 3, childrenCount: 1, preferences: ['Grønt & Sundt'],
    }, { merge: true }));
  });

  test('bob kan forlade husstanden', async () => {
    const s = db('bob');
    const batch = writeBatch(s);
    batch.update(doc(s, 'households/HH_A'), { members: arrayRemove('bob') });
    batch.update(doc(s, 'users/bob'), { householdId: deleteField() });
    await assertSucceeds(batch.commit());
  });

  test('alice (ejer) kan forlade husstanden ved at give ejerskabet til bob', async () => {
    await assertSucceeds(updateDoc(doc(db('alice'), 'households/HH_A'), {
      members: arrayRemove('alice'), admin: 'bob',
    }));
  });

  test('alice (ejer) kan fjerne bob', async () => {
    await assertSucceeds(updateDoc(doc(db('alice'), 'households/HH_A'), {
      members: arrayRemove('bob'),
    }));
  });

  test('carol accepterer sin invitation (ét samlet batch)', async () => {
    const s = db('carol');
    const batch = writeBatch(s);
    batch.update(doc(s, 'households/HH_A'), {
      members: arrayUnion('carol'), joinedWith: { type: 'invite', id: 'inv1' },
    });
    batch.set(doc(s, 'users/carol'), { householdId: 'HH_A' }, { merge: true });
    batch.update(doc(s, 'invitations/inv1'), { status: 'accepted' });
    await assertSucceeds(batch.commit());
    await assertSucceeds(getDocs(collection(s, 'households/HH_A/grocery_list')));
  });

  test('carol melder sig ind med en gyldig kode', async () => {
    const s = db('carol');
    await assertSucceeds(getDoc(doc(s, `join_codes/${VALID_CODE}`)));
    const batch = writeBatch(s);
    batch.update(doc(s, 'households/HH_A'), {
      members: arrayUnion('carol'), joinedWith: { type: 'code', id: VALID_CODE },
    });
    batch.set(doc(s, 'users/carol'), { householdId: 'HH_A' }, { merge: true });
    await assertSucceeds(batch.commit());
  });

  test('eve skifter fra sin egen husstand til Familien A med en kode', async () => {
    const s = db('eve');
    const batch = writeBatch(s);
    // Eve er eneste medlem, så husstanden står tom tilbage.
    batch.update(doc(s, 'households/HH_E'), { members: arrayRemove('eve') });
    batch.update(doc(s, 'households/HH_A'), {
      members: arrayUnion('eve'), joinedWith: { type: 'code', id: VALID_CODE },
    });
    batch.set(doc(s, 'users/eve'), { householdId: 'HH_A' }, { merge: true });
    await assertSucceeds(batch.commit());
  });

  test('alice kan lave en invitationskode', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), 'join_codes/MNPQRSTUVW'), {
      householdId: 'HH_A', createdBy: 'alice', createdAt: serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + 7 * DAY_MS),
    }));
  });

  test('alice kan sende og carol kan se en invitation', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), 'invitations/inv2'), {
      fromHouseholdId: 'HH_A', fromHouseholdName: 'Familien A', fromUserName: 'Alice',
      toUserEmail: 'carol@example.com', status: 'pending', createdAt: serverTimestamp(),
    }));
    await assertSucceeds(getDocs(query(
      collection(db('carol'), 'invitations'),
      where('toUserEmail', '==', 'carol@example.com'),
      where('status', '==', 'pending'),
    )));
  });

  test('alice henter husstandens + globale opskrifter (appens forespørgsel)', async () => {
    await assertSucceeds(getDocs(query(
      collection(db('alice'), 'recipes'),
      or(where('householdId', '==', 'HH_A'), where('householdId', '==', null)),
    )));
  });

  test('alice opretter, bob redigerer og alice sletter en opskrift', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), 'recipes/r2'), {
      title: 'Suppe', householdId: 'HH_A', createdBy: 'alice', calories: 200,
      createdAt: serverTimestamp(),
    }));
    await assertSucceeds(updateDoc(doc(db('bob'), 'recipes/r2'), { title: 'Bedre suppe' }));
    await assertFails(deleteDoc(doc(db('bob'), 'recipes/r2')));
    await assertSucceeds(deleteDoc(doc(db('alice'), 'recipes/r2')));
  });

  test('medlemmer kan bruge indkøbslisten', async () => {
    await assertSucceeds(setDoc(doc(db('bob'), 'households/HH_A/grocery_list/g2'), { name: 'Brød' }));
    await assertSucceeds(getDocs(collection(db('alice'), 'households/HH_A/grocery_list')));
  });
});

// ── Fast genkøb (fra main, #13) mod de strammere husstandsregler ──────────────
// Spejler RecurringItemsRepository.setShoppingWeekday og create.

describe('fast genkøb', () => {
  const item = (uid) => ({
    name: 'Mælk', quantity: '2', unit: 'l', category: 'Mejeri',
    frequency: 'weekly', intervalWeeks: 1, nextDate: '2026-10-05',
    createdBy: uid, createdAt: Date.now(),
  });

  test('et medlem sætter indkøbsdag og flytter varernes datoer i ét batch', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'households/HH_A/recurring_items/r1'), item('alice'));
    });
    const s = db('bob');
    const batch = writeBatch(s);
    batch.update(doc(s, 'households/HH_A'), { shoppingWeekday: 4 });
    batch.update(doc(s, 'households/HH_A/recurring_items/r1'), { nextDate: '2026-10-08' });
    await assertSucceeds(batch.commit());
  });

  test('ugyldig indkøbsdag afvises', async () => {
    await assertFails(updateDoc(doc(db('bob'), 'households/HH_A'), { shoppingWeekday: 8 }));
    await assertFails(updateDoc(doc(db('bob'), 'households/HH_A'), { shoppingWeekday: 'mandag' }));
  });

  test('eve kan ikke sætte Familien A\'s indkøbsdag', async () => {
    await assertFails(updateDoc(doc(db('eve'), 'households/HH_A'), { shoppingWeekday: 2 }));
  });

  test('medlemmer opretter genkøbs-varer; eve kan hverken læse eller oprette', async () => {
    await assertSucceeds(setDoc(doc(db('bob'), 'households/HH_A/recurring_items/r2'), item('bob')));
    await assertFails(getDocs(collection(db('eve'), 'households/HH_A/recurring_items')));
    await assertFails(setDoc(doc(db('eve'), 'households/HH_A/recurring_items/r3'), item('eve')));
  });

  test('en ny husstand må oprettes med en indkøbsdag', async () => {
    await assertSucceeds(setDoc(doc(db('carol'), 'households/SK-CAROL'), {
      name: 'Carols', members: ['carol'], admin: 'carol', shoppingWeekday: 5,
    }));
  });
});

