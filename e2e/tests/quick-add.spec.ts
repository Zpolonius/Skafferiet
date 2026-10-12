import { test, expect, flt } from '../helpers/fixtures';
import { readCollection, seedHousehold, setDoc } from '../helpers/emulator';
import { login, openTab, typeInto } from '../helpers/app';
import type { Page } from '@playwright/test';

/**
 * Hurtig-tilføj øverst på indkøbslisten (#33) gennem de rigtige firestore.rules:
 * flere varer i træk kun med tastaturet, mængde/enhed læses ud af teksten, og
 * en vare fra historikken får sin kategori.
 */

/** Feltet øverst (ikke knappen "Tilføj vare" nederst, som har samme navn). */
function quickField(page: Page) {
  return page.getByRole('textbox', { name: /Tilføj vare/ });
}

/** Klikker i feltet én gang og venter til Flutters skjulte input har fokus. */
async function focusQuickField(page: Page): Promise<void> {
  await quickField(page).click();
  await page.waitForFunction(() => {
    const a = document.activeElement;
    return !!a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA');
  });
}

/** Skriver i det felt der allerede har fokus (uden at klikke) og kontrollerer værdien. */
async function typeFocused(page: Page, text: string): Promise<void> {
  await page.keyboard.type(text, { delay: 20 });
  await expect
    .poll(() => page.evaluate(() => (document.activeElement as HTMLInputElement | null)?.value))
    .toBe(text);
}

async function groceries(householdId: string) {
  return readCollection(`households/${householdId}/grocery_list`);
}

test.describe('hurtig-tilføj på indkøbslisten (#33)', () => {
  test('flere varer i træk kun med tastaturet, med mængde og enhed', async ({ page }) => {
    const user = await seedHousehold();
    await login(page, user);
    await openTab(page, 'Indkøb');

    await focusQuickField(page);
    await typeFocused(page, '2 l mælk');
    await page.keyboard.press('Enter');
    await expect(flt(page, 'Mælk')).toBeVisible();

    // Feltet er tømt og har stadig fokus: næste vare skrives uden et klik.
    await expect
      .poll(() => page.evaluate(() => (document.activeElement as HTMLInputElement | null)?.value))
      .toBe('');
    await typeFocused(page, 'brød');
    await page.keyboard.press('Enter');
    await expect(flt(page, 'Brød')).toBeVisible();

    await expect
      .poll(async () => (await groceries(user.householdId)).length)
      .toBe(2);
    const items = await groceries(user.householdId);
    const milk = items.find((i) => i.name === 'Mælk');
    const bread = items.find((i) => i.name === 'Brød');
    expect(milk).toMatchObject({ quantity: '2', unit: 'l', category: 'Andet', source: 'manual' });
    expect(bread).toMatchObject({ quantity: '1', unit: 'stk', category: 'Andet', source: 'manual' });

    // Historikken er skrevet, og knappen nederst findes stadig.
    await expect
      .poll(async () => (await readCollection(`households/${user.householdId}/item_history`)).length)
      .toBe(2);
    await expect(page.getByRole('button', { name: 'Tilføj vare', exact: true })).toBeVisible();
  });

  test('en vare fra historikken får sin kategori og kan vælges som forslag', async ({ page }) => {
    const user = await seedHousehold();
    const history = (id: string, name: string, category: string, unit: string, quantity: string) =>
      setDoc(`households/${user.householdId}/item_history/${id}`, {
        name,
        category,
        unit,
        quantity,
        useCount: 3,
        lastUsed: new Date(),
      });
    await history('smør', 'Smør', 'Mejeri', 'pk', '1');
    await history('hakket oksekød', 'Hakket oksekød', 'Kød', 'g', '500');
    await login(page, user);
    await openTab(page, 'Indkøb');

    await focusQuickField(page);
    // Forslaget viser at historikken er hentet, før vi skriver videre.
    await typeFocused(page, 'sm');
    await expect(page.getByRole('button', { name: /Brug tidligere vare: Smør/ })).toBeVisible();
    await page.keyboard.type('ør', { delay: 20 });
    await page.keyboard.press('Enter');
    await expect(flt(page, 'Smør')).toBeVisible();

    // Et tryk på et forslag lægger varen på listen med det samme.
    await typeFocused(page, 'hak');
    await page.getByRole('button', { name: /Brug tidligere vare: Hakket oksekød/ }).click();
    await expect(flt(page, 'Hakket oksekød')).toBeVisible();

    await expect
      .poll(async () =>
        (await groceries(user.householdId))
          .map((i) => [i.name, i.category, i.quantity, i.unit])
          .sort((a, b) => String(a[0]).localeCompare(String(b[0]))),
      )
      .toEqual([
        ['Hakket oksekød', 'Kød', '500', 'g'],
        ['Smør', 'Mejeri', '1', 'pk'],
      ]);
    await expect
      .poll(async () => (await readCollection(`households/${user.householdId}/item_history`)).map((h) => h.useCount).sort())
      .toEqual([4, 4]);
  });

  test('en vare der kommer i historikken mens listen er åben foreslås uden at skifte fane', async ({ page }) => {
    const user = await seedHousehold();
    await login(page, user);
    await openTab(page, 'Indkøb');
    await expect(quickField(page)).toBeVisible();

    // "En anden telefon" bruger Kaffe nu – listen har været åben hele tiden.
    await setDoc(`households/${user.householdId}/item_history/kaffe`, {
      name: 'Kaffe',
      category: 'Kolonial',
      unit: 'pk',
      quantity: '1',
      useCount: 1,
      lastUsed: new Date(),
    });

    // 1. I hurtig-tilføj-feltet.
    await focusQuickField(page);
    await typeFocused(page, 'kaf');
    await expect(page.getByRole('button', { name: /Brug tidligere vare: Kaffe/ })).toBeVisible({ timeout: 10_000 });

    // 2. I arket "Tilføj vare" (#28).
    await page.getByRole('button', { name: 'Tilføj vare', exact: true }).click();
    await typeInto(page, 'Hvad skal du bruge? (f.eks. Mælk)', 'kaf');
    await expect(page.getByRole('button', { name: /Brug tidligere vare: Kaffe/ }).first()).toBeVisible();
  });
});
