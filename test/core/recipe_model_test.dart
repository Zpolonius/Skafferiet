import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/models/recipe.dart';

void main() {
  test('Ingredient gemmer og indlæser næring pr. 100', () {
    final original = Ingredient(
      name: 'Havregryn',
      quantity: 100,
      unit: 'g',
      category: 'Kolonial',
      nutritionPer100: const Nutrition(kcal: 370, protein: 13, carbs: 58, fat: 7),
    );
    final restored = Ingredient.fromMap(original.toMap());
    expect(restored.name, 'Havregryn');
    expect(restored.nutritionPer100!.kcal, 370);
    expect(restored.nutritionPer100!.fat, 7);
  });

  test('ældre ingredienser uden næring kan stadig læses', () {
    final restored = Ingredient.fromMap({'name': 'Løg', 'quantity': 1, 'unit': 'stk', 'category': 'Grønt'});
    expect(restored.nutritionPer100, isNull);
    expect(restored.toMap().containsKey('nutrition'), isFalse);
  });

  test('ugyldige næringsdata i databasen ignoreres', () {
    expect(Nutrition.fromMap({'kcal': -5}), isNull);
    expect(Nutrition.fromMap({'kcal': 'mange'}), isNull);
    expect(Nutrition.fromMap('ikke et map'), isNull);
    expect(Nutrition.fromMap({'kcal': 100})!.protein, 0);
  });

  test('hasNutrition er false for opskrifter uden næring', () {
    final r = Recipe(id: '1', title: 'T', calories: 0, time: '', category: RecipeCategory.snack);
    expect(r.hasNutrition, isFalse);
    expect(r.copyWith(protein: 10).hasNutrition, isTrue);
  });
}
