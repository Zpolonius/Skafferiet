import { expect, type Page } from '@playwright/test';
import type { TestUser } from './emulator';
import { flt } from './fixtures';

/** Venter til Flutter har startet og tilgængelighedstræet findes. */
export async function waitForApp(page: Page): Promise<void> {
  await page.locator('flt-semantics-host').waitFor({ state: 'attached', timeout: 60_000 });
}

/**
 * Skriver i et Flutter-tekstfelt (fundet via dets label). Flutter flytter
 * fokus til et skjult input efter klikket; skrives der før det er sket, går
 * tastetryk tabt. Derfor venter vi på fokus, rydder feltet, skriver og
 * kontrollerer værdien — og prøver igen et begrænset antal gange.
 */
export async function typeInto(page: Page, label: string, text: string): Promise<void> {
  const field = page.getByLabel(label);
  for (let attempt = 0; attempt < 5; attempt++) {
    await field.click();
    await page.waitForFunction(() => {
      const a = document.activeElement;
      return !!a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA');
    });
    await page.keyboard.press('ControlOrMeta+A');
    await page.keyboard.press('Backspace');
    await page.keyboard.type(text, { delay: 20 });
    const value = await page.evaluate(() => (document.activeElement as HTMLInputElement | null)?.value);
    if (value === text) return;
  }
  throw new Error(`Kunne ikke skrive i feltet "${label}" (tastetryk blev ved med at gå tabt)`);
}

/** Logger ind gennem den rigtige loginskærm og venter på hjemskærmen. */
export async function login(page: Page, user: Pick<TestUser, 'email' | 'password'>): Promise<void> {
  await page.goto('/');
  await waitForApp(page);
  // Flutter læser kun tastetryk: Playwrights fill() sætter DOM-værdien uden
  // at appen opdager det, så vi klikker i feltet og skriver.
  await typeInto(page, 'E-mail', user.email);
  await typeInto(page, 'Adgangskode', user.password);
  await page.getByRole('button', { name: 'Log ind', exact: true }).click();
  await expect(flt(page, 'Dagens Plan')).toBeVisible({ timeout: 45_000 });
}

/** Går til fanen i bundmenuen (fx 'Madplan', 'Indkøb', 'Opskrifter'). */
export async function openTab(page: Page, label: string): Promise<void> {
  await page.getByRole('button', { name: label }).first().click();
}

/**
 * Vælger dagen i madplanens ugevælger. Hver dag er en knap med et skærmlæser-
 * navn som "Mandag 12. oktober" (#63), så vi finder den via dagsnavn og dato.
 */
export async function selectPlanDay(page: Page, weekdayDa: string, date: Date): Promise<void> {
  const label = new RegExp(`^${weekdayDa} ${date.getDate()}\\.`);
  await page.getByRole('button', { name: label }).first().click();
  await expect(flt(page, `${weekdayDa}ens madplan`)).toBeVisible();
}
