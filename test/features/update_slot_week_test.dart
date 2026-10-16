// updateSlot skriver til den uge, der gives med (#60), ellers til den viste.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/features/grocery/recurring/recurring_items_provider.dart'
    show clockProvider;
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/profile/household_provider.dart';

class _Household extends StateNotifier<HouseholdState>
    with Mock
    implements HouseholdNotifier {
  _Household() : super(HouseholdState(householdId: 'h1'));
}

void main() {
  late FakeFirebaseFirestore fs;
  late ProviderContainer container;

  setUp(() {
    fs = FakeFirebaseFirestore();
    container = ProviderContainer(overrides: [
      householdProvider.overrideWith((ref) => _Household()),
      mealPlanProvider.overrideWith(() => MealPlanNotifier(firestore: fs)),
      clockProvider.overrideWithValue(() => DateTime(2026, 10, 15, 12)),
    ]);
    addTearDown(container.dispose);
  });

  Future<Map<String, dynamic>?> data(String id) async => (await fs
          .collection('households')
          .doc('h1')
          .collection('meal_plans')
          .doc(id)
          .get())
      .data();

  test('weekId styrer hvilket meal_plans-dokument der skrives', () async {
    await container.read(mealPlanProvider.future);
    container.read(weekOffsetProvider.notifier).state = 0;
    await container
        .read(mealPlanProvider.notifier)
        .updateSlot('Tirsdag', 'dinner', directEntry: 'Suppe', weekId: '2026-10-19');
    expect(await data('2026-10-12'), isNull);
    expect((await data('2026-10-19'))?['days']['Tirsdag']['dinner']['directEntry'], 'Suppe');
  });

  test('uden weekId bruges den viste uge', () async {
    await container.read(mealPlanProvider.future);
    container.read(weekOffsetProvider.notifier).state = 1;
    await container
        .read(mealPlanProvider.notifier)
        .updateSlot('Tirsdag', 'dinner', directEntry: 'Suppe');
    expect((await data('2026-10-19'))?['days']['Tirsdag']['dinner']['directEntry'], 'Suppe');
  });
}
