import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/grocery_item.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:skafferiet/core/models/meal_type.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/grocery/grocery_provider.dart';
import 'package:skafferiet/features/grocery/grocery_screen.dart';
import 'package:skafferiet/features/grocery/recurring/recurring_items_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_screen.dart';
import 'package:skafferiet/features/moderation/moderation_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/recipes/community_recipes_provider.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';
import 'package:skafferiet/features/recipes/recipes_screen.dart';
import 'package:skafferiet/shared/widgets/add_to_meal_plan_sheet.dart';

class _User extends Mock implements User {}

class _Auth extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _Auth(super.state);
}

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household([HouseholdState? state])
      : super(state ??
            HouseholdState(householdId: 'h1', mealTypes: MealType.values));
}

class _TestMealPlanNotifier extends StreamNotifier<WeeklyMealPlan>
    with Mock
    implements MealPlanNotifier {
  final WeeklyMealPlan _plan;
  final List<String> updateSlotCalls = [];
  final List<String> restoreSlotCalls = [];
  bool? lastOwnRemovePending;
  String? lastRestoredWeekId;

  _TestMealPlanNotifier(this._plan);

  @override
  String currentWeekId() => _plan.id;

  @override
  Stream<WeeklyMealPlan> build() => Stream.value(_plan);

  @override
  Future<void> updateSlot(
    String day,
    String slotType, {
    Recipe? recipe,
    String? directEntry,
    String? weekId,
  }) async {
    updateSlotCalls.add('$day-$slotType');
  }

  @override
  Future<void> restoreSlot(
    String day,
    String slotType,
    MealSlot slot, {
    String? weekId,
    bool ownRemovePending = false,
  }) async {
    restoreSlotCalls.add('$day-$slotType');
    lastRestoredWeekId = weekId;
    lastOwnRemovePending = ownRemovePending;
  }
}

class _TestRecipesNotifier extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  final List<Recipe> _recipes;
  Recipe? copied;

  _TestRecipesNotifier(this._recipes);

  @override
  Stream<List<Recipe>> build() => Stream.value(_recipes);

  @override
  Future<Recipe> copyToHousehold(Recipe recipe) async {
    copied = recipe;
    return recipe.copyWith(householdId: 'h1');
  }
}

class _TestGroceryNotifier extends StreamNotifier<List<GroceryItem>>
    with Mock
    implements GroceryListNotifier {
  final List<GroceryItem> addedItems = [];

  @override
  Stream<List<GroceryItem>> build() => Stream.value(const []);

  @override
  Future<void> addItem(GroceryItem item) async {
    addedItems.add(item);
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('da_DK', null);
    registerFallbackValue(MealSlot());
  });

  Recipe makeRecipe({
    String id = 'r1',
    String title = 'Pasta Bolognese',
    String? householdId = 'h1',
    bool isShared = false,
    List<Ingredient> ingredients = const [],
  }) {
    return Recipe(
      id: id,
      title: title,
      calories: 600,
      time: '30 min',
      category: RecipeCategory.aftensmad,
      householdId: householdId,
      visibility:
          isShared ? RecipeVisibility.public : RecipeVisibility.household,
      ingredients: ingredients,
    );
  }

  WeeklyMealPlan makeMealPlan({
    String id = '2026-10-12',
    DateTime? weekStart,
    Map<String, DailyPlan>? days,
  }) {
    return WeeklyMealPlan(
      id: id,
      weekStart: weekStart ?? DateTime(2026, 10, 12),
      days: days ?? {},
    );
  }

  ProviderContainer createContainer({
    List<Override> overrides = const [],
  }) {
    final user = _User();
    when(() => user.displayName).thenReturn('Test Bruger');
    when(() => user.photoURL).thenReturn(null);

    return ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _Auth(AuthState(user: user))),
        householdProvider.overrideWith((ref) => _Household()),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 12)),
        reportedRecipeIdsProvider.overrideWith((ref) => Stream.value(const {})),
        blockedAuthorsProvider.overrideWith((ref) => Stream.value(const [])),
        blockedAuthorIdsProvider.overrideWithValue(const {}),
        ...overrides,
      ],
    );
  }

  Widget createTestWidget({
    required Widget child,
    List<Override> overrides = const [],
  }) {
    final container = createContainer(overrides: overrides);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: child,
      ),
    );
  }

  group('Acceptkriterium 1: Madplan vandret swipe', () {
    testWidgets('Swipe mod venstre på dagsindholdet skifter til næste dag',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final plan = makeMealPlan();
      final planNotifier = _TestMealPlanNotifier(plan);

      final container = createContainer(
        overrides: [
          mealPlanProvider.overrideWith(() => planNotifier),
          selectedDayProvider.overrideWith((ref) => 'Mandag'),
          weekOffsetProvider.overrideWith((ref) => 0),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const MealPlanScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(selectedDayProvider), 'Mandag');

      // Swipe mod venstre på dagsindholdet (overskriften)
      final dayHeader = find.text('Mandagens madplan');
      expect(dayHeader, findsOneWidget);
      await tester.drag(dayHeader, const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(container.read(selectedDayProvider), 'Tirsdag');
      expect(container.read(weekOffsetProvider), 0);
    });

    testWidgets(
        'Swipe mod venstre fra Søndag skifter til Mandag og øger weekOffset',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final plan = makeMealPlan();
      final planNotifier = _TestMealPlanNotifier(plan);

      final container = createContainer(
        overrides: [
          mealPlanProvider.overrideWith(() => planNotifier),
          selectedDayProvider.overrideWith((ref) => 'Søndag'),
          weekOffsetProvider.overrideWith((ref) => 0),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const MealPlanScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dayHeader = find.text('Søndagens madplan');
      expect(dayHeader, findsOneWidget);
      await tester.drag(dayHeader, const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(container.read(selectedDayProvider), 'Mandag');
      expect(container.read(weekOffsetProvider), 1);
    });

    testWidgets('Swipe mod højre på dagsindholdet skifter til forrige dag',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final plan = makeMealPlan();
      final planNotifier = _TestMealPlanNotifier(plan);

      final container = createContainer(
        overrides: [
          mealPlanProvider.overrideWith(() => planNotifier),
          selectedDayProvider.overrideWith((ref) => 'Tirsdag'),
          weekOffsetProvider.overrideWith((ref) => 0),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const MealPlanScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dayHeader = find.text('Tirsdagens madplan');
      expect(dayHeader, findsOneWidget);
      await tester.drag(dayHeader, const Offset(300, 0));
      await tester.pumpAndSettle();

      expect(container.read(selectedDayProvider), 'Mandag');
      expect(container.read(weekOffsetProvider), 0);
    });

    testWidgets(
        'Swipe mod højre fra Mandag skifter til Søndag og formindsker weekOffset',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final plan = makeMealPlan();
      final planNotifier = _TestMealPlanNotifier(plan);

      final container = createContainer(
        overrides: [
          mealPlanProvider.overrideWith(() => planNotifier),
          selectedDayProvider.overrideWith((ref) => 'Mandag'),
          weekOffsetProvider.overrideWith((ref) => 0),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const MealPlanScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dayHeader = find.text('Mandagens madplan');
      expect(dayHeader, findsOneWidget);
      await tester.drag(dayHeader, const Offset(300, 0));
      await tester.pumpAndSettle();

      expect(container.read(selectedDayProvider), 'Søndag');
      expect(container.read(weekOffsetProvider), -1);
    });

    testWidgets(
        'Vandret swipe på ugestriben skifter ikke dag via dagsindholdet',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final plan = makeMealPlan();
      final planNotifier = _TestMealPlanNotifier(plan);

      final container = createContainer(
        overrides: [
          mealPlanProvider.overrideWith(() => planNotifier),
          selectedDayProvider.overrideWith((ref) => 'Mandag'),
          weekOffsetProvider.overrideWith((ref) => 0),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const MealPlanScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Swipe på ugestriben (findes i _WeeklyCarousel)
      expect(find.text('MAN'), findsOneWidget);
      await tester.drag(find.text('MAN'), const Offset(-200, 0));
      await tester.pumpAndSettle();

      // Dagen er stadig Mandag, da ugestriben ikke er dagsindhold
      expect(container.read(selectedDayProvider), 'Mandag');
    });
  });

  group('Acceptkriterium 2: Madplan fjern måltid ved swipe', () {
    testWidgets(
        'Udfyldt måltid kan swipes væk, kalder updateSlot og viser SnackBar med Fortryd',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final recipe = makeRecipe(title: 'Lasagne');
      final plan = makeMealPlan(
        days: {
          'Mandag': DailyPlan(
            breakfast: MealSlot(),
            lunch: MealSlot(),
            dinner: MealSlot(recipe: recipe),
            snack: MealSlot(),
          ),
        },
      );
      final planNotifier = _TestMealPlanNotifier(plan);

      await tester.pumpWidget(createTestWidget(
        overrides: [
          mealPlanProvider.overrideWith(() => planNotifier),
          selectedDayProvider.overrideWith((ref) => 'Mandag'),
        ],
        child: const MealPlanScreen(),
      ));
      await tester.pumpAndSettle();

      // Måltidskortet findes og kan swipes væk via Dismissible
      final slotFinder = find.byKey(const ValueKey('slot-card-dinner'));
      expect(slotFinder, findsOneWidget);
      expect(
          find.descendant(of: slotFinder, matching: find.byType(Dismissible)),
          findsOneWidget);

      // Swipe kortet væk
      await tester.drag(slotFinder, const Offset(-500, 0));
      await tester.pumpAndSettle();

      // Skal have kaldt updateSlot for at fjerne måltidet
      expect(planNotifier.updateSlotCalls, contains('Mandag-dinner'));

      // Skal vise SnackBar med tekst og Fortryd-knap
      expect(find.text('Aftensmad fjernet fra mandag'), findsOneWidget);
      expect(find.text('Fortryd'), findsOneWidget);

      // Tryk på Fortryd
      await tester.tap(find.text('Fortryd'));
      await tester.pumpAndSettle();

      expect(planNotifier.restoreSlotCalls, contains('Mandag-dinner'));
      expect(planNotifier.lastRestoredWeekId, '2026-10-12');
    });

    testWidgets('Tomt måltid har IKKE Dismissible', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final plan = makeMealPlan(); // alle tomme
      final planNotifier = _TestMealPlanNotifier(plan);

      await tester.pumpWidget(createTestWidget(
        overrides: [
          mealPlanProvider.overrideWith(() => planNotifier),
          selectedDayProvider.overrideWith((ref) => 'Mandag'),
        ],
        child: const MealPlanScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Dismissible), findsNothing);
    });
  });

  group('Acceptkriterium 3: Opskrifter long-press', () {
    testWidgets(
        'Long-press på opskrift i Vores åbner menu med Tilføj til madplan og Tilføj til indkøb',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final recipe = makeRecipe(
        title: 'Pandekager',
        ingredients: [
          Ingredient(
              name: 'Mel', quantity: 200, unit: 'g', category: 'Kolonial'),
          Ingredient(name: 'Mælk', quantity: 5, unit: 'dl', category: 'Mejeri'),
        ],
      );
      final recipesNotifier = _TestRecipesNotifier([recipe]);
      final groceryNotifier = _TestGroceryNotifier();

      await tester.pumpWidget(createTestWidget(
        overrides: [
          recipesProvider.overrideWith(() => recipesNotifier),
          groceryListProvider.overrideWith(() => groceryNotifier),
        ],
        child: const RecipesScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Pandekager'), findsOneWidget);

      // Long-press på opskriftskortet
      await tester.longPress(find.text('Pandekager'));
      await tester.pumpAndSettle();

      expect(find.text('Tilføj til madplan'), findsOneWidget);
      expect(find.text('Tilføj til indkøb'), findsOneWidget);

      // Tjek mindst 48 dp trykflader
      final madplanTile = tester
          .getRect(find.widgetWithText(InkWell, 'Tilføj til madplan').first);
      expect(madplanTile.height, greaterThanOrEqualTo(48.0));
      final indkobTile = tester
          .getRect(find.widgetWithText(InkWell, 'Tilføj til indkøb').first);
      expect(indkobTile.height, greaterThanOrEqualTo(48.0));

      // Tryk på Tilføj til indkøb
      await tester.tap(find.text('Tilføj til indkøb'));
      await tester.pumpAndSettle();

      expect(groceryNotifier.addedItems.length, 2);
      expect(find.text('2 ingredienser tilføjet til indkøbslisten'),
          findsOneWidget);
    });

    testWidgets(
        'Long-press på opskrift i Fællesskab åbner AddToMealPlanSheet med resolveRecipe',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final foreignRecipe = makeRecipe(
        id: 'foreign-1',
        title: 'Gullash',
        householdId: 'other-household',
        isShared: true,
      );
      final recipesNotifier = _TestRecipesNotifier([]);

      await tester.pumpWidget(createTestWidget(
        overrides: [
          recipesProvider.overrideWith(() => recipesNotifier),
          communityRecipesProvider.overrideWith(
            () => _StaticCommunityNotifier(
              CommunityState(browse: [foreignRecipe], isLoading: false),
            ),
          ),
        ],
        child: const RecipesScreen(),
      ));
      await tester.pumpAndSettle();

      // Skift til Fællesskab
      await tester.tap(find.text('Fællesskab'));
      await tester.pumpAndSettle();

      expect(find.text('Gullash'), findsOneWidget);

      // Long press
      await tester.longPress(find.text('Gullash'));
      await tester.pumpAndSettle();

      expect(find.text('Tilføj til madplan'), findsOneWidget);

      // Tryk på Tilføj til madplan
      await tester.tap(find.text('Tilføj til madplan'));
      await tester.pumpAndSettle();

      // Skal vise AddToMealPlanSheet med resolveRecipe
      final sheet =
          tester.widget<AddToMealPlanSheet>(find.byType(AddToMealPlanSheet));
      expect(sheet.resolveRecipe, isNotNull);
    });
  });

  group('Acceptkriterium 4: Lister træk-ned-for-at-opdatere', () {
    testWidgets(
        'MealPlanScreen har RefreshIndicator med AlwaysScrollableScrollPhysics',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final plan = makeMealPlan();
      await tester.pumpWidget(createTestWidget(
        overrides: [
          mealPlanProvider.overrideWith(() => _TestMealPlanNotifier(plan)),
        ],
        child: const MealPlanScreen(),
      ));
      await tester.pumpAndSettle();

      final indicator = find.byType(RefreshIndicator);
      expect(indicator, findsOneWidget);

      final scrollView =
          tester.widget<CustomScrollView>(find.byType(CustomScrollView));
      expect(scrollView.physics, isA<AlwaysScrollableScrollPhysics>());
    });

    testWidgets(
        'RecipesScreen har RefreshIndicator med AlwaysScrollableScrollPhysics',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createTestWidget(
        overrides: [
          recipesProvider.overrideWith(() => _TestRecipesNotifier([])),
        ],
        child: const RecipesScreen(),
      ));
      await tester.pumpAndSettle();

      final indicator = find.byType(RefreshIndicator);
      expect(indicator, findsOneWidget);

      final scrollView =
          tester.widget<CustomScrollView>(find.byType(CustomScrollView));
      expect(scrollView.physics, isA<AlwaysScrollableScrollPhysics>());
    });

    testWidgets(
        'GroceryScreen har RefreshIndicator med AlwaysScrollableScrollPhysics',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createTestWidget(
        overrides: [
          groceryListProvider.overrideWith(() => _TestGroceryNotifier()),
        ],
        child: const GroceryScreen(),
      ));
      await tester.pumpAndSettle();

      final indicator = find.byType(RefreshIndicator);
      expect(indicator, findsOneWidget);

      final scrollView =
          tester.widget<CustomScrollView>(find.byType(CustomScrollView));
      expect(scrollView.physics, isA<AlwaysScrollableScrollPhysics>());
    });
  });
}

class _StaticCommunityNotifier extends CommunityRecipesNotifier {
  final CommunityState _initial;
  _StaticCommunityNotifier(this._initial)
      : super(firestore: FakeFirebaseFirestore());

  @override
  CommunityState build() => _initial;
}
