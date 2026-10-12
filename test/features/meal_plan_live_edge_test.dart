// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockDoc extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class _Ctl {
  _Ctl(this.key, this.controllers, this.latest);
  final String key;
  final Map<String, StreamController<DocumentSnapshot<Map<String, dynamic>>>>
      controllers;
  final Map<String, DocumentSnapshot<Map<String, dynamic>>> latest;
  StreamController<DocumentSnapshot<Map<String, dynamic>>> get _c =>
      controllers.putIfAbsent(key, () => StreamController.broadcast());
  Stream<DocumentSnapshot<Map<String, dynamic>>> get stream => _c.stream;
  void add(DocumentSnapshot<Map<String, dynamic>> s) {
    latest[key] = s;
    _c.add(s);
  }
}

class _RecipesNotifier extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  _RecipesNotifier(this.c);
  final StreamController<List<Recipe>> c;
  @override
  Stream<List<Recipe>> build() => c.stream;
}

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household(super.s);
  void set(String? id) => state = HouseholdState(householdId: id);
}

_MockSnapshot _snap(Map<String, dynamic>? data) {
  final s = _MockSnapshot();
  when(() => s.exists).thenReturn(data != null);
  when(() => s.id).thenReturn('x');
  when(() => s.data()).thenReturn(data);
  return s;
}

Map<String, dynamic> _plan(Map<String, dynamic> dinner) => {
      'days': {
        'Mandag': {'dinner': dinner}
      }
    };

final _r1 = Recipe(
    id: 'r1',
    title: 'Pasta',
    category: RecipeCategory.aftensmad,
    calories: 1,
    time: '1',
    ingredients: []);

void main() {
  late StreamController<List<Recipe>> recipes;
  late _Household household;
  late ProviderContainer container;
  // key: "<household>/<weekId>"
  final controllers =
      <String, StreamController<DocumentSnapshot<Map<String, dynamic>>>>{};
  final active = <String, int>{};
  var listens = 0;

  final latest = <String, DocumentSnapshot<Map<String, dynamic>>>{};
  _Ctl ctl(String key) => _Ctl(key, controllers, latest);

  setUp(() {
    controllers.clear();
    latest.clear();
    active.clear();
    listens = 0;
    recipes = StreamController<List<Recipe>>.broadcast();
    household = _Household(HouseholdState(householdId: 'A'));
    final fs = _MockFirestore();
    final hs = _MockCollection();
    when(() => fs.collection('households')).thenReturn(hs);
    when(() => hs.doc(any())).thenAnswer((inv) {
      final hid = inv.positionalArguments.first as String;
      final h = _MockDoc();
      final plans = _MockCollection();
      when(() => h.collection('meal_plans')).thenReturn(plans);
      when(() => plans.doc(any())).thenAnswer((i2) {
        final key = '$hid/${i2.positionalArguments.first}';
        final d = _MockDoc();
        when(() => d.snapshots()).thenAnswer((_) {
          late StreamController<DocumentSnapshot<Map<String, dynamic>>> out;
          out = StreamController(
            onListen: () {
              listens++;
              active[key] = (active[key] ?? 0) + 1;
              final sub = ctl(key).stream.listen(out.add);
              final l = latest[key];
              if (l != null) scheduleMicrotask(() => out.add(l));
              out.onCancel = () {
                active[key] = active[key]! - 1;
                return sub.cancel();
              };
            },
          );
          return out.stream;
        });
        return d;
      });
      return h;
    });
    container = ProviderContainer(overrides: [
      householdProvider.overrideWith((ref) => household),
      recipesProvider.overrideWith(() => _RecipesNotifier(recipes)),
      mealPlanProvider.overrideWith(() => MealPlanNotifier(firestore: fs)),
    ]);
    addTearDown(() {
      container.dispose();
    });
  });

  Future<void> pump() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('recipes change: no reload spinner state, document listened to once',
      () async {
    final states = <AsyncValue<dynamic>>[];
    container.listen(mealPlanProvider, (_, n) => states.add(n),
        fireImmediately: true);
    await pump();
    final key = active.keys.single;
    ctl(key).add(_snap(_plan({'recipeId': 'r1'})));
    await pump();
    recipes.add([_r1]);
    await pump();
    ctl(key).add(_snap(_plan({'recipeId': 'r1'})));
    await pump();
    recipes.add([_r1, _r1]); // any recipe edit
    await pump();
    expect(active.values.where((v) => v > 1), isEmpty,
        reason: 'duplicate listeners');
    expect(states.where((s) => s.isLoading && s.hasValue), isEmpty,
        reason: 'reload with AsyncLoading -> .when() shows spinner');
    expect(listens, 1, reason: 'recipes changes must not resubscribe');
  });

  test('week switch: old sub cancelled, no stale plan', () async {
    container.listen(mealPlanProvider, (_, __) {});
    await pump();
    final k0 = active.keys.single;
    ctl(k0).add(_snap(_plan({'directEntry': 'THIS WEEK'})));
    await pump();
    container.read(weekOffsetProvider.notifier).state = 1;
    await pump();
    expect(active[k0], 0);
    // late event from old week must not leak
    ctl(k0).add(_snap(_plan({'directEntry': 'LATE OLD'})));
    await pump();
    expect(
        container
            .read(mealPlanProvider)
            .value
            ?.days['Mandag']
            ?.dinner
            .directEntry,
        isNot('LATE OLD'));
    final k1 = active.keys.firstWhere((k) => k != k0);
    ctl(k1).add(_snap(null));
    await pump();
    expect(container.read(mealPlanProvider).value!.days, isEmpty);
  });

  test('household switch/null: old sub cancelled, no stale plan', () async {
    container.listen(mealPlanProvider, (_, __) {});
    await pump();
    final kA = active.keys.single;
    ctl(kA).add(_snap(_plan({'directEntry': 'HOUSE A'})));
    await pump();
    household.set('B');
    await pump();
    expect(active[kA], 0);
    ctl(kA).add(_snap(_plan({'directEntry': 'LATE A'})));
    await pump();
    final kB = active.keys.firstWhere((k) => k.startsWith('B/'));
    ctl(kB).add(_snap(null));
    await pump();
    final v = container.read(mealPlanProvider).value;
    expect(v?.days['Mandag']?.dinner.directEntry, isNull);
    household.set(null);
    await pump();
    expect(active.values.every((x) => x == 0), isTrue);
    expect(container.read(mealPlanProvider).value!.days, isEmpty);
  });

  test('recipes error: plan still shown, recipe not flagged missing', () async {
    container.listen(mealPlanProvider, (_, __) {});
    await pump();
    final k = active.keys.single;
    ctl(k).add(_snap(_plan({'recipeId': 'r1'})));
    recipes.addError(Exception('boom'));
    await pump();
    final s = container.read(mealPlanProvider);
    expect(s.hasError, isFalse);
    expect(s.value!.days['Mandag']!.dinner.missingRecipe, isFalse);
  });

  test('recipes empty list: recipe flagged missing, no crash', () async {
    container.listen(mealPlanProvider, (_, __) {});
    await pump();
    final k = active.keys.single;
    ctl(k).add(_snap(_plan({'recipeId': 'r1'})));
    recipes.add([]);
    await pump();
    final slot = container.read(mealPlanProvider).value!.days['Mandag']!.dinner;
    expect(slot.missingRecipe, isTrue);
  });

  test('recipes arrive first then plan', () async {
    container.listen(mealPlanProvider, (_, __) {});
    recipes.add([_r1]);
    await pump();
    final k = active.keys.single;
    ctl(k).add(_snap(_plan({'recipeId': 'r1'})));
    await pump();
    final slot = container.read(mealPlanProvider).value!.days['Mandag']!.dinner;
    expect(slot.recipe?.id, 'r1');
  });
}
