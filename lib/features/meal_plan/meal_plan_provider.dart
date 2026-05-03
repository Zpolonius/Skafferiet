import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/meal_plan.dart';
import '../../core/models/recipe.dart';
import '../recipes/recipes_provider.dart';
import '../grocery/grocery_provider.dart';
import '../../core/models/grocery_item.dart';
import '../profile/household_provider.dart';
import 'package:uuid/uuid.dart';

final weekOffsetProvider = StateProvider<int>((ref) => 0);

class MealPlanNotifier extends AsyncNotifier<WeeklyMealPlan> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DateTime _getWeekStart(DateTime date) {
    // Finder mandagen i den uge, som 'date' tilhører
    return date.subtract(Duration(days: date.weekday - 1));
  }

  String _getWeekId(DateTime date) {
    final start = _getWeekStart(date);
    return '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
  }

  @override
  Future<WeeklyMealPlan> build() async {
    final householdId = ref.watch(householdProvider).householdId;
    final offset = ref.watch(weekOffsetProvider);
    
    final weekStart = _getWeekStart(DateTime.now()).add(Duration(days: offset * 7));
    final weekId = _getWeekId(weekStart);

    if (householdId == null) {
      return WeeklyMealPlan(id: 'empty', weekStart: weekStart, days: {});
    }

    final doc = await _firestore
        .collection('households')
        .doc(householdId)
        .collection('meal_plans')
        .doc(weekId)
        .get();
    
    if (!doc.exists) {
      return WeeklyMealPlan(id: weekId, weekStart: weekStart, days: {});
    }

    return _mapDocToPlan(doc, weekStart);
  }

  WeeklyMealPlan _mapDocToPlan(DocumentSnapshot doc, DateTime weekStart) {
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
      weekStart: weekStart,
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

    final offset = ref.read(weekOffsetProvider);
    final weekStart = _getWeekStart(DateTime.now()).add(Duration(days: offset * 7));
    final weekId = _getWeekId(weekStart);

    final planDoc = _firestore.collection('households').doc(householdId).collection('meal_plans').doc(weekId);
    
    final slotData = {
      'recipeId': recipe?.id,
      'directEntry': directEntry,
    };

    await planDoc.set({
      'days': {
        day.toLowerCase(): {
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
