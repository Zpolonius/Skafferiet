import '../../core/theme/theme_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/recipe.dart';
import '../../core/services/nutrition_calculator.dart';
import '../../features/profile/household_provider.dart';
import '../../shared/utils/image_upload_service.dart';
import 'recipe_form_widgets.dart';
import 'recipes_provider.dart';

class CreateRecipeScreen extends ConsumerStatefulWidget {
  const CreateRecipeScreen({super.key});

  @override
  ConsumerState<CreateRecipeScreen> createState() => _CreateRecipeScreenState();
}

class _CreateRecipeScreenState extends ConsumerState<CreateRecipeScreen> {
  final _titleController = TextEditingController();
  final _timeController = TextEditingController();
  final _nutrition = NutritionFormControllers();
  RecipeCategory _selectedCategory = RecipeCategory.aftensmad;
  List<Ingredient> _ingredients = [];
  int? _servings;
  String? _imageUrl;
  bool _isUploadingImage = false;
  bool _showErrors = false;

  @override
  void dispose() {
    _titleController.dispose();
    _timeController.dispose();
    _nutrition.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ny opskrift')),
      body: SafeArea(
        child: SingleChildScrollView(
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
            TextField(
              controller: _timeController,
              decoration: const InputDecoration(labelText: 'Tid', hintText: 'F.eks. 20 min'),
            ),
            const SizedBox(height: 16),
            ServingsStepper(
              value: _servings,
              onChanged: (v) => setState(() => _servings = v),
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
            _buildSectionTitle('Ingredienser'),
            IngredientListEditor(
              ingredients: _ingredients,
              onChanged: (list) => setState(() => _ingredients = list),
            ),
            const SizedBox(height: 32),
            _buildSectionTitle('Næring pr. portion'),
            NutritionFields(
              controllers: _nutrition,
              calculation: calculateNutrition(_ingredients),
              servings: _servings,
              showErrors: _showErrors,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 40),
            FilledButton(
              onPressed: _saveRecipe,
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
              child: const Text('Opret opskrift'),
            ),
          ],
        ),
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

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: Theme.of(context).textTheme.labelSmall),
    );
  }

  Future<void> _saveRecipe() async {
    if (_nutrition.hasErrors) {
      setState(() => _showErrors = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ret de markerede næringsfelter')),
      );
      return;
    }
    final nutrition = _nutrition.resolve(calculateNutrition(_ingredients).perServing(_servings));
    final recipe = Recipe(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _titleController.text,
      imageUrl: _imageUrl,
      calories: nutrition.calories,
      time: _timeController.text,
      category: _selectedCategory,
      ingredients: _ingredients,
      servings: _servings,
      protein: nutrition.protein,
      carbs: nutrition.carbs,
      fat: nutrition.fat,
      nutritionFromIngredients: nutrition.fromIngredients,
    );
    
    try {
      await ref.read(recipesProvider.notifier).addRecipe(recipe);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke gemme opskrift: $e'), backgroundColor: context.colors.error),
        );
      }
    }
  }
}
