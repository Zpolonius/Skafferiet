import { test as base, expect, type Locator, type Page } from '@playwright/test';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { resetEmulators } from './emulator';

const SDK_DIR = join(__dirname, '..', 'node_modules', 'firebase');

/**
 * Netværk i testen:
 *  - gstatic.com/firebasejs/** serveres fra npm-pakken `firebase` (samme
 *    bundles som CDN'et). Gør testene uafhængige af gstatic og dermed
 *    brugbare bag en firewall. Harmløst på en åben maskine.
 *  - Alt andet end localhost afvises med det samme (skrifttyper, billeder fra
 *    nettet m.m.), så ingen test hænger på et udefrakommende kald.
 */
async function routeNetwork(page: Page): Promise<void> {
  // Ét handler for alle eksterne værter (Playwright kører routes i omvendt
  // registreringsrækkefølge, så to overlappende routes ville tage hinanden).
  await page.context().route(
    (url) => url.protocol.startsWith('http') && !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname),
    async (route) => {
      const url = new URL(route.request().url());
      if (url.hostname === 'www.gstatic.com' && url.pathname.startsWith('/firebasejs/')) {
        const name = url.pathname.split('/').pop() ?? '';
        const file = join(SDK_DIR, name);
        if (/^firebase-[a-z-]+\.js$/.test(name) && existsSync(file)) {
          return route.fulfill({
            status: 200,
            contentType: 'application/javascript',
            headers: { 'Access-Control-Allow-Origin': '*' },
            body: readFileSync(file),
          });
        }
      }
      return route.abort('blockedbyclient');
    },
  );
}

export type ConsoleEntry = { type: string; text: string };

export const test = base.extend<{ consoleLog: ConsoleEntry[]; app: void }>({
  consoleLog: async ({ page }, use, testInfo) => {
    const entries: ConsoleEntry[] = [];
    page.on('console', (m) => entries.push({ type: m.type(), text: m.text() }));
    page.on('pageerror', (e) => {
      // google_fonts henter skrifttyper fra fonts.gstatic.com ved kørsel; det
      // afvises af routeNetwork, og fejlen er kendt støj (se docs/E2E.md).
      if (/Failed to load font with url/.test(String(e.message ?? e))) return;
      entries.push({ type: 'pageerror', text: String(e) });
    });
    await use(entries);
    if (testInfo.status !== testInfo.expectedStatus) {
      await testInfo.attach('console.log', {
        body: entries.map((e) => `[${e.type}] ${e.text}`).join('\n'),
        contentType: 'text/plain',
      });
    }
  },
  // Kører automatisk i hver test: ren database + netværksregler + konsol-log.
  app: [
    async ({ page, consoleLog }, use) => {
      void consoleLog;
      await resetEmulators();
      await routeNetwork(page);
      await use();
    },
    { auto: true },
  ],
});

export { expect };

/**
 * Finder en tekst i Flutters tilgængelighedstræ. Flutter web lægger en
 * widgets label som tekst i <flt-semantics>, men har noden børn (fx en
 * trykbar kort med en knap i), ligger labelen i stedet i `aria-label`. Derfor
 * søges begge steder. `text` matcher delstrenge (eller et regulært udtryk).
 * Begræns evt. med .first() — samme tekst kan stå flere steder.
 */
export function flt(page: Page, text: string | RegExp): Locator {
  const host = page.locator('flt-semantics-host');
  return host.getByText(text).or(host.getByLabel(text)).first();
}
