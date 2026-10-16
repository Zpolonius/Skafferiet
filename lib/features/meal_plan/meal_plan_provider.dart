import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/utils/number_format.dart';
import '../../core/models/meal_plan.dart';
import '../../core/models/recipe.dart';
import '../../core/services/item_history_writer.dart';
import '../../core/services/week_copy.dart';
import '../../core/services/week_dates.dart';
import '../grocery/recurring/recurring_items_provider.dart' show clockProvider;
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

/// Hvor mange uger fra den aktuelle uge madplanen viser (0 = denne uge).
final weekOffsetProvider = StateProvider<int>((ref) => 0);

/// Den valgte dag i madplanen (dansk ugedagsnavn).
final selectedDayProvider = StateProvider<String>((ref) => 'Mandag');

/// I dag (kl. 00:00). Alt der afhænger af "den aktuelle uge" – planen, skrivninger,
/// overskrift, weekendhjælp – udledes herfra, så de aldrig er uenige. Står appen
/// åben hen over midnat, kalder [DayRollover] [TodayNotifier.refresh].
final todayProvider = NotifierProvider<TodayNotifier, DateTime>(TodayNotifier.new);

class TodayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => _read();

  DateTime _read() {
    final now = ref.read(clockProvider)();
    return DateTime(now.year, now.month, now.day);
  }

  /// Læser uret igen. Er datoen skiftet, flyttes visningen med: en uge man har
  /// bladret til forbliver den samme uge, "denne uge" følger med, og valgt dag
  /// bliver i dag, når man ser den aktuelle uge. (Ved kold start er valgt dag
  /// stadig [selectedDayProvider]s standard, mandag, som før #56.)
  void refresh() {
    final today = _read();
    if (today == state) return;
    final weeks = weeksBetween(state, today);
    final offset = ref.read(weekOffsetProvider);
    final newOffset = offset == 0 ? 0 : offset - weeks;
    if (newOffset != offset) ref.read(weekOffsetProvider.notifier).state = newOffset;
    if (newOffset == 0) {
      ref.read(selectedDayProvider.notifier).state = planDayNames[today.weekday - 1];
    }
    state = today;
  }
}

/// Ugen (id = mandagens dato) hvis weekendhjælp "Planlægger du næste uge?" er
/// lukket. Kun i hukommelsen: den kommer igen næste weekend.
final weekendHintDismissedProvider = StateProvider<String?>((ref) => null);

/// Uger (id) hvor tilbuddet om at kopiere forrige uge er lukket.
final copyOfferDismissedProvider = StateProvider<Set<String>>((ref) => const {});

/// De udfyldte måltider i ugen [weekId].
class WeekSlots {
  final String weekId;
  final List<PlannedSlot> slots;
  const WeekSlots(this.weekId, this.slots);
}

/// Ugen før den viste uge. Fejl (fx ingen forbindelse til Firestore) betyder
/// blot at tilbuddet om at kopiere ikke vises.
final previousWeekSlotsProvider = StreamProvider.autoDispose<WeekSlots>((ref) {
  final offset = ref.watch(weekOffsetProvider);
  ref.watch(todayProvider);
  ref.watch(householdProvider.select((h) => h.householdId));
  return ref.watch(mealPlanProvider.notifier).watchWeekSlots(offset - 1);
});

/// Resultatet af [MealPlanNotifier.copyWeek]. [write] er skrivningen; den
/// fuldføres først når serveren har svaret, så vent ikke på den i UI'et.
class WeekCopy {
  final String weekId;
  final List<PlannedSlot> slots;
  final Future<void> write;
  const WeekCopy(this.weekId, this.slots, this.write);
}

class MealPlanNotifier extends StreamNotifier<WeeklyMealPlan> {
  final FirebaseFirestore _firestore;

  MealPlanNotifier({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Mandagen i den uge der ligger [offset] uger fra den aktuelle.
  DateTime _weekStartFor(int offset) =>
      addWeeks(weekStartOf(ref.read(todayProvider)), offset);

  @override
  Stream<WeeklyMealPlan> build() {
    // Kun husstand og uge styrer Firestore-abonnementet. Opskrifter lyttes der
    // separat til, så abonnementet ikke genstartes (og UI'et ikke viser en
    // spinner), når opskrifter indlæses eller ændres.
    final householdId = ref.watch(householdProvider).householdId;
    final offset = ref.watch(weekOffsetProvider);
    ref.watch(todayProvider);

    final weekStart = _weekStartFor(offset);
    final weekId = weekIdOf(weekStart);

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
    return weekIdOf(_weekStartFor(ref.read(weekOffsetProvider)));
  }

  /// De udfyldte måltider i ugen [offset] uger fra den aktuelle, live.
  Stream<WeekSlots> watchWeekSlots(int offset) {
    final id = weekIdOf(_weekStartFor(offset));
    final planDoc = _planDoc(id);
    if (planDoc == null) return Stream.value(WeekSlots(id, const []));
    return planDoc.snapshots().map((doc) => WeekSlots(id, slotsOfData(doc.data())));
  }

  /// Kopierer måltiderne [from] (typisk ugen før) til den viste uge. Kun tomme
  /// pladser udfyldes. Returnerer null hvis den viste uge ikke er indlæst, eller
  /// der intet er at kopiere (fx fordi et andet medlem har fyldt pladserne).
  ///
  /// Online køres det som en transaktion, der læser ugens dokument på serveren
  /// og kun fylder pladser der er tomme dér, så en forældet lokal kopi aldrig
  /// får et andet medlems måltid overskrevet. Offline kan en transaktion ikke
  /// køres; så bruges den lokale kopi og én `set(merge)` lægges i kø. Det er en
  /// bevidst afvejning: uden forbindelse kan vi ikke se serveren, og den lokale
  /// kopi er det bedste vi har. Offline kan kaldet vare et par sekunder, før
  /// transaktionen opgiver.
  Future<WeekCopy?> copyWeek({required List<PlannedSlot> from}) async {
    final weekId = currentWeekId();
    final planDoc = _planDoc(weekId);
    final plan = state.valueOrNull;
    // Under ugeskift viser state stadig den forrige uges plan.
    if (planDoc == null || plan == null || plan.id != weekId) return null;

    try {
      List<PlannedSlot> copied = const [];
      await _firestore.runTransaction((tx) async {
        final data = (await tx.get(planDoc)).data();
        copied = slotsToCopy(previous: from, current: slotsOfData(data));
        if (copied.isEmpty) return;
        tx.set(planDoc, withSlotsSet(data, copied));
      });
      if (copied.isEmpty) return null;
      return WeekCopy(weekId, copied, Future.value());
    } catch (e) {
      if (!_isUnavailable(e)) rethrow;
    }

    final slots = slotsToCopy(previous: from, current: slotsOfPlan(plan));
    if (slots.isEmpty) return null;
    final write = planDoc.set(slotsPayload(slots), SetOptions(merge: true));
    return WeekCopy(weekId, slots, write);
  }

  /// Fortryd [copyWeek]: rydder præcis de kopierede måltider, men kun dem der
  /// stadig er som kopieret. Er ingen af dem det, kastes
  /// [SlotChangedException]. Andre måltider i ugen røres ikke.
  ///
  /// [ownWritePending] skal være true, hvis serveren endnu ikke har bekræftet
  /// kopieringen ([WeekCopy.write]); så tjekkes den lokale kopi i stedet for
  /// en transaktion mod serveren (se [restoreSlot]).
  Future<void> undoCopy(WeekCopy copy, {bool ownWritePending = false}) async {
    final planDoc = _planDoc(copy.weekId);
    if (planDoc == null) return;

    Future<void> undoFromCache() async {
      Map<String, dynamic>? cached;
      try {
        cached = (await planDoc.get(const GetOptions(source: Source.cache))).data();
      } catch (_) {
        cached = null; // ukendt; vi skrev det netop selv, så ryd det
      }
      final undo = cached == null
          ? copy.slots
          : slotsToUndo(copied: copy.slots, current: slotsOfData(cached));
      if (undo.isEmpty) throw const SlotChangedException();
      await planDoc.set(slotsPayload(undo, clear: true), SetOptions(merge: true));
    }

    if (ownWritePending) return undoFromCache();

    try {
      await _firestore.runTransaction((tx) async {
        final data = (await tx.get(planDoc)).data();
        final undo = slotsToUndo(copied: copy.slots, current: slotsOfData(data));
        if (undo.isEmpty) throw const SlotChangedException();
        // Kun de ryddede måltiders egne felter røres.
        tx.update(planDoc, {
          for (final s in undo)
            FieldPath(['days', s.day, s.key]): {'recipeId': null, 'directEntry': null},
        });
      });
    } catch (e) {
      if (!_isUnavailable(e)) rethrow;
      await undoFromCache();
    }
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
