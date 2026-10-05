import 'package:flutter/material.dart';

import 'recipe.dart';

/// Et måltid i madplanen. [key] er nøglen i `meal_plans`-dokumenterne og i
/// brugerens `mealTypes` — skal matche `firestore.rules`.
enum MealType {
  breakfast('breakfast', 'Morgenmad', Icons.wb_twilight, RecipeCategory.morgenmad),
  lunch('lunch', 'Frokost', Icons.light_mode, RecipeCategory.frokost),
  dinner('dinner', 'Aftensmad', Icons.dark_mode, RecipeCategory.aftensmad),
  snack('snack', 'Snack', Icons.cookie, RecipeCategory.snack);

  final String key;
  final String label;
  final IconData icon;
  final RecipeCategory recipeCategory;

  const MealType(this.key, this.label, this.icon, this.recipeCategory);

  static MealType? fromCategory(RecipeCategory category) =>
      values.where((t) => t.recipeCategory == category).firstOrNull;

  /// Læser brugerens valg fra Firestore. Ukendte værdier ignoreres, og
  /// mangler feltet (eller er intet gyldigt valgt), vises alle måltider.
  static List<MealType> parseList(Object? raw) {
    if (raw is! List) return values;
    final parsed = values.where((t) => raw.contains(t.key)).toList();
    return parsed.isEmpty ? values : parsed;
  }
}
