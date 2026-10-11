import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { createRequire } from 'node:module';

/**
 * Appen henter Firebase JS SDK fra gstatic (se fixtures.ts, hvor det serveres
 * lokalt fra npm-pakken `firebase`). Versionerne skal passe: ellers kører
 * testene mod et andet SDK end appen forventer.
 */
export default function globalSetup(): void {
  const repo = resolve(__dirname, '..', '..');
  const lock = readFileSync(join(repo, 'pubspec.lock'), 'utf8');
  const m = lock.match(/^ {2}firebase_core_web:\n(?: {4}.*\n)*? {4}version: "([^"]+)"/m);
  if (!m) throw new Error('Fandt ikke firebase_core_web i pubspec.lock — kør "flutter pub get".');
  const webVersion = m[1];

  const pubCache = process.env.PUB_CACHE ?? join(homedir(), '.pub-cache');
  const file = join(pubCache, 'hosted', 'pub.dev', `firebase_core_web-${webVersion}`, 'lib', 'src', 'firebase_sdk_version.dart');
  if (!existsSync(file)) {
    console.warn(`[e2e] Kunne ikke finde ${file}; springer tjek af Firebase JS SDK-version over.`);
    return;
  }
  const sdk = readFileSync(file, 'utf8').match(/supportedFirebaseJsSdkVersion\s*=\s*'([^']+)'/)?.[1];
  const installed = createRequire(__filename)('firebase/package.json').version as string;
  if (sdk !== installed) {
    throw new Error(
      `Firebase JS SDK-version passer ikke: firebase_core_web ${webVersion} henter ${sdk}, ` +
        `men e2e/package.json har firebase@${installed}. Ret "firebase" i e2e/package.json til præcis ${sdk} og kør "npm install" i e2e/.`,
    );
  }
}
