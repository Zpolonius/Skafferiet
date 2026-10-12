import { defineConfig } from '@playwright/test';

const port = Number(process.env.E2E_PORT ?? 4317);

// På en maskine med en anden Chromium end den Playwright selv henter kan stien
// angives med E2E_CHROMIUM_PATH. Uden den bruges Playwrights egen Chromium
// (`npx playwright install chromium`).
const executablePath = process.env.E2E_CHROMIUM_PATH || undefined;

export default defineConfig({
  testDir: './tests',
  globalSetup: './helpers/global-setup.ts',
  // Alle tests deler de samme emulatorer og nulstiller dem før hver test.
  workers: 1,
  fullyParallel: false,
  retries: 0,
  timeout: 90_000,
  expect: { timeout: 15_000 },
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    viewport: { width: 420, height: 900 },
    locale: 'da-DK',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    launchOptions: { executablePath },
  },
  webServer: {
    command: 'node server.mjs',
    url: `http://127.0.0.1:${port}`,
    reuseExistingServer: false,
    timeout: 30_000,
    env: { E2E_PORT: String(port) },
  },
});
