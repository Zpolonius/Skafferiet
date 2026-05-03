import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:google_fonts/google_fonts.dart';
import 'grocery_provider.dart';
import '../../core/models/grocery_item.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/add_grocery_item_sheet.dart';
import '../../shared/widgets/profile_avatar.dart';

class GroceryScreen extends ConsumerWidget {
  const GroceryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(groceryListProvider);
    final categories = _groupItemsByCategory(items);

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
                        Text(
                          'Indkøbsliste',
                          style: Theme.of(context).textTheme.displayLarge,
                        ),
                        const ProfileAvatar(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${items.where((i) => !i.checked).length} ting tilbage at købe',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    _ProgressBar(
                      total: items.length,
                      completed: items.where((i) => i.checked).length,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            ...categories.entries.map((entry) {
              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CategoryHeader(title: entry.key),
                      const SizedBox(height: 12),
                      ...entry.value.map((item) => _GroceryItemTile(item: item)),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              );
            }),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => const AddGroceryItemSheet(),
          );
        },
        backgroundColor: AppColors.primaryContainer,
        foregroundColor: AppColors.onPrimaryContainer,
        shape: const CircleBorder(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Map<String, List<GroceryItem>> _groupItemsByCategory(List<GroceryItem> items) {
    final Map<String, List<GroceryItem>> grouped = {};
    for (final item in items) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }
    return grouped;
  }
}

class _ProgressBar extends StatelessWidget {
  final int total;
  final int completed;

  const _ProgressBar({required this.total, required this.completed});

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : completed / total;
    return Container(
      height: 8,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  final String title;

  const _CategoryHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          title == 'Grønt' ? Icons.eco : Icons.water_drop,
          size: 20,
          color: AppColors.primaryContainer,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryContainer,
          ),
        ),
      ],
    );
  }
}

class _GroceryItemTile extends ConsumerWidget {
  final GroceryItem item;

  const _GroceryItemTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Slidable(
        key: ValueKey(item.id),
        startActionPane: ActionPane(
          extentRatio: 0.25,
          motion: const ScrollMotion(),
          children: [
            SlidableAction(
              onPressed: (_) => ref.read(groceryListProvider.notifier).toggleChecked(item.id),
              backgroundColor: AppColors.primaryFixed,
              foregroundColor: AppColors.primary,
              icon: Icons.check_circle,
              label: 'Købt',
            ),
          ],
        ),
        endActionPane: ActionPane(
          extentRatio: 0.25,
          motion: const ScrollMotion(),
          children: [
            SlidableAction(
              onPressed: (_) => ref.read(groceryListProvider.notifier).removeItem(item.id),
              backgroundColor: AppColors.errorContainer,
              foregroundColor: AppColors.error,
              icon: Icons.delete,
              label: 'Slet',
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.surfaceVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => ref.read(groceryListProvider.notifier).toggleChecked(item.id),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: item.checked ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: item.checked ? AppColors.primary : AppColors.outlineVariant,
                      width: 2,
                    ),
                  ),
                  child: item.checked
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            decoration: item.checked ? TextDecoration.lineThrough : null,
                            color: item.checked ? AppColors.outline : AppColors.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    if (!item.checked)
                      Text(
                        'Økologisk, moden', // Mock subtext
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
              if (!item.checked)
                _QuantityPicker(
                  quantity: item.quantity,
                  onChanged: (val) => ref.read(groceryListProvider.notifier).updateQuantity(item.id, val),
                )
              else
                Text(
                  '${item.quantity} ${item.unit}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuantityPicker extends StatelessWidget {
  final String quantity;
  final ValueChanged<String> onChanged;

  const _QuantityPicker({required this.quantity, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CircleButton(
            icon: Icons.remove,
            onTap: () {
              final val = int.tryParse(quantity) ?? 1;
              if (val > 1) onChanged((val - 1).toString());
            },
            color: AppColors.surfaceContainerHighest,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 16,
            child: Text(
              quantity,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.onSurface,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          _CircleButton(
            icon: Icons.add,
            onTap: () {
              final val = int.tryParse(quantity) ?? 1;
              onChanged((val + 1).toString());
            },
            color: AppColors.primaryContainer,
            iconColor: AppColors.onPrimary,
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color? iconColor;

  const _CircleButton({
    required this.icon,
    required this.onTap,
    required this.color,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 16,
          color: iconColor ?? AppColors.onSurface,
        ),
      ),
    );
  }
}
