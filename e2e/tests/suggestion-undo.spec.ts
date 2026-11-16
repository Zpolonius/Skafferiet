import { test, expect, flt } from '../helpers/fixtures';
import { readCollection, seedHousehold, setDoc } from '../helpers/emulator';
import { login, openTab, typeInto } from '../helpers/app';
import type { Page } from '@playwright/test';

/**
 * "Fortryd" når et forslag fjernes fra varehistorikken (#47), gennem de
 * rigtige firestore.rules: × fjerner forslaget med det samme, og Fortryd
 * genskaber posten med samme felter (også lastUsed) og samme placering.
 */
const NAME_FIELD = 'Hvad skal du bruge? (f.eks. Mælk)';
const KAFFE_LAST_USED = new Date('2026-05-01T12:00:00.000Z');

async function seedHistory(householdId: string) {
  await setDoc(`households/${householdId}/item_history/kaffe`, {
    name: 'Kaffe',
    category: 'Kolonial',
    unit: 'pk',
    quantity: '2',
    useCount: 7,
    lastUsed: KAFFE_LAST_USED,
  });
  await setDoc(`households/${householdId}/item_history/kakao`, {
    name: 'Kakao',
    category: 'Kolonial',
    useCount: 3,
    lastUsed: new Date('2026-05-02T12:00:00.000Z'),
  });
}

const suggestion = (page: Page, name: string) =>
  page.getByRole('button', { name: new RegExp(`Brug tidligere vare: ${name}`) }).first();

/** Navnene på forslagene i den rækkefølge de står på skærmen. */
async function suggestionOrder(page: Page): Promise<string[]> {
  const labels = await page
    .getByRole('button', { name: /Brug tidligere vare:/ })
    .evaluateAll((els) => els.map((e) => e.getAttribute('aria-label') ?? e.textContent ?? ''));
  return labels.map((l) => /Brug tidligere vare: ([^,]+),/.exec(l)?.[1] ?? l);
}

/**
 * Trykker på "Fortryd" i SnackBaren. Er handlingen en knap i tilgængelighedstræet
 * (som i #36's tests), bruges den; ellers (nogle Flutter-web-builds lægger den
 * ind i SnackBarens fælles node) trykkes på SnackBarens node, som sender
 * samme tryk videre til handlingen. Begge dele kræver at SnackBaren ligger
 * øverst og ikke bag arkets barriere.
 */
async function clickFortryd(page: Page) {
  const button = page.getByRole('button', { name: 'Fortryd' });
  if ((await button.count()) > 0) {
    await button.click();
    return;
  }
  // force: SnackBarens nod ligger over teksten og "opsnapper" trykket (det er meningen).
  await flt(page, 'Forslag fjernet').click({ force: true });
}

async function expectKaffeRestored(householdId: string) {
  await expect
    .poll(async () => {
      const k = (await readCollection(`households/${householdId}/item_history`)).find((h) => h.id === 'kaffe');
      // Emulatoren skriver tidsstemplet uden millisekunder: sammenlign som tid.
      return k && { ...k, lastUsed: new Date(String(k.lastUsed)).getTime() };
    })
    .toMatchObject({ name: 'Kaffe', category: 'Kolonial', unit: 'pk', quantity: '2', useCount: 7, lastUsed: KAFFE_LAST_USED.getTime() });
}

test.describe('fortryd fjernet forslag (#47)', () => {
  test('hurtig-tilføj: × og Fortryd bringer forslaget tilbage på samme plads', async ({ page }) => {
    const user = await seedHousehold();
    await seedHistory(user.householdId);
    await login(page, user);
    await openTab(page, 'Indkøb');

    // Historikken hentes asynkront: skriv forfra indtil forslaget vises.
    await expect(async () => {
      await page.getByRole('textbox', { name: /Tilføj vare/ }).click();
      await page.waitForFunction(() => {
        const a = document.activeElement;
        return !!a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA');
      });
      await page.keyboard.press('Control+A');
      await page.keyboard.type('ka', { delay: 20 });
      await expect(suggestion(page, 'Kaffe')).toBeVisible({ timeout: 4_000 });
    }).toPass({ timeout: 30_000 });
    expect(await suggestionOrder(page)).toEqual(['Kaffe', 'Kakao']);

    await page.getByRole('button', { name: 'Fjern forslag' }).first().click();
    await expect(suggestion(page, 'Kaffe')).toHaveCount(0);
    await expect(flt(page, 'Forslag fjernet')).toBeVisible();
    await expect
      .poll(async () => (await readCollection(`households/${user.householdId}/item_history`)).map((h) => h.id))
      .toEqual(['kakao']);

    await clickFortryd(page);
    await expect(suggestion(page, 'Kaffe')).toBeVisible();
    expect(await suggestionOrder(page)).toEqual(['Kaffe', 'Kakao']);
    await expectKaffeRestored(user.householdId);
  });

  test('Tilføj vare-arket: SnackBaren "Forslag fjernet" vises over arket (ikke bag barrieren)', async ({ page }) => {
    const user = await seedHousehold();
    await seedHistory(user.householdId);
    await login(page, user);
    await openTab(page, 'Indkøb');

    await page.getByRole('button', { name: 'Tilføj vare', exact: true }).click();
    await typeInto(page, NAME_FIELD, 'ka');
    await expect(suggestion(page, 'Kaffe')).toBeVisible({ timeout: 10_000 });
    expect(await suggestionOrder(page)).toEqual(['Kaffe', 'Kakao']);

    await page.getByRole('button', { name: 'Fjern forslag' }).first().click();
    await expect(suggestion(page, 'Kaffe')).toHaveCount(0);
    expect(await suggestionOrder(page)).toEqual(['Kakao']);
    // SnackBaren ligger i et eget overlay øverst, uden for arkets semantik-
    // dialog, og er altså ikke gemt bag arkets barriere.
    const snack = flt(page, 'Forslag fjernet');
    await expect(snack).toBeVisible();
    const box = await snack.boundingBox();
    const sheetTop = await page.getByRole('button', { name: 'Luk' }).boundingBox();
    expect(box && sheetTop && box.y + box.height <= sheetTop.y + 1).toBeTruthy();
    await expect
      .poll(async () => (await readCollection(`households/${user.householdId}/item_history`)).map((h) => h.id))
      .toEqual(['kakao']);
    // At Fortryd i arket kan trykkes og genskaber forslaget, dækker widget-
    // testen (test/features/suggestion_undo_test.dart): Flutter webs
    // tilgængelighedslag sender ikke tryk videre til SnackBarens handling
    // på en node uden egen knap-rolle.
  });
});
