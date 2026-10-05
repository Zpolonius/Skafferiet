import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/meal_type.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import '../profile/household_provider.dart';

/// Lader brugeren vælge, hvilke måltider der vises i deres madplan — fx
/// uden frokost, hvis de har frokostordning. Valget er personligt.
class MealTypesSheet extends ConsumerStatefulWidget {
  const MealTypesSheet({super.key});

  static Future<void> show(BuildContext context) => showAppBottomSheet<void>(
        context: context,
        builder: (_) => const MealTypesSheet(),
      );

  @override
  ConsumerState<MealTypesSheet> createState() => _MealTypesSheetState();
}

class _MealTypesSheetState extends ConsumerState<MealTypesSheet> {
  // Vises i sheetet selv: en snackbar ville ligge skjult bag det.
  String? _error;

  Future<void> _save(Set<MealType> next) async {
    setState(() => _error = null);
    final error = await ref.read(householdProvider.notifier).setMealTypes(next);
    if (mounted && error != null) setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final selected = ref.watch(householdProvider.select((h) => h.mealTypes));

    return Container(
      padding: EdgeInsets.only(top: 24, bottom: sheetBottomInset(context) + 16),
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
            child: Text('Mine måltider', style: textTheme.displayMedium),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Vælg hvilke måltider du vil se i madplanen. Det gælder kun for '
              'dig – resten af husstanden ser stadig alle måltider.',
              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 8),
          for (final type in MealType.values)
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              secondary: Icon(type.icon, color: colorScheme.primary),
              title: Text(type.label),
              value: selected.contains(type),
              // Det sidste valgte måltid kan ikke slås fra.
              onChanged: selected.contains(type) && selected.length == 1
                  ? null
                  : (on) {
                      final next = {...selected};
                      on ? next.add(type) : next.remove(type);
                      _save(next);
                    },
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text(
                _error!,
                style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
