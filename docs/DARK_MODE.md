# Dark Mode — analyse og plan

**Status: ikke påbegyndt.** Dette dokument beskriver, hvorfor opgaven er
væsentligt større end "tilføj en toggle", og hvordan den bør gribes an.

Baseret på kodeanalyse 21. september 2026.

---

## Den faktiske tilstand

```
ThemeMode        → findes ikke noget sted i lib/
darkTheme        → findes ikke; AppTheme eksponerer kun lightTheme
Toggle i UI      → findes ikke i profile_screen.dart
```

`main.dart:170` sætter udelukkende `theme: AppTheme.lightTheme`. Der er ingen
`darkTheme:` og ingen `themeMode:`.

> **Bemærk:** `PLAY_STORE_CHECKLIST.md` har tidligere beskrevet en toggle med
> "tom `onChanged`" i `profile_screen.dart:98–102`. Den beskrivelse er forældet —
> skærmen er omskrevet siden, og der findes ikke længere nogen toggle. Punktet
> er rettet i checklisten.
>
> `android/app/src/main/res/values-night/styles.xml` findes, men er Flutters
> egen standardfil til launch-skærmen. Den siger intet om appens tema.

---

## Hvorfor en toggle ikke er nok

Det reelle problem er ikke temaet — det er, at widgets henter farver uden om det.

`AppColors` er **47 `static const Color`-konstanter** med hårdkodede lyse
værdier. En `static const` kan pr. definition ikke skifte med temaet. Widgets,
der læser dem direkte, vil se præcis ens ud i dark mode.

Der er **260 direkte `AppColors.`-opslag**. 40 af dem sidder i `app_theme.dart`,
hvor de hører hjemme — resten er widgets, der omgår temaet:

| Fil | Forekomster |
|---|---:|
| `lib/features/onboarding/onboarding_screen.dart` | 60 |
| `lib/features/meal_plan/meal_plan_screen.dart` | 32 |
| `lib/features/profile/profile_screen.dart` | 30 |
| `lib/features/grocery/grocery_screen.dart` | 26 |
| `lib/features/recipes/recipe_detail_screen.dart` | 11 |
| `lib/features/recipes/recipes_screen.dart` | 8 |
| `lib/shared/widgets/add_to_meal_plan_sheet.dart` | 7 |
| `lib/features/meal_plan/add_custom_meal_sheet.dart` | 7 |
| `lib/shared/widgets/offline_banner.dart` | 4 |
| `lib/shared/widgets/empty_state_widget.dart` | 4 |
| `lib/shared/widgets/profile_avatar.dart` | 3 |
| `lib/features/meal_plan/edit_meal_slot_sheet.dart` | 3 |
| `lib/features/recipes/edit_recipe_screen.dart` | 2 |
| `lib/features/recipes/create_recipe_screen.dart` | 2 |
| `lib/features/auth/login_screen.dart` | 2 |
| **I alt uden for `app_theme.dart`** | **220** |

Det strider samtidig mod reglen i `CLAUDE.md`:

> Always use `Theme.of(context).colorScheme` and `Theme.of(context).textTheme`,
> never hard-code colours.

Slår man en toggle til i dag, skifter stort set intet — bortset fra de få
steder, hvor Material-komponenter selv trækker på `ColorScheme`. Resultatet
ville være en app, der ser i stykker ud: mørke systemkomponenter oven på lyse,
hårdkodede flader. **Det er værre end ingen dark mode.**

---

## Anbefalet fremgangsmåde

Rækkefølgen er vigtig. Trin 2 er den egentlige opgave, og den bør være færdig,
før toggleren bliver synlig for brugerne.

### Trin 1 — Byg et mørkt farvesæt

Udvid `AppColors` med mørke varianter, eller — bedre — omlæg til to
`ColorScheme`-objekter, så farverne kun findes ét sted:

```dart
static ThemeData get lightTheme => _themeFrom(_lightScheme);
static ThemeData get darkTheme  => _themeFrom(_darkScheme);
```

At dele `_themeFrom()` sikrer, at typografi, `cardTheme` og
`inputDecorationTheme` ikke når at drive fra hinanden mellem de to temaer.

Husk `Brightness.dark` på det mørke `ColorScheme` — ellers vælger Material
forkerte kontrastfarver til sine egne komponenter.

**Designnote:** "Kitchen Harmony"-primærfarven `#0F5238` er for mørk til at
fungere på en mørk flade. Den skal lysnes i den mørke palet for at opnå
tilstrækkelig kontrast. Det samme gælder sekundærfarven `#895100`.

### Trin 2 — Ryd de 220 direkte opslag op

Den tunge del. Fil for fil, startende med de største:

| Erstat | Med |
|---|---|
| `AppColors.primary` | `Theme.of(context).colorScheme.primary` |
| `AppColors.surface` | `Theme.of(context).colorScheme.surface` |
| `AppColors.onSurfaceVariant` | `Theme.of(context).colorScheme.onSurfaceVariant` |

Nogle konstanter har ingen direkte `ColorScheme`-modsvarighed
(f.eks. `primaryFixed`, `secondaryFixed`). De skal enten mappes til en
nærmeste rolle eller lægges i en `ThemeExtension`, så de også kan skifte
med temaet.

Tag ét feature-område ad gangen og gennemse det visuelt i begge temaer.
Det er en mekanisk, men ikke automatiserbar opgave — hvert opslag kræver en
vurdering af, hvilken semantisk rolle farven faktisk udfylder.

### Trin 3 — `ThemeMode`-provider med persistering

En `StateNotifier<ThemeMode>` i `lib/features/profile/`, i tråd med hvordan
øvrig lokal UI-tilstand håndteres (se `CLAUDE.md`).

Valget skal overleve genstart. **`shared_preferences` er ikke en afhængighed
i dag** og skal tilføjes til `pubspec.yaml`.

Understøt alle tre tilstande — `system`, `light`, `dark` — og lad `system`
være standard, så appen følger telefonens indstilling fra start.

### Trin 4 — Toggle i profilskærmen

Først nu. En `SwitchListTile` eller et trevejsvalg under en ny
`_SectionHeader(title: 'Udseende')` i `profile_screen.dart`.

---

## Omfang

Trin 2 dominerer. 220 opslag over 15 filer, hvor hvert enkelt kræver en
semantisk vurdering — ikke en søg-og-erstat.

Realistisk er det **flere arbejdsgange**, ikke én aften. Forsøger man at klare
det i ét hug, ender man typisk med halvt konverterede skærme, der ser værre
ud end udgangspunktet.

**Forslag til opdeling:** tag trin 1 og trin 2 for de fire største filer
(148 af de 220 opslag) som første bid. Så er hovedparten af appen klar, og
resten kan følge løbende.

---

## Relateret

- [ROADMAP.md](../ROADMAP.md) — Fase 3
- [PLAY_STORE_CHECKLIST.md](../PLAY_STORE_CHECKLIST.md)
- `lib/core/theme/app_colors.dart` — de 47 konstanter
- `lib/core/theme/app_theme.dart` — nuværende `lightTheme`
