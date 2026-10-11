# End-to-end-tests

E2E-testene starter den rigtige app (Flutter web-build) i en rigtig Chromium
via Playwright. Appen kører mod Firebase-**emulatorer** (Auth, Firestore og
Storage) med de rigtige `firestore.rules` og `storage.rules`, så der aldrig
røres ved projektet `siet-8630a`.

Det fanger fejl som enhedstestene ikke kan: data der forsvinder ved
genindlæsning, lyttere der ikke opdaterer live, regler der afviser en skrivning.

## Forudsætninger

- Flutter (samme version som resten af projektet) og Node 20+ (testet med 22).
- Java 21+ (Firebase-emulatorerne; firebase-tools 14 kræver 21, 11 er ikke nok).
- Første gang på egen maskine: `cd e2e && npm ci && npx playwright install chromium`.

## Kør alle tests

```bash
tool/e2e.sh
```

Scriptet:

1. skriver en minimal `lib/firebase_options.dart`, **kun hvis den mangler**,
   mens appen bygges, og fjerner den igen bagefter (en rigtig fil overskrives
   eller fjernes aldrig),
2. bygger `flutter build web --target lib/main_e2e.dart --no-web-resources-cdn`,
3. installerer `e2e/node_modules` hvis de mangler,
4. starter emulatorerne og kører `npx playwright test` inde i dem.

En kørsel tager ca. 2 minutter (heraf ca. 1 minut er web-builden).

Nyttige varianter (alt efter `tool/e2e.sh` sendes videre til Playwright):

```bash
tool/e2e.sh smoke                       # kun filer/titler der matcher "smoke"
tool/e2e.sh -g "live"                   # kun tests med "live" i titlen (æøå og mellemrum er ok)
tool/e2e.sh --repeat-each=3             # gentag hver test
tool/e2e.sh --headed                    # vis browseren
tool/e2e.sh --debug                     # Playwright Inspector
E2E_SKIP_BUILD=1 tool/e2e.sh            # genbrug build/web (hvis appen er uændret)
```

Rapport og trace efter en fejl:

```bash
cd e2e
npx playwright show-report                          # HTML-rapport
npx playwright show-trace test-results/<test>/trace.zip
```

Ved en fejl gemmes skærmbillede, trace og browserens konsollog under
`e2e/test-results/`. Bemærk at tekst ikke tegnes på skærmbilleder, hvis
skrifttyper ikke kan hentes (se nedenfor) — brug trace eller konsollogen.

`EMULATOR_HOST` (valgfri) bages ind i web-builden som adressen appen bruger til
emulatorerne. Standard er `localhost`, som er rigtigt for denne harness
(emulatorerne startes lokalt og lytter på 127.0.0.1). Den er kun tænkt til
fremtidige scenarier, fx en Android-emulator hvor værten hedder `10.0.2.2`, og
kræver en ny build (ikke sammen med `E2E_SKIP_BUILD=1`).

## Sådan er det bygget

| Fil | Rolle |
| --- | --- |
| `lib/main_e2e.dart` | Alternativ indgang: demo-Firebase-indstillinger, forbinder til emulatorerne, slår tilgængelighedstræet til og kører derefter samme `MyApp` som `main.dart`. |
| `firebase.json` (`emulators`) | Porte: Auth 9099, Firestore 8080, Storage 9199. |
| `e2e/server.mjs` | Lille statisk server for `build/web` på port 4317 (startes af Playwright; `E2E_PORT` ændrer den). |
| `e2e/run-playwright.mjs` | Starter Playwright inde i emulatorerne. Argumenter fra `tool/e2e.sh` sendes som JSON uden om en shell. |
| `e2e/playwright.config.ts` | Konfiguration (1 worker, da testene deler emulatorerne). |
| `e2e/helpers/emulator.ts` | Nulstil og seed data via emulatorernes REST-API'er. |
| `e2e/helpers/app.ts` | `login`, `openTab`, `selectPlanDay` m.fl. |
| `e2e/helpers/fixtures.ts` | `test` med automatisk nulstilling før hver test, netværksregler og `flt()`. |
| `e2e/tests/` | Selve testene. |

Før hver test nulstilles alle Firestore-dokumenter og Auth-brugere.

## Skriv en ny test

```ts
import { test, expect, flt } from '../helpers/fixtures';
import { seedHousehold, seedRecipe, seedMealPlan, danishWeekday } from '../helpers/emulator';
import { login, openTab, selectPlanDay } from '../helpers/app';

test('min test', async ({ page }) => {
  // En bruger + husstand, der lander direkte på hjemskærmen (ingen onboarding).
  const user = await seedHousehold();
  await seedRecipe({ id: 'r1', title: 'Pandekager', householdId: user.householdId, createdBy: user.uid });
  await seedMealPlan(user.householdId, { [danishWeekday()]: { dinner: { recipeId: 'r1' } } });

  await login(page, user);          // går gennem den rigtige loginskærm
  await openTab(page, 'Madplan');
  await selectPlanDay(page, danishWeekday(), new Date());
  await expect(flt(page, 'Pandekager')).toBeVisible();
});
```

Seed-hjælperne skriver direkte i emulatoren med `Authorization: Bearer owner`,
som omgår reglerne. Brug dem kun til at forberede data — selve handlingen, der
testes, skal gå gennem appen, så reglerne også afprøves.

### Gode råd

- **Find tekst med `flt(page, 'tekst')`.** Flutter web tegner på et canvas; det
  Playwright kan se er tilgængelighedstræet (`<flt-semantics>`). En label står
  enten som tekst eller — hvis noden har børn, fx et trykbart kort med en knap —
  i `aria-label`. `flt()` søger begge steder. Knapper findes med
  `page.getByRole('button', { name: '…' })`, tekstfelter med `getByLabel('…')`.
- **Skriv i felter med `typeInto(page, 'E-mail', '…')`**, ikke `fill()`.
  Flutter lytter efter tastetryk; `fill()` sætter kun DOM-værdien, og appen
  opdager ikke noget.
- Valgt dag i madplanen er mandag efter hver opstart (også efter
  `page.reload()`), så vælg dagen igen med `selectPlanDay`.
- `page.reload()` svarer til at lukke og åbne appen: login ligger i
  IndexedDB og overlever.
- Ændr data mens appen kører med `patchDoc` / `updateMealSlot` for at teste
  live-opdatering.

## Kendte fejl markeret med `test.fail`

To tests i `tests/meal-plan.spec.ts` (genindlæsning og live-opdatering af
madplanen) afdækker fejl #24 og er markeret som forventet fejlende, indtil
rettelsen (PR #38) er merget — de står som "bestået" i rapporten, så længe fejlen
findes. Når den er rettet, vil Playwright melde at de "uventet består": fjern
da `test.fail(...)`-linjen og kommentaren `Fjernes når #24 (PR #38) er merget`.
Med `E2E_FIXED=1 tool/e2e.sh` køres de uden forventet fejl.

## Begrænsninger

- Kun **web**-builden testes (Chromium). Android/iOS-specifik adfærd, kamera,
  push osv. dækkes ikke.
- Billeder og skrifttyper fra nettet afvises med vilje (hurtige fejl i stedet
  for hængende tests). Derfor tegnes tekst ikke på skærmbilleder i et
  begrænset netværk; semantik-træet er upåvirket.
- Firebase JS SDK'et, som FlutterFire henter fra `www.gstatic.com`, leveres i
  testene fra npm-pakken `firebase` (se `routeNetwork` i `helpers/fixtures.ts`).
  Det er kun nødvendigt bag en firewall, men er harmløst ellers.
  **Versionen i `e2e/package.json` skal være præcis den, som
  `firebase_core_web` henter** (`supportedFirebaseJsSdkVersion`). Opgraderer du
  FlutterFire, og testene starter med fejlen "Firebase JS SDK-version passer
  ikke", så ret `firebase` i `e2e/package.json` til den version, fejlen nævner,
  og kør `npm install` i `e2e/`.
- Appens ur fastfryses i hver madplanstest til testens starttidspunkt
  (`page.clock.setFixedTime`), så en kørsel over midnat ikke kan skifte uge.
  Seed-hjælperne tager et `Date` — send det samme som uret er sat til.
- Testene **læser** kun gennem reglerne; skrivninger fra appen (opret opskrift,
  tilføj vare osv.) er endnu ikke dækket, så skriveregler er ikke afprøvet her
  (brug `rules_test/` til dem).
- Storage-emulatorens URL'er (`http://localhost:9199/...`) opfylder ikke regler,
  der kræver `https://firebasestorage.googleapis.com/...` (fx opslagstavlens
  fotosedler). Fremtidige foto-tests skal tage højde for det.
- Konsollen kan indeholde støj: 4 `pageerror` med "Failed to load font with
  url …" kommer fra google_fonts, der henter skrifttyper fra fonts.gstatic.com
  ved kørsel — det afviser harness'en med vilje. Præcis disse filtreres fra i
  `helpers/fixtures.ts`; appens skrifttyper er uændrede.
- Emulatorerne efterlader `firestore-debug.log` og andre `*-debug.log` i `e2e/`
  (git-ignorerede).
- Tests kører efter hinanden (1 worker) fordi de deler emulatorerne.
- `Chromium` hentes af Playwright. Peg på en anden med `E2E_CHROMIUM_PATH`.
