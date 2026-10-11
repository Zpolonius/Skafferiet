import { expect, type Page } from '@playwright/test';
import type { TestUser } from './emulator';
import { flt } from './fixtures';

/** Venter til Flutter har startet og tilgængelighedstræet findes. */
export async function waitForApp(page: Page): Promise<void> {
  await page.locator('flt-semantics-host').waitFor({ state: 'attached', timeout: 60_000 });
}

/** Skriver i et Flutter-tekstfelt (fundet via dets label). */
export async function typeInto(page: Page, label: string, text: string): Promise<void> {
  await page.getByLabel(label).click();
  await page.keyboard.type(text);
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
 * Vælger dagen i madplanens ugevælger. Dagene vises som "MAN 12"-kort uden
 * eget navn, så vi finder kortet via de tre første bogstaver og datoen.
 */
export async function selectPlanDay(page: Page, weekdayDa: string, date: Date): Promise<void> {
  const label = new RegExp(`^${weekdayDa.slice(0, 3)}\\s*${date.getDate()}$`, 'i');
  await page.getByRole('button', { name: label }).first().click();
  await expect(flt(page, `${weekdayDa}ens madplan`)).toBeVisible();
}
