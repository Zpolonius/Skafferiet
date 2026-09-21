import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/profile/profile_screen.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';
import 'package:skafferiet/features/grocery/grocery_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/models/grocery_item.dart';
import 'package:skafferiet/core/models/meal_plan.dart';

// ── Mock classes ───────────────────────────────────────────────────────────────

class _MockUser extends Mock implements User {}

class _MockAuthNotifier extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _MockAuthNotifier(super.state);
}

class _MockHouseholdNotifier extends StateNotifier<HouseholdState> with Mock implements HouseholdNotifier {
  _MockHouseholdNotifier(super.state);
}

class _EmptyRecipesNotifier extends StreamNotifier<List<Recipe>> with Mock implements RecipesNotifier {
  @override
  Stream<List<Recipe>> build() => const Stream.empty();
}

class _LoadedRecipesNotifier extends StreamNotifier<List<Recipe>> with Mock implements RecipesNotifier {
  @override
  Stream<List<Recipe>> build() => Stream.value(List.generate(
    3,
    (i) => Recipe(
      id: 'r$i',
      title: 'Opskrift $i',
      calories: 400,
      time: '20 min',
      category: RecipeCategory.aftensmad,
      ingredients: [],
      instructions: [],
    ),
  ));
}

class _EmptyGroceryNotifier extends StreamNotifier<List<GroceryItem>> with Mock implements GroceryListNotifier {
  @override
  Stream<List<GroceryItem>> build() => const Stream.empty();
}

class _LoadedGroceryNotifier extends StreamNotifier<List<GroceryItem>> with Mock implements GroceryListNotifier {
  @override
  Stream<List<GroceryItem>> build() => Stream.value(List.generate(
    5,
    (i) => GroceryItem(
      id: 'g$i',
      name: 'Vare $i',
      category: 'Mejeri',
      quantity: '1',
      isChecked: false,
      source: 'manual',
      createdAt: DateTime(2026, 5, 1),
      sortOrder: i,
    ),
  ));
}

class _EmptyMealPlanNotifier extends AsyncNotifier<WeeklyMealPlan> with Mock implements MealPlanNotifier {
  @override
  Future<WeeklyMealPlan> build() async => WeeklyMealPlan(id: 'empty', weekStart: DateTime(2026, 5, 5), days: {});
}

class _LoadedMealPlanNotifier extends AsyncNotifier<WeeklyMealPlan> with Mock implements MealPlanNotifier {
  @override
  Future<WeeklyMealPlan> build() async => WeeklyMealPlan(
    id: 'week1',
    weekStart: DateTime(2026, 5, 5),
    days: {
      'monday': DailyPlan(
        breakfast: MealSlot(),
        lunch: MealSlot(),
        dinner: MealSlot(directEntry: 'Pasta'),
        snack: MealSlot(),
      ),
      'tuesday': DailyPlan(
        breakfast: MealSlot(),
        lunch: MealSlot(directEntry: 'Salat'),
        dinner: MealSlot(),
        snack: MealSlot(),
      ),
    },
  );
}

// ── Helper ─────────────────────────────────────────────────────────────────────

Widget _buildProfileScreen({
  required HouseholdState householdState,
  required _MockHouseholdNotifier householdNotifier,
  RecipesNotifier Function()? recipesFactory,
  GroceryListNotifier Function()? groceryFactory,
  MealPlanNotifier Function()? mealPlanFactory,
  AuthState? authState,
}) {
  final mockUser = _MockUser();
  when(() => mockUser.displayName).thenReturn('Test Bruger');
  when(() => mockUser.email).thenReturn('test@example.com');
  when(() => mockUser.photoURL).thenReturn(null);
  when(() => mockUser.uid).thenReturn('test-uid');

  return ProviderScope(
    overrides: [
      authProvider.overrideWith(
        (ref) => _MockAuthNotifier(authState ?? AuthState(user: mockUser)),
      ),
      householdProvider.overrideWith((ref) => householdNotifier),
      recipesProvider.overrideWith(recipesFactory ?? () => _EmptyRecipesNotifier()),
      groceryListProvider.overrideWith(groceryFactory ?? () => _EmptyGroceryNotifier()),
      mealPlanProvider.overrideWith(mealPlanFactory ?? () => _EmptyMealPlanNotifier()),
    ],
    child: const MaterialApp(home: ProfileScreen()),
  );
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(const AsyncValue<List<Recipe>>.loading());
    registerFallbackValue(const AsyncValue<List<GroceryItem>>.loading());
  });

  group('Stats row', () {
    testWidgets('shows dash when providers are loading', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockHouseholdNotifier(
        HouseholdState(householdId: 'hh-1', isLoading: false),
      );

      await tester.pumpWidget(_buildProfileScreen(
        householdState: HouseholdState(householdId: 'hh-1', isLoading: false),
        householdNotifier: notifier,
        // All providers return Stream.empty() → AsyncLoading → value == null → '–'
      ));
      await tester.pumpAndSettle();

      expect(find.text('–'), findsWidgets);
    });

    testWidgets('shows counts when all providers have data', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockHouseholdNotifier(
        HouseholdState(householdId: 'hh-1', isLoading: false),
      );

      await tester.pumpWidget(_buildProfileScreen(
        householdState: HouseholdState(householdId: 'hh-1', isLoading: false),
        householdNotifier: notifier,
        recipesFactory: () => _LoadedRecipesNotifier(),
        groceryFactory: () => _LoadedGroceryNotifier(),
        mealPlanFactory: () => _LoadedMealPlanNotifier(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget); // 3 recipes
      expect(find.text('5'), findsOneWidget); // 5 grocery items
      expect(find.text('2'), findsOneWidget); // 2 meal plan days
    });
  });

  group('Household detail card', () {
    testWidgets('shows Ejer badge for household admin', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockHouseholdNotifier(
        HouseholdState(
          householdId: 'hh-1',
          householdName: 'Familie Skafferi',
          adminUid: 'admin-uid',
          members: ['admin-uid', 'member-uid'],
          memberNames: {
            'admin-uid': 'Admin Bruger',
            'member-uid': 'Alm. Bruger',
          },
          isLoading: false,
        ),
      );

      await tester.pumpWidget(_buildProfileScreen(
        householdState: notifier.state,
        householdNotifier: notifier,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Ejer'), findsOneWidget);
      expect(find.text('Admin Bruger'), findsOneWidget);
    });

    testWidgets('shows Kan redigere badge for non-admin member', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockHouseholdNotifier(
        HouseholdState(
          householdId: 'hh-1',
          adminUid: 'admin-uid',
          members: ['admin-uid', 'member-uid'],
          memberNames: {
            'admin-uid': 'Ejer Person',
            'member-uid': 'Redaktør Person',
          },
          isLoading: false,
        ),
      );

      await tester.pumpWidget(_buildProfileScreen(
        householdState: notifier.state,
        householdNotifier: notifier,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Kan redigere'), findsOneWidget);
      expect(find.text('Redaktør Person'), findsOneWidget);
    });

    testWidgets('shows household name in header', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockHouseholdNotifier(
        HouseholdState(
          householdId: 'hh-1',
          householdName: 'Vores Skafferi',
          adminUid: 'uid-1',
          members: ['uid-1'],
          memberNames: {'uid-1': 'Bruger'},
          isLoading: false,
        ),
      );

      await tester.pumpWidget(_buildProfileScreen(
        householdState: notifier.state,
        householdNotifier: notifier,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Vores Skafferi'), findsOneWidget);
    });
  });

  group('Rename dialog', () {
    testWidgets('opens dialog when edit icon is tapped', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockHouseholdNotifier(
        HouseholdState(
          householdId: 'hh-1',
          householdName: 'Gammelt Navn',
          adminUid: 'uid-1',
          members: ['uid-1'],
          memberNames: {'uid-1': 'Bruger'},
          isLoading: false,
        ),
      );
      when(() => notifier.renameHousehold(any())).thenAnswer((_) async {});

      await tester.pumpWidget(_buildProfileScreen(
        householdState: notifier.state,
        householdNotifier: notifier,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Omdøb husstand'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('calls renameHousehold with entered name on confirm', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockHouseholdNotifier(
        HouseholdState(
          householdId: 'hh-1',
          householdName: 'Gammelt Navn',
          adminUid: 'uid-1',
          members: ['uid-1'],
          memberNames: {'uid-1': 'Bruger'},
          isLoading: false,
        ),
      );
      when(() => notifier.renameHousehold(any())).thenAnswer((_) async {});

      await tester.pumpWidget(_buildProfileScreen(
        householdState: notifier.state,
        householdNotifier: notifier,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Nyt Husstandsnavn');
      await tester.tap(find.text('Gem'));
      await tester.pumpAndSettle();

      verify(() => notifier.renameHousehold('Nyt Husstandsnavn')).called(1);
    });
  });

  group('Menu tiles', () {
    testWidgets('shows all 5 menu items', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockHouseholdNotifier(
        HouseholdState(householdId: 'hh-1', isLoading: false),
      );

      await tester.pumpWidget(_buildProfileScreen(
        householdState: notifier.state,
        householdNotifier: notifier,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Mine opskrifter'), findsOneWidget);
      expect(find.text('Delte lister'), findsOneWidget);
      expect(find.text('Notifikationer'), findsOneWidget);
      expect(find.text('Præferencer & Diæt'), findsOneWidget);
      expect(find.text('Hjælp & Support'), findsOneWidget);
    });

    testWidgets('tapping Notifikationer shows snackbar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockHouseholdNotifier(
        HouseholdState(householdId: 'hh-1', isLoading: false),
      );

      await tester.pumpWidget(_buildProfileScreen(
        householdState: notifier.state,
        householdNotifier: notifier,
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Notifikationer'));
      await tester.tap(find.text('Notifikationer'));
      await tester.pumpAndSettle();

      expect(find.text('Notifikationer kommer snart!'), findsOneWidget);
    });
  });

  group('Profile Avatar', () {
    testWidgets('shows camera badge and user initial', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notifier = _MockHouseholdNotifier(
        HouseholdState(householdId: 'hh-1', isLoading: false),
      );

      await tester.pumpWidget(_buildProfileScreen(
        householdState: notifier.state,
        householdNotifier: notifier,
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
      expect(find.text('T'), findsOneWidget); // Test Bruger -> 'T'
    });

    testWidgets('renders CachedNetworkImage when user has photoURL', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mockUser = _MockUser();
      when(() => mockUser.displayName).thenReturn('Anna');
      when(() => mockUser.email).thenReturn('anna@example.com');
      when(() => mockUser.photoURL).thenReturn('https://example.com/anna.jpg');
      when(() => mockUser.uid).thenReturn('anna-uid');

      final notifier = _MockHouseholdNotifier(
        HouseholdState(householdId: 'hh-1', isLoading: false),
      );

      await tester.pumpWidget(_buildProfileScreen(
        householdState: notifier.state,
        householdNotifier: notifier,
        authState: AuthState(user: mockUser),
      ));

      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });
  });
}
