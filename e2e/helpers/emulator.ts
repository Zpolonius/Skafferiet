// Hjælpere der taler direkte med Firebase-emulatorernes REST-API'er, så testene
// kan nulstille og seede data uden at gå gennem appen eller Firebase SDK'et.

export const PROJECT_ID = 'demo-skafferiet';
export const EMULATOR_HOST = process.env.EMULATOR_HOST ?? 'localhost';
const FIRESTORE = `http://${EMULATOR_HOST}:8080`;
const AUTH = `http://${EMULATOR_HOST}:9099`;
const DOCS = `${FIRESTORE}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
// "Bearer owner" omgår firestore.rules (kun til seeding, aldrig i appen).
const OWNER = { Authorization: 'Bearer owner', 'Content-Type': 'application/json' };

async function ok(res: Response, what: string): Promise<Response> {
  if (!res.ok) throw new Error(`${what} fejlede: ${res.status} ${await res.text()}`);
  return res;
}

/** Sletter alle Firestore-dokumenter og alle Auth-brugere. */
export async function resetEmulators(): Promise<void> {
  await ok(
    await fetch(`${FIRESTORE}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`, {
      method: 'DELETE',
    }),
    'Nulstilling af Firestore',
  );
  await ok(
    await fetch(`${AUTH}/emulator/v1/projects/${PROJECT_ID}/accounts`, { method: 'DELETE' }),
    'Nulstilling af Auth',
  );
}

export type TestUser = { uid: string; email: string; password: string; name: string };

/** Opretter en e-mail/adgangskode-bruger i Auth-emulatoren. */
export async function createAuthUser(
  email: string,
  password: string,
  name: string,
): Promise<TestUser> {
  const res = await ok(
    await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, displayName: name, returnSecureToken: true }),
    }),
    'Oprettelse af bruger',
  );
  const body = (await res.json()) as { localId: string };
  return { uid: body.localId, email, password, name };
}

// ── Firestore REST: konvertering mellem JS-værdier og typede felter ──────────

type FsValue = Record<string, unknown>;

export function toFsValue(v: unknown): FsValue {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') {
    return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  }
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toFsValue) } };
  if (typeof v === 'object') return { mapValue: { fields: toFsFields(v as Record<string, unknown>) } };
  throw new Error(`Kan ikke konvertere ${String(v)} til Firestore-værdi`);
}

function toFsFields(obj: Record<string, unknown>): Record<string, FsValue> {
  return Object.fromEntries(Object.entries(obj).map(([k, v]) => [k, toFsValue(v)]));
}

/** Skriver (erstatter) dokumentet `path`, fx "households/abc". */
export async function setDoc(path: string, data: Record<string, unknown>): Promise<void> {
  await ok(
    await fetch(`${DOCS}/${path}`, {
      method: 'PATCH',
      headers: OWNER,
      body: JSON.stringify({ fields: toFsFields(data) }),
    }),
    `Skrivning af ${path}`,
  );
}

/**
 * Sætter kun de angivne felter (på øverste niveau) og lader resten stå,
 * ligesom `set(..., merge: true)`. Bruges til at ændre data mens appen kører.
 */
export async function patchDoc(path: string, data: Record<string, unknown>): Promise<void> {
  const mask = Object.keys(data)
    .map((k) => `updateMask.fieldPaths=${encodeURIComponent('`' + k + '`')}`)
    .join('&');
  await ok(
    await fetch(`${DOCS}/${path}?${mask}`, {
      method: 'PATCH',
      headers: OWNER,
      body: JSON.stringify({ fields: toFsFields(data) }),
    }),
    `Opdatering af ${path}`,
  );
}

// ── Seed ─────────────────────────────────────────────────────────────────────

export type SeededHousehold = TestUser & { householdId: string };

let counter = 0;

/**
 * Opretter en bruger + husstand, så brugeren efter login lander direkte på
 * hjemskærmen (ingen onboarding). Felterne følger HouseholdNotifier og
 * redirect-logikken i lib/main.dart:
 *  - users/{uid}: householdId + hasCompletedOnboarding
 *  - households/{id}: name, members, admin (+ antal/præferencer)
 */
export async function seedHousehold(
  opts: { email?: string; password?: string; name?: string; householdName?: string } = {},
): Promise<SeededHousehold> {
  const n = ++counter;
  const email = opts.email ?? `test${n}@example.com`;
  const password = opts.password ?? 'test1234';
  const name = opts.name ?? 'Testbruger';
  const user = await createAuthUser(email, password, name);
  const householdId = `hh${n}x${Date.now().toString(36)}`;

  await setDoc(`households/${householdId}`, {
    name: opts.householdName ?? 'Testens Skafferi',
    members: [user.uid],
    admin: user.uid,
    adultsCount: 2,
    childrenCount: 2,
    preferences: [],
    createdAt: new Date(),
  });
  await setDoc(`users/${user.uid}`, {
    displayName: name,
    email,
    householdId,
    hasCompletedOnboarding: true,
  });
  return { ...user, householdId };
}

export type SeedRecipe = {
  id: string;
  title: string;
  householdId: string;
  createdBy: string;
  category?: 'morgenmad' | 'frokost' | 'aftensmad' | 'snack';
  calories?: number;
  /** Ingrediensnavne (resten af felterne udfyldes med gyldige standardværdier). */
  ingredients?: string[];
  /** Delt med alle brugere (fanen Fællesskab). Standard: kun husstanden. */
  visibility?: 'household' | 'public';
  /** Skaberens fornavn (kun på delte opskrifter). */
  authorName?: string;
  createdAt?: Date;
};

/** Skriver `recipes/{id}` med felter der er gyldige iflg. firestore.rules. */
export async function seedRecipe(r: SeedRecipe): Promise<void> {
  await setDoc(`recipes/${r.id}`, {
    title: r.title,
    titleLower: r.title.toLowerCase(),
    visibility: r.visibility ?? 'household',
    ...(r.authorName ? { authorName: r.authorName } : {}),
    createdAt: r.createdAt ?? new Date(),
    category: `RecipeCategory.${r.category ?? 'aftensmad'}`,
    calories: r.calories ?? 450,
    time: '30 min',
    ingredients: (r.ingredients ?? []).map((name) => ({ name, quantity: 1, unit: 'stk', category: 'Andet' })),
    instructions: ['Lav maden.'],
    householdId: r.householdId,
    createdBy: r.createdBy,
  });
}

// ── Madplan ──────────────────────────────────────────────────────────────────

export const DANISH_WEEKDAYS = ['Mandag', 'Tirsdag', 'Onsdag', 'Torsdag', 'Fredag', 'Lørdag', 'Søndag'];

/** Dansk ugedagsnavn som appen bruger som nøgle (Mandag … Søndag). */
export function danishWeekday(date: Date = new Date()): string {
  return DANISH_WEEKDAYS[(date.getDay() + 6) % 7];
}

/** Mandagen i ugen som `yyyy-MM-dd` — præcis som MealPlanNotifier._getWeekId. */
export function weekId(date: Date = new Date()): string {
  const monday = new Date(date.getFullYear(), date.getMonth(), date.getDate() - ((date.getDay() + 6) % 7));
  const p = (x: number) => String(x).padStart(2, '0');
  return `${monday.getFullYear()}-${p(monday.getMonth() + 1)}-${p(monday.getDate())}`;
}

export type SlotKey = 'breakfast' | 'lunch' | 'dinner' | 'snack';
export type SlotValue = { recipeId?: string | null; directEntry?: string | null };

/**
 * Skriver madplanen for ugen med `date` (standard: i dag).
 * `days` er fx { Mandag: { dinner: { recipeId: 'r1' } } }.
 * Erstatter hele dokumentet.
 */
export async function seedMealPlan(
  householdId: string,
  days: Record<string, Partial<Record<SlotKey, SlotValue>>>,
  date: Date = new Date(),
): Promise<string> {
  const id = weekId(date);
  const normalized = Object.fromEntries(
    Object.entries(days).map(([day, slots]) => [
      day,
      Object.fromEntries(
        Object.entries(slots).map(([slot, v]) => [
          slot,
          { recipeId: v?.recipeId ?? null, directEntry: v?.directEntry ?? null },
        ]),
      ),
    ]),
  );
  await setDoc(`households/${householdId}/meal_plans/${id}`, { days: normalized });
  return id;
}

/** Ændrer ét måltid i en eksisterende madplan (øvrige dage/måltider bevares). */
export async function updateMealSlot(
  householdId: string,
  day: string,
  slot: SlotKey,
  value: SlotValue,
  date: Date = new Date(),
): Promise<void> {
  const id = weekId(date);
  // Nested felt-sti: days.<Dag>.<slot>
  // Dagsnavne som 'Søndag' skal i backticks for at være en gyldig feltsti.
  const fieldPath = `days.\`${day}\`.${slot}`;
  await ok(
    await fetch(
      `${DOCS}/households/${householdId}/meal_plans/${id}?updateMask.fieldPaths=${encodeURIComponent(fieldPath)}`,
      {
        method: 'PATCH',
        headers: OWNER,
        body: JSON.stringify({
          fields: {
            days: {
              mapValue: {
                fields: {
                  [day]: {
                    mapValue: {
                      fields: {
                        [slot]: toFsValue({
                          recipeId: value.recipeId ?? null,
                          directEntry: value.directEntry ?? null,
                        }),
                      },
                    },
                  },
                },
              },
            },
          },
        }),
      },
    ),
    'Opdatering af måltid',
  );
}

/**
 * Læser ét måltid direkte fra Firestore (omgår reglerne). Returnerer null for
 * felter der ikke er sat, og `undefined` hvis dokumentet/dagen/måltidet ikke
 * findes.
 */
export async function readMealSlot(
  householdId: string,
  day: string,
  slot: SlotKey,
  date: Date = new Date(),
): Promise<{ recipeId: string | null; directEntry: string | null } | undefined> {
  const res = await fetch(`${DOCS}/households/${householdId}/meal_plans/${weekId(date)}`, {
    headers: OWNER,
  });
  if (res.status === 404) return undefined;
  const doc: any = await (await ok(res, 'Læsning af madplan')).json();
  const fields = doc.fields?.days?.mapValue?.fields?.[day]?.mapValue?.fields?.[slot]?.mapValue?.fields;
  if (!fields) return undefined;
  const str = (v: any): string | null => (v && 'stringValue' in v ? v.stringValue : null);
  return { recipeId: str(fields.recipeId), directEntry: str(fields.directEntry) };
}

function fromFsValue(v: any): unknown {
  if (!v) return null;
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('arrayValue' in v) return (v.arrayValue.values ?? []).map(fromFsValue);
  if ('mapValue' in v) {
    return Object.fromEntries(Object.entries(v.mapValue.fields ?? {}).map(([k, x]) => [k, fromFsValue(x)]));
  }
  return null;
}

/**
 * Læser alle dokumenter i en collection direkte fra Firestore (omgår
 * reglerne), som { id, felter på øverste niveau }. Understøtter strenge,
 * tal, booleans, tidsstempler, lister og maps.
 */
export async function readCollection(path: string): Promise<Array<Record<string, unknown>>> {
  const res = await fetch(`${DOCS}/${path}?pageSize=300`, { headers: OWNER });
  const body: any = await (await ok(res, `Læsning af ${path}`)).json();
  return (body.documents ?? []).map((d: any) => ({
    id: String(d.name).split('/').pop(),
    ...Object.fromEntries(Object.entries(d.fields ?? {}).map(([k, v]) => [k, fromFsValue(v)])),
  }));
}
