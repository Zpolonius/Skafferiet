import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skafferiet/features/meal_plan/meal_plan_provider.dart';
import 'package:skafferiet/features/grocery/grocery_provider.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';

void main() {
  group('MealPlanNotifier Tests', () {
    late ProviderContainer container;

    setUp(() async {
      container = ProviderContainer();
      // Vi skal vente på at opskrifter er hentet, da MealPlanNotifier afhænger af dem
      await container.read(recipesProvider.future);
      await container.read(mealPlanProvider.future);
      await container.read(groceryListProvider.future);
    });

    tearDown(() {
      container.dispose();
    });

    test('updateSlot should update correctly', () async {
      final notifier = container.read(mealPlanProvider.notifier);
      
      await notifier.updateSlot('Mandag', 'Aftensmad', directEntry: 'Sushi');
      
      final plan = container.read(mealPlanProvider).value!;
      expect(plan.days['Mandag']?.dinner.directEntry, 'Sushi');
    });

    test('transferToShoppingList should add items', () async {
      final mealNotifier = container.read(mealPlanProvider.notifier);      
      final initialCount = container.read(groceryListProvider).value!.length;
      final count = await mealNotifier.transferToShoppingList();
      
      expect(count, greaterThan(0));
      expect(container.read(groceryListProvider).value!.length, initialCount + count);
    });
  });
}
