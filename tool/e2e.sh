#!/usr/bin/env bash
# Kører e2e-testene (Playwright mod en Flutter web-build og Firebase-emulatorer).
# Brug: tool/e2e.sh [playwright-argumenter], fx  tool/e2e.sh --headed -g "smoke"
# Se docs/E2E.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# 1. firebase_options.dart er git-ignoreret og mangler i en frisk klon. Lav kun
#    en stub hvis filen ikke findes — en rigtig fil overskrives aldrig.
OPTIONS="lib/firebase_options.dart"
if [ ! -f "$OPTIONS" ]; then
  echo "==> $OPTIONS mangler: skriver en stub (git-ignoreret, bruges kun til at kompilere)"
  cat > "$OPTIONS" <<'DART'
// STUB genereret af tool/e2e.sh. Erstattes af `flutterfire configure`.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static const FirebaseOptions currentPlatform = FirebaseOptions(
    apiKey: 'stub',
    appId: 'stub',
    messagingSenderId: 'stub',
    projectId: 'demo-skafferiet',
  );
}
DART
fi

# 2. Flutter web-build med lokal CanvasKit (ingen CDN-afhængighed).
BUILD_ARGS=(--target lib/main_e2e.dart --no-web-resources-cdn)
if [ -n "${EMULATOR_HOST:-}" ]; then
  BUILD_ARGS+=("--dart-define=EMULATOR_HOST=$EMULATOR_HOST")
fi
if [ "${E2E_SKIP_BUILD:-0}" = "1" ]; then
  echo "==> E2E_SKIP_BUILD=1: genbruger eksisterende build/web"
else
  echo "==> flutter build web ${BUILD_ARGS[*]}"
  flutter build web "${BUILD_ARGS[@]}"
fi

# 3. Node-afhængigheder.
cd "$ROOT/e2e"
if [ ! -d node_modules ]; then
  if [ -f package-lock.json ]; then npm ci; else npm install; fi
fi

# 4. Emulatorer (med de rigtige regler fra ../firebase.json) + Playwright.
#    "$@" sendes videre som korrekt citerede argumenter.
PW_ARGS=""
for a in "$@"; do PW_ARGS+=" $(printf '%q' "$a")"; done
exec npx firebase emulators:exec \
  --config ../firebase.json \
  --only auth,firestore,storage \
  --project demo-skafferiet \
  "npx playwright test$PW_ARGS"
