import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/recipe.dart';
import '../../core/theme/theme_context.dart';
import '../../features/profile/household_provider.dart';
import '../../shared/utils/image_upload_service.dart';
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
  String? _imageUrl;
  bool _isUploadingImage = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.recipe.title);
    _caloriesController = TextEditingController(text: widget.recipe.calories.toString());
    _timeController = TextEditingController(text: widget.recipe.time);
    _selectedCategory = widget.recipe.category;
    _ingredients = List.from(widget.recipe.ingredients);
    _imageUrl = widget.recipe.imageUrl;
  }

  Future<void> _pickImage(BuildContext context) async {
    final householdId = ref.read(householdProvider).householdId;
    final folder = householdId != null
        ? 'households/$householdId/recipes'
        : 'temp/recipes';
    setState(() => _isUploadingImage = true);
    try {
      final url = await ImageUploadService.pickAndUpload(context, storagePath: folder);
      if (mounted && url != null) setState(() => _imageUrl = url);
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Widget _buildImagePicker(BuildContext context) {
    return GestureDetector(
      onTap: _isUploadingImage ? null : () => _pickImage(context),
      child: Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.colors.surfaceContainerHighest),
          image: _imageUrl != null
              ? DecorationImage(image: NetworkImage(_imageUrl!), fit: BoxFit.cover)
              : null,
        ),
        child: _isUploadingImage
            ? const Center(child: CircularProgressIndicator())
            : _imageUrl == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 48, color: context.colors.outlineVariant),
                      const SizedBox(height: 8),
                      Text(
                        'Tilføj billede',
                        style: TextStyle(color: context.colors.outline, fontSize: 14),
                      ),
                    ],
                  )
                : Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: PhotoOverlay.scrim.withValues(alpha: 0.54),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.edit, size: 16, color: PhotoOverlay.foreground),
                          onPressed: () => _pickImage(context),
                        ),
                      ),
                    ),
                  ),
      ),
    );
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
            _buildImagePicker(context),
            const SizedBox(height: 24),
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
                  icon: Icon(Icons.add_circle_outline, color: context.colors.primary),
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
                      icon: Icon(Icons.remove_circle_outline, color: context.colors.error),
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

  Future<void> _saveRecipe() async {
    final updatedRecipe = widget.recipe.copyWith(
      title: _titleController.text,
      imageUrl: _imageUrl,
      calories: int.tryParse(_caloriesController.text) ?? 0,
      time: _timeController.text,
      category: _selectedCategory,
      ingredients: _ingredients,
    );
    
    try {
      await ref.read(recipesProvider.notifier).updateRecipe(updatedRecipe);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke opdatere opskrift: $e'), backgroundColor: context.colors.error),
        );
      }
    }
  }
}
