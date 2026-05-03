import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skafferiet/features/grocery/grocery_provider.dart';
import 'package:skafferiet/core/models/grocery_item.dart';

void main() {
  group('GroceryListNotifier Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('Should load initial mock items', () async {
      final items = await container.read(groceryListProvider.future);
      expect(items.length, greaterThan(0));
      expect(items.any((i) => i.name == 'Hass Avocado'), true);
    });

    test('addItem should add a new item', () async {
      final notifier = container.read(groceryListProvider.notifier);
      final newItem = GroceryItem(
        id: 'test-123',
        name: 'Test Milk',
        category: 'Mejeri',
        quantity: '2',
        source: 'manual',
        createdAt: DateTime.now(),
      );
      
      await notifier.addItem(newItem);
      
      final items = container.read(groceryListProvider).value!;
      expect(items.any((i) => i.id == 'test-123'), true);
    });

    test('toggleItem should update isChecked', () async {
      final notifier = container.read(groceryListProvider.notifier);
      await container.read(groceryListProvider.future);
      
      await notifier.toggleItem('1');
      
      final items = container.read(groceryListProvider).value!;
      final item = items.firstWhere((i) => i.id == '1');
      expect(item.isChecked, true);
    });
  });
}
