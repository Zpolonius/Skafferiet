import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:skafferiet/core/models/recipe.dart';

void main() {
  group('MealSlot / DailyPlan med manglende opskrift', () {
    test('DailyPlan.isEmpty er false når en slot peger på en slettet opskrift',
        () {
      final plan = DailyPlan.empty().copyWith(
        dinner: MealSlot(recipeId: 'gone', missingRecipe: true),
      );
      expect(plan.isEmpty, isFalse);
      expect(DailyPlan.empty().isEmpty, isTrue);
    });

    test('toMap skriver kun recipeId og directEntry', () {
      final map = MealSlot(recipeId: 'gone', missingRecipe: true).toMap();
      expect(map, {'recipeId': 'gone', 'directEntry': null});
    });

    test('copyWith bevarer recipeId og missingRecipe', () {
      final slot = MealSlot(recipeId: 'gone', missingRecipe: true)
          .copyWith(directEntry: 'x');
      expect(slot.recipeId, 'gone');
      expect(slot.missingRecipe, isTrue);
    });

    test('copyWith med ny opskrift fjerner "mangler" og skifter id', () {
      final recipe = Recipe(
        id: 'new',
        title: 'Lasagne',
        calories: 600,
        time: '45 min',
        category: RecipeCategory.aftensmad,
      );
      final slot = MealSlot(recipeId: 'gone', missingRecipe: true)
          .copyWith(recipe: recipe);
      expect(slot.recipeId, 'new');
      expect(slot.missingRecipe, isFalse);
      expect(slot.toMap()['recipeId'], 'new');
    });
  });
}
