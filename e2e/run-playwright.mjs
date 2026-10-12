// Kører `playwright test` med argumenter fra miljøvariablen E2E_PLAYWRIGHT_ARGS
// (JSON-liste, sat af tool/e2e.sh). Argumenterne går aldrig gennem en shell,
// så fx -g "genindlæsning" virker på tværs af bash, dash og cmd.exe.
// Startes af `firebase emulators:exec`, så emulatorerne kører imens.
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';

const args = JSON.parse(process.env.E2E_PLAYWRIGHT_ARGS || '[]');
const cli = createRequire(import.meta.url).resolve('@playwright/test/cli');
const result = spawnSync(process.execPath, [cli, 'test', ...args], { stdio: 'inherit', shell: false });
if (result.error) {
  console.error(result.error);
  process.exit(1);
}
process.exit(result.status ?? 1);
