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

  MealSlot copyWith({
    Recipe? recipe,
    String? directEntry,
  }) {
    return MealSlot(
      recipe: recipe ?? this.recipe,
      directEntry: directEntry ?? this.directEntry,
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

  int get totalCalories {
    int total = 0;
    if (breakfast.recipe != null) total += breakfast.recipe!.calories;
    if (lunch.recipe != null) total += lunch.recipe!.calories;
    if (dinner.recipe != null) total += dinner.recipe!.calories;
    if (snack.recipe != null) total += snack.recipe!.calories;
    return total;
  }

  bool get isEmpty =>
      breakfast.recipe == null &&
      breakfast.directEntry == null &&
      lunch.recipe == null &&
      lunch.directEntry == null &&
      dinner.recipe == null &&
      dinner.directEntry == null &&
      snack.recipe == null &&
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
