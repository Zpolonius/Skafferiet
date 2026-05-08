import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/recipe.dart';
import '../../core/theme/app_colors.dart';
import '../../features/profile/household_provider.dart';
import '../../shared/utils/image_upload_service.dart';
import 'recipes_provider.dart';

class CreateRecipeScreen extends ConsumerStatefulWidget {
  const CreateRecipeScreen({super.key});

  @override
  ConsumerState<CreateRecipeScreen> createState() => _CreateRecipeScreenState();
}

class _CreateRecipeScreenState extends ConsumerState<CreateRecipeScreen> {
  final _titleController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _timeController = TextEditingController();
  RecipeCategory _selectedCategory = RecipeCategory.Aftensmad;
  final List<Ingredient> _ingredients = [];
  String? _imageUrl;
  bool _isUploadingImage = false;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ny opskrift')),
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
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        decoration: const InputDecoration(hintText: 'Mængde'),
                        onChanged: (val) => _ingredients[idx] = ing.copyWith(quantity: double.tryParse(val) ?? 0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        decoration: const InputDecoration(hintText: 'Enh.'),
                        onChanged: (val) => _ingredients[idx] = ing.copyWith(unit: val),
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
              child: const Text('Opret opskrift'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePicker(BuildContext context) {
    return GestureDetector(
      onTap: _isUploadingImage ? null : () => _pickImage(context),
      child: Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[300]!),
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
                      Icon(Icons.add_photo_alternate_outlined, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text(
                        'Tilføj billede',
                        style: TextStyle(color: Colors.grey[500], fontSize: 14),
                      ),
                    ],
                  )
                : Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.black54,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.edit, size: 16, color: Colors.white),
                          onPressed: () => _pickImage(context),
                        ),
                      ),
                    ),
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
    final recipe = Recipe(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _titleController.text,
      imageUrl: _imageUrl,
      calories: int.tryParse(_caloriesController.text) ?? 0,
      time: _timeController.text,
      category: _selectedCategory,
      ingredients: _ingredients,
    );
    
    ref.read(recipesProvider.notifier).addRecipe(recipe);
    Navigator.pop(context);
  }
}
