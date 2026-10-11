import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/meal_plan.dart';
import '../../core/models/recipe.dart';
import '../recipes/recipes_provider.dart';

import '../profile/household_provider.dart';


final weekOffsetProvider = StateProvider<int>((ref) => 0);

class MealPlanNotifier extends StreamNotifier<WeeklyMealPlan> {
  final FirebaseFirestore _firestore;

  MealPlanNotifier({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  DateTime _getWeekStart(DateTime date) {
    // Finder mandagen i den uge, som 'date' tilhører
    return date.subtract(Duration(days: date.weekday - 1));
  }

  String _getWeekId(DateTime date) {
    final start = _getWeekStart(date);
    return '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
  }

  @override
  Stream<WeeklyMealPlan> build() {
    // Kun husstand og uge styrer Firestore-abonnementet. Opskrifter lyttes der
    // separat til, så abonnementet ikke genstartes (og UI'et ikke viser en
    // spinner), når opskrifter indlæses eller ændres.
    final householdId = ref.watch(householdProvider).householdId;
    final offset = ref.watch(weekOffsetProvider);

    final weekStart = _getWeekStart(DateTime.now()).add(Duration(days: offset * 7));
    final weekId = _getWeekId(weekStart);

    if (householdId == null) {
      return Stream.value(WeeklyMealPlan(id: 'empty', weekStart: weekStart, days: {}));
    }

    final controller = StreamController<WeeklyMealPlan>();
    DocumentSnapshot<Map<String, dynamic>>? latest;

    void emit() {
      final doc = latest;
      if (doc == null || controller.isClosed) return;
      if (!doc.exists) {
        controller.add(WeeklyMealPlan(id: weekId, weekStart: weekStart, days: {}));
        return;
      }
      controller.add(_mapDocToPlan(doc, weekStart, ref.read(recipesProvider)));
    }

    final sub = _firestore
        .collection('households')
        .doc(householdId)
        .collection('meal_plans')
        .doc(weekId)
        .snapshots()
        .listen((doc) {
      latest = doc;
      emit();
    }, onError: controller.addError);

    // Opskrifter der indlæses/ændres genberegner planen uden at gå via loading.
    ref.listen(recipesProvider, (_, __) => emit());

    ref.onDispose(() {
      sub.cancel();
      controller.close();
    });

    return controller.stream;
  }

  WeeklyMealPlan _mapDocToPlan(
    DocumentSnapshot<Map<String, dynamic>> doc,
    DateTime weekStart,
    AsyncValue<List<Recipe>> recipesAsync,
  ) {
    final data = doc.data() ?? {};
    final daysData = data['days'] as Map<String, dynamic>? ?? {};
    // null = opskrifter ikke indlæst endnu; så afgør vi ikke om en opskrift mangler.
    final recipes = recipesAsync.hasValue ? recipesAsync.value : null;

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

  MealSlot _mapSlot(Map<String, dynamic>? data, List<Recipe>? recipes) {
    if (data == null) return MealSlot();
    final recipeId = data['recipeId'] as String?;
    Recipe? recipe;
    var missing = false;
    if (recipeId != null && recipes != null) {
      final matches = recipes.where((r) => r.id == recipeId);
      if (matches.isEmpty) {
        missing = true;
      } else {
        recipe = matches.first;
      }
    }
    return MealSlot(
      recipe: recipe,
      recipeId: recipeId,
      missingRecipe: missing,
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
        day: {
          slotType.toLowerCase(): slotData,
        }
      }
    }, SetOptions(merge: true));
  }

  Future<int> transferToShoppingList() async {
    final householdId = ref.read(householdProvider).householdId;
    // Under skift af uge/husstand viser state stadig den forrige plan.
    if (householdId == null || state.isLoading || state.value == null) return 0;

    final plan = state.value!;
    final batch = _firestore.batch();
    int count = 0;
    
    for (final day in plan.days.values) {
      final slots = [day.breakfast, day.lunch, day.dinner, day.snack];
      for (final slot in slots) {
        if (slot.recipe != null) {
          for (final ing in slot.recipe!.ingredients) {
            final docRef = _firestore
                .collection('households')
                .doc(householdId)
                .collection('grocery_list')
                .doc(); // Genererer nyt ID
            
            batch.set(docRef, {
              'name': ing.name,
              'category': ing.category,
              'quantity': ing.quantity.toString(),
              'unit': ing.unit,
              'source': 'meal_plan',
              'isChecked': false,
              'createdAt': DateTime.now().millisecondsSinceEpoch,
            });
            count++;
          }
        }
      }
    }

    if (count > 0) {
      await batch.commit();
    }
    
    return count;
  }
}

final mealPlanProvider = StreamNotifierProvider<MealPlanNotifier, WeeklyMealPlan>(
  MealPlanNotifier.new,
);

final selectedDayProvider = StateProvider<String>((ref) => 'Mandag');
