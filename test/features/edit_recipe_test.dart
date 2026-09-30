import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skafferiet/features/recipes/edit_recipe_screen.dart';
import 'package:skafferiet/features/recipes/recipe_form_widgets.dart';
import 'package:skafferiet/core/models/recipe.dart';

void main() {
  final testRecipe = Recipe(
    id: 'test-1',
    title: 'Test Pasta',
    category: RecipeCategory.aftensmad,
    calories: 500,
    time: '20 min',
    ingredients: [
      Ingredient(name: 'Pasta', quantity: 200, unit: 'g', category: 'Kolonial'),
    ],
  );

  Future<void> pumpScreen(WidgetTester tester, Recipe recipe) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(home: EditRecipeScreen(recipe: recipe))),
    );
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('EditRecipeScreen loads recipe data correctly', (tester) async {
    await pumpScreen(tester, testRecipe);

    expect(find.text('Rediger opskrift'), findsOneWidget);
    expect(find.text('Test Pasta'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(find.text('Pasta'), findsOneWidget);
    expect(find.text('200 g'), findsOneWidget, reason: 'mængder vises uden ".0"');
  });

  testWidgets('Tilføj ingrediens via sheet med enheds-chip og komma-tal', (tester) async {
    await pumpScreen(tester, testRecipe);

    await tapVisible(tester, find.byKey(const Key('add-ingredient')));
    expect(find.text('Tilføj ingrediens'), findsWidgets);

    await tester.enterText(find.byKey(const Key('ingredient-name')), 'Mælk');
    await tester.enterText(find.byKey(const Key('ingredient-quantity')), '1,5');
    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'dl'));
    await tapVisible(tester, find.byKey(const Key('ingredient-submit')));

    expect(find.text('Mælk'), findsOneWidget, reason: 'navnet må ikke gå tabt');
    expect(find.text('1,5 dl'), findsOneWidget);
  });

  testWidgets('Sheet kræver et navn og bliver åbent ved fejl', (tester) async {
    await pumpScreen(tester, testRecipe);

    await tapVisible(tester, find.byKey(const Key('add-ingredient')));
    await tapVisible(tester, find.byKey(const Key('ingredient-submit')));

    expect(find.text('Skriv navnet på ingrediensen'), findsOneWidget);
    expect(find.byKey(const Key('ingredient-name')), findsOneWidget);
  });

  testWidgets('Fjern ingrediens', (tester) async {
    await pumpScreen(tester, testRecipe);
    await tapVisible(tester, find.byTooltip('Fjern Pasta'));
    expect(find.text('Pasta'), findsNothing);
    expect(find.text('Ingen ingredienser endnu.'), findsOneWidget);
  });

  testWidgets('Næring beregnes ud fra ingredienser og portioner', (tester) async {
    final recipe = Recipe(
      id: 'r2',
      title: 'Pasta',
      calories: 0,
      time: '',
      category: RecipeCategory.aftensmad,
      servings: 4,
      ingredients: [
        Ingredient(
          name: 'Spaghetti',
          quantity: 400,
          unit: 'g',
          category: 'Kolonial',
          nutritionPer100: const Nutrition(kcal: 350, protein: 12, carbs: 70, fat: 1.5),
        ),
      ],
    );
    await pumpScreen(tester, recipe);

    expect(find.textContaining('Beregnet ud fra alle 1 ingredienser'), findsOneWidget);
    // Tomme felter viser den beregnede værdi pr. portion som hint.
    final kcalField = tester.widget<TextField>(find.byKey(const Key('recipe-nutrition-Kalorier')));
    expect(kcalField.decoration!.hintText, '350');
    final proteinField = tester.widget<TextField>(find.byKey(const Key('recipe-nutrition-Protein')));
    expect(proteinField.decoration!.hintText, '12');

    // Uden portioner kan der ikke regnes pr. portion.
    await tapVisible(tester, find.byTooltip('Færre portioner')); // 4 → 3
    expect(find.text('3'), findsOneWidget);
  });

  group('NutritionFormControllers.resolve', () {
    const calc = Nutrition(kcal: 349.6, protein: 12.04, carbs: 70, fat: 1.5);

    test('tomme felter bruger beregningen og markeres som beregnet', () {
      final c = NutritionFormControllers();
      final r = c.resolve(calc);
      expect(r.calories, 350);
      expect(r.protein, 12.0);
      expect(r.fromIngredients, isTrue);
    });

    test('brugerens tal vinder over beregningen', () {
      final c = NutritionFormControllers()..kcal.text = '420';
      final r = c.resolve(calc);
      expect(r.calories, 420);
      expect(r.protein, 12.0);
      expect(r.fromIngredients, isFalse);
    });

    test('uden beregning og uden input bliver alt tomt', () {
      final r = NutritionFormControllers().resolve(null);
      expect(r.calories, 0);
      expect(r.protein, isNull);
      expect(r.fromIngredients, isFalse);
    });

    test('for store tal giver fejl', () {
      final c = NutritionFormControllers()..fat.text = '5000';
      expect(c.hasErrors, isTrue);
    });
  });
}
