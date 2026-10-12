import { test, expect, flt } from '../helpers/fixtures';
import { danishWeekday, readMealSlot, seedHousehold, seedRecipe } from '../helpers/emulator';
import { login, openTab, selectPlanDay, typeInto } from '../helpers/app';

/**
 * #35: "Søg opskrifter" i Tilføj måltid finder også på ingredienser, tåler et
 * efterstillet mellemrum, og uden træffere kan man skrive søgningen som eget
 * måltid. Uret fastfryses som i de øvrige madplanstests.
 */
async function setup(page: import('@playwright/test').Page) {
  const now = new Date();
  await page.clock.setFixedTime(now);
  const weekday = danishWeekday(now);
  const user = await seedHousehold();
  await seedRecipe({
    id: 'r-thai',
    title: 'Thai karry',
    ingredients: ['Kyllingebryst', 'Kokosmælk'],
    householdId: user.householdId,
    createdBy: user.uid,
  });
  await seedRecipe({ id: 'r-pasta', title: 'Pasta pesto', householdId: user.householdId, createdBy: user.uid });

  await login(page, user);
  await openTab(page, 'Madplan');
  await selectPlanDay(page, weekday, now);
  await flt(page, 'Tilføj aftensmad').click();
  await flt(page, 'Søg opskrifter').click();
  return { now, weekday, user };
}

test('søg på ingrediens med efterstillet mellemrum og læg opskriften i madplanen', async ({ page }) => {
  const { now, weekday, user } = await setup(page);

  await typeInto(page, 'Find i dine opskrifter', 'kylling ');
  await expect(flt(page, 'Indeholder: Kyllingebryst')).toBeVisible();
  await expect(page.getByRole('button', { name: /Pasta pesto/ })).toHaveCount(0);

  await page.getByRole('button', { name: /Thai karry/ }).click();
  await expect(flt(page, 'Søg opskrifter')).toHaveCount(0);
  await expect(flt(page, 'Thai karry')).toBeVisible();
  await expect
    .poll(() => readMealSlot(user.householdId, weekday, 'dinner', now))
    .toEqual({ recipeId: 'r-thai', directEntry: null });
});

test('ingen træffere: Skriv som eget måltid fylder teksten ud og gemmer den', async ({ page }) => {
  const { now, weekday, user } = await setup(page);

  await typeInto(page, 'Find i dine opskrifter', 'lasagne ');
  await expect(flt(page, 'Ingen opskrifter matcher')).toBeVisible();
  await page.getByRole('button', { name: 'Skriv som eget måltid' }).click();

  // Nu på fanen "Eget måltid" med teksten udfyldt (trimmet).
  await expect(flt(page, 'Tilføj eget måltid')).toBeVisible();
  await page.getByRole('button', { name: 'Gem måltid' }).click();
  await expect
    .poll(() => readMealSlot(user.householdId, weekday, 'dinner', now))
    .toEqual({ recipeId: null, directEntry: 'lasagne' });
  await expect(flt(page, 'lasagne')).toBeVisible();
});
