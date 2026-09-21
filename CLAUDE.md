# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
flutter pub get                                          # Install dependencies
flutter run                                             # Run the app
flutter test                                            # Run all tests
flutter test test/features/grocery_list_test.dart       # Run a single test file
flutter analyze                                         # Static analysis
dart format .                                           # Format code
dart run build_runner build --delete-conflicting-outputs  # Regenerate Riverpod/codegen files
flutterfire configure                                   # Reconfigure Firebase
```

After adding or modifying any `@riverpod`-annotated provider, run `build_runner` to regenerate `.g.dart` files.

## Architecture

**Feature-sliced layout**: `lib/features/<feature>/` — each feature owns its provider(s) and screen(s) side by side. Shared widgets live in `lib/shared/widgets/`. Domain models, services, providers, and theme live in `lib/core/`.

**State management (Riverpod v2)**:
- `AsyncNotifier` for Firestore-backed data (recipes, grocery list, meal plan).
- `StateNotifier` / `StateProvider` for local/ephemeral UI state (auth, week offset, selected day).
- Providers are in `*_provider.dart` files co-located with their feature.

**Navigation (GoRouter)**:
- Configured in `lib/main.dart` with a `StatefulShellRoute` for 4 bottom tabs: Meal Plan (`/meal-plan`), Home (`/`), Grocery (`/grocery`), Recipes (`/recipes`).
- `/login` sits outside the shell. `/profile` hangs off Home.
- Recipe sub-routes: `/recipes/create`, `/recipes/:id`.

**Firestore data model**:
- All user data is scoped to a `householdId` — collections are `households`, `recipes`, `grocery_list`, `meal_plans`, `invitations`, `users`.
- `GroceryItem` has a `source` field (`'manual'` or `'meal_plan'`) to distinguish origin.
- `MealSlot` holds either a linked `Recipe` reference or a `directEntry` string.

**Theme**:
- "Kitchen Harmony" design system — always use `Theme.of(context).colorScheme` and `Theme.of(context).textTheme`, never hard-code colours.
- Primary: `#0F5238` (dark green), Secondary: `#895100` (brown). Fonts: Plus Jakarta Sans (headlines), Be Vietnam Pro (body).

## Firebase

- Firebase project ID: `siet-8630a`. Platforms: Android, iOS, Web.
- `lib/firebase_options.dart` is auto-generated and git-ignored — regenerate with `flutterfire configure`.
- `android/app/google-services.json` is git-ignored too. Both files are therefore **absent in a fresh clone and in every git worktree**, and Android builds fail until they are copied in from the main checkout.
- Auth, Firestore, and Storage are all in use.

## Release builds

- Release is minified with R8 — rules in `android/app/proguard-rules.pro`. Verify a minified build actually runs before shipping; a successful build does not prove the app works.
- Signing reads `android/key.properties` (git-ignored). Without it, release falls back to debug keys and prints a warning that `flutter build` hides unless you pass `--verbose`. Check the artifact instead: `apksigner verify --print-certs <apk>`.
- Full guide: `docs/SIGNING.md`.

## Dark mode

Not implemented — there is no `darkTheme`, no `ThemeMode` and no toggle. Note that `AppColors` holds 47 hardcoded light `static const` values, and 220 widget call sites read them directly instead of going through the theme, so a toggle alone would change almost nothing. See `docs/DARK_MODE.md` before starting.

## Testing

Tests live in `test/features/`. Uses `mocktail` for mocks and `riverpod_test` for provider testing. Mock classes cover Firestore, FirebaseAuth, and document/collection references.

## Localization

The app defaults to Danish (`da_DK`). UI strings are in Danish.
