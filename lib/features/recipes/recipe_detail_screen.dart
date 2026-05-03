import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../recipes/recipes_provider.dart';
import '../grocery/grocery_provider.dart';
import '../../core/models/recipe.dart';
import '../../core/models/grocery_item.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/add_to_meal_plan_sheet.dart';
import 'package:uuid/uuid.dart';
import 'edit_recipe_screen.dart';

class RecipeDetailScreen extends ConsumerWidget {
  final String recipeId;

  const RecipeDetailScreen({super.key, required this.recipeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(recipesProvider);
    return Scaffold(
      body: recipes.when(
        data: (recipeList) {
          final recipe = recipeList.firstWhere((r) => r.id == recipeId);
          return CustomScrollView(
            slivers: [
              // Header with Image
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Image.network(
                recipe.imageUrl ?? 'https://via.placeholder.com/400x300',
                fit: BoxFit.cover,
              ),
            ),
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(
                backgroundColor: Colors.white.withValues(alpha: 0.9),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: CircleAvatar(
                  backgroundColor: Colors.white.withValues(alpha: 0.9),
                  child: IconButton(
                    icon: const Icon(Icons.edit, color: AppColors.onSurface),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => EditRecipeScreen(recipe: recipe)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        recipe.category.name.toUpperCase(),
                        style: GoogleFonts.beVietnamPro(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.schedule, size: 18, color: AppColors.outline),
                        const SizedBox(width: 4),
                        Text('25 min', style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  recipe.title,
                  style: Theme.of(context).textTheme.displayLarge,
                ),
                const SizedBox(height: 24),
                
                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _addIngredientsToList(context, ref, recipe),
                        icon: const Icon(Icons.shopping_basket),
                        label: const Text('Tilføj til indkøb'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _showAddToMealPlan(context, recipe),
                        icon: const Icon(Icons.calendar_today),
                        label: const Text('Til madplan'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.secondaryContainer,
                          foregroundColor: AppColors.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 32),
                Text(
                  'Ingredienser',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 16),
                ...recipe.ingredients.map((ing) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          ing.name,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        '${ing.quantity} ${ing.unit}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )),
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      );
    },
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (err, stack) => Center(child: Text('Fejl: $err')),
    ),
  );
}

  void _addIngredientsToList(BuildContext context, WidgetRef ref, dynamic recipe) {
    for (final ing in recipe.ingredients) {
      ref.read(groceryListProvider.notifier).addItem(
        GroceryItem(
          id: const Uuid().v4(),
          name: ing.name,
          category: ing.category,
          quantity: ing.quantity.toString(),
          unit: ing.unit,
          source: 'recipe',
          createdAt: DateTime.now(),
        ),
      );
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${recipe.ingredients.length} ingredienser tilføjet til indkøbslisten'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showAddToMealPlan(BuildContext context, Recipe recipe) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddToMealPlanSheet(recipe: recipe),
    );
  }
}
