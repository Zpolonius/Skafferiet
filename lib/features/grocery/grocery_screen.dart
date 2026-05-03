import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/models/grocery_item.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/add_grocery_item_sheet.dart';
import '../../shared/widgets/profile_avatar.dart';
import '../../shared/widgets/empty_state_widget.dart';
import 'grocery_provider.dart';

class GroceryScreen extends ConsumerWidget {
  const GroceryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(groceryListProvider);

    return Scaffold(
      body: SafeArea(
        child: items.when(
          data: (itemsList) {
            final categories = itemsList.isEmpty ? <String, List<GroceryItem>>{} : _groupItemsByCategory(itemsList);
            return CustomScrollView(
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
                                  'Indkøb',
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
                        if (itemsList.isNotEmpty) _SearchBar(),
                      ],
                    ),
                  ),
                ),
                if (itemsList.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _GhostGroceryItem(name: 'Mælk', onTap: () => _showAddItemSheet(context)),
                          _GhostGroceryItem(name: 'Brød', onTap: () => _showAddItemSheet(context)),
                          _GhostGroceryItem(name: 'Grøntsager', onTap: () => _showAddItemSheet(context)),
                          const SizedBox(height: 24),
                          Text(
                            'Tryk for at tilføj din første vare',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.6),
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                for (final category in categories.keys) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Text(
                        category,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = categories[category]![index];
                          return _GroceryItemTile(item: item);
                        },
                        childCount: categories[category]!.length,
                      ),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Fejl: $err')),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddItemSheet(context),
        label: const Text('Tilføj vare'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Map<String, List<GroceryItem>> _groupItemsByCategory(List<GroceryItem> items) {
    final Map<String, List<GroceryItem>> categories = {};
    for (final item in items) {
      if (!categories.containsKey(item.category)) {
        categories[item.category] = [];
      }
      categories[item.category]!.add(item);
    }
    return categories;
  }

  void _showAddItemSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddGroceryItemSheet(),
    );
  }
}

class _SearchBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: InputDecoration(
        hintText: 'Søg i din indkøbsliste...',
        prefixIcon: const Icon(Icons.search, color: AppColors.outline),
        filled: true,
        fillColor: AppColors.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _GroceryItemTile extends ConsumerWidget {
  final GroceryItem item;

  const _GroceryItemTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Slidable(
        key: ValueKey(item.id),
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          extentRatio: 0.25,
          children: [
            SlidableAction(
              onPressed: (_) => ref.read(groceryListProvider.notifier).removeItem(item.id),
              backgroundColor: AppColors.errorContainer,
              foregroundColor: AppColors.error,
              icon: Icons.delete_outline,
              label: 'Slet',
              borderRadius: BorderRadius.circular(16),
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: InkWell(
            onTap: () => ref.read(groceryListProvider.notifier).toggleItem(item.id),
            child: Row(
              children: [
                // Image or Category Icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    image: item.imageUrl != null
                        ? DecorationImage(
                            image: NetworkImage(item.imageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: item.imageUrl == null
                      ? Icon(
                          _getCategoryIcon(item.category),
                          color: AppColors.primary,
                          size: 24,
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              decoration: item.isChecked ? TextDecoration.lineThrough : null,
                              color: item.isChecked ? AppColors.outline : AppColors.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      Text(
                        item.category,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                if (!item.isChecked)
                  _QuantityPicker(
                    quantity: item.quantity,
                    onChanged: (val) => ref.read(groceryListProvider.notifier).updateQuantity(item.id, val),
                  )
                else
                  const Icon(Icons.check_circle, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Frugt & Grønt': return Icons.apple;
      case 'Mejeri': return Icons.egg_alt;
      case 'Kød & Fisk': return Icons.restaurant;
      case 'Frost': return Icons.ac_unit;
      case 'Drikkevarer': return Icons.local_drink;
      default: return Icons.shopping_basket;
    }
  }
}

class _QuantityPicker extends StatelessWidget {
  final String quantity;
  final ValueChanged<String> onChanged;

  const _QuantityPicker({required this.quantity, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryFixed,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        quantity,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _GhostGroceryItem extends StatelessWidget {
  final String name;
  final VoidCallback onTap;

  const _GhostGroceryItem({required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.5),
              style: BorderStyle.solid,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: AppColors.primary.withValues(alpha: 0.3),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.outline.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppColors.outline.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
