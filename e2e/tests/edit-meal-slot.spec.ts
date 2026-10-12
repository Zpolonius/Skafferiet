import { test, expect, flt } from '../helpers/fixtures';
import {
  danishWeekday,
  readMealSlot,
  seedHousehold,
  seedMealPlan,
  seedRecipe,
  updateMealSlot,
} from '../helpers/emulator';
import { login, openTab, selectPlanDay } from '../helpers/app';

/**
 * Disse tests er de første hvor APPEN selv skriver gennem de rigtige
 * firestore.rules (seed-hjælperne omgår dem). Pinner uret som de øvrige
 * madplanstests.
 */
async function pinClock(page: import('@playwright/test').Page): Promise<{ now: Date; weekday: string }> {
  const now = new Date();
  await page.clock.setFixedTime(now);
  return { now, weekday: danishWeekday(now) };
}

test.describe('redigér måltid i madplanen (#36)', () => {
  test('fjern måltid og fortryd gendanner opskriften i appen og i Firestore', async ({ page }) => {
    const { now, weekday } = await pinClock(page);
    const user = await seedHousehold();
    await seedRecipe({ id: 'r-lasagne', title: 'Lasagne e2e', householdId: user.householdId, createdBy: user.uid });
    await seedMealPlan(user.householdId, { [weekday]: { dinner: { recipeId: 'r-lasagne' } } }, now);

    await login(page, user);
    await openTab(page, 'Madplan');
    await selectPlanDay(page, weekday, now);
    await expect(flt(page, 'Lasagne e2e')).toBeVisible();

    await flt(page, 'Lasagne e2e').click();
    await expect(page.getByRole('button', { name: 'Fjern fra madplanen' })).toBeVisible();
    await page.getByRole('button', { name: 'Fjern fra madplanen' }).click();

    // Tomt i appen (arket er lukket) og i Firestore.
    await expect(flt(page, 'Tilføj aftensmad')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Fortryd' })).toBeVisible();
    await expect
      .poll(() => readMealSlot(user.householdId, weekday, 'dinner', now))
      .toEqual({ recipeId: null, directEntry: null });

    await page.getByRole('button', { name: 'Fortryd' }).click();
    await expect(flt(page, 'Lasagne e2e')).toBeVisible();
    await expect
      .poll(() => readMealSlot(user.householdId, weekday, 'dinner', now))
      .toEqual({ recipeId: 'r-lasagne', directEntry: null });
  });

  test('skift måltid til en anden opskrift', async ({ page }) => {
    const { now, weekday } = await pinClock(page);
    const user = await seedHousehold();
    await seedRecipe({ id: 'r-lasagne', title: 'Lasagne e2e', householdId: user.householdId, createdBy: user.uid });
    await seedRecipe({ id: 'r-pasta', title: 'Pasta pesto e2e', householdId: user.householdId, createdBy: user.uid });
    await seedMealPlan(user.householdId, { [weekday]: { dinner: { recipeId: 'r-lasagne' } } }, now);

    await login(page, user);
    await openTab(page, 'Madplan');
    await selectPlanDay(page, weekday, now);
    await flt(page, 'Lasagne e2e').click();
    await page.getByRole('button', { name: 'Skift', exact: true }).click();
    await page.getByRole('button', { name: /Pasta pesto e2e/ }).click();

    await expect(page.getByRole('button', { name: 'Fjern fra madplanen' })).toHaveCount(0);
    await expect(flt(page, 'Pasta pesto e2e')).toBeVisible();
    await expect
      .poll(() => readMealSlot(user.householdId, weekday, 'dinner', now))
      .toEqual({ recipeId: 'r-pasta', directEntry: null });
  });

  test('tom aftensmad: Søg opskrifter -> vælg opskrift gemmes i Firestore', async ({ page }) => {
    const { now, weekday } = await pinClock(page);
    const user = await seedHousehold();
    await seedRecipe({ id: 'r-pasta', title: 'Pasta pesto e2e', householdId: user.householdId, createdBy: user.uid });

    await login(page, user);
    await openTab(page, 'Madplan');
    await selectPlanDay(page, weekday, now);
    await flt(page, 'Tilføj aftensmad').click();
    await flt(page, 'Søg opskrifter').click();
    await page.getByRole('button', { name: /Pasta pesto e2e/ }).click();

    await expect(flt(page, 'Pasta pesto e2e')).toBeVisible();
    await expect(flt(page, 'Søg opskrifter')).toHaveCount(0);
    await expect
      .poll(() => readMealSlot(user.householdId, weekday, 'dinner', now))
      .toEqual({ recipeId: 'r-pasta', directEntry: null });
  });

  test('Fortryd efter at et andet medlem har fyldt pladsen overskriver ikke', async ({ page }) => {
    const { now, weekday } = await pinClock(page);
    const user = await seedHousehold();
    await seedRecipe({ id: 'r-lasagne', title: 'Lasagne e2e', householdId: user.householdId, createdBy: user.uid });
    await seedMealPlan(user.householdId, { [weekday]: { dinner: { recipeId: 'r-lasagne' } } }, now);

    await login(page, user);
    await openTab(page, 'Madplan');
    await selectPlanDay(page, weekday, now);
    await flt(page, 'Lasagne e2e').click();
    await page.getByRole('button', { name: 'Fjern fra madplanen' }).click();
    await expect(page.getByRole('button', { name: 'Fortryd' })).toBeVisible();

    await updateMealSlot(user.householdId, weekday, 'dinner', { directEntry: 'Pizza fra B' }, now);
    await expect(flt(page, 'Pizza fra B')).toBeVisible();
    await page.getByRole('button', { name: 'Fortryd' }).click();
    await expect(flt(page, 'ændret i mellemtiden')).toBeVisible();
    await expect
      .poll(() => readMealSlot(user.householdId, weekday, 'dinner', now))
      .toEqual({ recipeId: null, directEntry: 'Pizza fra B' });
  });

  test('offline: Fjern lukker arket med det samme og synkroniseres når nettet er tilbage', async ({ page }) => {
    const { now, weekday } = await pinClock(page);
    const user = await seedHousehold();
    await seedRecipe({ id: 'r-lasagne', title: 'Lasagne e2e', householdId: user.householdId, createdBy: user.uid });
    await seedMealPlan(user.householdId, { [weekday]: { dinner: { recipeId: 'r-lasagne' } } }, now);

    await login(page, user);
    await openTab(page, 'Madplan');
    await selectPlanDay(page, weekday, now);
    await expect(flt(page, 'Lasagne e2e')).toBeVisible();

    await page.context().setOffline(true);
    await flt(page, 'Lasagne e2e').click();
    await page.getByRole('button', { name: 'Fjern fra madplanen' }).click();
    // Arket venter ikke på serveren, og pladsen er tom lokalt.
    await expect(page.getByRole('button', { name: 'Fjern fra madplanen' })).toHaveCount(0, { timeout: 10_000 });
    await expect(flt(page, 'Tilføj aftensmad')).toBeVisible();
    expect(await readMealSlot(user.householdId, weekday, 'dinner', now)).toEqual({
      recipeId: 'r-lasagne',
      directEntry: null,
    });

    await page.context().setOffline(false);
    await expect
      .poll(() => readMealSlot(user.householdId, weekday, 'dinner', now), { timeout: 30_000 })
      .toEqual({ recipeId: null, directEntry: null });
  });

  test('offline: Fortryd gendanner lokalt og i Firestore når nettet er tilbage', async ({ page }) => {
    const { now, weekday } = await pinClock(page);
    const user = await seedHousehold();
    await seedRecipe({ id: 'r-lasagne', title: 'Lasagne e2e', householdId: user.householdId, createdBy: user.uid });
    await seedMealPlan(user.householdId, { [weekday]: { dinner: { recipeId: 'r-lasagne' } } }, now);

    await login(page, user);
    await openTab(page, 'Madplan');
    await selectPlanDay(page, weekday, now);
    await flt(page, 'Lasagne e2e').click();
    await page.getByRole('button', { name: 'Fjern fra madplanen' }).click();
    await expect
      .poll(() => readMealSlot(user.householdId, weekday, 'dinner', now))
      .toEqual({ recipeId: null, directEntry: null });

    await page.context().setOffline(true);
    await page.getByRole('button', { name: 'Fortryd' }).click();
    await expect(flt(page, 'Lasagne e2e')).toBeVisible({ timeout: 30_000 });

    await page.context().setOffline(false);
    await expect
      .poll(() => readMealSlot(user.householdId, weekday, 'dinner', now), { timeout: 30_000 })
      .toEqual({ recipeId: 'r-lasagne', directEntry: null });
  });
});
