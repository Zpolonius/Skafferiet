import 'recipe.dart';

class MealSlot {
  final Recipe? recipe;
  final String? directEntry; // For "Almonds & Apple Slices" style entries

  MealSlot({this.recipe, this.directEntry});

  Map<String, dynamic> toMap() {
    return {
      'recipeId': recipe?.id,
      'directEntry': directEntry,
    };
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
}
