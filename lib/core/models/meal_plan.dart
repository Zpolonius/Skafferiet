import 'meal_type.dart';
import 'recipe.dart';

class MealSlot {
  final Recipe? recipe;
  final String? directEntry; // For "Almonds & Apple Slices" style entries

  /// Id of the linked recipe as stored in Firestore (set even when the recipe
  /// itself could not be resolved).
  final String? recipeId;

  /// True when [recipeId] points to a recipe that no longer exists (only
  /// decided once recipes have loaded).
  final bool missingRecipe;

  MealSlot({
    this.recipe,
    this.directEntry,
    String? recipeId,
    this.missingRecipe = false,
  }) : recipeId = recipeId ?? recipe?.id;

  Map<String, dynamic> toMap() {
    return {
      'recipeId': recipeId,
      'directEntry': directEntry,
    };
  }

  MealSlot copyWith({
    Recipe? recipe,
    String? directEntry,
  }) {
    // En ny opskrift erstatter både id og "mangler"-markeringen.
    return MealSlot(
      recipe: recipe ?? this.recipe,
      directEntry: directEntry ?? this.directEntry,
      recipeId: recipe?.id ?? recipeId,
      missingRecipe: recipe == null && missingRecipe,
    );
  }
}

class DailyPlan {
  final MealSlot breakfast;
  final MealSlot lunch;
  final MealSlot dinner;
  final MealSlot snack;

  DailyPlan({
    required this.breakfast,
    required this.lunch,
    required this.dinner,
    required this.snack,
  });

  factory DailyPlan.empty() {
    return DailyPlan(
      breakfast: MealSlot(),
      lunch: MealSlot(),
      dinner: MealSlot(),
      snack: MealSlot(),
    );
  }

  DailyPlan copyWith({
    MealSlot? breakfast,
    MealSlot? lunch,
    MealSlot? dinner,
    MealSlot? snack,
  }) {
    return DailyPlan(
      breakfast: breakfast ?? this.breakfast,
      lunch: lunch ?? this.lunch,
      dinner: dinner ?? this.dinner,
      snack: snack ?? this.snack,
    );
  }

  MealSlot slot(MealType type) {
    switch (type) {
      case MealType.breakfast: return breakfast;
      case MealType.lunch: return lunch;
      case MealType.dinner: return dinner;
      case MealType.snack: return snack;
    }
  }

  int get totalCalories => totalCaloriesFor(MealType.values);

  /// Kalorier for de måltider brugeren har valgt at se.
  int totalCaloriesFor(Iterable<MealType> types) {
    int total = 0;
    for (final type in types) {
      total += slot(type).recipe?.calories ?? 0;
    }
    return total;
  }

  bool get isEmpty =>
      breakfast.recipe == null &&
      !breakfast.missingRecipe &&
      breakfast.directEntry == null &&
      lunch.recipe == null &&
      !lunch.missingRecipe &&
      lunch.directEntry == null &&
      dinner.recipe == null &&
      !dinner.missingRecipe &&
      dinner.directEntry == null &&
      snack.recipe == null &&
      !snack.missingRecipe &&
      snack.directEntry == null;
}

class WeeklyMealPlan {
  final String id;
  final DateTime weekStart;
  final Map<String, DailyPlan> days; // monday, tuesday, etc.

  WeeklyMealPlan({
    required this.id,
    required this.weekStart,
    required this.days,
  });

  WeeklyMealPlan copyWith({
    String? id,
    DateTime? weekStart,
    Map<String, DailyPlan>? days,
  }) {
    return WeeklyMealPlan(
      id: id ?? this.id,
      weekStart: weekStart ?? this.weekStart,
      days: days ?? this.days,
    );
  }
}
