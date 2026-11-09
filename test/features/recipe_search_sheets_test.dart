// #35: ingen træffere i opskriftssøgningen -> "Skriv som eget måltid" i
// både Tilføj måltid og Skift-arket.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/services/week_dates.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/meal_plan/add_custom_meal_sheet.dart';
import 'package:skafferiet/features/meal_plan/edit_meal_slot_sheet.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_screen.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';

class _User extends Mock implements User {}

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _Auth extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _Auth(super.state);
}

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'h1'));
}

Recipe _recipe(String id, String title, List<String> ingredients) => Recipe(
      id: id,
      title: title,
      calories: 500,
      time: '30 min',
      category: RecipeCategory.aftensmad,
      ingredients: [
        for (final i in ingredients)
          Ingredient(name: i, quantity: 1, unit: 'stk', category: 'Andet')
      ],
    );

final _lasagne = _recipe('r1', 'Lasagne', ['Pasta']);
final _karry = _recipe('r2', 'Thai karry', ['Kyllingebryst']);

class _Recipes extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  @override
  Stream<List<Recipe>> build() => Stream.value([_lasagne, _karry]);
}

class _Plan extends MealPlanNotifier {
  _Plan() : super(firestore: _MockFirestore());
  final calls = <String>[];

  @override
  Stream<WeeklyMealPlan> build() {
    DailyPlan dinner(MealSlot s) => DailyPlan(
        breakfast: MealSlot(), lunch: MealSlot(), dinner: s, snack: MealSlot());
    return Stream.value(
        WeeklyMealPlan(id: 'w', weekStart: DateTime(2026, 9, 28), days: {
      'Tirsdag': dinner(MealSlot(recipe: _lasagne)),
    }));
  }

  @override
  Future<void> updateSlot(String day, String slotType,
      {Recipe? recipe, String? directEntry, String? weekId}) async {
    calls.add('$day|$slotType|${recipe?.id}|$directEntry');
  }
}

Future<_Plan> _pump(WidgetTester tester, String day) async {
  final user = _User();
  when(() => user.displayName).thenReturn('Mette');
  when(() => user.photoURL).thenReturn(null);
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final plan = _Plan();
  final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, __) => const MealPlanScreen())]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _Auth(AuthState(user: user))),
      mealPlanProvider.overrideWith(() => plan),
      recipesProvider.overrideWith(() => _Recipes()),
      householdProvider.overrideWith((ref) => _Household()),
      selectedDayProvider.overrideWith((ref) => day),
    ],
    child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return plan;
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 3; i++) {
    await t.pump();
    await t.pump(const Duration(milliseconds: 150));
  }
}

/// Teksten i dagens måltidskort (aftensmad), uden "Ugens aftensmad"-oversigten:
/// finder præcis ét match, så testen stadig fanger dobbelte kort.
Finder _dayCard(String text) => find.descendant(
    of: find.byKey(const ValueKey('slot-card-dinner')), matching: find.text(text));

void main() {
  setUpAll(() => initializeDateFormatting('da_DK', null));

  group('Tilføj måltid', () {
    Finder inAdd(Finder f) =>
        find.descendant(of: find.byType(AddCustomMealSheet), matching: f);

    testWidgets('finder opskrift på ingrediens og lægger den i madplanen',
        (tester) async {
      final plan = await _pump(tester, 'Torsdag');
      await tester.tap(find.text('Tilføj aftensmad'));
      await _settle(tester);
      await tester.enterText(inAdd(find.byType(TextField)).first, 'kylling ');
      await _settle(tester);
      expect(inAdd(find.text('Indeholder: Kyllingebryst')), findsOneWidget);
      await tester.tap(inAdd(find.text('Thai karry')));
      await _settle(tester);
      expect(plan.calls, ['Torsdag|dinner|r2|null']);
      expect(find.byType(AddCustomMealSheet), findsNothing);
    });

    testWidgets(
        'ingen træffere: Skriv som eget måltid skifter fane med teksten, dag og måltid bevares',
        (tester) async {
      final plan = await _pump(tester, 'Torsdag');
      await tester.tap(find.text('Tilføj aftensmad'));
      await _settle(tester);

      // Vælg fredag i dagsstrimlen og frokost som måltid.
      final fri = daysOfWeek(weekStartOf(DateTime.now()))[4];
      final friCard = inAdd(find.text('${fri.day}')).first;
      await tester.ensureVisible(friCard);
      await tester.pump();
      await tester.tap(friCard);
      await _settle(tester);
      await tester.tap(inAdd(find.text('frokost')));
      await _settle(tester);

      await tester.enterText(inAdd(find.byType(TextField)).first, ' pizza  ');
      await _settle(tester);
      expect(inAdd(find.text('Ingen opskrifter matcher')), findsOneWidget);
      final button = inAdd(find.text('Skriv som eget måltid'));
      expect(button, findsOneWidget);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await _settle(tester);

      expect(inAdd(find.text('Tilføj eget måltid')), findsOneWidget);
      final title = inAdd(find.widgetWithText(TextField, 'pizza'));
      expect(title, findsOneWidget);

      await tester.tap(inAdd(find.text('Gem måltid')));
      await _settle(tester);
      expect(plan.calls, ['Fredag|lunch|null|pizza']);
    });
  });

  group('Skift-arket', () {
    Finder inEdit(Finder f) =>
        find.descendant(of: find.byType(EditMealSlotSheet), matching: f);

    testWidgets('ingen træffere: Skriv som eget måltid skifter til Eget måltid',
        (tester) async {
      final plan = await _pump(tester, 'Tirsdag');
      await tester.tap(_dayCard('Lasagne'));
      await _settle(tester);
      await tester.tap(find.text('Skift'));
      await _settle(tester);
      await tester.enterText(inEdit(find.byType(TextField)), 'pizza ');
      await _settle(tester);

      final button = inEdit(find.text('Skriv som eget måltid'));
      expect(button, findsOneWidget);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await _settle(tester);

      expect(inEdit(find.widgetWithText(TextField, 'pizza')), findsOneWidget);
      expect(inEdit(find.text('Hvad skal I spise?')), findsOneWidget);
      await tester.tap(inEdit(find.text('Gem')));
      await _settle(tester);
      expect(plan.calls, ['Tirsdag|dinner|null|pizza']);
    });

    testWidgets('ingrediens-søgning i Skift viser nuværende med flueben',
        (tester) async {
      final plan = await _pump(tester, 'Tirsdag');
      await tester.tap(_dayCard('Lasagne'));
      await _settle(tester);
      await tester.tap(find.text('Skift'));
      await _settle(tester);
      await tester.enterText(inEdit(find.byType(TextField)), 'pasta');
      await _settle(tester);
      expect(inEdit(find.text('Indeholder: Pasta')), findsOneWidget);
      expect(inEdit(find.byIcon(Icons.check)), findsOneWidget);
      expect(plan.calls, isEmpty);
    });
  });
}
