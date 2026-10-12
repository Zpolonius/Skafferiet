import { homedir } from 'node:os';
import { join } from 'node:path';

/** Version af firebase_core_web i en pubspec.lock (tåler både LF og CRLF). */
export function firebaseCoreWebVersion(lock: string): string | undefined {
  return lock.match(/^ {2}firebase_core_web:\r?\n(?: {4}.*\r?\n)*? {4}version: "([^"]+)"/m)?.[1];
}

/** Pub-cachens placering: PUB_CACHE, ellers %LOCALAPPDATA%\\Pub\\Cache på Windows, ellers ~/.pub-cache. */
export function pubCacheDir(
  env: NodeJS.ProcessEnv = process.env,
  platform: NodeJS.Platform = process.platform,
): string {
  if (env.PUB_CACHE) return env.PUB_CACHE;
  if (platform === 'win32') {
    return join(env.LOCALAPPDATA ?? join(homedir(), 'AppData', 'Local'), 'Pub', 'Cache');
  }
  return join(homedir(), '.pub-cache');
}
