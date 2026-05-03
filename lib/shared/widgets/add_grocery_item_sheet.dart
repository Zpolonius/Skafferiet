import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/grocery_item.dart';
import '../../features/grocery/grocery_provider.dart';
import 'package:uuid/uuid.dart';

class AddGroceryItemSheet extends ConsumerStatefulWidget {
  const AddGroceryItemSheet({super.key});

  @override
  ConsumerState<AddGroceryItemSheet> createState() => _AddGroceryItemSheetState();
}

class _AddGroceryItemSheetState extends ConsumerState<AddGroceryItemSheet> {
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _customCategoryController = TextEditingController();
  
  String _selectedCategory = 'Grønt';
  String _selectedUnit = 'stk';
  bool _isAddingCustomCategory = false;

  final categories = ['Grønt', 'Mejeri', 'Kød', 'Frost', 'Brød', 'Andet'];
  final units = ['stk', 'g', 'kg', 'ml', 'l', 'pk', 'bakke', 'poser'];

  @override
  Widget build(BuildContext context) {
    final groceryList = ref.watch(groceryListProvider);
    final existingCategories = groceryList.when(
      data: (items) => items.map((i) => i.category).toSet().toList(),
      loading: () => <String>[],
      error: (_, __) => <String>[],
    );

    // Merge predefined with existing
    final allCategories = {...categories, ...existingCategories}.toList();

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        top: 24,
        left: 24,
        right: 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tilføj vare',
            style: Theme.of(context).textTheme.displayMedium,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Hvad skal du bruge?',
              prefixIcon: Icon(Icons.shopping_cart_outlined),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Mængde'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  value: _selectedUnit,
                  decoration: const InputDecoration(labelText: 'Enhed'),
                  items: units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                  onChanged: (v) => setState(() => _selectedUnit = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Kategori', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ...allCategories.map((cat) {
                  final isSelected = _selectedCategory == cat && !_isAddingCustomCategory;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: isSelected,
                      onSelected: (val) {
                        setState(() {
                          _selectedCategory = cat;
                          _isAddingCustomCategory = false;
                        });
                      },
                    ),
                  );
                }),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('+ Ny'),
                    selected: _isAddingCustomCategory,
                    onSelected: (val) {
                      setState(() {
                        _isAddingCustomCategory = true;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_isAddingCustomCategory) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _customCategoryController,
              decoration: const InputDecoration(
                hintText: 'Navn på ny kategori...',
                prefixIcon: Icon(Icons.label_outline),
              ),
              onChanged: (val) => setState(() => _selectedCategory = val),
            ),
          ],
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () {
              if (_nameController.text.isNotEmpty) {
                ref.read(groceryListProvider.notifier).addItem(
                  GroceryItem(
                    id: const Uuid().v4(),
                    name: _nameController.text,
                    category: _selectedCategory,
                    quantity: _quantityController.text,
                    unit: _selectedUnit,
                    source: 'manual',
                    createdAt: DateTime.now(),
                  ),
                );
                Navigator.pop(context);
              }
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Tilføj til liste'),
          ),
        ],
      ),
    );
  }
}
