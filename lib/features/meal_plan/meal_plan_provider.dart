import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/utils/number_format.dart';
import '../../core/models/meal_plan.dart';
import '../../core/models/recipe.dart';
import '../../core/services/item_history_writer.dart';
import '../../core/services/meal_plan_dates.dart';
import '../../core/services/week_copy.dart';
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

/// Husstandens startdag for madplanen (1 = mandag … 7 = søndag). Mandag, når
/// intet er valgt. Alle medlemmer læser den fra husstanden og ser samme start.
final planStartWeekdayProvider = Provider<int>(
    (ref) => ref.watch(householdProvider.select((h) => h.planStartWeekday)));

/// Hvor mange plan-uger fra den aktuelle uge madplanen viser (0 = denne uge).
final weekOffsetProvider = StateProvider<int>((ref) => 0);

/// Den valgte dag i madplanen (dansk ugedagsnavn). Starter på i dag, så man
/// ser dagens måltider, når madplanen åbnes.
final selectedDayProvider =
    StateProvider<String>((ref) => dayNameOf(ref.read(todayProvider)));

/// I dag (kl. 00:00). Alt der afhænger af "den aktuelle uge" – planen, skrivninger,
/// overskrift, weekendhjælp – udledes herfra, så de aldrig er uenige. Står appen
/// åben hen over midnat, kalder [DayRollover] [TodayNotifier.refresh].
final todayProvider = NotifierProvider<TodayNotifier, DateTime>(TodayNotifier.new);

class TodayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    // Skifter husstanden startdag, mens appen er åben, bliver man på den
    // aktuelle plan-uge og dagen i dag. (Her og ikke i madplanens build, for
    // dér ville lytteren blive fjernet, når planen genopbygges af skiftet.)
    ref.listen(planStartWeekdayProvider, (previous, next) {
      if (previous == null || previous == next) return;
      ref.read(weekOffsetProvider.notifier).state = 0;
      ref.read(selectedDayProvider.notifier).state = dayNameOf(_read());
    });
    return _read();
  }

  DateTime _read() {
    final now = ref.read(clockProvider)();
    return DateTime(now.year, now.month, now.day);
  }

  /// Læser uret igen. Er datoen skiftet, flyttes visningen med: en uge man har
  /// bladret til forbliver den samme uge, "denne uge" følger med, og valgt dag
  /// bliver i dag, når man ser den aktuelle uge – ligesom når appen starter.
  void refresh() {
    final today = _read();
    if (today == state) return;
    final weeks =
        planWeeksBetween(state, today, ref.read(planStartWeekdayProvider));
    final offset = ref.read(weekOffsetProvider);
    final newOffset = offset == 0 ? 0 : offset - weeks;
    if (newOffset != offset) ref.read(weekOffsetProvider.notifier).state = newOffset;
    if (newOffset == 0) {
      ref.read(selectedDayProvider.notifier).state = dayNameOf(today);
    }
    state = today;
  }
}

/// Plan-ugen (id = startdagens dato) hvis weekendhjælp "Planlægger du næste uge?" er
/// lukket. Kun i hukommelsen: den kommer igen næste weekend.
final weekendHintDismissedProvider = StateProvider<String?>((ref) => null);

/// Uger (id) hvor tilbuddet om at kopiere forrige uge er lukket.
final copyOfferDismissedProvider = StateProvider<Set<String>>((ref) => const {});

/// De udfyldte måltider i plan-ugen [weekId] (startdagens dato).
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
  ref.watch(planStartWeekdayProvider);
  ref.watch(householdProvider.select((h) => h.householdId));
  return ref.watch(mealPlanProvider.notifier).watchWeekSlots(offset - 1);
});

/// Resultatet af [MealPlanNotifier.copyWeek]. [write] er skrivningen; den
/// fuldføres først når serveren har svaret, så vent ikke på den i UI'et.
class WeekCopy {
  /// Plan-ugens id (startdagens dato).
  final String weekId;
  final List<PlannedSlot> slots;
  final Future<void> write;

  /// Dagsnavn → id på det mandags-dokument dagen blev kopieret til. Uden den
  /// ligger alle dage i dokumentet [weekId] (mandagsstart).
  final Map<String, String> docByDay;
  const WeekCopy(this.weekId, this.slots, this.write, {this.docByDay = const {}});

  String docOf(String day) => docByDay[day] ?? weekId;
}

class MealPlanNotifier extends StreamNotifier<WeeklyMealPlan> {
  final FirebaseFirestore _firestore;

  MealPlanNotifier({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Første dag i den plan-uge der ligger [offset] uger fra den aktuelle.
  DateTime _weekStartFor(int offset) =>
      planWeekStart(ref.read(todayProvider), ref.read(planStartWeekdayProvider), offset);

  @override
  Stream<WeeklyMealPlan> build() {
    // Kun husstand, startdag og uge styrer Firestore-abonnementet. Opskrifter
    // lyttes der separat til, så abonnementet ikke genstartes (og UI'et ikke
    // viser en spinner), når opskrifter indlæses eller ændres.
    final householdId = ref.watch(householdProvider).householdId;
    ref.watch(planStartWeekdayProvider);
    final offset = ref.watch(weekOffsetProvider);
    ref.watch(todayProvider);

    final weekStart = _weekStartFor(offset);
    final planId = dateKey(weekStart);

    if (householdId == null) {
      return Stream.value(WeeklyMealPlan(id: 'empty', weekStart: weekStart, days: {}));
    }

    final sources = planSources(weekStart);
    final controller = StreamController<WeeklyMealPlan>();
    List<DocumentSnapshot<Map<String, dynamic>>>? latest;

    void emit() {
      final docs = latest;
      if (docs == null || controller.isClosed) return;
      controller.add(_mapDocsToPlan(planId, weekStart, sources, docs, ref.read(recipesProvider)));
    }

    final sub = _watchDocs([for (final src in sources) _planDoc(src.weekId)!]).listen((docs) {
      latest = docs;
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

  /// Lytter live på flere dokumenter og udsender først, når alle har svaret.
  Stream<List<DocumentSnapshot<Map<String, dynamic>>>> _watchDocs(
      List<DocumentReference<Map<String, dynamic>>> refs) {
    late final StreamController<List<DocumentSnapshot<Map<String, dynamic>>>> controller;
    final subs = <StreamSubscription<dynamic>>[];
    final latest = List<DocumentSnapshot<Map<String, dynamic>>?>.filled(refs.length, null);
    controller = StreamController(
      onListen: () {
        for (var i = 0; i < refs.length; i++) {
          subs.add(refs[i].snapshots().listen((doc) {
            latest[i] = doc;
            if (latest.every((d) => d != null)) {
              controller.add([for (final d in latest) d!]);
            }
          }, onError: controller.addError));
        }
      },
      onCancel: () async {
        for (final sub in subs) {
          await sub.cancel();
        }
      },
    );
    return controller.stream;
  }

  /// Samler plan-ugens dage ud fra dens dokumenter: hver dag hentes fra det
  /// dokument datoen hører til (se [locate]); andre dage i dokumentet (fra
  /// ugen før/efter) ignoreres.
  WeeklyMealPlan _mapDocsToPlan(
    String planId,
    DateTime weekStart,
    List<PlanSource> sources,
    List<DocumentSnapshot<Map<String, dynamic>>> docs,
    AsyncValue<List<Recipe>> recipesAsync,
  ) {
    // null = opskrifter ikke indlæst endnu; så afgør vi ikke om en opskrift mangler.
    final recipes = recipesAsync.hasValue ? recipesAsync.value : null;

    final Map<String, DailyPlan> days = {};
    for (var i = 0; i < sources.length; i++) {
      final data = docs[i].data() ?? {};
      final daysData = data['days'] as Map<String, dynamic>? ?? {};
      for (final dayName in sources[i].dayNames) {
        final value = daysData[dayName];
        if (value == null) continue;
        days[dayName] = DailyPlan(
          breakfast: _mapSlot(value['breakfast'], recipes),
          lunch: _mapSlot(value['lunch'], recipes),
          dinner: _mapSlot(value['dinner'], recipes),
          snack: _mapSlot(value['snack'], recipes),
        );
      }
    }

    return WeeklyMealPlan(id: planId, weekStart: weekStart, days: days);
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

  /// Id på den plan-uge madplanen viser lige nu: startdagens dato. Ved
  /// mandagsstart er det også dokumentets id; ellers består ugen af to
  /// dokumenter, og skrivninger skal bruge [weekIdForDay].
  String currentWeekId() => dateKey(_weekStartFor(ref.read(weekOffsetProvider)));

  /// Id på det mandags-dokument [day] (dagsnavn) i den viste plan-uge ligger i.
  String weekIdForDay(String day) {
    // Mandagsstart: hele ugen ligger i ét dokument.
    if (ref.read(planStartWeekdayProvider) == DateTime.monday) return currentWeekId();
    final start = _weekStartFor(ref.read(weekOffsetProvider));
    for (final date in daysOfPlanWeek(start)) {
      if (dayNameOf(date) == day) return locate(date).weekId;
    }
    return currentWeekId();
  }

  /// De udfyldte måltider i plan-ugen [offset] uger fra den aktuelle, live
  /// (samlet af op til to dokumenter).
  Stream<WeekSlots> watchWeekSlots(int offset) {
    final start = _weekStartFor(offset);
    final id = dateKey(start);
    final sources = planSources(start);
    final refs = [for (final src in sources) _planDoc(src.weekId)];
    if (refs.any((r) => r == null)) return Stream.value(WeekSlots(id, const []));
    return _watchDocs([for (final r in refs) r!]).map((docs) => WeekSlots(id, [
          for (var i = 0; i < sources.length; i++)
            ..._slotsOfSource(sources[i], docs[i].data()),
        ]));
  }

  /// Måltiderne i [data] for de dage der hører til [source].
  List<PlannedSlot> _slotsOfSource(PlanSource source, Map<String, dynamic>? data) => [
        for (final s in slotsOfData(data))
          if (source.dayNames.contains(s.day)) s
      ];

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
    final planId = currentWeekId();
    final start = _weekStartFor(ref.read(weekOffsetProvider));
    final sources = planSources(start);
    final docs = [for (final src in sources) _planDoc(src.weekId)];
    final plan = state.valueOrNull;
    // Under ugeskift viser state stadig den forrige uges plan.
    if (docs.any((d) => d == null) || plan == null || plan.id != planId) return null;
    final docByDay = {
      for (final src in sources)
        for (final d in src.dayNames) d: src.weekId,
    };

    // Måltiderne der hører til dokument nr. i.
    List<PlannedSlot> forDoc(int i, List<PlannedSlot> slots) =>
        [for (final s in slots) if (sources[i].dayNames.contains(s.day)) s];

    try {
      List<PlannedSlot> copied = const [];
      await _firestore.runTransaction((tx) async {
        // Alle læsninger før skrivninger.
        final datas = [for (final d in docs) (await tx.get(d!)).data()];
        final current = [
          for (var i = 0; i < sources.length; i++) ..._slotsOfSource(sources[i], datas[i]),
        ];
        copied = slotsToCopy(previous: from, current: current);
        if (copied.isEmpty) return;
        for (var i = 0; i < sources.length; i++) {
          final part = forDoc(i, copied);
          if (part.isNotEmpty) tx.set(docs[i]!, withSlotsSet(datas[i], part));
        }
      });
      if (copied.isEmpty) return null;
      return WeekCopy(planId, copied, Future.value(), docByDay: docByDay);
    } catch (e) {
      if (!_isUnavailable(e)) rethrow;
    }

    final slots = slotsToCopy(previous: from, current: slotsOfPlan(plan));
    if (slots.isEmpty) return null;
    final writes = [
      for (var i = 0; i < sources.length; i++)
        if (forDoc(i, slots).isNotEmpty)
          docs[i]!.set(slotsPayload(forDoc(i, slots)), SetOptions(merge: true)),
    ];
    return WeekCopy(planId, slots, Future.wait(writes).then((_) {}), docByDay: docByDay);
  }

  /// Fortryd [copyWeek]: rydder præcis de kopierede måltider, men kun dem der
  /// stadig er som kopieret. Er ingen af dem det, kastes
  /// [SlotChangedException]. Andre måltider i ugen røres ikke.
  ///
  /// [ownWritePending] skal være true, hvis serveren endnu ikke har bekræftet
  /// kopieringen ([WeekCopy.write]); så tjekkes den lokale kopi i stedet for
  /// en transaktion mod serveren (se [restoreSlot]).
  Future<void> undoCopy(WeekCopy copy, {bool ownWritePending = false}) async {
    // De dokumenter kopieringen skrev til, og de kopierede måltider i hvert.
    final byDoc = <String, List<PlannedSlot>>{};
    for (final s in copy.slots) {
      byDoc.putIfAbsent(copy.docOf(s.day), () => []).add(s);
    }
    final refs = <String, DocumentReference<Map<String, dynamic>>>{};
    for (final id in byDoc.keys) {
      final doc = _planDoc(id);
      if (doc == null) return;
      refs[id] = doc;
    }

    Future<void> undoFromCache() async {
      var any = false;
      for (final e in byDoc.entries) {
        final doc = refs[e.key]!;
        Map<String, dynamic>? cached;
        try {
          cached = (await doc.get(const GetOptions(source: Source.cache))).data();
        } catch (_) {
          cached = null; // ukendt; vi skrev det netop selv, så ryd det
        }
        final undo = cached == null
            ? e.value
            : slotsToUndo(copied: e.value, current: slotsOfData(cached));
        if (undo.isEmpty) continue;
        any = true;
        await doc.set(slotsPayload(undo, clear: true), SetOptions(merge: true));
      }
      if (!any) throw const SlotChangedException();
    }

    if (ownWritePending) return undoFromCache();

    try {
      await _firestore.runTransaction((tx) async {
        final undos = <String, List<PlannedSlot>>{};
        for (final e in byDoc.entries) {
          final data = (await tx.get(refs[e.key]!)).data();
          final undo = slotsToUndo(copied: e.value, current: slotsOfData(data));
          if (undo.isNotEmpty) undos[e.key] = undo;
        }
        if (undos.isEmpty) throw const SlotChangedException();
        // Kun de ryddede måltiders egne felter røres.
        for (final e in undos.entries) {
          tx.update(refs[e.key]!, {
            for (final s in e.value)
              FieldPath(['days', s.day, s.key]): {'recipeId': null, 'directEntry': null},
          });
        }
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

  /// [weekId] er mandags-dokumentet der skrives til (find det med [locate] eller
  /// [weekIdForDay]); uden den bruges dokumentet for [day] i den viste uge.
  Future<void> updateSlot(String day, String slotType,
      {Recipe? recipe, String? directEntry, String? weekId}) async {
    final planDoc = _planDoc(weekId ?? weekIdForDay(day));
    if (planDoc == null) return;
    await planDoc.set(_slotPayload(day, slotType, recipe?.id, directEntry), SetOptions(merge: true));
  }

  /// Fortryd: skriver et måltid tilbage præcis som det var, også når opskriften
  /// ikke findes mere (der er så kun et [MealSlot.recipeId], intet [Recipe]).
  ///
  /// Skriver kun hvis pladsen stadig er tom. Har et andet medlem fyldt den i
  /// mellemtiden, kastes [SlotChangedException] og intet overskrives. Står det
  /// gamle måltid der allerede, sker der intet.
  /// [weekId] er mandags-dokumentet måltidet stod i (se [locate]); uden den
  /// bruges dokumentet for [day] i den viste uge.
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
    final planDoc = _planDoc(weekId ?? weekIdForDay(day));
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
