// #44: opfølgning på "Tilføj måltid" (#36) – bekræftelse før en udfyldt plads
// overskrives, labels på tælleknapperne, 320 px, "Gem som opskrift" med
// rigtige mængder og ingen sen faneskift efter interaktion.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/models/recipe_units.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/meal_plan/add_custom_meal_sheet.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'h1'));
}

Recipe _recipe(String id, String title) => Recipe(
      id: id,
      title: title,
      calories: 500,
      time: '30 min',
      category: RecipeCategory.aftensmad,
      ingredients: const [],
    );

final _lasagne = _recipe('r1', 'Lasagne');
final _karry = _recipe('r2', 'Thai karry');

class _Recipes extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  _Recipes(this.source);
  final Stream<List<Recipe>> source;
  final added = <Recipe>[];

  @override
  Stream<List<Recipe>> build() => source;

  @override
  Future<void> addRecipe(Recipe recipe) async => added.add(recipe);
}

/// Tirsdag aftensmad er Lasagne, onsdag aftensmad er "Rester"; resten er tomt.
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
      'Onsdag': dinner(MealSlot(directEntry: 'Rester')),
    }));
  }

  @override
  Future<void> updateSlot(String day, String slotType,
      {Recipe? recipe, String? directEntry, String? weekId}) async {
    calls.add('$day|$slotType|${recipe?.id}|$directEntry');
  }
}

typedef _Setup = ({_Plan plan, _Recipes recipes});

Future<_Setup> _open(
  WidgetTester tester, {
  String day = 'Tirsdag',
  Size size = const Size(390, 1400),
  Stream<List<Recipe>>? recipes,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final plan = _Plan();
  final recipesNotifier = _Recipes(recipes ?? Stream.value([_lasagne, _karry]));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mealPlanProvider.overrideWith(() => plan),
      recipesProvider.overrideWith(() => recipesNotifier),
      householdProvider.overrideWith((ref) => _Household()),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: Consumer(
        builder: (context, ref, _) {
          // Holder planen i live, som madplanskærmen gør.
          ref.watch(mealPlanProvider);
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => AddCustomMealSheet(
                      initialDay: day, initialCategory: 'Aftensmad'),
                ),
                child: const Text('Åbn'),
              ),
            ),
          );
        },
      ),
    ),
  ));
  await tester.pump();
  await tester.tap(find.text('Åbn'));
  await _settle(tester);
  return (plan: plan, recipes: recipesNotifier);
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.pump();
    await t.pump(const Duration(milliseconds: 150));
  }
}

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(AddCustomMealSheet), matching: f);

Future<void> _toOwnMeal(WidgetTester tester) async {
  await tester.tap(_inSheet(find.text('Eget måltid')));
  await _settle(tester);
}

Future<void> _saveOwnMeal(WidgetTester tester, String title) async {
  await tester.enterText(_inSheet(find.byType(TextField)).first, title);
  await tester.ensureVisible(find.text('Gem måltid'));
  await tester.tap(find.text('Gem måltid'));
  await _settle(tester);
}

void main() {
  setUpAll(() => initializeDateFormatting('da_DK', null));

  group('udfyldt plads overskrives ikke uden bekræftelse', () {
    testWidgets('Søg opskrifter: Annuller lader Lasagne stå', (tester) async {
      final s = await _open(tester);
      await tester.tap(_inSheet(find.text('Thai karry')));
      await _settle(tester);

      expect(find.text('Erstat Lasagne?'), findsOneWidget);
      expect(
          find.text(
              'Lasagne står allerede som aftensmad tirsdag. Vil du erstatte det med Thai karry?'),
          findsOneWidget);
      await tester.tap(find.text('Annuller'));
      await _settle(tester);

      expect(s.plan.calls, isEmpty);
      expect(find.byType(AddCustomMealSheet), findsOneWidget);
    });

    testWidgets('Søg opskrifter: Erstat gemmer og lukker', (tester) async {
      final s = await _open(tester);
      await tester.tap(_inSheet(find.text('Thai karry')));
      await _settle(tester);
      await tester.tap(find.text('Erstat'));
      await _settle(tester);

      expect(s.plan.calls, ['Tirsdag|dinner|r2|null']);
      expect(find.byType(AddCustomMealSheet), findsNothing);
    });

    testWidgets('Eget måltid: spørger før Lasagne erstattes', (tester) async {
      final s = await _open(tester);
      await _toOwnMeal(tester);
      await _saveOwnMeal(tester, 'Pizza');

      expect(find.text('Erstat Lasagne?'), findsOneWidget);
      await tester.tap(find.text('Annuller'));
      await _settle(tester);
      expect(s.plan.calls, isEmpty);
      expect(find.byType(AddCustomMealSheet), findsOneWidget);

      await tester.tap(find.text('Gem måltid'));
      await _settle(tester);
      await tester.tap(find.text('Erstat'));
      await _settle(tester);
      expect(s.plan.calls, ['Tirsdag|dinner|null|Pizza']);
      expect(find.byType(AddCustomMealSheet), findsNothing);
    });

    testWidgets('Eget måltid oven på et eget måltid spørger også',
        (tester) async {
      final s = await _open(tester, day: 'Onsdag');
      await _toOwnMeal(tester);
      await _saveOwnMeal(tester, 'Pizza');

      expect(find.text('Erstat Rester?'), findsOneWidget);
      await tester.tap(find.text('Erstat'));
      await _settle(tester);
      expect(s.plan.calls, ['Onsdag|dinner|null|Pizza']);
    });

    testWidgets('tom plads: ingen dialog', (tester) async {
      final s = await _open(tester, day: 'Torsdag');
      await tester.tap(_inSheet(find.text('Thai karry')));
      await _settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(s.plan.calls, ['Torsdag|dinner|r2|null']);
    });

    testWidgets('samme opskrift igen: ingen dialog', (tester) async {
      final s = await _open(tester);
      await tester.tap(_inSheet(find.text('Lasagne')).last);
      await _settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(s.plan.calls, ['Tirsdag|dinner|r1|null']);
    });

    testWidgets('anden dag valgt i arket: tjekker den valgte dag',
        (tester) async {
      final s = await _open(tester, day: 'Torsdag');
      // Kortet for tirsdag (andet kort i ugen).
      await tester.tap(_inSheet(find.text('TIR')));
      await _settle(tester);
      await tester.tap(_inSheet(find.text('Thai karry')));
      await _settle(tester);
      expect(find.text('Erstat Lasagne?'), findsOneWidget);
      expect(s.plan.calls, isEmpty);
    });
  });

  group('tilgængelighed og layout', () {
    testWidgets('tælleknapperne har labels og virker', (tester) async {
      await _open(tester);
      await _toOwnMeal(tester);
      expect(find.byTooltip('Færre personer'), findsOneWidget);
      expect(find.byTooltip('Flere personer'), findsOneWidget);
      await tester.tap(find.byTooltip('Flere personer'));
      await tester.pump();
      expect(_inSheet(find.text('5')), findsOneWidget);
      await tester.tap(find.byTooltip('Færre personer'));
      await tester.pump();
      expect(_inSheet(find.text('4')), findsOneWidget);
    });

    for (final tab in ['Søg opskrifter', 'Eget måltid']) {
      testWidgets('guidelines på fanen "$tab"', (tester) async {
        final handle = tester.ensureSemantics();
        await _open(tester);
        await tester.tap(_inSheet(find.text(tab)));
        await _settle(tester);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        handle.dispose();
      });

      testWidgets('ingen overflow på 320 px: "$tab"', (tester) async {
        await _open(tester, size: const Size(320, 640));
        await tester.tap(_inSheet(find.text(tab)));
        await _settle(tester);
        // Rul hele formularen igennem, så alle dele bliver bygget.
        await tester.drag(_inSheet(find.byType(SingleChildScrollView)).first,
            const Offset(0, -2000));
        await _settle(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Gem også som opskrift', () {
    test('parseIngredientAmount læser mængde og enhed', () {
      expect(parseIngredientAmount('400g'),
          (quantity: 400.0, unit: 'g', note: null));
      expect(parseIngredientAmount(' 1,5 KG '),
          (quantity: 1.5, unit: 'kg', note: null));
      expect(parseIngredientAmount('2 dl'),
          (quantity: 2.0, unit: 'dl', note: null));
      expect(parseIngredientAmount('3 cl'),
          (quantity: 3.0, unit: 'cl', note: null));
      expect(
          parseIngredientAmount('2'), (quantity: 2.0, unit: 'stk', note: null));
      expect(parseIngredientAmount('2 store'),
          (quantity: 2.0, unit: 'store', note: null));
      expect(parseIngredientAmount('efter smag'),
          (quantity: 0.0, unit: '', note: 'efter smag'));
      expect(parseIngredientAmount(''), (quantity: 0.0, unit: '', note: null));
      expect(
          parseIngredientAmount('0 g'), (quantity: 0.0, unit: '', note: '0 g'));
      expect(parseIngredientAmount('2 meget store stykker'),
          (quantity: 2.0, unit: 'stk', note: 'meget store stykker'));
    });

    testWidgets('gemmer rigtige mængder og enheder', (tester) async {
      final s = await _open(tester, day: 'Torsdag');
      await _toOwnMeal(tester);
      final fields = _inSheet(find.byType(TextField));
      // Felterne: titel, ingrediens-navn, mængde, noter.
      await tester.enterText(fields.at(1), 'Hakkede tomater');
      await tester.enterText(fields.at(2), '400g');
      await tester.tap(find.text('Tilføj ingrediens'));
      await tester.pump();
      await tester.enterText(_inSheet(find.byType(TextField)).at(3), 'Salt');
      await tester.enterText(
          _inSheet(find.byType(TextField)).at(4), 'efter smag');
      await tester.ensureVisible(find.text('Gem som opskrift'));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await _saveOwnMeal(tester, 'Tomatsuppe');

      expect(s.plan.calls, ['Torsdag|dinner|null|Tomatsuppe']);
      expect(s.recipes.added, hasLength(1));
      final ingredients = s.recipes.added.single.ingredients;
      expect(ingredients.map((i) => (i.name, i.quantity, i.unit)).toList(), [
        ('Hakkede tomater', 400.0, 'g'),
        ('Salt (efter smag)', 0.0, ''),
      ]);
    });
  });

  group('sen faneskift', () {
    testWidgets('uden interaktion skifter fanen, når opskrifterne kommer',
        (tester) async {
      final recipes = StreamController<List<Recipe>>();
      addTearDown(recipes.close);
      await _open(tester, recipes: recipes.stream);
      expect(find.text('Tilføj eget måltid'), findsOneWidget);
      recipes.add([_lasagne, _karry]);
      await _settle(tester);
      expect(find.text('Tilføj måltid'), findsOneWidget);
    });

    final interactions = <String, Future<void> Function(WidgetTester)>{
      'valgt dag': (t) async {
        await t.ensureVisible(_inSheet(find.text('ONS')));
        await t.tap(_inSheet(find.text('ONS')));
      },
      'valgt kategori': (t) => t.tap(_inSheet(find.byType(ChoiceChip)).first),
      'Gem som opskrift': (t) async {
        await t.ensureVisible(find.byType(Checkbox));
        await t.tap(find.byType(Checkbox));
      },
      'skrevet ingrediens': (t) =>
          t.enterText(_inSheet(find.byType(TextField)).at(1), 'Løg'),
      'skrevet noter': (t) =>
          t.enterText(_inSheet(find.byType(TextField)).last, 'Husk brød'),
      'ændret personer': (t) => t.tap(find.byTooltip('Flere personer')),
    };
    for (final MapEntry(key: name, value: interact) in interactions.entries) {
      testWidgets('efter $name bliver fanen', (tester) async {
        final recipes = StreamController<List<Recipe>>();
        addTearDown(recipes.close);
        await _open(tester, recipes: recipes.stream);
        await interact(tester);
        await tester.pump();
        recipes.add([_lasagne, _karry]);
        await _settle(tester);
        expect(find.text('Tilføj eget måltid'), findsOneWidget);
      });
    }
  });
}
