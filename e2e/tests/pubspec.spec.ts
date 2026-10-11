import { test, expect } from '@playwright/test';
import { firebaseCoreWebVersion, pubCacheDir } from '../helpers/pubspec';

// Rene tests af hjælperne i helpers/pubspec.ts (kræver ingen browser).
const lock = [
  'packages:',
  '  firebase_core_platform_interface:',
  '    dependency: transitive',
  '    version: "9.9.9"',
  '  firebase_core_web:',
  '    dependency: transitive',
  '    description:',
  '      name: firebase_core_web',
  '    source: hosted',
  '    version: "3.12.0"',
  '  firebase_storage:',
  '    version: "1.0.0"',
  '',
];

test('pubspec.lock med LF og CRLF giver samme version', () => {
  expect(firebaseCoreWebVersion(lock.join('\n'))).toBe('3.12.0');
  expect(firebaseCoreWebVersion(lock.join('\r\n'))).toBe('3.12.0');
  expect(firebaseCoreWebVersion('packages:\n')).toBeUndefined();
});

test('pub-cache findes via PUB_CACHE, LOCALAPPDATA eller hjemmemappen', () => {
  expect(pubCacheDir({ PUB_CACHE: '/x' }, 'linux')).toBe('/x');
  expect(pubCacheDir({ LOCALAPPDATA: 'C:\\L' }, 'win32')).toMatch(/Pub[\\/]Cache$/);
  expect(pubCacheDir({}, 'linux')).toMatch(/\.pub-cache$/);
});
