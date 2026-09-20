import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'recipes_provider.dart';
import '../../core/models/recipe.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/empty_state_widget.dart';
import '../../shared/widgets/profile_avatar.dart';


class RecipesScreen extends ConsumerStatefulWidget {
  const RecipesScreen({super.key});

  @override
  ConsumerState<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends ConsumerState<RecipesScreen> {
  String searchQuery = '';
  RecipeCategory? selectedCategory;

  @override
  Widget build(BuildContext context) {
    final recipes = ref.watch(recipesProvider);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Image.asset('assets/images/logo.png', height: 32),
                            const SizedBox(width: 12),
                            Text(
                              'Opskrifter',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryContainer,
                              ),
                            ),
                          ],
                        ),
                        const ProfileAvatar(),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SearchBar(
                      onChanged: (val) => setState(() => searchQuery = val),
                    ),
                    const SizedBox(height: 16),
                    _CategoryFilter(
                      selected: selectedCategory,
                      onSelected: (cat) => setState(() => selectedCategory = cat),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            recipes.when(
              data: (recipeList) {
                final results = recipeList.where((r) {
                  final matchesQuery = r.title.toLowerCase().contains(searchQuery.toLowerCase());
                  final matchesCategory = selectedCategory == null || r.category == selectedCategory;
                  return matchesQuery && matchesCategory;
                }).toList();

                if (results.isEmpty) {
                  if (searchQuery.isNotEmpty || selectedCategory != null) {
                    return const SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyStateWidget(
                        icon: Icons.search_off,
                        title: 'Ingen opskrifter fundet',
                        message: 'Prøv at søge efter noget andet eller nulstil filteret.',
                      ),
                    );
                  }
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyStateWidget(
                      icon: Icons.restaurant_menu_outlined,
                      title: 'Ingen opskrifter endnu',
                      message: 'Opret familiens yndlingsretter, så du nemt kan planlægge ugens måltider.',
                      actionLabel: 'Opret opskrift',
                      onAction: () => context.push('/recipes/create'),
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 1,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final recipe = results[index];
                        return GestureDetector(
                          onTap: () => GoRouter.of(context).push('/recipes/${recipe.id}'),
                          child: _RecipeCard(recipe: recipe, isFeatured: index == 0),
                        );
                      },
                      childCount: results.length,
                    ),
                  ),
                );
              },
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, stack) => SliverFillRemaining(
                child: Center(child: Text('Fejl: $err')),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/recipes/create'),
        label: const Text('Opret opskrift'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final ValueChanged<String> onChanged;

  const _SearchBar({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Søg i opskrifter, ingredienser...',
        prefixIcon: const Icon(Icons.search, color: AppColors.outline),
        suffixIcon: IconButton(
          icon: const Icon(Icons.tune, color: AppColors.outline),
          onPressed: () {},
        ),
      ),
    );
  }
}

class _CategoryFilter extends StatelessWidget {
  final RecipeCategory? selected;
  final ValueChanged<RecipeCategory?> onSelected;

  const _CategoryFilter({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _CategoryChip(
            label: 'Alle',
            isSelected: selected == null,
            onTap: () => onSelected(null),
          ),
          const SizedBox(width: 8),
          ...RecipeCategory.values.map((cat) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _CategoryChip(
                label: _capitalize(cat.name),
                isSelected: selected == cat,
                onTap: () => onSelected(cat),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _capitalize(String s) => s[0].toUpperCase() + s.substring(1);
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryContainer : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isSelected ? AppColors.primaryContainer : AppColors.outlineVariant,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.beVietnamPro(
            color: isSelected ? AppColors.onPrimary : AppColors.onSurfaceVariant,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final bool isFeatured;

  const _RecipeCard({required this.recipe, this.isFeatured = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        image: recipe.imageUrl != null
            ? DecorationImage(
                image: CachedNetworkImageProvider(recipe.imageUrl!),
                fit: BoxFit.cover,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.1),
                    Colors.black.withValues(alpha: 0.8),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite_border, color: Colors.white, size: 18),
            ),
          ),
          Positioned(
            bottom: 12,
            left: 12,
            right: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    recipe.category.name.toUpperCase(),
                    style: GoogleFonts.beVietnamPro(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  recipe.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: isFeatured ? 20 : 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

