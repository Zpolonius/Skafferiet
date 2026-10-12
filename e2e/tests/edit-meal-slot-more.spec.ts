import { test, expect, flt } from '../helpers/fixtures';

// QA-supplement til edit-meal-slot.spec.ts (#36): skrivninger gennem reglerne
// for slettet opskrift og eget måltid, SnackBar over bundmenuen og Se opskrift.
import {
  danishWeekday,
  readMealSlot,
  seedHousehold,
  seedMealPlan,
  seedRecipe,
} from '../helpers/emulator';
import { login, openTab, selectPlanDay, typeInto } from '../helpers/app';

async function setup(page: import('@playwright/test').Page, dinner: { recipeId?: string; directEntry?: string }) {
  const now = new Date();
  await page.clock.setFixedTime(now);
  const weekday = danishWeekday(now);
  const user = await seedHousehold();
  await seedRecipe({ id: 'r-lasagne', title: 'Lasagne e2e', householdId: user.householdId, createdBy: user.uid });
  await seedMealPlan(user.householdId, { [weekday]: { dinner } }, now);
  await login(page, user);
  await openTab(page, 'Madplan');
  await selectPlanDay(page, weekday, now);
  return { now, weekday, user };
}

test('slettet opskrift fjern + fortryd bevarer id; SnackBar over bundmenu', async ({ page }) => {
  const { now, weekday, user } = await setup(page, { recipeId: 'r-gone' });
  await flt(page, 'Opskriften findes ikke længere').click();
  await expect(page.getByRole('button', { name: 'Se opskrift' })).toHaveCount(0);
  await page.getByRole('button', { name: 'Fjern fra madplanen' }).click();
  const fortryd = page.getByRole('button', { name: 'Fortryd' });
  await expect(fortryd).toBeVisible();
  await expect.poll(() => readMealSlot(user.householdId, weekday, 'dinner', now)).toEqual({ recipeId: null, directEntry: null });

  // SnackBar vs bundmenu: bundmenuens knapper skal ligge under SnackBar'ens bund.
  const snack = await fortryd.boundingBox();
  // Hjem-knappen er hævet over baren; Madplan-knappen ligger i selve baren.
  const nav = await page.getByRole('button', { name: 'Madplan' }).first().boundingBox();
  expect(snack!.y + snack!.height).toBeLessThanOrEqual(nav!.y);

  await fortryd.click();
  await expect(flt(page, 'Opskriften findes ikke længere')).toBeVisible();
  await expect.poll(() => readMealSlot(user.householdId, weekday, 'dinner', now)).toEqual({ recipeId: 'r-gone', directEntry: null });
});

test('skift til eget måltid gennem reglerne', async ({ page }) => {
  const { now, weekday, user } = await setup(page, { recipeId: 'r-lasagne' });
  await flt(page, 'Lasagne e2e').click();
  await page.getByRole('button', { name: 'Skift', exact: true }).click();
  await page.getByRole('radio', { name: 'Eget måltid' }).click();
  await typeInto(page, 'Hvad skal I spise?', 'Rugbrød æøå');
  await page.getByRole('button', { name: 'Gem', exact: true }).click();
  await expect(flt(page, 'Rugbrød æøå')).toBeVisible();
  await expect.poll(() => readMealSlot(user.householdId, weekday, 'dinner', now)).toEqual({ recipeId: null, directEntry: 'Rugbrød æøå' });
});

test('Se opskrift åbner opskriften, og tilbage lander i madplanen', async ({ page }) => {
  const { weekday } = await setup(page, { recipeId: 'r-lasagne' });
  await flt(page, 'Lasagne e2e').click();
  await page.getByRole('button', { name: 'Se opskrift' }).click();
  await expect(page.getByRole('button', { name: 'Fjern fra madplanen' })).toHaveCount(0);
  await expect(flt(page, 'Ingredienser').first()).toBeVisible();
  await expect(flt(page, `${weekday}ens madplan`)).toHaveCount(0);
  await page.goBack();
  await expect(flt(page, `${weekday}ens madplan`)).toBeVisible();
});

test('langsom forbindelse: Fortryd før sletningen er bekræftet gendanner måltidet', async ({ page }) => {
  const { now, weekday, user } = await setup(page, { recipeId: 'r-lasagne' });
  // Hold Firestores skrive-kanal tilbage i 4 s: sletningen er lokalt synlig, men
  // serveren har ikke bekræftet den, når brugeren trykker Fortryd.
  const delayWrites = async (route: import('@playwright/test').Route) => {
    if (route.request().method() === 'POST') await new Promise((r) => setTimeout(r, 4000));
    // Firestore kan selv have afbrudt anmodningen under ventetiden.
    await route.continue().catch(() => {});
  };
  await page.route('**/google.firestore.v1.Firestore/Write/channel**', delayWrites);

  await flt(page, 'Lasagne e2e').first().click();
  await page.getByRole('button', { name: 'Fjern fra madplanen' }).click();
  await page.getByRole('button', { name: 'Fortryd' }).click();
  // Sletningen var stadig ikke nået frem til serveren, da Fortryd blev trykket.
  expect(await readMealSlot(user.householdId, weekday, 'dinner', now)).toEqual({ recipeId: 'r-lasagne', directEntry: null });

  await page.unroute('**/google.firestore.v1.Firestore/Write/channel**', delayWrites, { behavior: 'ignoreErrors' });
  await expect.poll(() => readMealSlot(user.householdId, weekday, 'dinner', now), { timeout: 20_000 })
    .toEqual({ recipeId: 'r-lasagne', directEntry: null });
  // Ingen falsk konflikt, og måltidet står i appen.
  await expect(flt(page, 'ændret i mellemtiden')).toHaveCount(0);
  await expect(flt(page, 'Lasagne e2e').first()).toBeVisible();
  // Bliver stående, når alle skrivninger er nået frem.
  await page.waitForTimeout(3000);
  expect(await readMealSlot(user.householdId, weekday, 'dinner', now)).toEqual({ recipeId: 'r-lasagne', directEntry: null });
});
