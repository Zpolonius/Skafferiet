import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'h1'));
}

class _Recipes extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  @override
  Stream<List<Recipe>> build() => Stream.value(const []);
}

/// Opfører sig som en klient uden forbindelse: transaktioner kan ikke køres.
class _OfflineFirestore extends FakeFirebaseFirestore {
  final String code;
  _OfflineFirestore([this.code = 'unavailable']);

  @override
  Future<T> runTransaction<T>(TransactionHandler<T> transactionHandler,
      {Duration timeout = const Duration(seconds: 30), int maxAttempts = 5}) {
    throw FirebaseException(plugin: 'cloud_firestore', code: code);
  }
}

const _week = '2026-09-28';

Future<(MealPlanNotifier, FakeFirebaseFirestore)> _setup(
  FakeFirebaseFirestore fs,
  Map<String, dynamic>? dinner,
) async {
  final doc =
      fs.collection('households').doc('h1').collection('meal_plans').doc(_week);
  if (dinner != null) {
    await doc.set({
      'days': {
        'Tirsdag': {'dinner': dinner}
      }
    });
  }
  final container = ProviderContainer(overrides: [
    householdProvider.overrideWith((ref) => _Household()),
    recipesProvider.overrideWith(() => _Recipes()),
    mealPlanProvider.overrideWith(() => MealPlanNotifier(firestore: fs)),
  ]);
  addTearDown(container.dispose);
  await container.read(mealPlanProvider.future);
  return (container.read(mealPlanProvider.notifier), fs);
}

Future<Map?> _dinner(FakeFirebaseFirestore fs) async {
  final data = (await fs
          .collection('households')
          .doc('h1')
          .collection('meal_plans')
          .doc(_week)
          .get())
      .data();
  return ((data?['days'] as Map?)?['Tirsdag'] as Map?)?['dinner'] as Map?;
}

void main() {
  final lasagne = MealSlot(recipeId: 'r1');

  test('offline: tom plads i cachen -> almindelig skrivning gendanner',
      () async {
    final (n, fs) = await _setup(
        _OfflineFirestore(), {'recipeId': null, 'directEntry': null});
    await n.restoreSlot('Tirsdag', 'dinner', lasagne, weekId: _week);
    expect(await _dinner(fs), {'recipeId': 'r1', 'directEntry': null});
  });

  test('offline: plads uden dokument i cachen -> gendanner', () async {
    final (n, fs) = await _setup(_OfflineFirestore(), null);
    await n.restoreSlot('Tirsdag', 'dinner', lasagne, weekId: _week);
    expect(await _dinner(fs), {'recipeId': 'r1', 'directEntry': null});
  });

  test('offline: fyldt plads i cachen -> SlotChangedException, intet skrives',
      () async {
    final (n, fs) = await _setup(
        _OfflineFirestore(), {'recipeId': null, 'directEntry': 'Pizza'});
    await expectLater(
      n.restoreSlot('Tirsdag', 'dinner', lasagne, weekId: _week),
      throwsA(isA<SlotChangedException>()),
    );
    expect(await _dinner(fs), {'recipeId': null, 'directEntry': 'Pizza'});
  });

  test('andre Firestore-fejl end unavailable kastes videre uden skrivning',
      () async {
    final (n, fs) = await _setup(_OfflineFirestore('permission-denied'),
        {'recipeId': null, 'directEntry': null});
    await expectLater(
      n.restoreSlot('Tirsdag', 'dinner', lasagne, weekId: _week),
      throwsA(isA<FirebaseException>()),
    );
    expect(await _dinner(fs), {'recipeId': null, 'directEntry': null});
  });

  test(
      'egen sletning venter stadig: ingen transaktion, lokal kopi tjekkes og '
      'skrivningen lægges i kø', () async {
    // runTransaction ville kaste en ikke-offline-fejl; den må ikke blive brugt.
    final (n, fs) = await _setup(_OfflineFirestore('failed-precondition'),
        {'recipeId': null, 'directEntry': null});
    await n.restoreSlot('Tirsdag', 'dinner', lasagne,
        weekId: _week, ownRemovePending: true);
    expect(await _dinner(fs), {'recipeId': 'r1', 'directEntry': null});
  });

  test('egen sletning venter, men en anden har fyldt pladsen -> konflikt',
      () async {
    final (n, fs) = await _setup(_OfflineFirestore('failed-precondition'),
        {'recipeId': null, 'directEntry': 'Pizza'});
    await expectLater(
      n.restoreSlot('Tirsdag', 'dinner', lasagne,
          weekId: _week, ownRemovePending: true),
      throwsA(isA<SlotChangedException>()),
    );
    expect(await _dinner(fs), {'recipeId': null, 'directEntry': 'Pizza'});
  });

  test('det gamle måltid står der allerede -> ingen konflikt, intet ændres',
      () async {
    final (n, fs) = await _setup(
        FakeFirebaseFirestore(), {'recipeId': 'r1', 'directEntry': null});
    await n.restoreSlot('Tirsdag', 'dinner', lasagne, weekId: _week);
    expect(await _dinner(fs), {'recipeId': 'r1', 'directEntry': null});
  });

  test('online: transaktionen gendanner kun en tom plads', () async {
    final (n, fs) = await _setup(
        FakeFirebaseFirestore(), {'recipeId': null, 'directEntry': null});
    await n.restoreSlot('Tirsdag', 'dinner', lasagne, weekId: _week);
    expect(await _dinner(fs), {'recipeId': 'r1', 'directEntry': null});
  });
}
