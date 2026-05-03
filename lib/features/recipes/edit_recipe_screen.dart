import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/recipe.dart';
import '../../core/theme/app_colors.dart';
import 'recipes_provider.dart';

class EditRecipeScreen extends ConsumerStatefulWidget {
  final Recipe recipe;
  const EditRecipeScreen({super.key, required this.recipe});

  @override
  ConsumerState<EditRecipeScreen> createState() => _EditRecipeScreenState();
}

class _EditRecipeScreenState extends ConsumerState<EditRecipeScreen> {
  late TextEditingController _titleController;
  late TextEditingController _caloriesController;
  late TextEditingController _timeController;
  late RecipeCategory _selectedCategory;
  late List<Ingredient> _ingredients;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.recipe.title);
    _caloriesController = TextEditingController(text: widget.recipe.calories.toString());
    _timeController = TextEditingController(text: widget.recipe.time);
    _selectedCategory = widget.recipe.category;
    _ingredients = List.from(widget.recipe.ingredients);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rediger opskrift')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Grundlæggende info'),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Titel', hintText: 'F.eks. Pasta Carbonara'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _caloriesController,
                    decoration: const InputDecoration(labelText: 'Kalorier', suffixText: 'kcal'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _timeController,
                    decoration: const InputDecoration(labelText: 'Tid', hintText: 'F.eks. 20 min'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Kategori'),
            Wrap(
              spacing: 8,
              children: RecipeCategory.values.map((cat) {
                final isSelected = _selectedCategory == cat;
                return ChoiceChip(
                  label: Text(cat.name.split('.').last),
                  selected: isSelected,
                  onSelected: (val) => setState(() => _selectedCategory = cat),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSectionTitle('Ingredienser'),
                IconButton(
                  onPressed: _addIngredient,
                  icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                ),
              ],
            ),
            ..._ingredients.asMap().entries.map((entry) {
              final idx = entry.key;
              final ing = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        decoration: const InputDecoration(hintText: 'Navn'),
                        onChanged: (val) => _ingredients[idx] = ing.copyWith(name: val),
                        controller: TextEditingController(text: ing.name),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        decoration: const InputDecoration(hintText: 'Mængde'),
                        onChanged: (val) => _ingredients[idx] = ing.copyWith(quantity: double.tryParse(val) ?? 0),
                        controller: TextEditingController(text: ing.quantity.toString()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        decoration: const InputDecoration(hintText: 'Enh.'),
                        onChanged: (val) => _ingredients[idx] = ing.copyWith(unit: val),
                        controller: TextEditingController(text: ing.unit),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _ingredients.removeAt(idx)),
                      icon: const Icon(Icons.remove_circle_outline, color: AppColors.error),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 40),
            FilledButton(
              onPressed: _saveRecipe,
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
              child: const Text('Gem ændringer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: Theme.of(context).textTheme.labelSmall),
    );
  }

  void _addIngredient() {
    setState(() {
      _ingredients.add(Ingredient(name: '', quantity: 0, unit: '', category: 'Andet'));
    });
  }

  void _saveRecipe() {
    final updatedRecipe = widget.recipe.copyWith(
      title: _titleController.text,
      calories: int.tryParse(_caloriesController.text) ?? 0,
      time: _timeController.text,
      category: _selectedCategory,
      ingredients: _ingredients,
    );
    
    ref.read(recipesProvider.notifier).updateRecipe(updatedRecipe);
    Navigator.pop(context);
  }
}
