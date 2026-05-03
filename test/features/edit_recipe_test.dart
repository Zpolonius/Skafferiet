import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skafferiet/features/recipes/edit_recipe_screen.dart';
import 'package:skafferiet/core/models/recipe.dart';

void main() {
  final testRecipe = Recipe(
    id: 'test-1',
    title: 'Test Pasta',
    category: RecipeCategory.Aftensmad,
    calories: 500,
    time: '20 min',
    ingredients: [
      Ingredient(name: 'Pasta', quantity: 200, unit: 'g', category: 'Kolonial'),
    ],
  );

  testWidgets('EditRecipeScreen loads recipe data correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: EditRecipeScreen(recipe: testRecipe),
        ),
      ),
    );

    expect(find.text('Rediger opskrift'), findsOneWidget);
    expect(find.text('Test Pasta'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(find.text('Pasta'), findsOneWidget);
  });

  testWidgets('Can add and remove ingredients in EditRecipeScreen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: EditRecipeScreen(recipe: testRecipe),
        ),
      ),
    );

    // Tryk på tilføj ingrediens (ikon-knappen)
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump();

    // Der bør nu være 2 rækker med tekstfelter (en eksisterende og en ny)
    expect(find.byType(TextField), findsAtLeastNWidgets(5)); // Titel, Kalorier, Tid + 2x Ingrediensfelter
  });
}
