import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/utils/number_format.dart';
import '../../core/models/meal_plan.dart';
import '../../core/models/recipe.dart';
import '../../core/services/item_history_writer.dart';
import '../recipes/recipes_provider.dart';

import '../profile/household_provider.dart';


/// Kastes af [MealPlanNotifier.restoreSlot] når pladsen er fyldt igen.
class SlotChangedException implements Exception {
  const SlotChangedException();
  @override
  String toString() => 'SlotChangedException';

  /// På web pakkes fejl fra en transaktion ind i et JS-objekt, så typen
  /// forsvinder; derfor kigges der også på teksten.
  static bool matches(Object error) =>
      error is SlotChangedException || error.toString().contains('SlotChangedException');
}

/// Offline-fejl fra Firestore. Også her kan typen være pakket ind på web.
bool _isUnavailable(Object error) =>
    error is FirebaseException
        ? error.code == 'unavailable'
        : error.toString().contains('[cloud_firestore/unavailable]');

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

  /// Id (mandagens dato) på den uge madplanen viser lige nu.
  String currentWeekId() {
    final offset = ref.read(weekOffsetProvider);
    return _getWeekId(_getWeekStart(DateTime.now()).add(Duration(days: offset * 7)));
  }

  DocumentReference<Map<String, dynamic>>? _planDoc(String weekId) {
    final householdId = ref.read(householdProvider).householdId;
    if (householdId == null) return null;
    return _firestore.collection('households').doc(householdId).collection('meal_plans').doc(weekId);
  }

  Future<void> updateSlot(String day, String slotType, {Recipe? recipe, String? directEntry}) async {
    final planDoc = _planDoc(currentWeekId());
    if (planDoc == null) return;
    await planDoc.set(_slotPayload(day, slotType, recipe?.id, directEntry), SetOptions(merge: true));
  }

  /// Fortryd: skriver et måltid tilbage præcis som det var, også når opskriften
  /// ikke findes mere (der er så kun et [MealSlot.recipeId], intet [Recipe]).
  ///
  /// Skriver kun hvis pladsen stadig er tom. Har et andet medlem fyldt den i
  /// mellemtiden, kastes [SlotChangedException] og intet overskrives. Står det
  /// gamle måltid der allerede, sker der intet.
  /// [weekId] er ugen måltidet stod i (se [currentWeekId]); uden den bruges den
  /// viste uge.
  ///
  /// [ownRemovePending] skal være true, hvis serveren endnu ikke har bekræftet
  /// den sletning, der fortrydes. En transaktion læser fra serveren, hvor
  /// sletningen så ikke er nået frem, og ville fejlagtigt melde en konflikt. I
  /// stedet tjekkes den lokale kopi (som allerede viser sletningen), og en
  /// almindelig skrivning lægges i kø efter sletningen.
  Future<void> restoreSlot(
    String day,
    String slotType,
    MealSlot slot, {
    String? weekId,
    bool ownRemovePending = false,
  }) async {
    final planDoc = _planDoc(weekId ?? currentWeekId());
    if (planDoc == null) return;
    final key = slotType.toLowerCase();
    final payload = _slotPayload(day, slotType, slot.recipeId, slot.directEntry);

    Map? current(Map<String, dynamic>? data) {
      final days = data?['days'];
      final value = days is Map && days[day] is Map ? (days[day] as Map)[key] : null;
      return value is Map ? value : null;
    }

    bool filled(Map? c) => c != null && (c['recipeId'] != null || c['directEntry'] != null);
    bool isPrevious(Map? c) =>
        c != null && c['recipeId'] == slot.recipeId && c['directEntry'] == slot.directEntry;

    Future<void> restoreFromCache() async {
      Map<String, dynamic>? cached;
      try {
        cached = (await planDoc.get(const GetOptions(source: Source.cache))).data();
      } catch (_) {
        cached = null; // ukendt; skriv alligevel (pladsen blev netop ryddet)
      }
      final c = current(cached);
      if (isPrevious(c)) return;
      if (filled(c)) throw const SlotChangedException();
      await planDoc.set(payload, SetOptions(merge: true));
    }

    if (ownRemovePending) return restoreFromCache();

    try {
      await _firestore.runTransaction((tx) async {
        final c = current((await tx.get(planDoc)).data());
        if (isPrevious(c)) return;
        if (filled(c)) throw const SlotChangedException();
        tx.set(planDoc, payload, SetOptions(merge: true));
      });
    } catch (e) {
      // Offline kan en transaktion ikke køres. Så tjekkes den lokale kopi, og
      // en almindelig skrivning lægges i kø og synkroniseres senere.
      if (!_isUnavailable(e)) rethrow;
      await restoreFromCache();
    }
  }

  Map<String, dynamic> _slotPayload(String day, String slotType, String? recipeId, String? directEntry) => {
        'days': {
          day: {
            slotType.toLowerCase(): {
              'recipeId': recipeId,
              'directEntry': directEntry,
            },
          }
        }
      };

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
              'quantity': formatQuantity(ing.quantity),
              'unit': ing.unit,
              'source': 'meal_plan',
              'isChecked': false,
              'createdAt': DateTime.now().millisecondsSinceEpoch,
            });
            ItemHistoryWriter.addToBatch(
              batch,
              _firestore,
              householdId,
              name: ing.name,
              category: ing.category,
              unit: ing.unit,
              quantity: formatQuantity(ing.quantity),
            );
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
