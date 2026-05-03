import 'package:flutter/material.dart';
import '../../core/models/recipe.dart';
import '../../core/theme/app_colors.dart';

class CreateRecipeScreen extends StatefulWidget {
  const CreateRecipeScreen({super.key});

  @override
  State<CreateRecipeScreen> createState() => _CreateRecipeScreenState();
}

class _CreateRecipeScreenState extends State<CreateRecipeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  RecipeCategory _selectedCategory = RecipeCategory.dinner;
  final List<Map<String, dynamic>> _ingredients = [];

  void _addIngredient() {
    setState(() {
      _ingredients.add({
        'name': '',
        'quantity': 1.0,
        'unit': 'stk',
        'category': 'Andet',
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Opret opskrift'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Basis information', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 12),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: 'Opskriftens navn',
              ),
              validator: (v) => v == null || v.isEmpty ? 'Indtast navn' : null,
            ),
            const SizedBox(height: 16),
            
            Text('Kategori', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: RecipeCategory.values.map((cat) {
                final isSelected = _selectedCategory == cat;
                return ChoiceChip(
                  label: Text(cat.name[0].toUpperCase() + cat.name.substring(1)),
                  selected: isSelected,
                  onSelected: (val) => setState(() => _selectedCategory = cat),
                );
              }).toList(),
            ),
            
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Ingredienser', style: Theme.of(context).textTheme.labelSmall),
                TextButton.icon(
                  onPressed: _addIngredient,
                  icon: const Icon(Icons.add),
                  label: const Text('Tilføj'),
                ),
              ],
            ),
            
            ...List.generate(_ingredients.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        decoration: const InputDecoration(hintText: 'Navn'),
                        onChanged: (v) => _ingredients[index]['name'] = v,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        decoration: const InputDecoration(hintText: 'Antal'),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => _ingredients[index]['quantity'] = double.tryParse(v) ?? 1.0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        decoration: const InputDecoration(hintText: 'Enhed'),
                        initialValue: 'stk',
                        onChanged: (v) => _ingredients[index]['unit'] = v,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.error),
                      onPressed: () => setState(() => _ingredients.removeAt(index)),
                    ),
                  ],
                ),
              );
            }),
            
            const SizedBox(height: 40),
            FilledButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  // In a real app, we would add to provider/Firebase here
                  Navigator.pop(context);
                }
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Gem opskrift'),
            ),
          ],
        ),
      ),
    );
  }
}
