import '../models/recipe.dart';
import '../models/recipe_units.dart';

/// Resultatet af at regne næring ud fra en opskrifts ingredienser.
class NutritionCalculation {
  /// Summen for hele opskriften.
  final Nutrition total;

  /// Antal ingredienser der indgår i summen.
  final int countedIngredients;

  /// Antal ingredienser i alt (uden tomme navne).
  final int totalIngredients;

  const NutritionCalculation({
    required this.total,
    required this.countedIngredients,
    required this.totalIngredients,
  });

  bool get hasData => countedIngredients > 0;

  /// Næring pr. portion, eller null hvis antal portioner mangler.
  Nutrition? perServing(int? servings) {
    if (!hasData || servings == null || servings < 1) return null;
    return total.scale(1 / servings);
  }
}

/// Regner opskriftens samlede næring ud: for hver ingrediens med næring
/// pr. 100 g/ml ganges med mængden omregnet til gram/ml.
/// Ingredienser uden næringsdata, uden mængde eller med en enhed der ikke
/// kan omregnes (stk, fed …) springes over.
NutritionCalculation calculateNutrition(List<Ingredient> ingredients) {
  var total = Nutrition.zero;
  var counted = 0;
  final named = ingredients.where((i) => i.name.trim().isNotEmpty).toList();

  for (final ing in named) {
    final per100 = ing.nutritionPer100;
    if (per100 == null || ing.quantity <= 0) continue;
    final amount = toGramsOrMl(ing.quantity, ing.unit);
    if (amount == null) continue;
    total = total + per100.scale(amount / 100);
    counted++;
  }

  return NutritionCalculation(
    total: total,
    countedIngredients: counted,
    totalIngredients: named.length,
  );
}
