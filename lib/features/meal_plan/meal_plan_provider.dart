import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/meal_plan.dart';
import '../../core/models/recipe.dart';
import '../recipes/recipes_provider.dart';
import '../grocery/grocery_provider.dart';
import '../../core/models/grocery_item.dart';
import '../profile/household_provider.dart';
import 'package:uuid/uuid.dart';

class MealPlanNotifier extends AsyncNotifier<WeeklyMealPlan> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Future<WeeklyMealPlan> build() async {
    final householdId = ref.watch(householdProvider).householdId;
    if (householdId == null) {
      return WeeklyMealPlan(id: 'empty', weekStart: DateTime.now(), days: {});
    }

    final doc = await _firestore.collection('households').doc(householdId).collection('meal_plans').doc('current').get();
    
    if (!doc.exists) {
      return WeeklyMealPlan(id: 'current', weekStart: DateTime.now(), days: {});
    }

    return _mapDocToPlan(doc);
  }

  WeeklyMealPlan _mapDocToPlan(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final daysData = data['days'] as Map<String, dynamic>? ?? {};
    final recipes = ref.read(recipesProvider).value ?? [];

    final Map<String, DailyPlan> days = {};
    daysData.forEach((key, value) {
      days[key] = DailyPlan(
        breakfast: _mapSlot(value['breakfast'], recipes),
        lunch: _mapSlot(value['lunch'], recipes),
        dinner: _mapSlot(value['dinner'], recipes),
        snack: _mapSlot(value['snack'], recipes),
      );
    });

    return WeeklyMealPlan(
      id: doc.id,
      weekStart: DateTime.now(), // Kunne gemmes rigtigt
      days: days,
    );
  }

  MealSlot _mapSlot(Map<String, dynamic>? data, List<Recipe> recipes) {
    if (data == null) return MealSlot();
    Recipe? recipe;
    if (data['recipeId'] != null && recipes.isNotEmpty) {
      recipe = recipes.firstWhere((r) => r.id == data['recipeId'], orElse: () => recipes.first);
    }
    return MealSlot(
      recipe: recipe,
      directEntry: data['directEntry'],
    );
  }

  Future<void> updateSlot(String day, String slotType, {Recipe? recipe, String? directEntry}) async {
    final householdId = ref.read(householdProvider).householdId;
    if (householdId == null) return;

    final planDoc = _firestore.collection('households').doc(householdId).collection('meal_plans').doc('current');
    
    final slotData = {
      'recipeId': recipe?.id,
      'directEntry': directEntry,
    };

    await planDoc.set({
      'days': {
        day: {
          slotType.toLowerCase(): slotData,
        }
      }
    }, SetOptions(merge: true));
    
    ref.invalidateSelf();
  }

  Future<int> transferToShoppingList(GroceryListNotifier groceryNotifier) async {
    if (state.value == null) return 0;
    final plan = state.value!;
    int count = 0;
    
    for (final day in plan.days.values) {
      final slots = [day.breakfast, day.lunch, day.dinner, day.snack];
      for (final slot in slots) {
        if (slot.recipe != null) {
          for (final ing in slot.recipe!.ingredients) {
            await groceryNotifier.addItem(
              GroceryItem(
                id: const Uuid().v4(),
                name: ing.name,
                category: ing.category,
                quantity: ing.quantity.toString(),
                unit: ing.unit,
                source: 'meal_plan',
                createdAt: DateTime.now(),
              ),
            );
            count++;
          }
        }
      }
    }
    return count;
  }
}

final mealPlanProvider = AsyncNotifierProvider<MealPlanNotifier, WeeklyMealPlan>(() {
  return MealPlanNotifier();
});

final selectedDayProvider = StateProvider<String>((ref) => 'Mandag');
