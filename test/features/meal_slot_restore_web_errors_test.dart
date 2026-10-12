// QA for #36 (runde 3): fejl fra web (pakket ind som tekst) klassificeres
// snævert, og awaitSlotWrite melder sene fejl.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/models/meal_plan.dart';
import 'package:skafferiet/core/models/recipe.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/meal_plan/slot_write.dart';
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

class _Throwing extends FakeFirebaseFirestore {
  _Throwing(this.error);
  final Object error;
  @override
  Future<T> runTransaction<T>(TransactionHandler<T> h,
          {Duration timeout = const Duration(seconds: 30),
          int maxAttempts = 5}) =>
      Future.error(error);
}

const _week = '2026-09-28';

Future<(MealPlanNotifier, FakeFirebaseFirestore)> _setup(
    FakeFirebaseFirestore fs) async {
  await fs
      .collection('households')
      .doc('h1')
      .collection('meal_plans')
      .doc(_week)
      .set({
    'days': {
      'Tirsdag': {
        'dinner': {'recipeId': null, 'directEntry': null}
      }
    }
  });
  final c = ProviderContainer(overrides: [
    householdProvider.overrideWith((ref) => _Household()),
    recipesProvider.overrideWith(() => _Recipes()),
    mealPlanProvider.overrideWith(() => MealPlanNotifier(firestore: fs)),
  ]);
  addTearDown(c.dispose);
  await c.read(mealPlanProvider.future);
  return (c.read(mealPlanProvider.notifier), fs);
}

Future<Map?> _dinner(FakeFirebaseFirestore fs) async {
  final d = (await fs
          .collection('households')
          .doc('h1')
          .collection('meal_plans')
          .doc(_week)
          .get())
      .data();
  return ((d?['days'] as Map?)?['Tirsdag'] as Map?)?['dinner'] as Map?;
}

void main() {
  final slot = MealSlot(recipeId: 'r1');

  test('web-wrapped unavailable falls back to cache write', () async {
    final (n, fs) = await _setup(_Throwing(Exception(
        'Error: Dart exception: [cloud_firestore/unavailable] Failed to get document because the client is offline.')));
    await n.restoreSlot('Tirsdag', 'dinner', slot, weekId: _week);
    expect(await _dinner(fs), {'recipeId': 'r1', 'directEntry': null});
  });

  for (final msg in [
    'Error: Dart exception: [cloud_firestore/permission-denied] Missing or insufficient permissions.',
    '[cloud_firestore/permission-denied] service unavailable',
    'Error: unavailable',
    '[cloud_firestore/aborted] Transaction failed: unavailable',
  ]) {
    test('non-offline error is rethrown without write: $msg', () async {
      final (n, fs) = await _setup(_Throwing(Exception(msg)));
      Object? err;
      try {
        await n.restoreSlot('Tirsdag', 'dinner', slot, weekId: _week);
      } catch (e) {
        err = e;
      }
      expect(err, isNotNull);
      expect(await _dinner(fs), {'recipeId': null, 'directEntry': null});
    });
  }

  test('SlotChangedException.matches is narrow', () {
    expect(SlotChangedException.matches(const SlotChangedException()), isTrue);
    expect(
        SlotChangedException.matches(
            Exception('Dart exception: SlotChangedException')),
        isTrue);
    expect(
        SlotChangedException.matches(
            Exception('[cloud_firestore/permission-denied]')),
        isFalse);
  });

  test(
      'awaitSlotWrite: early error throws, late error -> pending + onLateError',
      () async {
    final early = Completer<void>();
    final f = awaitSlotWrite(early.future,
        onLateError: (_) => fail('no'),
        wait: const Duration(milliseconds: 100));
    early.completeError('x');
    await expectLater(f, throwsA('x'));

    final late = Completer<void>();
    Object? got;
    final r = await awaitSlotWrite(late.future,
        onLateError: (e) => got = e, wait: const Duration(milliseconds: 50));
    expect(r, SlotWriteResult.pending);
    late.completeError('y');
    await Future<void>.delayed(Duration.zero);
    expect(got, 'y');
  });
}
