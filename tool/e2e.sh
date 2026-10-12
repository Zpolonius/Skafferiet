#!/usr/bin/env bash
# Kører e2e-testene (Playwright mod en Flutter web-build og Firebase-emulatorer).
# Brug: tool/e2e.sh [playwright-argumenter], fx  tool/e2e.sh --headed -g "smoke"
# Se docs/E2E.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# 1+2. Flutter web-build med lokal CanvasKit (ingen CDN-afhængighed).
#    firebase_options.dart er git-ignoreret og mangler i en frisk klon. Hvis den
#    mangler, skrives en stub kun mens der bygges, og den fjernes igen bagefter.
#    En rigtig fil røres aldrig.
OPTIONS="lib/firebase_options.dart"
CREATED_STUB=0
cleanup() {
  if [ "$CREATED_STUB" = "1" ]; then
    rm -f "$ROOT/$OPTIONS"
    echo "==> Fjernede stub-filen $OPTIONS igen (den blev oprettet af dette script)"
  fi
}
trap cleanup EXIT

BUILD_ARGS=(--target lib/main_e2e.dart --no-web-resources-cdn)
if [ -n "${EMULATOR_HOST:-}" ]; then
  BUILD_ARGS+=("--dart-define=EMULATOR_HOST=$EMULATOR_HOST")
fi
if [ "${E2E_SKIP_BUILD:-0}" = "1" ]; then
  echo "==> E2E_SKIP_BUILD=1: genbruger eksisterende build/web"
else
  # En stub efterladt af en afbrudt kørsel (fx SIGKILL) genkendes på første
  # linje og behandles som scriptets egen, så den også fjernes denne gang.
  if [ -f "$OPTIONS" ] && head -n 1 "$OPTIONS" | grep -q '^// STUB genereret af tool/e2e.sh'; then
    rm -f "$OPTIONS"
  fi
  if [ ! -f "$OPTIONS" ]; then
    echo "==> $OPTIONS mangler: skriver en midlertidig stub, så appen kan kompilere"
    CREATED_STUB=1
    cat > "$OPTIONS" <<'DART'
// STUB genereret af tool/e2e.sh (fjernes igen). Erstattes af `flutterfire configure`.
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
  echo "==> flutter build web ${BUILD_ARGS[*]}"
  flutter build web "${BUILD_ARGS[@]}"
  cleanup
  CREATED_STUB=0
fi

# 3. Node-afhængigheder.
cd "$ROOT/e2e"
if [ ! -d node_modules ]; then
  if [ -f package-lock.json ]; then npm ci; else npm install; fi
fi

# 4. Emulatorer (med de rigtige regler fra ../firebase.json) + Playwright.
#    Argumenterne sendes som JSON i en miljøvariabel og startes af
#    run-playwright.mjs uden om en shell, så specialtegn (æøå, mellemrum,
#    citationstegn) overlever uændret.
E2E_PLAYWRIGHT_ARGS="$(node -e 'console.log(JSON.stringify(process.argv.slice(1)))' -- "$@")"
export E2E_PLAYWRIGHT_ARGS
npx firebase emulators:exec \
  --config ../firebase.json \
  --only auth,firestore,storage \
  --project demo-skafferiet \
  "node run-playwright.mjs"
