import { test, expect, flt } from '../helpers/fixtures';
import { readMealSlot, seedHousehold, seedRecipe } from '../helpers/emulator';
import { login, openTab, selectPlanDay } from '../helpers/app';

/**
 * #60: "Til madplan" fra en opskrift viser hvilken uge måltidet lægges i, og
 * ugen kan skiftes med pilene uden at madplanens egen uge ændres.
 */
const thursday = new Date(2026, 9, 15, 12, 0); // torsdag 15. okt. 2026 (uge 42)
const nextMonday = new Date(2026, 9, 19);

test('Til madplan: næste uge med pil, gemt i uge 43, madplanen bliver på denne uge', async ({ page }) => {
  const user = await seedHousehold();
  await seedRecipe({
    id: 'r-chili',
    title: 'Chili e2e',
    householdId: user.householdId,
    createdBy: user.uid,
  });
  await page.clock.setFixedTime(thursday);
  await login(page, user);
  await openTab(page, 'Opskrifter');
  await flt(page, 'Chili e2e').first().click();
  await page.getByRole('button', { name: 'Til madplan' }).click();

  await expect(flt(page, 'Uge 42, 12. til 18. oktober, denne uge')).toBeVisible();
  await page.getByRole('button', { name: 'Næste uge' }).last().click();
  await expect(flt(page, 'Uge 43, 19. til 25. oktober, næste uge')).toBeVisible();

  await flt(page, 'Tirsdag').last().click();
  await flt(page, 'Aftensmad').last().click();
  await page.getByRole('button', { name: 'Bekræft' }).click();
  await expect(flt(page, 'Chili e2e tilføjet til tirsdag i uge 43 (Aftensmad)')).toBeVisible();

  await expect
    .poll(() => readMealSlot(user.householdId, 'Tirsdag', 'dinner', nextMonday))
    .toEqual({ recipeId: 'r-chili', directEntry: null });
  expect(await readMealSlot(user.householdId, 'Tirsdag', 'dinner', thursday)).toBeUndefined();

  // Madplanen viser stadig denne uge; i næste uge ligger retten.
  await page.goBack();
  await expect(flt(page, 'Chili e2e')).toBeVisible();
  await expect(flt(page, 'tilføjet til tirsdag')).toHaveCount(0, { timeout: 15_000 });
  await openTab(page, 'Madplan');
  await expect(flt(page, 'Uge 42, 12. til 18. oktober, denne uge')).toBeVisible();
  await page.getByRole('button', { name: 'Næste uge' }).last().click();
  await selectPlanDay(page, 'Tirsdag', new Date(2026, 9, 20));
  await expect(flt(page, 'Chili e2e')).toBeVisible();
});
