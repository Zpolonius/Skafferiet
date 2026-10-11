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

/// Recipes that arrive when the test says so (cold start: plan before recipes).
class _ControlledRecipesNotifier extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  _ControlledRecipesNotifier(this.controller);
  final StreamController<List<Recipe>> controller;

  @override
  Stream<List<Recipe>> build() => controller.stream;
}

/// Behaves like a Firestore `snapshots()` stream: every new listener first
/// gets the latest snapshot, then live updates.
class _ReplayingPlanStream {
  final _controller =
      StreamController<DocumentSnapshot<Map<String, dynamic>>>.broadcast();
  DocumentSnapshot<Map<String, dynamic>>? _latest;

  void add(DocumentSnapshot<Map<String, dynamic>> snap) {
    _latest = snap;
    _controller.add(snap);
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> listen() async* {
    final latest = _latest;
    if (latest != null) yield latest;
    yield* _controller.stream;
  }

  Future<void> close() => _controller.close();
}

class _TestHouseholdNotifier extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _TestHouseholdNotifier(super.state);
}

_MockSnapshot _snapshot(Map<String, dynamic>? data) {
  final snap = _MockSnapshot();
  when(() => snap.exists).thenReturn(data != null);
  when(() => snap.id).thenReturn('2026-09-14');
  when(() => snap.data()).thenReturn(data);
  return snap;
}

Map<String, dynamic> _planWith(Map<String, dynamic> dinner) => {
      'days': {
        'Mandag': {'dinner': dinner},
      },
    };

final _recipe = Recipe(
  id: 'r1',
  title: 'Pasta Bolognese',
  category: RecipeCategory.aftensmad,
  calories: 600,
  time: '30 min',
  ingredients: [],
);

void main() {
  late _ReplayingPlanStream planStream;
  late StreamController<List<Recipe>> recipesStream;
  late ProviderContainer container;

  setUp(() {
    planStream = _ReplayingPlanStream();
    recipesStream = StreamController<List<Recipe>>.broadcast();

    final firestore = _MockFirestore();
    final households = _MockCollection();
    final household = _MockDoc();
    final plans = _MockCollection();
    final planDoc = _MockDoc();
    when(() => firestore.collection('households')).thenReturn(households);
    when(() => households.doc(any())).thenReturn(household);
    when(() => household.collection('meal_plans')).thenReturn(plans);
    when(() => plans.doc(any())).thenReturn(planDoc);
    when(() => planDoc.snapshots()).thenAnswer((_) => planStream.listen());

    container = ProviderContainer(
      overrides: [
        householdProvider.overrideWith(
          (ref) => _TestHouseholdNotifier(HouseholdState(householdId: 'hh-1')),
        ),
        recipesProvider
            .overrideWith(() => _ControlledRecipesNotifier(recipesStream)),
        mealPlanProvider
            .overrideWith(() => MealPlanNotifier(firestore: firestore)),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await planStream.close();
      await recipesStream.close();
    });
  });

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  test('slot with recipeId shows the recipe when recipes arrive after the plan',
      () async {
    final sub = container.listen(mealPlanProvider, (_, __) {});
    addTearDown(sub.close);

    planStream.add(_snapshot(_planWith({'recipeId': 'r1'})));
    await pump();
    await pump();

    // Recipes are still loading: must not claim the recipe is missing.
    final loading =
        container.read(mealPlanProvider).value!.days['Mandag']!.dinner;
    expect(loading.recipe, isNull);
    expect(loading.missingRecipe, isFalse);

    recipesStream.add([_recipe]);
    await pump();
    await pump();

    final slot = container.read(mealPlanProvider).value!.days['Mandag']!.dinner;
    expect(slot.recipe?.id, 'r1');
    expect(slot.missingRecipe, isFalse);
  });

  test('provider emits a new plan when the Firestore document changes',
      () async {
    final sub = container.listen(mealPlanProvider, (_, __) {});
    addTearDown(sub.close);
    recipesStream.add([_recipe]);

    planStream.add(_snapshot(_planWith({'directEntry': 'Sushi'})));
    await pump();
    await pump();
    expect(
        container
            .read(mealPlanProvider)
            .value!
            .days['Mandag']!
            .dinner
            .directEntry,
        'Sushi');

    // Another household member changes the slot.
    planStream.add(_snapshot(_planWith({'recipeId': 'r1'})));
    await pump();
    await pump();
    expect(
        container
            .read(mealPlanProvider)
            .value!
            .days['Mandag']!
            .dinner
            .recipe
            ?.id,
        'r1');
  });

  test('deleted recipe is flagged as missing once recipes have loaded',
      () async {
    final sub = container.listen(mealPlanProvider, (_, __) {});
    addTearDown(sub.close);

    planStream.add(_snapshot(_planWith({'recipeId': 'gone'})));
    recipesStream.add([_recipe]);
    await pump();
    await pump();

    final slot = container.read(mealPlanProvider).value!.days['Mandag']!.dinner;
    expect(slot.recipe, isNull);
    expect(slot.recipeId, 'gone');
    expect(slot.missingRecipe, isTrue);
  });
}
