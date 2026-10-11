import { test, expect, flt } from '../helpers/fixtures';
import {
  danishWeekday,
  seedHousehold,
  seedMealPlan,
  seedRecipe,
  updateMealSlot,
} from '../helpers/emulator';
import { login, openTab, selectPlanDay } from '../helpers/app';

/**
 * Appens ur fastfryses til testens starttidspunkt, så dag/uge ikke kan skifte
 * midt i en kørsel (fx over midnat søndag→mandag). Det samme Date bruges til
 * at seede data. Fastfrysningen sker før login (page.goto) og er tæt på det
 * rigtige tidspunkt, så Firebase-tokens stadig er gyldige.
 */
async function pinClock(page: import('@playwright/test').Page): Promise<{ now: Date; weekday: string }> {
  const now = new Date();
  await page.clock.setFixedTime(now);
  return { now, weekday: danishWeekday(now) };
}

test.describe('madplan', () => {
  // NB: På ikke-rettet kode fejler genindlæsningstesten allerede ved det første
  // view (før reload), fordi opskriften aldrig slås op. Selve reload-trinnet
  // afprøves derfor først på rettet kode (E2E_FIXED=1).
  test('opskrift i madplanen overlever genindlæsning (#24)', async ({ page }) => {
    const { now, weekday } = await pinClock(page);
    const user = await seedHousehold();
    await seedRecipe({
      id: 'r-lasagne',
      title: 'Lasagne e2e',
      householdId: user.householdId,
      createdBy: user.uid,
    });
    await seedMealPlan(user.householdId, { [weekday]: { dinner: { recipeId: 'r-lasagne' } } }, now);

    await login(page, user);
    await openTab(page, 'Madplan');
    await selectPlanDay(page, weekday, now);

    // Fjernes når #24 (PR #38) er merget. Først herfra er en fejl "forventet":
    // fejl i login/opstart/forudsætninger tæller stadig som rigtige fejl.
    // (E2E_FIXED=1 kører testen uden forventet fejl.)
    test.fail(process.env.E2E_FIXED !== '1', 'Kendt fejl #24: madplanen slår opskrifter op for tidligt');
    await expect(flt(page, 'Lasagne e2e')).toBeVisible();

    // Genindlæsning svarer til at lukke og åbne appen igen (login ligger i IndexedDB).
    await page.reload();
    await expect(flt(page, 'Overfør til indkøb')).toBeVisible({ timeout: 45_000 });
    // Valgt dag nulstilles til mandag ved opstart, så vi vælger i dag igen.
    await selectPlanDay(page, weekday, now);
    await expect(flt(page, 'Lasagne e2e')).toBeVisible();
  });

  test('madplanen opdateres live uden genindlæsning (#24)', async ({ page }) => {
    const { now, weekday } = await pinClock(page);
    const user = await seedHousehold();
    await seedMealPlan(user.householdId, { [weekday]: { dinner: { directEntry: 'Aftensmad fra start' } } }, now);

    await login(page, user);
    await openTab(page, 'Madplan');
    await selectPlanDay(page, weekday, now);
    await expect(flt(page, 'Aftensmad fra start')).toBeVisible();

    // Fjernes når #24 (PR #38) er merget. Først herfra er en fejl "forventet".
    test.fail(process.env.E2E_FIXED !== '1', 'Kendt fejl #24: madplanen bruger .get() og lytter ikke live');
    // En anden enhed ændrer frokosten, mens siden er åben.
    await updateMealSlot(user.householdId, weekday, 'lunch', { directEntry: 'Frokost fra anden enhed' }, now);
    await expect(flt(page, 'Frokost fra anden enhed')).toBeVisible({ timeout: 10_000 });
  });
});
