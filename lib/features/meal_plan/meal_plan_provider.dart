import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/meal_plan.dart';
import '../recipes/recipes_provider.dart';

class MealPlanNotifier extends AsyncNotifier<WeeklyMealPlan> {
  @override
  Future<WeeklyMealPlan> build() async {
    final recipesAsync = ref.watch(recipesProvider);
    
    return recipesAsync.when(
      data: (recipes) => WeeklyMealPlan(
        id: 'week1',
        weekStart: DateTime.now(),
        days: {
          'Mandag': DailyPlan(
            breakfast: MealSlot(recipe: recipes[0]),
            lunch: MealSlot(recipe: recipes[1]),
            dinner: MealSlot(),
            snack: MealSlot(directEntry: 'Almonds & Apple Slices'),
          ),
          'Tirsdag': DailyPlan.empty(),
          'Onsdag': DailyPlan.empty(),
          'Torsdag': DailyPlan.empty(),
          'Fredag': DailyPlan.empty(),
          'Lørdag': DailyPlan.empty(),
          'Søndag': DailyPlan.empty(),
        },
      ),
      loading: () => throw Exception('Loading recipes...'),
      error: (err, stack) => throw err,
    );
  }
}

final mealPlanProvider = AsyncNotifierProvider<MealPlanNotifier, WeeklyMealPlan>(() {
  return MealPlanNotifier();
});

final selectedDayProvider = StateProvider<String>((ref) => 'Mandag');
