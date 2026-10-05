import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/models/meal_type.dart';
import 'package:skafferiet/features/profile/household_provider.dart';

/// Kører hele vejen rundt med lytterne på bruger- og husstandsdokumentet, så
/// et snapshot ikke kan overskrive brugerens valg, lige efter det er gemt.
void main() {
  test('et fravalgt måltid bliver fravalgt, også når snapshots kommer bagefter', () async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'u1', email: 'a@b.dk', displayName: 'A'),
    );
    await firestore
        .collection('households')
        .doc('SK-1')
        .set({'name': 'H', 'members': ['u1'], 'admin': 'u1'});
    await firestore
        .collection('users')
        .doc('u1')
        .set({'householdId': 'SK-1', 'hasCompletedOnboarding': true, 'displayName': 'A'});

    final notifier = HouseholdNotifier(firestore: firestore, auth: auth);
    addTearDown(notifier.dispose);
    await pumpEventQueue();
    expect(notifier.state.householdId, 'SK-1');
    expect(notifier.state.mealTypes, MealType.values);

    final error = await notifier.setMealTypes({MealType.breakfast, MealType.dinner});
    await pumpEventQueue();

    expect(error, isNull);
    expect(notifier.state.mealTypes, [MealType.breakfast, MealType.dinner]);
    final saved = await firestore.collection('users').doc('u1').get();
    expect(saved.data()?['mealTypes'], ['breakfast', 'dinner']);
  });
}
