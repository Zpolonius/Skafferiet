import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'recipes_provider.dart';
import '../../core/models/recipe.dart';
import '../../shared/widgets/empty_state_widget.dart';
import '../../shared/widgets/profile_avatar.dart';
import '../../core/theme/theme_context.dart';


class RecipesScreen extends ConsumerStatefulWidget {
  const RecipesScreen({super.key});

  @override
  ConsumerState<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends ConsumerState<RecipesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String searchQuery = '';
  RecipeCategory? selectedCategory;

  @override
  void initState() {
    super.initState();
    // Skærmen kan blive bygget første gang netop fordi nogen bad om søgning.
    _focusSearchIfRequested();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Giver søgefeltet fokus, hvis en anden skærm har bedt om det. Venter til
  /// efter skiftet til fanen, så fokus ikke går tabt undervejs.
  void _focusSearchIfRequested() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !ref.read(focusRecipeSearchProvider)) return;
      ref.read(focusRecipeSearchProvider.notifier).state = false;
      _searchFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final recipes = ref.watch(recipesProvider);
    ref.listen(focusRecipeSearchProvider, (_, requested) {
      if (requested) _focusSearchIfRequested();
    });

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
                              style: context.text.headlineLarge?.copyWith(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: context.colors.primaryContainer,
                              ),
                            ),
                          ],
                        ),
                        const ProfileAvatar(),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SearchBar(
                      controller: _searchController,
                      focusNode: _searchFocus,
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
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyStateWidget(
                        icon: Icons.search_off,
                        title: 'Ingen opskrifter fundet',
                        message: 'Prøv at søge efter noget andet eller nulstil filteret.',
                        actionLabel: 'Nulstil søgning og filter',
                        onAction: () {
                          setState(() {
                            searchQuery = '';
                            selectedCategory = null;
                            _searchController.clear();
                          });
                        },
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
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String> onChanged;

  const _SearchBar({this.controller, this.focusNode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // Ingen filter-knap: den gjorde intet, og kategorierne herunder filtrerer.
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Søg i opskrifter, ingredienser...',
        prefixIcon: Icon(Icons.search, color: context.colors.outline),
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
          color: isSelected ? context.colors.primaryContainer : context.colors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isSelected ? context.colors.primaryContainer : context.colors.outlineVariant,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: context.colors.primary.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))]
              : null,
        ),
        child: Text(
          label,
          style: context.text.bodySmall?.copyWith(
            color: isSelected ? context.colors.onPrimary : context.colors.onSurfaceVariant,
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
            color: context.colors.shadow.withValues(alpha: 0.08),
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
                    context.colors.scrim.withValues(alpha: 0.1),
                    context.colors.scrim.withValues(alpha: 0.8),
                  ],
                ),
              ),
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
                    color: context.colors.primaryContainer.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    recipe.category.name.toUpperCase(),
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.surfaceContainerLowest,
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
                  style: context.text.titleMedium?.copyWith(
                    color: context.colors.surfaceContainerLowest,
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

