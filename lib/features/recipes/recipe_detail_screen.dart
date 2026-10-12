import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../recipes/recipes_provider.dart';
import '../grocery/grocery_provider.dart';
import '../../core/models/recipe.dart';
import '../../core/models/grocery_item.dart';
import '../../shared/widgets/add_to_meal_plan_sheet.dart';
import 'package:uuid/uuid.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import 'edit_recipe_screen.dart';
import 'recipe_form_widgets.dart';
import '../../shared/utils/number_format.dart';
import '../../core/theme/theme_context.dart';

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
              background: CachedNetworkImage(
                imageUrl: recipe.imageUrl ?? 'https://via.placeholder.com/400x300',
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: context.colors.surfaceContainerHigh,
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => const Icon(Icons.error),
              ),
            ),
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(
                backgroundColor: context.colors.surfaceContainerLowest.withValues(alpha: 0.9),
                child: IconButton(
                  icon: Icon(Icons.arrow_back, color: context.colors.onSurface),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: CircleAvatar(
                  backgroundColor: context.colors.surfaceContainerLowest.withValues(alpha: 0.9),
                  child: IconButton(
                    icon: Icon(Icons.edit, color: context.colors.onSurface),
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
                // Wrap i stedet for Row, så tid/portioner ombrydes på smalle skærme.
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.colors.primaryContainer.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        recipe.category.name.toUpperCase(),
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (recipe.time.trim().isNotEmpty) ...[
                          Icon(Icons.schedule, size: 18, color: context.colors.outline),
                          const SizedBox(width: 4),
                          Text(recipe.time, style: Theme.of(context).textTheme.labelSmall),
                        ],
                        if (recipe.servings != null) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.people_outline, size: 18, color: context.colors.outline),
                          const SizedBox(width: 4),
                          Text(
                            recipe.servings == 1 ? '1 portion' : '${recipe.servings} portioner',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  recipe.title,
                  style: Theme.of(context).textTheme.displayLarge,
                ),
                if (recipe.hasNutrition) ...[
                  const SizedBox(height: 20),
                  _NutritionSummary(recipe: recipe),
                ],
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
                          backgroundColor: context.colors.primaryContainer,
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
                          backgroundColor: context.colors.secondaryContainer,
                          foregroundColor: context.colors.onSecondaryContainer,
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
                        decoration: BoxDecoration(
                          color: context.colors.primary,
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
                        formatIngredientAmount(ing),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.colors.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                )),
                if (recipe.instructions.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  RecipeInstructions(steps: recipe.instructions),
                ],
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
          quantity: formatQuantity(ing.quantity),
          unit: ing.unit,
          source: 'recipe',
          createdAt: DateTime.now(),
        ),
      );
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${recipe.ingredients.length} ingredienser tilføjet til indkøbslisten'),
        backgroundColor: context.colors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showAddToMealPlan(BuildContext context, Recipe recipe) {
    showAppBottomSheet(
      context: context,
      builder: (context) => AddToMealPlanSheet(recipe: recipe),
    );
  }
}

/// Fire små felter med næring pr. portion under titlen.
class _NutritionSummary extends StatelessWidget {
  final Recipe recipe;
  const _NutritionSummary({required this.recipe});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    String grams(double? v) => v == null ? '–' : '${formatDanishNumber(v)} g';

    final tiles = [
      ('${recipe.calories}', 'kcal'),
      (grams(recipe.protein), 'protein'),
      (grams(recipe.carbs), 'kulhydrat'),
      (grams(recipe.fat), 'fedt'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          tiles[i].$1,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tiles[i].$2,
                        style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          recipe.nutritionFromIngredients
              ? 'Pr. portion · beregnet ud fra ingredienserne'
              : 'Pr. portion',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Fremgangsmåden som nummererede trin. Tryk på et trin for at markere det
/// som udført mens man laver mad — det huskes kun lokalt og gemmes ikke.
class RecipeInstructions extends StatefulWidget {
  final List<String> steps;
  const RecipeInstructions({super.key, required this.steps});

  @override
  State<RecipeInstructions> createState() => _RecipeInstructionsState();
}

class _RecipeInstructionsState extends State<RecipeInstructions> {
  final Set<int> _done = {};

  @override
  void didUpdateWidget(RecipeInstructions old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.steps, widget.steps)) _done.clear();
  }

  void _toggle(int i) => setState(() => _done.contains(i) ? _done.remove(i) : _done.add(i));

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fremgangsmåde', style: text.headlineLarge),
        const SizedBox(height: 16),
        for (var i = 0; i < widget.steps.length; i++)
          Semantics(
            container: true,
            button: true,
            excludeSemantics: true,
            label: 'Trin ${i + 1}: ${widget.steps[i]}',
            value: _done.contains(i) ? 'udført' : null,
            hint: _done.contains(i) ? 'Tryk for at fjerne markeringen' : 'Tryk for at markere som udført',
            onTap: () => _toggle(i),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _toggle(i),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: _done.contains(i) ? colors.surfaceContainerHigh : colors.primaryContainer,
                        child: _done.contains(i)
                            ? Icon(Icons.check, size: 16, color: colors.onSurfaceVariant)
                            : Text(
                                '${i + 1}',
                                style: text.labelSmall?.copyWith(
                                  color: colors.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            widget.steps[i],
                            style: text.bodyMedium?.copyWith(
                              decoration: _done.contains(i) ? TextDecoration.lineThrough : null,
                              color: _done.contains(i) ? colors.onSurfaceVariant : colors.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
