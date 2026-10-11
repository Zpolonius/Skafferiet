import { test, expect, flt } from '../helpers/fixtures';
import {
  danishWeekday,
  seedHousehold,
  seedMealPlan,
  seedRecipe,
  updateMealSlot,
} from '../helpers/emulator';
import { login, openTab, selectPlanDay } from '../helpers/app';

const today = new Date();
const weekday = danishWeekday(today);

test.describe('madplan', () => {
  test('opskrift i madplanen overlever genindlæsning (#24)', async ({ page }) => {
    // Fjernes når #24 (PR #38) er merget
    // (E2E_FIXED=1 kører testen uden forventet fejl, fx for at bevise at den er korrekt.)
    test.fail(process.env.E2E_FIXED !== '1', 'Kendt fejl #24: madplanen slår opskrifter op for tidligt');
    const user = await seedHousehold();
    await seedRecipe({
      id: 'r-lasagne',
      title: 'Lasagne e2e',
      householdId: user.householdId,
      createdBy: user.uid,
    });
    await seedMealPlan(user.householdId, {
      [weekday]: { dinner: { recipeId: 'r-lasagne' } },
    });

    await login(page, user);
    await openTab(page, 'Madplan');
    await selectPlanDay(page, weekday, today);
    await expect(flt(page, 'Lasagne e2e')).toBeVisible();

    // Genindlæsning svarer til at lukke og åbne appen igen (login ligger i IndexedDB).
    await page.reload();
    await expect(flt(page, 'Overfør til indkøb')).toBeVisible({ timeout: 45_000 });
    // Valgt dag nulstilles til mandag ved opstart, så vi vælger i dag igen.
    await selectPlanDay(page, weekday, today);
    await expect(flt(page, 'Lasagne e2e')).toBeVisible();
  });

  test('madplanen opdateres live uden genindlæsning (#24)', async ({ page }) => {
    // Fjernes når #24 (PR #38) er merget
    test.fail(process.env.E2E_FIXED !== '1', 'Kendt fejl #24: madplanen bruger .get() og lytter ikke live');
    const user = await seedHousehold();
    await seedMealPlan(user.householdId, {
      [weekday]: { dinner: { directEntry: 'Aftensmad fra start' } },
    });

    await login(page, user);
    await openTab(page, 'Madplan');
    await selectPlanDay(page, weekday, today);
    await expect(flt(page, 'Aftensmad fra start')).toBeVisible();

    // En anden enhed ændrer frokosten, mens siden er åben.
    await updateMealSlot(user.householdId, weekday, 'lunch', { directEntry: 'Frokost fra anden enhed' });
    await expect(flt(page, 'Frokost fra anden enhed')).toBeVisible({ timeout: 10_000 });
  });
});
