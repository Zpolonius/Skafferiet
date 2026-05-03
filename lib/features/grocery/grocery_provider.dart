import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/grocery_item.dart';

class GroceryListNotifier extends AsyncNotifier<List<GroceryItem>> {
  @override
  Future<List<GroceryItem>> build() async {
    // Dette simulerer et netværkskald
    await Future.delayed(const Duration(milliseconds: 500));
    return _mockItems;
  }

  Future<void> toggleItem(String id) async {
    final currentItems = state.value ?? [];
    state = AsyncValue.data(
      currentItems.map((item) {
        if (item.id == id) {
          return item.copyWith(isChecked: !item.isChecked);
        }
        return item;
      }).toList(),
    );
  }

  Future<void> removeItem(String id) async {
    final currentItems = state.value ?? [];
    state = AsyncValue.data(
      currentItems.where((item) => item.id != id).toList(),
    );
  }

  Future<void> addItem(GroceryItem item) async {
    final currentItems = state.value ?? [];
    state = AsyncValue.data([...currentItems, item]);
  }

  Future<void> updateQuantity(String id, String newQuantity) async {
    final currentItems = state.value ?? [];
    state = AsyncValue.data(
      currentItems.map((item) {
        if (item.id == id) {
          return item.copyWith(quantity: newQuantity);
        }
        return item;
      }).toList(),
    );
  }
}

final groceryListProvider = AsyncNotifierProvider<GroceryListNotifier, List<GroceryItem>>(() {
  return GroceryListNotifier();
});

final _mockItems = [
  GroceryItem(
    id: '1',
    name: 'Hass Avocado',
    category: 'Frugt & Grønt',
    quantity: '4',
    unit: 'stk',
    source: 'manual',
    createdAt: DateTime.now(),
    imageUrl: 'https://images.unsplash.com/photo-1523049673857-eb18f1d7b578?w=200',
  ),
  GroceryItem(
    id: '2',
    name: 'Cherrytomater',
    category: 'Frugt & Grønt',
    quantity: '1',
    unit: 'bakke',
    source: 'manual',
    createdAt: DateTime.now(),
  ),
  GroceryItem(
    id: '3',
    name: 'Spinat',
    category: 'Frugt & Grønt',
    quantity: '2',
    unit: 'poser',
    isChecked: true,
    source: 'manual',
    createdAt: DateTime.now(),
  ),
  GroceryItem(
    id: '4',
    name: 'Mandelmælk',
    category: 'Mejeri',
    quantity: '1',
    unit: 'liter',
    source: 'manual',
    createdAt: DateTime.now(),
  ),
];
