import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/features/recipes/create_recipe_screen.dart';
import 'package:skafferiet/features/recipes/edit_recipe_screen.dart';
import 'package:skafferiet/features/recipes/recipe_detail_screen.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';

/// Fanger det der gemmes, så skærmene kan testes uden Firestore.
class _CapturingNotifier extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  final List<Recipe> recipes;
  Recipe? added;
  Recipe? updated;
  _CapturingNotifier([this.recipes = const []]);

  @override
  Stream<List<Recipe>> build() => Stream.value(recipes);

  @override
  Future<void> addRecipe(Recipe recipe) async => added = recipe;

  @override
  Future<void> updateRecipe(Recipe updatedRecipe) async =>
      updated = updatedRecipe;
}

void main() {
  void phoneSize(WidgetTester tester,
      {double width = 1080, double height = 2400}) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Recipe recipe({List<String> steps = const []}) => Recipe(
        id: 'r1',
        title: 'Gryderet',
        calories: 500,
        time: '40 min',
        category: RecipeCategory.aftensmad,
        ingredients: [
          Ingredient(name: 'Løg', quantity: 2, unit: 'stk', category: 'Grønt')
        ],
        instructions: steps,
        householdId: 'hh',
        createdBy: 'u1',
      );

  group('Opret opskrift', () {
    testWidgets('gemmer fremgangsmåden trimmet og uden tomme trin',
        (tester) async {
      phoneSize(tester);
      final notifier = _CapturingNotifier();
      await tester.pumpWidget(ProviderScope(
        overrides: [recipesProvider.overrideWith(() => notifier)],
        child: const MaterialApp(home: CreateRecipeScreen()),
      ));

      expect(find.text('Fremgangsmåde'), findsOneWidget);
      await tapVisible(tester, find.text('Tilføj trin'));
      await tester.enterText(
          find.widgetWithText(TextField, 'Trin 1'), '  Hak løget  ');
      await tapVisible(tester, find.text('Tilføj trin'));
      await tapVisible(tester, find.text('Tilføj trin'));
      await tester.enterText(
          find.widgetWithText(TextField, 'Trin 3'), 'Steg det');
      await tester.enterText(find.widgetWithText(TextField, 'Trin 2'), '   ');
      await tapVisible(tester, find.text('Opret opskrift'));

      expect(notifier.added, isNotNull);
      expect(notifier.added!.instructions, ['Hak løget', 'Steg det']);
    });
  });

  group('Rediger opskrift', () {
    Future<_CapturingNotifier> pumpEdit(WidgetTester tester, Recipe r,
        {double width = 1080}) async {
      phoneSize(tester, width: width);
      final notifier = _CapturingNotifier([r]);
      await tester.pumpWidget(ProviderScope(
        overrides: [recipesProvider.overrideWith(() => notifier)],
        child: MaterialApp(home: EditRecipeScreen(recipe: r)),
      ));
      return notifier;
    }

    testWidgets('indlæser og bevarer eksisterende trin ved gem',
        (tester) async {
      final notifier =
          await pumpEdit(tester, recipe(steps: ['Hak løget', 'Steg det']));
      expect(find.widgetWithText(TextField, 'Trin 1'), findsOneWidget);
      expect(find.text('Hak løget'), findsOneWidget);
      expect(find.text('Steg det'), findsOneWidget);

      await tapVisible(tester, find.text('Gem ændringer'));
      expect(notifier.updated!.instructions, ['Hak løget', 'Steg det']);
    });

    testWidgets('ændrer, sletter og tilføjer trin', (tester) async {
      final notifier = await pumpEdit(tester, recipe(steps: ['A', 'B', 'C']));

      await tester.enterText(find.widgetWithText(TextField, 'Trin 1'), 'A2');
      await tapVisible(tester, find.byTooltip('Slet trin').at(1));
      await tapVisible(tester, find.text('Tilføj trin'));
      await tester.enterText(find.widgetWithText(TextField, 'Trin 3'), 'D');
      await tapVisible(tester, find.text('Gem ændringer'));

      expect(notifier.updated!.instructions, ['A2', 'C', 'D']);
    });

    testWidgets('kan tømme alle trin', (tester) async {
      final notifier = await pumpEdit(tester, recipe(steps: ['A']));
      await tapVisible(tester, find.byTooltip('Slet trin'));
      await tapVisible(tester, find.text('Gem ændringer'));
      expect(notifier.updated!.instructions, isEmpty);
    });

    testWidgets('trin kan flyttes uden at trække', (tester) async {
      final notifier = await pumpEdit(tester, recipe(steps: ['A', 'B']));
      await tapVisible(tester, find.byTooltip('Flyt ned').first);
      await tapVisible(tester, find.text('Gem ændringer'));
      expect(notifier.updated!.instructions, ['B', 'A']);
    });

    testWidgets('ingen overflow på 360 dp bredde', (tester) async {
      await pumpEdit(tester,
          recipe(steps: ['Et ret langt trin der fylder en del af skærmen']),
          width: 1080);
      await tester.ensureVisible(find.text('Tilføj trin'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Detaljeskærm', () {
    Future<void> pumpDetail(WidgetTester tester, Recipe r) async {
      phoneSize(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          recipesProvider.overrideWith(() => _CapturingNotifier([r]))
        ],
        child: MaterialApp(home: RecipeDetailScreen(recipeId: r.id)),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('viser nummererede trin under ingredienserne', (tester) async {
      await pumpDetail(tester, recipe(steps: ['Hak løget', 'Steg det']));
      await tester.scrollUntilVisible(find.text('Fremgangsmåde'), 300,
          scrollable: find.byType(Scrollable).first);

      expect(find.text('Fremgangsmåde'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Hak løget'), findsOneWidget);
      expect(find.text('Steg det'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Fremgangsmåde')).dy,
        greaterThan(tester.getTopLeft(find.text('Ingredienser')).dy),
      );
    });

    testWidgets('tryk markerer et trin som udført og igen som ikke udført',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpDetail(tester, recipe(steps: ['Hak løget', 'Steg det']));
      await tester.scrollUntilVisible(find.text('Hak løget'), 300,
          scrollable: find.byType(Scrollable).first);

      TextDecoration? deco(String t) =>
          tester.widget<Text>(find.text(t)).style?.decoration;
      expect(deco('Hak løget'), isNot(TextDecoration.lineThrough));

      await tester.tap(find.text('Hak løget'));
      await tester.pump();
      expect(deco('Hak løget'), TextDecoration.lineThrough);
      expect(deco('Steg det'), isNot(TextDecoration.lineThrough));
      expect(tester.getSemantics(find.text('Hak løget')).value,
          contains('udført'));

      await tester.tap(find.text('Hak løget'));
      await tester.pump();
      expect(deco('Hak løget'), isNot(TextDecoration.lineThrough));
      handle.dispose();
    });

    testWidgets('ingen sektion når opskriften ikke har trin', (tester) async {
      await pumpDetail(tester, recipe());
      await tester.scrollUntilVisible(find.text('Ingredienser'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Fremgangsmåde'), findsNothing);
    });
  });
}
