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
cd rules_test && npm install && npm test                # Test firestore.rules against the emulator (needs Java 11+)
```

After any change to `firestore.rules`, run the rules tests in `rules_test/` and add a test for the new rule.

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
- All user data is scoped to a `householdId` — collections are `households`, `recipes`, `grocery_list`, `meal_plans`, `invitations`, `users`, `join_codes`.
- Joining a household requires proof the rules can check: the joiner writes `joinedWith: {type: 'code'|'invite', id}` in the same batch as adding themselves to `members`. Codes live in `join_codes/{code}` (10 chars, expire). See `HouseholdNotifier._switchHousehold`.
- Membership changes go through `HouseholdNotifier._commitMembershipChange` (pass `householdIdAfter`). Leaving gives the user a fresh household in the same batch; a sole member cannot leave. Removing a member also deletes the household's `join_codes` (members may list them by `householdId`). A user who gets `permission-denied` on their household (removed) is given a fresh household and a `HouseholdState.notice`, shown app-wide via the `ScaffoldMessenger` key in `main.dart`.
- Household dialogs shared by the profile and `/profile/household` live in `features/profile/household_dialogs.dart`; the onboarding pickers reused by `/profile/preferences` in `features/onboarding/household_setup_widgets.dart`. Sending, listing and cancelling invitations is `InvitationService` (`features/profile/invitation_service.dart`); accepting one is a membership change and stays in `HouseholdNotifier`.
- Firebase Auth error codes are translated in one place, `features/auth/auth_error_messages.dart`; pass `overrides` for wording specific to one screen. Login never says whether the e-mail exists.
- `users/{uid}.householdId` may only point at a household the user is a member of; only members can read a household.
- Account deletion (`features/profile/account_deletion_service.dart`) runs the cleanup client-side in a fixed order; `rules_test/` mirrors the same queries. Call `HouseholdNotifier.pauseForAccountDeletion()` first, or deleting the profile triggers auto-creation of a new household.
- The privacy policy text lives in `features/legal/privacy_policy_content.dart`; after editing it run `dart run tool/export_privacy_policy.dart` (a test compares it to `docs/PRIVACY_POLICY.md`). Publisher contact details are in `core/app_info.dart`.
- `GroceryItem` has a `source` field (`'manual'` or `'meal_plan'`) to distinguish origin.
- `MealSlot` holds either a linked `Recipe` reference or a `directEntry` string.
- `Recipe.calories` is **per serving** (the meal plan sums it per day). Optional `servings`, `protein`/`carbs`/`fat` (g per serving) and `nutritionFromIngredients`. Each `Ingredient` may carry `nutrition` per 100 g/ml; `core/services/nutrition_calculator.dart` sums it for units convertible to g/ml (`core/models/recipe_units.dart`). Limits are enforced in `firestore.rules`.

**Theme**:
- "Kitchen Harmony" design system — spec in `design/kitchen_harmony/DESIGN.md`, screen mockups in `design/*/screen.png`. Always use `context.colors` / `context.text` (`core/theme/theme_context.dart`, shorthand for `Theme.of(context).colorScheme` / `.textTheme`); never hard-code colours or call `GoogleFonts` in widgets.
- `AppTheme` maps every Material 3 text role and colour role (incl. `surfaceContainer*` and `*Fixed`) to the tokens, so any role is safe to use. `test/core/app_theme_test.dart` checks this.
- `test/design_system_test.dart` fails if any file in `lib/` (except `app_theme.dart`/`app_colors.dart`) uses `Colors.*` (other than `transparent`), `Color(0x…)`, `AppColors.*` or `GoogleFonts.*`.
- Settings-style screens use `SectionTitle`, `SettingsGroup`, `SettingsTile` and `showResultSnackBar` from `shared/widgets/settings_list.dart`.
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
