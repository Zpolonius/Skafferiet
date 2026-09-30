import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/features/recipes/ingredient_sheet.dart';
import 'package:skafferiet/features/recipes/recipe_detail_screen.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';

class _FixedRecipesNotifier extends StreamNotifier<List<Recipe>> with Mock implements RecipesNotifier {
  final List<Recipe> recipes;
  _FixedRecipesNotifier(this.recipes);

  @override
  Stream<List<Recipe>> build() => Stream.value(recipes);
}

void main() {
  void phoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('IngredientSheet', () {
    Future<Ingredient?> Function() openSheet(WidgetTester tester, {Ingredient? initial}) {
      Ingredient? result;
      var done = false;
      return () async {
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showIngredientSheet(context, initial: initial);
                  done = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        return done ? result : null;
      };
    }

    testWidgets('gemmer næring pr. 100 g på ingrediensen', (tester) async {
      phoneSize(tester);
      Ingredient? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await showIngredientSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('ingredient-name')), 'Havregryn');
      await tester.enterText(find.byKey(const Key('ingredient-quantity')), '100');
      await tapVisible(tester, find.byKey(const Key('ingredient-add-nutrition')));
      expect(find.text('Næring pr. 100 g'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('ingredient-nutrition-Energi')), '370');
      await tester.enterText(find.byKey(const Key('ingredient-nutrition-Protein')), '13,5');
      await tapVisible(tester, find.byKey(const Key('ingredient-submit')));

      expect(result, isNotNull);
      expect(result!.name, 'Havregryn');
      expect(result!.unit, 'g');
      expect(result!.nutritionPer100!.kcal, 370);
      expect(result!.nutritionPer100!.protein, 13.5);
      expect(result!.nutritionPer100!.fat, 0, reason: 'tomme felter tæller som 0');
    });

    testWidgets('næring gemmes ikke for enheder der ikke kan omregnes', (tester) async {
      phoneSize(tester);
      final existing = Ingredient(
        name: 'Løg',
        quantity: 2,
        unit: 'g',
        category: 'Grønt',
        nutritionPer100: const Nutrition(kcal: 40),
      );
      Ingredient? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await showIngredientSheet(context, initial: existing),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Ret ingrediens'), findsOneWidget);
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'stk'));
      expect(find.textContaining('Næring kan kun regnes ud'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('ingredient-submit')));

      expect(result!.unit, 'stk');
      expect(result!.nutritionPer100, isNull);
      expect(result!.category, 'Grønt', reason: 'kategori bevares ved redigering');
    });

    testWidgets('egen enhed via "+ Anden"', (tester) async {
      phoneSize(tester);
      final open = openSheet(tester);
      await open();
      await tester.enterText(find.byKey(const Key('ingredient-name')), 'Salt');
      await tapVisible(tester, find.widgetWithText(ChoiceChip, '+ Anden'));
      await tapVisible(tester, find.byKey(const Key('ingredient-submit')));
      expect(find.text('Skriv en enhed'), findsOneWidget, reason: 'tom egen enhed afvises');
      await tester.enterText(find.byKey(const Key('ingredient-custom-unit')), 'knivspids');
      await tapVisible(tester, find.byKey(const Key('ingredient-submit')));
      expect(find.byKey(const Key('ingredient-name')), findsNothing, reason: 'sheet lukker');
    });
  });

  group('RecipeDetailScreen', () {
    Future<void> pumpDetail(WidgetTester tester, Recipe recipe) async {
      phoneSize(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          recipesProvider.overrideWith(() => _FixedRecipesNotifier([recipe]))
        ],
        child: MaterialApp(home: RecipeDetailScreen(recipeId: recipe.id)),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('viser næring pr. portion, portioner og rigtig tid', (tester) async {
      await pumpDetail(
        tester,
        Recipe(
          id: 'r1',
          title: 'Grød',
          calories: 350,
          time: '10 min',
          category: RecipeCategory.morgenmad,
          servings: 2,
          protein: 12.5,
          carbs: 58,
          fat: 7,
          nutritionFromIngredients: true,
          ingredients: [Ingredient(name: 'Mælk', quantity: 1.5, unit: 'dl', category: 'Mejeri')],
        ),
      );

      expect(find.text('10 min'), findsOneWidget);
      expect(find.text('25 min'), findsNothing);
      expect(find.text('2 portioner'), findsOneWidget);
      expect(find.text('350'), findsOneWidget);
      expect(find.text('12,5 g'), findsOneWidget);
      expect(find.text('Pr. portion · beregnet ud fra ingredienserne'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('1,5 dl'), 200);
      expect(find.text('1,5 dl'), findsOneWidget);
    });

    testWidgets('skjuler næring for ældre opskrifter uden data', (tester) async {
      await pumpDetail(
        tester,
        Recipe(id: 'r2', title: 'Gammel', calories: 0, time: '', category: RecipeCategory.snack),
      );
      expect(find.text('kcal'), findsNothing);
      expect(find.byIcon(Icons.schedule), findsNothing);
    });
  });
}
