import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:skafferiet/core/models/meal_type.dart';
import 'package:skafferiet/core/models/recipe.dart';

Recipe _recipe(int kcal) =>
    Recipe(id: '$kcal', title: 'R', calories: kcal, time: '', category: RecipeCategory.aftensmad);

void main() {
  group('MealType.parseList', () {
    test('manglende eller ugyldigt felt giver alle måltider', () {
      expect(MealType.parseList(null), MealType.values);
      expect(MealType.parseList('dinner'), MealType.values);
      expect(MealType.parseList(<String>[]), MealType.values);
      expect(MealType.parseList(['brunch']), MealType.values);
    });

    test('ukendte værdier ignoreres og rækkefølgen er altid fast', () {
      expect(MealType.parseList(['snack', 'brunch', 'breakfast']),
          [MealType.breakfast, MealType.snack]);
    });

    test('nøglerne matcher meal_plans-dokumenterne', () {
      expect(MealType.values.map((t) => t.key), ['breakfast', 'lunch', 'dinner', 'snack']);
    });
  });

  group('DailyPlan', () {
    final plan = DailyPlan(
      breakfast: MealSlot(recipe: _recipe(300)),
      lunch: MealSlot(recipe: _recipe(500)),
      dinner: MealSlot(recipe: _recipe(700)),
      snack: MealSlot(directEntry: 'Æble'),
    );

    test('slot finder det rigtige måltid', () {
      expect(plan.slot(MealType.lunch).recipe?.calories, 500);
      expect(plan.slot(MealType.snack).directEntry, 'Æble');
    });

    test('totalCaloriesFor tæller kun de valgte måltider', () {
      expect(plan.totalCalories, 1500);
      expect(plan.totalCaloriesFor([MealType.breakfast, MealType.dinner]), 1000);
    });
  });
}
