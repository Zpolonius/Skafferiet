import { test, expect, flt } from '../helpers/fixtures';
import { readCollection, seedHousehold } from '../helpers/emulator';
import { login, openTab, typeInto } from '../helpers/app';

/**
 * #25: fremgangsmåde kan skrives ved oprettelse, gemmes trimmet i Firestore
 * og vises nummereret på opskriftens detaljeskærm.
 */
test('opret opskrift med to trin og se dem nummereret på detaljeskærmen', async ({ page }) => {
  const user = await seedHousehold();
  await login(page, user);
  await openTab(page, 'Opskrifter');
  await page.getByRole('button', { name: 'Opret opskrift' }).first().click();

  await typeInto(page, 'Titel', 'Trinvis suppe');

  await page.getByRole('button', { name: 'Tilføj trin' }).click();
  await typeInto(page, 'Trin 1', '  Hak løget  ');
  await page.getByRole('button', { name: 'Tilføj trin' }).click();
  await typeInto(page, 'Trin 2', 'Kog suppen');

  await page.getByRole('button', { name: 'Opret opskrift' }).last().click();

  // Gemt i Firestore: præcis de to trin, trimmet.
  await expect
    .poll(async () => {
      const recipes = await readCollection('recipes');
      return recipes.find((r) => r.title === 'Trinvis suppe')?.instructions;
    })
    .toEqual(['Hak løget', 'Kog suppen']);

  // Åbn opskriften: begge trin vises nummereret.
  await page.getByRole('button', { name: /Trinvis suppe/ }).first().click();
  await expect(flt(page, 'Fremgangsmåde')).toBeVisible();
  await expect(flt(page, 'Trin 1: Hak løget')).toBeVisible();
  await expect(flt(page, 'Trin 2: Kog suppen')).toBeVisible();
});
