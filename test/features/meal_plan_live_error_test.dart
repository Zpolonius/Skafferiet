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

class _Fs extends Mock implements FirebaseFirestore {}

class _Col extends Mock implements CollectionReference<Map<String, dynamic>> {}

class _Doc extends Mock implements DocumentReference<Map<String, dynamic>> {}

class _Rec extends StreamNotifier<List<Recipe>>
    with Mock
    implements RecipesNotifier {
  @override
  Stream<List<Recipe>> build() => Stream.value([]);
}

class _Hh extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Hh() : super(HouseholdState(householdId: 'A'));
}

void main() {
  test('snapshots error becomes AsyncError; dispose cancels subscription',
      () async {
    var cancelled = false;
    late StreamController<DocumentSnapshot<Map<String, dynamic>>> c;
    c = StreamController(onCancel: () => cancelled = true);
    final fs = _Fs();
    final col = _Col();
    final doc = _Doc();
    when(() => fs.collection(any())).thenReturn(col);
    when(() => col.doc(any())).thenReturn(doc);
    when(() => doc.collection(any())).thenReturn(col);
    when(() => doc.snapshots()).thenAnswer((_) => c.stream);
    final container = ProviderContainer(overrides: [
      householdProvider.overrideWith((ref) => _Hh()),
      recipesProvider.overrideWith(() => _Rec()),
      mealPlanProvider.overrideWith(() => MealPlanNotifier(firestore: fs)),
    ]);
    container.listen(mealPlanProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);
    c.addError(FirebaseException(plugin: 'x', code: 'permission-denied'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final s = container.read(mealPlanProvider);
    expect(s.hasError, isTrue);
    expect((s.error as FirebaseException).code, 'permission-denied');
    container.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(cancelled, isTrue);
  });
}
