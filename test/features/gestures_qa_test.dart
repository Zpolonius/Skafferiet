import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:skafferiet/core/models/meal_type.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/grocery/recurring/recurring_items_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_screen.dart';
import 'package:skafferiet/features/moderation/moderation_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/recipes/community_recipes_provider.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';
import 'package:skafferiet/features/recipes/recipes_screen.dart';
import 'package:skafferiet/shared/widgets/add_to_meal_plan_sheet.dart';
import 'package:firebase_auth/firebase_auth.dart';

class _MockUser extends Mock implements User {}

class _MockAuth extends StateNotifier<AuthState>
    with Mock
    implements AuthNotifier {
  _MockAuth(super.state);
}

class _MockHousehold extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _MockHousehold([HouseholdState? state])
      : super(state ??
            HouseholdState(householdId: 'h1', mealTypes: MealType.values));
}

class _TestMealPlanNotifier extends StreamNotifier<WeeklyMealPlan>
    with Mock
    implements MealPlanNotifier {
  final WeeklyMealPlan _plan;
  final List<String> updateSlotCalls = [];
  final List<String> restoreSlotCalls = [];

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

class _StaticCommunityNotifier extends CommunityRecipesNotifier {
  final CommunityState _initial;
  _StaticCommunityNotifier(this._initial)
      : super(firestore: FakeFirebaseFirestore());

  @override
  CommunityState build() => _initial;
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
      ingredients: const [],
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
    final user = _MockUser();
    when(() => user.displayName).thenReturn('Test Bruger');
    when(() => user.photoURL).thenReturn(null);

    return ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _MockAuth(AuthState(user: user))),
        householdProvider.overrideWith((ref) => _MockHousehold()),
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

  group('QA Kanttilfælde: Dismissible og UI-stabilitet', () {
    testWidgets(
        'Fjernelse af måltid ved swipe bevarer sektionstitel og viser tomt måltidskort',
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

      // Før dismiss findes 'Aftensmad' overskriften
      expect(find.text('Aftensmad'), findsWidgets);

      // Swipe kortet væk
      final slotFinder = find.byKey(const ValueKey('slot-card-dinner'));
      await tester.drag(slotFinder, const Offset(-500, 0));
      await tester.pumpAndSettle();

      // Efter dismiss forbliver sektionsoverskriften 'Aftensmad' synlig i slot-card-dinner,
      // og der vises et tomt kort ('Tilføj aftensmad') i stedet for at hele sektionen forsvinder.
      expect(
        find.descendant(of: slotFinder, matching: find.text('Aftensmad')),
        findsOneWidget,
        reason: 'Sektionstitlen forbliver synlig efter swipe-dismiss',
      );
      expect(
        find.descendant(
            of: slotFinder, matching: find.text('Tilføj aftensmad')),
        findsOneWidget,
        reason:
            'Tomt måltidskort vises efter swipe-dismiss indtil data opdateres',
      );
    });

    testWidgets(
        'Egen opskrift vist i Fællesskab kopieres ikke ved Tilføj til madplan',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Opskrift delt af VORES husstand ('h1')
      final ownSharedRecipe = makeRecipe(
        id: 'r-own-shared',
        title: 'Vores Delte Opskrift',
        householdId: 'h1',
        isShared: true,
      );

      final recipesNotifier = _TestRecipesNotifier([ownSharedRecipe]);

      final container = createContainer(
        overrides: [
          householdProvider.overrideWith((ref) => _MockHousehold(
                HouseholdState(householdId: 'h1', mealTypes: MealType.values),
              )),
          recipesProvider.overrideWith(() => recipesNotifier),
          communityRecipesProvider.overrideWith(
            () => _StaticCommunityNotifier(
              CommunityState(browse: [ownSharedRecipe], isLoading: false),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const RecipesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Skift til Fællesskab
      await tester.tap(find.text('Fællesskab'));
      await tester.pumpAndSettle();

      expect(find.text('Vores Delte Opskrift'), findsOneWidget);

      // Long-press på opskriftskortet
      await tester.longPress(find.text('Vores Delte Opskrift'));
      await tester.pumpAndSettle();

      // Bundkort med handlinger vises
      expect(find.text('Tilføj til madplan'), findsOneWidget);
      await tester.tap(find.text('Tilføj til madplan'));
      await tester.pumpAndSettle();

      // AddToMealPlanSheet vises
      final sheetFinder = find.byType(AddToMealPlanSheet);
      expect(sheetFinder, findsOneWidget);
      final sheet = tester.widget<AddToMealPlanSheet>(sheetFinder);

      // Egen husstands opskrift i Fællesskab skal IKKE kopieres (resolveRecipe er null)
      expect(
        sheet.resolveRecipe,
        isNull,
        reason:
            'Egen husstands opskrift skal ikke have resolveRecipe/copyToHousehold sat',
      );
    });
  });
}
