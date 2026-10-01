import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/grocery_item.dart';
import '../../core/models/recurring_item.dart';
import '../../shared/widgets/add_grocery_item_sheet.dart';
import '../../shared/widgets/empty_state_widget.dart';
import '../../shared/widgets/profile_avatar.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import 'edit_grocery_item_dialog.dart';
import 'grocery_provider.dart';
import 'recurring/recurring_item_sheet.dart';
import 'recurring/recurring_items_provider.dart';
import '../../core/theme/theme_context.dart';

class GroceryScreen extends ConsumerStatefulWidget {
  const GroceryScreen({super.key});

  @override
  ConsumerState<GroceryScreen> createState() => _GroceryScreenState();
}

class _GroceryScreenState extends ConsumerState<GroceryScreen> {
  String? _selectedCategory; // null = Alle
  bool _isReorderMode = false;

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(groceryListProvider);

    return Scaffold(
      body: SafeArea(
        child: items.when(
          data: (itemsList) {
            final uniqueCategories =
                itemsList.map((i) => i.category).toSet().toList()..sort();

            final filtered = _selectedCategory == null
                ? itemsList
                : itemsList
                    .where((i) => i.category == _selectedCategory)
                    .toList();

            final categories = filtered.isEmpty
                ? <String, List<GroceryItem>>{}
                : _groupItemsByCategory(filtered);

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
                                Image.asset('assets/images/logo.png',
                                    height: 32),
                                const SizedBox(width: 12),
                                Text(
                                  'Indkøb',
                                  style: context.text.headlineLarge?.copyWith(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: context.colors.primaryContainer,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                if (itemsList.isNotEmpty)
                                  IconButton(
                                    icon: Icon(
                                      _isReorderMode
                                          ? Icons.check_rounded
                                          : Icons.sort,
                                      color: _isReorderMode
                                          ? context.colors.primary
                                          : context.colors.outline,
                                    ),
                                    tooltip: _isReorderMode
                                        ? 'Gem rækkefølge'
                                        : 'Sorter liste',
                                    onPressed: () => setState(() {
                                      _isReorderMode = !_isReorderMode;
                                      if (_isReorderMode) {
                                        _selectedCategory = null;
                                      }
                                    }),
                                  ),
                                if (itemsList.any((i) => i.isChecked))
                                  IconButton(
                                    icon: Icon(
                                        Icons.delete_sweep_outlined,
                                        color: context.colors.primary),
                                    onPressed: () => ref
                                        .read(groceryListProvider.notifier)
                                        .clearCheckedItems(),
                                    tooltip: 'Fjern markerede',
                                  ),
                                PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert,
                                      color: context.colors.outline),
                                  onSelected: (value) {
                                    if (value == 'clear_all') {
                                      _showClearAllDialog(context, ref);
                                    } else if (value == 'clear_checked') {
                                      ref
                                          .read(groceryListProvider.notifier)
                                          .clearCheckedItems();
                                    } else if (value == 'recurring') {
                                      context.push('/grocery/recurring');
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'recurring',
                                      child: Row(
                                        children: [
                                          Icon(Icons.event_repeat, size: 20),
                                          SizedBox(width: 12),
                                          Text('Faste varer'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'clear_checked',
                                      child: Row(
                                        children: [
                                          Icon(Icons.check_box_outlined,
                                              size: 20),
                                          SizedBox(width: 12),
                                          Text('Fjern markerede'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'clear_all',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_forever_outlined,
                                              size: 20, color: context.colors.error),
                                          const SizedBox(width: 12),
                                          Text('Tøm listen',
                                              style: TextStyle(
                                                  color: context.colors.error)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 8),
                                const ProfileAvatar(),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (itemsList.isNotEmpty && !_isReorderMode) ...[
                          _SearchBar(),
                          const SizedBox(height: 12),
                          _CategoryFilterRow(
                            categories: uniqueCategories,
                            selected: _selectedCategory,
                            onSelected: (cat) =>
                                setState(() => _selectedCategory = cat),
                          ),
                        ],
                        if (_isReorderMode)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                Icon(Icons.drag_indicator,
                                    size: 16, color: context.colors.outline),
                                const SizedBox(width: 6),
                                Text(
                                  'Hold og træk for at ændre rækkefølge',
                                  style: TextStyle(
                                      fontSize: 12, color: context.colors.outline),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (itemsList.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyStateWidget(
                      icon: Icons.shopping_basket_outlined,
                      title: 'Indkøbslisten er tom',
                      message:
                          'Tilføj varer manuelt eller overfør ingredienser direkte fra madplanen.',
                      actionLabel: 'Tilføj første vare',
                      onAction: () => _showAddItemSheet(context),
                    ),
                  )
                else if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyStateWidget(
                      icon: Icons.filter_alt_off,
                      title: 'Ingen varer fundet',
                      message:
                          'Der er ingen varer i kategorien "$_selectedCategory".',
                      actionLabel: 'Vis alle varer',
                      onAction: () => setState(() => _selectedCategory = null),
                    ),
                  )
                else if (_isReorderMode)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    sliver: SliverReorderableList(
                      itemCount: itemsList.length,
                      onReorder: (oldIndex, newIndex) {
                        if (newIndex > oldIndex) newIndex--;
                        final reordered = [...itemsList];
                        final moved = reordered.removeAt(oldIndex);
                        reordered.insert(newIndex, moved);
                        ref
                            .read(groceryListProvider.notifier)
                            .reorderItems(reordered.map((i) => i.id).toList());
                      },
                      itemBuilder: (context, index) {
                        final item = itemsList[index];
                        return ReorderableDelayedDragStartListener(
                          key: ValueKey(item.id),
                          index: index,
                          child: _GroceryItemTile(
                              item: item, showDragHandle: true),
                        );
                      },
                    ),
                  )
                else
                  for (final category in categories.keys) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Text(
                          category,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: context.colors.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
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

  Map<String, List<GroceryItem>> _groupItemsByCategory(
      List<GroceryItem> items) {
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
    showAppBottomSheet(
      context: context,
      builder: (context) => const AddGroceryItemSheet(),
    );
  }

  void _showClearAllDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tøm indkøbslisten?'),
        content: const Text(
            'Er du sikker på, at du vil slette alle varer fra listen? Denne handling kan ikke fortrydes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuller'),
          ),
          TextButton(
            onPressed: () {
              ref.read(groceryListProvider.notifier).clearAllItems();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
            child: const Text('Tøm liste'),
          ),
        ],
      ),
    );
  }
}

class _CategoryFilterRow extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _CategoryFilterRow({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChip(
            label: 'Alle',
            isSelected: selected == null,
            onTap: () => onSelected(null),
          ),
          ...categories.map((cat) => _FilterChip(
                label: cat,
                isSelected: selected == cat,
                onTap: () => onSelected(cat),
              )),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip(
      {required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? context.colors.primary
                : context.colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? context.colors.primary : context.colors.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? context.colors.onPrimary : context.colors.onSurface,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: InputDecoration(
        hintText: 'Søg i din indkøbsliste...',
        prefixIcon: Icon(Icons.search, color: context.colors.outline),
        filled: true,
        fillColor: context.colors.surfaceContainerLowest,
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
  final bool showDragHandle;

  const _GroceryItemTile({required this.item, this.showDragHandle = false});

  Future<void> _showEditDialog(
    BuildContext context,
    RecurringItem? recurringItem,
  ) async {
    final result = await showDialog<Object?>(
      context: context,
      builder: (context) =>
          EditGroceryItemDialog(item: item, recurringItem: recurringItem),
    );
    if (result is! ManageRecurringRequest || !context.mounted) return;
    if (recurringItem != null) {
      await RecurringItemSheet.show(context, existing: recurringItem);
    } else {
      await RecurringItemSheet.show(context, fromGroceryItem: result.item);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Kun aktive faste varer – er den faste vare stoppet, er varen almindelig.
    final recurringId = item.recurringId;
    final recurringItem = recurringId == null
        ? null
        : ref.watch(recurringItemsProvider.select((items) =>
            items.valueOrNull?.where((r) => r.id == recurringId).firstOrNull));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Slidable(
        key: ValueKey(item.id),
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          extentRatio: 0.5,
          children: [
            SlidableAction(
              onPressed: (_) => _showEditDialog(context, recurringItem),
              backgroundColor: context.colors.primaryFixed,
              foregroundColor: context.colors.primary,
              icon: Icons.edit_outlined,
              label: 'Rediger',
              borderRadius: BorderRadius.circular(16),
            ),
            SlidableAction(
              onPressed: (_) =>
                  ref.read(groceryListProvider.notifier).removeItem(item.id),
              backgroundColor: context.colors.errorContainer,
              foregroundColor: context.colors.error,
              icon: Icons.delete_outline,
              label: 'Slet',
              borderRadius: BorderRadius.circular(16),
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.colors.outlineVariant),
          ),
          child: InkWell(
            onTap: () =>
                ref.read(groceryListProvider.notifier).toggleItem(item.id),
            // I sorteringstilstand bruges long-press til at trække varen.
            onLongPress: showDragHandle
                ? null
                : () => _showEditDialog(context, recurringItem),
            child: Row(
              children: [
                // Image or Category Icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: context.colors.surfaceContainerHigh,
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
                          color: context.colors.primary,
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
                              decoration: item.isChecked
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: item.isChecked
                                  ? context.colors.outline
                                  : context.colors.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      Row(
                        children: [
                          if (recurringItem != null) ...[
                            Icon(
                              Icons.event_repeat,
                              size: 14,
                              color: Theme.of(context).colorScheme.primary,
                              semanticLabel: 'Fast vare',
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              recurringItem != null
                                  ? '${item.category} · ${recurringItem.recurrence.label}'
                                  : item.category,
                              style: Theme.of(context).textTheme.labelSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (showDragHandle)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.drag_indicator,
                        color: context.colors.outline, size: 22),
                  )
                else if (!item.isChecked)
                  _QuantityPicker(
                    quantity: item.quantity,
                    onChanged: (val) => ref
                        .read(groceryListProvider.notifier)
                        .updateQuantity(item.id, val),
                  )
                else
                  Icon(Icons.check_circle, color: context.colors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Frugt & Grønt':
        return Icons.apple;
      case 'Mejeri':
        return Icons.egg_alt;
      case 'Kød & Fisk':
        return Icons.restaurant;
      case 'Frost':
        return Icons.ac_unit;
      case 'Drikkevarer':
        return Icons.local_drink;
      default:
        return Icons.shopping_basket;
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
        color: context.colors.primaryFixed,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        quantity,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.colors.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
