// Madplanens startdag (#37): en husstand der starter ugen på søndag. Lagringen
// er uændret (et dokument pr. mandag), så planen samles af to dokumenter.
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

class _NoRecipes extends StreamNotifier<List<Recipe>>
    implements RecipesNotifier {
  @override
  Stream<List<Recipe>> build() => Stream.value(const []);
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

Future<FakeFirebaseFirestore> _seed() async {
  final fs = FakeFirebaseFirestore();
  // Mandags-ugen 5.–11. okt.: søndag 11. okt. hører til planen, resten ikke.
  await _doc(fs, '2026-10-05').set({
    'days': {
      'Mandag': _dinner('Gammel mandag'),
      'Søndag': _dinner('Søndagssteg')
    }
  });
  // Mandags-ugen 12.–18. okt.: mandag–lørdag hører til planen, søndag 18. ikke.
  await _doc(fs, '2026-10-12').set({
    'days': {
      'Mandag': _dinner('Mandagsgryde'),
      'Lørdag': _dinner('Lørdagspizza'),
      'Søndag': _dinner('Næste søndag')
    }
  });
  return fs;
}

ProviderContainer _container(FakeFirebaseFirestore fs, int? start) {
  final c = ProviderContainer(overrides: [
    mealPlanProvider.overrideWith(() => MealPlanNotifier(firestore: fs)),
    recipesProvider.overrideWith(() => _NoRecipes()),
    householdProvider.overrideWith((ref) => _Household(start)),
    clockProvider.overrideWithValue(() => _thursday),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<Map<String, String?>> _dinners(ProviderContainer c) async {
  final plan = await c.read(mealPlanProvider.future);
  return {for (final e in plan.days.entries) e.key: e.value.dinner.directEntry};
}

void main() {
  test(
      'søndagsstart: planen samler søndag fra forrige mandags-dokument og '
      'mandag–lørdag fra næste', () async {
    final fs = await _seed();
    final c = _container(fs, 7);
    final dinners = await _dinners(c);
    expect(dinners, {
      'Søndag': 'Søndagssteg',
      'Mandag': 'Mandagsgryde',
      'Lørdag': 'Lørdagspizza',
    });
  });

  test('mandagsstart (ingen indstilling): uændret – kun ét dokument', () async {
    final fs = await _seed();
    final c = _container(fs, null);
    final dinners = await _dinners(c);
    // Ugen 12.–18. okt.: dokumentet vises som det er.
    expect(dinners['Mandag'], 'Mandagsgryde');
    expect(dinners['Søndag'], 'Næste søndag');
    expect(dinners.length, 3);
  });

  test('søndagsstart: skriv på søndag lander i forrige mandags dokument',
      () async {
    final fs = await _seed();
    final c = _container(fs, 7);
    await c.read(mealPlanProvider.future);
    await c
        .read(mealPlanProvider.notifier)
        .updateSlot('Søndag', 'dinner', directEntry: 'Ny søndag');
    final before = (await _doc(fs, '2026-10-05').get()).data()!['days'];
    final after = (await _doc(fs, '2026-10-12').get()).data()!['days'];
    expect(before['Søndag']['dinner']['directEntry'], 'Ny søndag');
    expect(after['Søndag']['dinner']['directEntry'], 'Næste søndag');
  });
}
