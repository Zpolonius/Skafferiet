import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/models/grocery_item.dart';

void main() {
  group('GroceryItem.sortOrder', () {
    test('defaults to createdAt milliseconds when not provided', () {
      final createdAt = DateTime(2024, 6, 1, 12, 0, 0);
      final item = GroceryItem(
        id: 'a',
        name: 'Mælk',
        category: 'Mejeri',
        quantity: '1',
        source: 'manual',
        createdAt: createdAt,
      );
      expect(item.sortOrder, createdAt.millisecondsSinceEpoch);
    });

    test('uses provided value when given', () {
      final item = GroceryItem(
        id: 'a',
        name: 'Mælk',
        category: 'Mejeri',
        quantity: '1',
        source: 'manual',
        createdAt: DateTime.now(),
        sortOrder: 42,
      );
      expect(item.sortOrder, 42);
    });

    test('toMap includes sortOrder', () {
      final item = GroceryItem(
        id: 'a',
        name: 'Mælk',
        category: 'Mejeri',
        quantity: '1',
        source: 'manual',
        createdAt: DateTime.now(),
        sortOrder: 5,
      );
      expect(item.toMap()['sortOrder'], 5);
    });

    test('fromMap reads sortOrder correctly', () {
      final createdAt = DateTime(2024, 6, 1);
      final item = GroceryItem.fromMap({
        'name': 'Mælk',
        'category': 'Mejeri',
        'quantity': '1',
        'source': 'manual',
        'isChecked': false,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'sortOrder': 3,
      }, 'test-id');
      expect(item.sortOrder, 3);
    });

    test('fromMap falls back to createdAt when sortOrder missing', () {
      final createdAt = DateTime(2024, 6, 1);
      final item = GroceryItem.fromMap({
        'name': 'Brød',
        'category': 'Kolonial',
        'quantity': '2',
        'source': 'manual',
        'isChecked': false,
        'createdAt': createdAt.millisecondsSinceEpoch,
      }, 'test-id');
      expect(item.sortOrder, createdAt.millisecondsSinceEpoch);
    });

    test('copyWith preserves sortOrder when not overridden', () {
      final item = GroceryItem(
        id: 'a',
        name: 'Mælk',
        category: 'Mejeri',
        quantity: '1',
        source: 'manual',
        createdAt: DateTime.now(),
        sortOrder: 7,
      );
      expect(item.copyWith(name: 'Sødmælk').sortOrder, 7);
    });

    test('copyWith can override sortOrder', () {
      final item = GroceryItem(
        id: 'a',
        name: 'Mælk',
        category: 'Mejeri',
        quantity: '1',
        source: 'manual',
        createdAt: DateTime.now(),
        sortOrder: 7,
      );
      expect(item.copyWith(sortOrder: 99).sortOrder, 99);
    });
  });

  group('GroceryItem ordering', () {
    test('items sort correctly by sortOrder', () {
      final now = DateTime.now();
      final items = [
        GroceryItem(id: 'c', name: 'C', category: 'X', quantity: '1', source: 'manual', createdAt: now, sortOrder: 2),
        GroceryItem(id: 'a', name: 'A', category: 'X', quantity: '1', source: 'manual', createdAt: now, sortOrder: 0),
        GroceryItem(id: 'b', name: 'B', category: 'X', quantity: '1', source: 'manual', createdAt: now, sortOrder: 1),
      ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      expect(items.map((i) => i.name).toList(), ['A', 'B', 'C']);
    });
  });
}
