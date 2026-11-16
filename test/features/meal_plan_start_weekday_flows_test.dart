// Madplanens startdag (#37): overførsel til indkøb, kopiér forrige uge,
// fortryd og skift af dag/dato med søndag som startdag (to mandags-dokumenter).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/models/recipe.dart';
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

class _Recipes extends StreamNotifier<List<Recipe>> implements RecipesNotifier {
  _Recipes(this.recipes);
  final List<Recipe> recipes;
  @override
  Stream<List<Recipe>> build() => Stream.value(recipes);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// Torsdag 2026-10-15. Søndagsstart: planen er søn 11. okt. – lør 17. okt.
final _thursday = DateTime(2026, 10, 15, 12);

DocumentReference<Map<String, dynamic>> _doc(
        FakeFirebaseFirestore fs, String id) =>
    fs.collection('households').doc('h1').collection('meal_plans').doc(id);

Map<String, dynamic> _dinner(String text) => {
      'dinner': {'recipeId': null, 'directEntry': text}
    };

Map<String, dynamic> _byId(String id) => {
      'dinner': {'recipeId': id, 'directEntry': null}
    };

ProviderContainer _container(
  FakeFirebaseFirestore fs,
  int? start, {
  List<Recipe> recipes = const [],
  DateTime Function()? clock,
  _Household? household,
}) {
  final c = ProviderContainer(overrides: [
    mealPlanProvider.overrideWith(() => MealPlanNotifier(firestore: fs)),
    recipesProvider.overrideWith(() => _Recipes(recipes)),
    householdProvider.overrideWith((ref) => household ?? _Household(start)),
    clockProvider.overrideWithValue(clock ?? () => _thursday),
  ]);
  addTearDown(c.dispose);
  return c;
}

Recipe _recipe(String id) => Recipe(
      id: id,
      title: id,
      category: RecipeCategory.aftensmad,
      calories: 1,
      time: '1 min',
      ingredients: [
        Ingredient(
            name: 'Vare $id', quantity: 1, unit: 'stk', category: 'Andet')
      ],
    );

void main() {
  group('overfør til indkøb', () {
    test('søndagsstart: præcis de 7 viste dage, fra begge dokumenter',
        () async {
      final fs = FakeFirebaseFirestore();
      await _doc(fs, '2026-10-05').set({
        'days': {'Mandag': _byId('gammel'), 'Søndag': _byId('soendag')}
      });
      await _doc(fs, '2026-10-12').set({
        'days': {
          'Mandag': _byId('mandag'),
          'Lørdag': _byId('loerdag'),
          'Søndag': _byId('naeste') // 18. okt. hører til næste plan-uge
        }
      });
      final c = _container(fs, 7, recipes: [
        for (final id in ['gammel', 'soendag', 'mandag', 'loerdag', 'naeste'])
          _recipe(id)
      ]);
      await c.read(mealPlanProvider.future);
      final count =
          await c.read(mealPlanProvider.notifier).transferToShoppingList();
      expect(count, 3);
      final names = (await fs.collection('households/h1/grocery_list').get())
          .docs
          .map((d) => d['name'])
          .toSet();
      expect(names, {'Vare soendag', 'Vare mandag', 'Vare loerdag'});
    });

    test('mandagsstart (eksisterende husstande): uændret, ét dokument',
        () async {
      final fs = FakeFirebaseFirestore();
      await _doc(fs, '2026-10-12').set({
        'days': {'Mandag': _byId('mandag'), 'Søndag': _byId('soendag')}
      });
      await _doc(fs, '2026-10-05').set({
        'days': {'Mandag': _byId('gammel')}
      });
      final c = _container(fs, null, recipes: [
        for (final id in ['mandag', 'soendag', 'gammel']) _recipe(id)
      ]);
      await c.read(mealPlanProvider.future);
      expect(
          await c.read(mealPlanProvider.notifier).transferToShoppingList(), 2);
    });
  });

  group('kopiér forrige uge med søndagsstart', () {
    // Forrige plan-uge: søn 4. okt. (dok. 2026-09-28) + man 5.–lør 10. okt.
    // (dok. 2026-10-05). Nuværende: søn 11. okt. (dok. 2026-10-05) + 12.–17.
    Future<FakeFirebaseFirestore> seed() async {
      final fs = FakeFirebaseFirestore();
      await _doc(fs, '2026-09-28').set({
        'days': {'Søndag': _dinner('Forrige søndag')}
      });
      await _doc(fs, '2026-10-05').set({
        'days': {
          'Mandag': _dinner('Forrige mandag'),
          'Lørdag': _dinner('Forrige lørdag'),
          'Søndag': _dinner('Søndagssteg') // 11. okt. = nuværende uge
        }
      });
      return fs;
    }

    test('forrige uges måltider samles på tværs af to dokumenter', () async {
      final fs = await seed();
      final c = _container(fs, 7);
      final prev =
          await c.read(mealPlanProvider.notifier).watchWeekSlots(-1).first;
      expect(prev.weekId, '2026-10-04');
      expect({
        for (final s in prev.slots) s.day: s.directEntry
      }, {
        'Søndag': 'Forrige søndag',
        'Mandag': 'Forrige mandag',
        'Lørdag': 'Forrige lørdag',
      });
    });

    test(
        'kopierer kun til tomme pladser, hver i sit dokument; fortryd rydder præcis dem',
        () async {
      final fs = await seed();
      final c = _container(fs, 7);
      await c.read(mealPlanProvider.future);
      final notifier = c.read(mealPlanProvider.notifier);
      final prev = await notifier.watchWeekSlots(-1).first;

      final copy = await notifier.copyWeek(from: prev.slots);
      expect(copy, isNotNull);
      // Søndag er fyldt (11. okt.) og overskrives aldrig.
      expect({for (final s in copy!.slots) s.day}, {'Mandag', 'Lørdag'});
      final d05 = (await _doc(fs, '2026-10-05').get()).data()!['days'];
      final d12 = (await _doc(fs, '2026-10-12').get()).data()!['days'];
      expect(d05['Søndag']['dinner']['directEntry'], 'Søndagssteg');
      expect(d12['Mandag']['dinner']['directEntry'], 'Forrige mandag');
      expect(d12['Lørdag']['dinner']['directEntry'], 'Forrige lørdag');
      // Forrige uges egne dage i dokument 2026-10-05 er urørte.
      expect(d05['Mandag']['dinner']['directEntry'], 'Forrige mandag');

      await notifier.undoCopy(copy);
      final after = (await _doc(fs, '2026-10-12').get()).data()!['days'];
      expect(after['Mandag']['dinner']['directEntry'], isNull);
      expect(after['Lørdag']['dinner']['directEntry'], isNull);
      final d05b = (await _doc(fs, '2026-10-05').get()).data()!['days'];
      expect(d05b['Søndag']['dinner']['directEntry'], 'Søndagssteg');
      expect(d05b['Mandag']['dinner']['directEntry'], 'Forrige mandag');
    });

    test('fortryd rører ikke et måltid der er ændret i mellemtiden', () async {
      final fs = await seed();
      final c = _container(fs, 7);
      await c.read(mealPlanProvider.future);
      final notifier = c.read(mealPlanProvider.notifier);
      final prev = await notifier.watchWeekSlots(-1).first;
      final copy = (await notifier.copyWeek(from: prev.slots))!;
      await notifier.updateSlot('Mandag', 'dinner', directEntry: 'Ændret');
      await notifier.undoCopy(copy);
      final after = (await _doc(fs, '2026-10-12').get()).data()!['days'];
      expect(after['Mandag']['dinner']['directEntry'], 'Ændret');
      expect(after['Lørdag']['dinner']['directEntry'], isNull);
    });

    test('mandagsstart: kopiering og fortryd som før (ét dokument)', () async {
      final fs = FakeFirebaseFirestore();
      await _doc(fs, '2026-10-05').set({
        'days': {'Mandag': _dinner('Forrige mandag')}
      });
      final c = _container(fs, null);
      await c.read(mealPlanProvider.future);
      final notifier = c.read(mealPlanProvider.notifier);
      final prev = await notifier.watchWeekSlots(-1).first;
      expect(prev.weekId, '2026-10-05');
      final copy = (await notifier.copyWeek(from: prev.slots))!;
      expect(copy.weekId, '2026-10-12');
      expect(
          (await _doc(fs, '2026-10-12').get()).data()!['days']['Mandag']
              ['dinner']['directEntry'],
          'Forrige mandag');
      await notifier.undoCopy(copy);
      expect(
          (await _doc(fs, '2026-10-12').get()).data()!['days']['Mandag']
              ['dinner']['directEntry'],
          isNull);
    });
  });

  group('fjern og fortryd', () {
    test('en fjernet søndag lægges tilbage i forrige mandags dokument',
        () async {
      final fs = FakeFirebaseFirestore();
      await _doc(fs, '2026-10-05').set({
        'days': {'Søndag': _dinner('Søndagssteg')}
      });
      await _doc(fs, '2026-10-12').set({
        'days': {'Søndag': _dinner('Næste søndag')}
      });
      final c = _container(fs, 7);
      final plan = await c.read(mealPlanProvider.future);
      final notifier = c.read(mealPlanProvider.notifier);
      final slot = plan.days['Søndag']!.dinner;
      final weekId = notifier.weekIdForDay('Søndag');
      expect(weekId, '2026-10-05');
      await notifier.updateSlot('Søndag', 'dinner', weekId: weekId);
      await notifier.restoreSlot('Søndag', 'dinner', slot, weekId: weekId);
      final d05 = (await _doc(fs, '2026-10-05').get()).data()!['days'];
      final d12 = (await _doc(fs, '2026-10-12').get()).data()!['days'];
      expect(d05['Søndag']['dinner']['directEntry'], 'Søndagssteg');
      expect(d12['Søndag']['dinner']['directEntry'], 'Næste søndag');
    });
  });

  group('skift af dag og dato', () {
    test('ny dag flytter plan-ugen med: "næste uge" bliver denne', () async {
      final fs = FakeFirebaseFirestore();
      var now = DateTime(2026, 10, 17, 12); // lørdag = sidste dag i søndagsugen
      final c = _container(fs, 7, clock: () => now);
      expect(c.read(selectedDayProvider), 'Lørdag');
      c.listen(mealPlanProvider, (_, __) {});
      c.read(weekOffsetProvider.notifier).state = 1; // bladret til næste uge
      now = DateTime(2026, 10, 18, 0, 5); // søndag: næste plan-uge er nu denne
      c.read(todayProvider.notifier).refresh();
      expect(c.read(weekOffsetProvider), 0);
      expect(c.read(selectedDayProvider), 'Søndag');
    });

    test('mandagsstart: søndag er stadig samme uge som lørdag (uændret)',
        () async {
      final fs = FakeFirebaseFirestore();
      var now = DateTime(2026, 10, 17, 12);
      final c = _container(fs, null, clock: () => now);
      c.listen(mealPlanProvider, (_, __) {});
      now = DateTime(2026, 10, 18, 0, 5);
      c.read(todayProvider.notifier).refresh();
      expect(c.read(weekOffsetProvider), 0);
      expect(c.read(selectedDayProvider), 'Søndag');
      c.read(weekOffsetProvider.notifier).state = 1;
      now = DateTime(2026, 10, 19, 0, 5);
      c.read(todayProvider.notifier).refresh();
      expect(c.read(weekOffsetProvider), 0); // mandag: "næste uge" er nu denne
    });

    test('startdagen skiftes mens appen er åben: man bliver på i dag',
        () async {
      final fs = FakeFirebaseFirestore();
      await _doc(fs, '2026-10-05').set({
        'days': {'Søndag': _dinner('Søndagssteg')}
      });
      final household = _Household(null);
      final c = _container(fs, null, household: household);
      c.listen(mealPlanProvider, (_, __) {});
      await c.read(mealPlanProvider.future);
      c.read(weekOffsetProvider.notifier).state = 2;
      c.read(selectedDayProvider.notifier).state = 'Mandag';
      household.state =
          HouseholdState(householdId: 'h1', mealPlanStartWeekday: 7);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(weekOffsetProvider), 0);
      expect(c.read(selectedDayProvider), 'Torsdag');
      final plan = await c.read(mealPlanProvider.future);
      expect(plan.id, '2026-10-11');
      expect(plan.days['Søndag']!.dinner.directEntry, 'Søndagssteg');
    });
  });
}
