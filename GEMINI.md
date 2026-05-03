# Skafferiet - Kitchen Harmony

Skafferiet is a modern meal planning and grocery shopping application built with Flutter and Firebase. The project follows a feature-based architecture and emphasizes a clean, minimalist "Kitchen Harmony" design.

## Project Overview

- **Main Purpose**: Help users manage their kitchen by planning meals and generating grocery lists.
- **Target Platform**: Mobile (Android/iOS).
- **Language**: Dart (Flutter SDK).
- **Core Technologies**:
  - **State Management**: [Flutter Riverpod](https://riverpod.dev/) (v2.x) using `AsyncNotifier` and `StateNotifier`.
  - **Navigation**: [GoRouter](https://pub.dev/packages/go_router) with `StatefulShellRoute` for multi-tab navigation.
  - **Backend**: Firebase (Authentication, Firestore, Storage).
  - **UI System**: Material 3 with custom theming.
  - **Fonts**: Plus Jakarta Sans (Headlines) and Be Vietnam Pro (Body).

## Project Structure

- `lib/core/`: Centralized domain models, services, and theme configurations.
  - `models/`: Data classes (Recipe, GroceryItem, MealPlan).
  - `theme/`: App colors and global `ThemeData`.
- `lib/features/`: Feature-sliced architecture. Each directory contains logic and UI for a specific feature:
  - `auth/`: Login, signup, and authentication state.
  - `grocery/`: Interactive grocery list with Firestore synchronization.
  - `meal_plan/`: Weekly meal planning grid.
  - `recipes/`: Recipe discovery and details.
  - `home/`: Dashboard overview.
- `lib/shared/`: Reusable widgets and utility functions.
- `assets/`: Icons and images used in the app.
- `design/`: HTML/CSS mockups and reference screens for UI implementation.

## Development Workflows

### Setup
1. Install dependencies:
   ```bash
   flutter pub get
   ```
2. Configure Firebase:
   ```bash
   flutterfire configure
   ```

### Building and Running
- **Run the app**: `flutter run`
- **Build APK/IPA**: `flutter build apk` or `flutter build ios`
- **Code Generation**: (Used for Riverpod and other generators)
  ```bash
  dart run build_runner build --delete-conflicting-outputs
  ```

### Testing and Quality
- **Run Tests**: `flutter test`
- **Static Analysis**: `flutter analyze`
- **Formatting**: `dart format .`

## Architecture & Conventions

- **State Management**: Use `AsyncNotifier` for asynchronous data (e.g., Firestore streams) and `StateNotifier` for local/ephemeral state.
- **Theming**: Always use `Theme.of(context).colorScheme` or `Theme.of(context).textTheme` to maintain consistency with the "Kitchen Harmony" design system.
- **Naming**: Use `PascalCase` for classes and `camelCase` for variables/functions. Files should be `snake_case`.
- **Localization**: The app currently defaults to Danish (`da_DK`).
- **Data Persistence**: Firestore is used as the primary data store. Data is organized by `householdId` to support shared lists and plans.

## Key Files
- `lib/main.dart`: Entry point and GoRouter configuration.
- `lib/core/theme/app_theme.dart`: Global theme definitions.
- `lib/features/auth/auth_provider.dart`: Authentication logic.
- `lib/features/grocery/grocery_provider.dart`: Real-time grocery list management.
