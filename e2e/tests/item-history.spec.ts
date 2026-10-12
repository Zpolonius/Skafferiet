import { test, expect, flt } from '../helpers/fixtures';
import { readCollection, seedHousehold } from '../helpers/emulator';
import { login, openTab, typeInto } from '../helpers/app';

/**
 * Varehistorik og forslag i "Tilføj vare" (#28), gennem de rigtige
 * firestore.rules: historikken skal overleve at indkøbslisten tømmes.
 */
const NAME_FIELD = 'Hvad skal du bruge? (f.eks. Mælk)';

test.describe('varehistorik og forslag (#28)', () => {
  test('en tidligere vare foreslås igen efter listen er tømt og udfylder navn og kategori', async ({ page }) => {
    const user = await seedHousehold();
    await login(page, user);
    await openTab(page, 'Indkøb');

    // 1. Tilføj "Hakket oksekød" i kategorien "Kød".
    await page.getByRole('button', { name: 'Tilføj vare', exact: true }).click();
    await typeInto(page, NAME_FIELD, 'Hakket oksekød');
    await page.getByRole('button', { name: 'Kød', exact: true }).click();
    await page.getByRole('button', { name: 'Tilføj til liste', exact: true }).click();
    await expect(flt(page, 'Hakket oksekød')).toBeVisible();

    // 2. Tøm listen – varen forsvinder, men historikken bliver.
    await page.getByRole('button', { name: /Vis menu|Show menu/ }).click();
    await page.getByRole('menuitem', { name: /Tøm listen/ }).click();
    await page.getByRole('button', { name: 'Tøm liste', exact: true }).click();
    await expect(flt(page, 'Hakket oksekød')).toHaveCount(0);
    expect(await readCollection(`households/${user.householdId}/grocery_list`)).toHaveLength(0);
    const history = await readCollection(`households/${user.householdId}/item_history`);
    expect(history).toHaveLength(1);
    expect(history[0]).toMatchObject({ id: 'hakket oksekød', name: 'Hakket oksekød', category: 'Kød', useCount: 1 });

    // 3. Skriv "hak": forslaget vises, og et tryk udfylder navn og kategori.
    await page.getByRole('button', { name: 'Tilføj vare', exact: true }).click();
    await typeInto(page, NAME_FIELD, 'hak');
    const suggestion = page.getByRole('button', { name: /Brug tidligere vare: Hakket oksekød/ });
    await expect(suggestion).toBeVisible();
    await suggestion.click();

    // Forslaget er væk (feltet er nu identisk med det), og vælges "Tilføj til
    // liste", kommer varen på listen med den tidligere kategori.
    await expect(suggestion).toHaveCount(0);
    await page.getByRole('button', { name: 'Tilføj til liste', exact: true }).click();
    await expect(flt(page, 'Hakket oksekød')).toBeVisible();
    await expect
      .poll(async () => (await readCollection(`households/${user.householdId}/grocery_list`)).map((g) => [g.name, g.category]))
      .toEqual([['Hakket oksekød', 'Kød']]);
    await expect
      .poll(async () => (await readCollection(`households/${user.householdId}/item_history`))[0]?.useCount)
      .toBe(2);
  });
});
