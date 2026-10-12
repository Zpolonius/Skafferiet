// Redigering af trin (#25) bevarer alle andre felter på opskriften.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/features/recipes/edit_recipe_screen.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';

class _Cap extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  final List<Recipe> recipes;
  Recipe? updated;
  _Cap(this.recipes);
  @override
  Stream<List<Recipe>> build() => Stream.value(recipes);
  @override
  Future<void> updateRecipe(Recipe r) async => updated = r;
}

void main() {
  testWidgets('ret trin: øvrige felter uændrede', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final r = Recipe(
      id: 'r1',
      title: 'Gryde',
      calories: 420,
      time: '30 min',
      category: RecipeCategory.frokost,
      ingredients: [
        Ingredient(name: 'Ris', quantity: 500, unit: 'g', category: 'Kolonial')
      ],
      instructions: ['A', 'B'],
      householdId: 'hh',
      createdBy: 'u1',
      servings: 4,
      protein: 20,
      carbs: 50,
      fat: 10,
    );
    final n = _Cap([r]);
    await tester.pumpWidget(ProviderScope(
      overrides: [recipesProvider.overrideWith(() => n)],
      child: MaterialApp(home: EditRecipeScreen(recipe: r)),
    ));
    await tester.enterText(find.widgetWithText(TextField, 'Trin 2'), ' B2 ');
    await tester.ensureVisible(find.text('Gem ændringer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gem ændringer'));
    await tester.pumpAndSettle();
    final u = n.updated!;
    expect(u.instructions, ['A', 'B2']);
    expect([
      u.title,
      u.imageUrl,
      u.calories,
      u.time,
      u.category,
      u.servings,
      u.protein,
      u.carbs,
      u.fat,
      u.householdId,
      u.createdBy
    ], [
      r.title,
      r.imageUrl,
      r.calories,
      r.time,
      r.category,
      r.servings,
      r.protein,
      r.carbs,
      r.fat,
      r.householdId,
      r.createdBy
    ]);
    expect(u.ingredients.single.name, 'Ris');
    expect(u.ingredients.single.quantity, 500);
  });
}
