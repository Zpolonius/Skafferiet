// QA-prober for #37 (madplanens startdag): kanttilfælde der ikke er dækket af
// udviklerens tests.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/core/services/meal_plan_dates.dart';
import 'package:skafferiet/features/grocery/recurring/recurring_items_provider.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';

class _Household extends StateNotifier<HouseholdState>
    implements HouseholdNotifier {
  _Household(int? start)
      : super(HouseholdState(householdId: 'h1', mealPlanStartWeekday: start));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _NoRecipes extends StreamNotifier<List<Recipe>>
    implements RecipesNotifier {
  @override
  Stream<List<Recipe>> build() => Stream.value(const []);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Offline: transaktioner fejler med 'unavailable'.
class _OfflineFs extends FakeFirebaseFirestore {
  @override
  Future<T> runTransaction<T>(TransactionHandler<T> transactionHandler,
      {Duration timeout = const Duration(seconds: 30), int maxAttempts = 5}) {
    throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
  }
}

final _thursday = DateTime(2026, 10, 15, 12);

DocumentReference<Map<String, dynamic>> _doc(
        FakeFirebaseFirestore fs, String id) =>
    fs.collection('households').doc('h1').collection('meal_plans').doc(id);

Map<String, dynamic> _dinner(String text) => {
      'dinner': {'recipeId': null, 'directEntry': text}
    };

ProviderContainer _container(FakeFirebaseFirestore fs, int? start,
    {DateTime Function()? clock, _Household? household}) {
  final c = ProviderContainer(overrides: [
    mealPlanProvider.overrideWith(() => MealPlanNotifier(firestore: fs)),
    recipesProvider.overrideWith(() => _NoRecipes()),
    householdProvider.overrideWith((ref) => household ?? _Household(start)),
    clockProvider.overrideWithValue(clock ?? () => _thursday),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('P1: forrige uge følger med, når startdagen skiftes ved offset 0',
      () async {
    final fs = FakeFirebaseFirestore();
    await _doc(fs, '2026-09-28').set({
      'days': {'Søndag': _dinner('Forrige søndag')}
    });
    final household = _Household(null);
    final c = _container(fs, null, household: household);
    c.listen(previousWeekSlotsProvider, (_, __) {});
    c.listen(mealPlanProvider, (_, __) {});
    await c.read(mealPlanProvider.future);
    await c.read(previousWeekSlotsProvider.future);
    expect(c.read(previousWeekSlotsProvider).value!.weekId, '2026-10-05');

    household.state = HouseholdState(householdId: 'h1', mealPlanStartWeekday: 7);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final plan = await c.read(mealPlanProvider.future);
    expect(plan.id, '2026-10-11');
    // Kopi-tilbuddet kræver previous.weekId == dateKey(forrige plan-uges start).
    expect(c.read(previousWeekSlotsProvider).valueOrNull?.weekId, '2026-10-04');
  });

  test('P2: offline kopiér + fortryd med søndagsstart rammer begge dokumenter',
      () async {
    final fs = _OfflineFs();
    await _doc(fs, '2026-09-28').set({
      'days': {'Søndag': _dinner('Forrige søndag')}
    });
    await _doc(fs, '2026-10-05').set({
      'days': {'Mandag': _dinner('Forrige mandag')}
    });
    final c = _container(fs, 7);
    await c.read(mealPlanProvider.future);
    final n = c.read(mealPlanProvider.notifier);
    final prev = await n.watchWeekSlots(-1).first;
    final copy = (await n.copyWeek(from: prev.slots))!;
    await copy.write;
    expect({for (final s in copy.slots) s.day}, {'Søndag', 'Mandag'});
    final d05 = (await _doc(fs, '2026-10-05').get()).data()!['days'];
    final d12 = (await _doc(fs, '2026-10-12').get()).data()!['days'];
    expect(d05['Søndag']['dinner']['directEntry'], 'Forrige søndag');
    expect(d05['Mandag']['dinner']['directEntry'], 'Forrige mandag');
    expect(d12['Mandag']['dinner']['directEntry'], 'Forrige mandag');

    await n.undoCopy(copy, ownWritePending: true);
    final d05b = (await _doc(fs, '2026-10-05').get()).data()!['days'];
    final d12b = (await _doc(fs, '2026-10-12').get()).data()!['days'];
    expect(d05b['Søndag']['dinner']['directEntry'], isNull);
    expect(d05b['Mandag']['dinner']['directEntry'], 'Forrige mandag');
    expect(d12b['Mandag']['dinner']['directEntry'], isNull);
  });

  test('P3: hver startdag og hver dag i ugen: planen indeholder i dag',
      () async {
    for (var start = 1; start <= 7; start++) {
      for (var d = 11; d <= 17; d++) {
        final today = DateTime(2026, 10, d, 9);
        final fs = FakeFirebaseFirestore();
        final loc = locate(today);
        await _doc(fs, loc.weekId).set({
          'days': {loc.dayName: _dinner('I dag')}
        });
        final c = _container(fs, start, clock: () => today);
        final plan = await c.read(mealPlanProvider.future);
        expect(plan.days[loc.dayName]?.dinner.directEntry, 'I dag',
            reason: 'start $start, dag $d');
        expect(c.read(selectedDayProvider), loc.dayName);
        expect(c.read(mealPlanProvider.notifier).weekIdForDay(loc.dayName),
            loc.weekId);
        expect(plan.weekStart.weekday, start);
      }
    }
  });

  test('P4: gammel app skriver i mandags-dok.; ny app (søndag) ser det live',
      () async {
    final fs = FakeFirebaseFirestore();
    final c = _container(fs, 7);
    final seen = <WeeklyMealPlan>[];
    c.listen(mealPlanProvider, (_, next) {
      if (next.hasValue) seen.add(next.value!);
    });
    await c.read(mealPlanProvider.future);
    // Gammel app (mandagsstart) skriver søndag 11. okt. i sin uge 2026-10-05
    // og fredag 16. okt. i 2026-10-12.
    await _doc(fs, '2026-10-05').set({
      'days': {'Søndag': _dinner('Gammel søndag')}
    }, SetOptions(merge: true));
    await _doc(fs, '2026-10-12').set({
      'days': {'Fredag': _dinner('Gammel fredag'), 'Søndag': _dinner('18. okt')}
    }, SetOptions(merge: true));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final plan = seen.last;
    expect(plan.days['Søndag']?.dinner.directEntry, 'Gammel søndag');
    expect(plan.days['Fredag']?.dinner.directEntry, 'Gammel fredag');
  });

  test('P5: skift af uge annullerer de gamle lyttere (ingen gammel data)',
      () async {
    final fs = FakeFirebaseFirestore();
    final c = _container(fs, 7);
    final seen = <WeeklyMealPlan>[];
    c.listen(mealPlanProvider, (_, next) {
      if (next.hasValue) seen.add(next.value!);
    });
    await c.read(mealPlanProvider.future);
    c.read(weekOffsetProvider.notifier).state = 1;
    final next = await c.read(mealPlanProvider.future);
    expect(next.id, '2026-10-18');
    seen.clear();
    // Skrivning i den gamle uges første dokument må ikke give en emission.
    await _doc(fs, '2026-10-05').set({
      'days': {'Søndag': _dinner('Gammel uge')}
    });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(seen.where((p) => p.id != '2026-10-18'), isEmpty);
  });
}
