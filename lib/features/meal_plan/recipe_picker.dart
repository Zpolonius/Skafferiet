import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/recipe.dart';
import '../../core/theme/theme_context.dart';
import '../recipes/recipe_search.dart';
import '../recipes/recipes_provider.dart';

/// Filtrerbar liste over husstandens opskrifter. Bruges både når man skifter
/// et måltid og når man tilføjer en opskrift til en tom plads i madplanen.
/// Selve valget håndteres af [onPick]; [enabled] låser listen mens der gemmes.
class RecipePicker extends ConsumerStatefulWidget {
  final ValueChanged<Recipe> onPick;
  final bool enabled;

  /// Opskriften der allerede står i måltidet (får et flueben).
  final String? currentRecipeId;

  /// Kaldes med den trimmede søgetekst når ingen opskrift matcher; så vises
  /// knappen "Skriv som eget måltid". Uden den vises ingen knap.
  final ValueChanged<String>? onNoMatch;

  const RecipePicker({
    super.key,
    required this.onPick,
    this.enabled = true,
    this.currentRecipeId,
    this.onNoMatch,
  });

  @override
  ConsumerState<RecipePicker> createState() => _RecipePickerState();
}

class _RecipePickerState extends ConsumerState<RecipePicker> {
  final _filterController = TextEditingController();

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recipesAsync = ref.watch(recipesProvider);
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _filterController,
          enabled: widget.enabled,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Find i dine opskrifter',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: recipesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Kunne ikke hente opskrifter',
                style: TextStyle(color: colors.error),
              ),
            ),
            data: (all) {
              final query = _filterController.text;
              final recipes = searchRecipes(all, query);
              if (recipes.isEmpty) {
                final noMatch = widget.onNoMatch;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        all.isEmpty
                            ? 'Du har ingen opskrifter endnu'
                            : 'Ingen opskrifter matcher',
                        style: context.text.bodyMedium
                            ?.copyWith(color: colors.outline),
                      ),
                      if (all.isNotEmpty && noMatch != null) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                              minimumSize: const Size(48, 48)),
                          onPressed: widget.enabled
                              ? () => noMatch(query.trim())
                              : null,
                          icon: const Icon(Icons.edit_note),
                          label: const Text('Skriv som eget måltid'),
                        ),
                      ],
                    ],
                  ),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                itemCount: recipes.length,
                itemBuilder: (context, i) {
                  final recipe = recipes[i];
                  final via = titleMatchesRecipeSearch(recipe, query)
                      ? const <String>[]
                      : matchingIngredientNames(recipe, query);
                  return ListTile(
                    minTileHeight: 56,
                    contentPadding: EdgeInsets.zero,
                    enabled: widget.enabled,
                    leading: RecipeThumb(imageUrl: recipe.imageUrl),
                    title: Text(recipe.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${recipe.calories} kcal • ${recipe.time}'),
                        if (via.isNotEmpty)
                          Text(
                            'Indeholder: ${via.take(3).join(', ')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    trailing: recipe.id == widget.currentRecipeId
                        ? Icon(Icons.check,
                            color: colors.primary, semanticLabel: 'Nuværende')
                        : null,
                    onTap: () => widget.onPick(recipe),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Billede af en opskrift, eller et tema-ikon når der intet billede er.
class RecipeThumb extends StatelessWidget {
  final String? imageUrl;

  const RecipeThumb({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final placeholder =
        Icon(Icons.restaurant_menu_outlined, color: colors.outline);
    final url = imageUrl;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: (url == null || url.isEmpty)
          ? placeholder
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder,
            ),
    );
  }
}
