import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/meal_plan.dart';
import '../../core/models/recipe.dart';
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
            snack: MealSlot(directEntry: 'Mandler & Æbler'),
          ),
          'Tirsdag': DailyPlan.empty(),
          'Onsdag': DailyPlan.empty(),
          'Torsdag': DailyPlan.empty(),
          'Fredag': DailyPlan.empty(),
          'Lørdag': DailyPlan.empty(),
          'Søndag': DailyPlan.empty(),
        },
      ),
      loading: () => throw Exception('Henter opskrifter...'),
      error: (err, stack) => throw err,
    );
  }

  Future<void> updateSlot(String day, String slotType, {Recipe? recipe, String? directEntry}) async {
    if (state.value == null) return;
    
    final currentPlan = state.value!;
    final dayPlan = currentPlan.days[day] ?? DailyPlan.empty();
    
    final newSlot = MealSlot(recipe: recipe, directEntry: directEntry);
    
    final newDays = Map<String, DailyPlan>.from(currentPlan.days);
    final updatedDayPlan = _updateDayPlanWithSlot(dayPlan, slotType, newSlot);
    newDays[day] = updatedDayPlan;
    
    state = AsyncValue.data(currentPlan.copyWith(days: newDays));
  }

  DailyPlan _updateDayPlanWithSlot(DailyPlan dayPlan, String slotType, MealSlot slot) {
    switch (slotType) {
      case 'Morgenmad': return dayPlan.copyWith(breakfast: slot);
      case 'Frokost': return dayPlan.copyWith(lunch: slot);
      case 'Aftensmad': return dayPlan.copyWith(dinner: slot);
      case 'Snack': return dayPlan.copyWith(snack: slot);
      default: return dayPlan;
    }
  }
}

final mealPlanProvider = AsyncNotifierProvider<MealPlanNotifier, WeeklyMealPlan>(() {
  return MealPlanNotifier();
});

final selectedDayProvider = StateProvider<String>((ref) => 'Mandag');
