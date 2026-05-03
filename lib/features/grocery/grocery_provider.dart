import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/grocery_item.dart';

class GroceryListNotifier extends StateNotifier<List<GroceryItem>> {
  GroceryListNotifier() : super(_mockItems);

  void toggleChecked(String id) {
    state = [
      for (final item in state)
        if (item.id == id) item.copyWith(checked: !item.checked) else item,
    ];
  }

  void removeItem(String id) {
    state = state.where((item) => item.id != id).toList();
  }

  void addItem(GroceryItem item) {
    state = [...state, item];
  }

  void updateQuantity(String id, String newQuantity) {
    state = [
      for (final item in state)
        if (item.id == id) item.copyWith(quantity: newQuantity) else item,
    ];
  }
}

final groceryListProvider = StateNotifierProvider<GroceryListNotifier, List<GroceryItem>>((ref) {
  return GroceryListNotifier();
});

final _mockItems = [
  GroceryItem(
    id: '1',
    name: 'Hass Avocados',
    category: 'Grønt',
    quantity: '4',
    unit: 'stk',
    source: 'manual',
    createdAt: DateTime.now(),
  ),
  GroceryItem(
    id: '2',
    name: 'Cherrytomater',
    category: 'Grønt',
    quantity: '1',
    unit: 'bakke',
    source: 'manual',
    createdAt: DateTime.now(),
  ),
  GroceryItem(
    id: '3',
    name: 'Spinat',
    category: 'Grønt',
    quantity: '2',
    unit: 'poser',
    checked: true,
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
