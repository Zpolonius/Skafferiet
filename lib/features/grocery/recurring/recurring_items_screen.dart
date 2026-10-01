import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/recurring_item.dart';
import '../../../core/services/recurring_schedule.dart';
import '../../../shared/utils/danish_dates.dart';
import '../../../shared/widgets/app_bottom_sheet.dart';
import '../../../shared/widgets/empty_state_widget.dart';
import '../../profile/household_provider.dart';
import 'recurring_item_sheet.dart';
import 'recurring_items_provider.dart';

/// Oversigt over husstandens faste varer og indkøbsdag.
class RecurringItemsScreen extends ConsumerWidget {
  const RecurringItemsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(recurringItemsProvider);
    final shoppingWeekday =
        ref.watch(householdProvider.select((h) => h.shoppingWeekday));
    final today = dateOnly(ref.watch(clockProvider)());

    return Scaffold(
      appBar: AppBar(title: const Text('Faste varer')),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Kunne ikke hente faste varer. Tjek din forbindelse.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          children: [
            _ShoppingDayCard(
              weekday: shoppingWeekday,
              onTap: () =>
                  _showShoppingDayPicker(context, ref, shoppingWeekday),
            ),
            const SizedBox(height: 24),
            if (list.isEmpty)
              const EmptyStateWidget(
                icon: Icons.event_repeat,
                title: 'Ingen faste varer endnu',
                message:
                    'Varer du køber hver uge eller hver måned kan komme på '
                    'indkøbslisten helt af sig selv.',
              )
            else
              for (final item in list)
                _RecurringItemCard(item: item, today: today),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => RecurringItemSheet.show(context),
        icon: const Icon(Icons.add),
        label: const Text('Ny fast vare'),
      ),
    );
  }

  Future<void> _showShoppingDayPicker(
    BuildContext context,
    WidgetRef ref,
    int? current,
  ) async {
    final chosen = await showAppBottomSheet<int>(
      context: context,
      builder: (_) => _ShoppingDaySheet(current: current),
    );
    if (chosen == null || chosen == current) return;

    final householdId = ref.read(householdProvider).householdId;
    if (householdId == null) return;
    try {
      await ref.read(recurringItemsServiceProvider).changeShoppingWeekday(
            householdId,
            chosen,
            ref.read(recurringItemsProvider).valueOrNull ?? const [],
          );
    } catch (e) {
      developer.log('Kunne ikke skifte indkøbsdag',
          error: e, name: 'recurring_items');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Kunne ikke gemme indkøbsdagen. Prøv igen.'),
        ));
      }
    }
  }
}

class _ShoppingDayCard extends StatelessWidget {
  final int? weekday;
  final VoidCallback onTap;

  const _ShoppingDayCard({required this.weekday, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final day = weekday;
    final dayBefore = day == null ? null : (day + 5) % 7 + 1;

    return Material(
      color: colorScheme.primaryContainer.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.storefront_outlined, color: colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Indkøbsdag', style: textTheme.labelSmall),
                    const SizedBox(height: 2),
                    Text(
                      day == null ? 'Ikke valgt' : weekdayName(day),
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      day == null
                          ? 'Vælg dagen I handler ind – ugentlige varer følger den.'
                          : 'Ugentlige varer kommer på listen '
                              '${danishWeekdays[dayBefore! - 1]} – dagen før.',
                      style: textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Text(
                day == null ? 'Vælg' : 'Skift',
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShoppingDaySheet extends StatelessWidget {
  final int? current;

  const _ShoppingDaySheet({required this.current});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.only(
        top: 24,
        bottom: sheetBottomInset(context) + 16,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text('Hvilken dag handler I ind?',
                style: Theme.of(context).textTheme.displayMedium),
          ),
          const SizedBox(height: 8),
          for (var day = DateTime.monday; day <= DateTime.sunday; day++)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: Text(weekdayName(day)),
              trailing: day == current
                  ? Icon(Icons.check, color: colorScheme.primary)
                  : null,
              selected: day == current,
              onTap: () => Navigator.pop(context, day),
            ),
        ],
      ),
    );
  }
}

class _RecurringItemCard extends StatelessWidget {
  final RecurringItem item;
  final DateTime today;

  const _RecurringItemCard({required this.item, required this.today});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final amount = [item.quantity, if (item.unit != null) item.unit].join(' ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => RecurringItemSheet.show(context, existing: item),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    image: item.imageUrl != null
                        ? DecorationImage(
                            image: NetworkImage(item.imageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: item.imageUrl == null
                      ? Icon(Icons.event_repeat, color: colorScheme.primary)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '$amount · ${item.recurrence.label}',
                        style: textTheme.bodySmall
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      Text(
                        'På listen ${formatShortDate(addToListDate(item.nextDate), today: today)}',
                        style: textTheme.labelSmall
                            ?.copyWith(color: colorScheme.primary),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colorScheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
