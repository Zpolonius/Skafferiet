import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/meal_type.dart';
import '../../core/models/recipe.dart';
import '../../core/services/week_dates.dart';
import 'app_bottom_sheet.dart';
import '../../features/meal_plan/meal_plan_provider.dart';
import '../../features/profile/household_provider.dart';
import '../../core/theme/theme_context.dart';

class AddToMealPlanSheet extends ConsumerStatefulWidget {
  final Recipe recipe;

  /// Kaldes lige før opskriften sættes i madplanen, og den opskrift der
  /// returneres bruges. Bruges til at gemme en kopi af en delt opskrift først,
  /// så madplanen aldrig peger på en anden husstands opskrift.
  final Future<Recipe> Function(Recipe recipe)? resolveRecipe;

  const AddToMealPlanSheet({super.key, required this.recipe, this.resolveRecipe});

  @override
  ConsumerState<AddToMealPlanSheet> createState() => _AddToMealPlanSheetState();
}

class _AddToMealPlanSheetState extends ConsumerState<AddToMealPlanSheet> {
  String? selectedDay;
  MealType? selectedSlot;
  bool _saving = false;

  /// Mandagen i den uge der gemmes i. Starter på den uge madplanen viser, men
  /// ændres kun her – madplanens egen uge røres ikke. Gemmes som dato (ikke som
  /// offset fra i dag), så ugen ikke hopper, hvis midnat passerer mens arket er åbent.
  late DateTime _weekStart =
      addWeeks(weekStartOf(ref.read(todayProvider)), ref.read(weekOffsetProvider));

  final days = ['Mandag', 'Tirsdag', 'Onsdag', 'Torsdag', 'Fredag', 'Lørdag', 'Søndag'];

  Future<void> _confirm() async {
    if (_saving) return;
    setState(() => _saving = true);
    // Context, navigator og messenger hentes før await'et.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final mealPlan = ref.read(mealPlanProvider.notifier);
    final weekStart = _weekStart;
    final colors = context.colors;
    final day = selectedDay!;
    final slot = selectedSlot!;
    try {
      final recipe = await widget.resolveRecipe?.call(widget.recipe) ?? widget.recipe;
      await mealPlan.updateSlot(day, slot.key, recipe: recipe, weekId: weekIdOf(weekStart));
      if (mounted) navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${widget.recipe.title} tilføjet til ${day.toLowerCase()} '
            'i uge ${isoWeekNumber(weekStart)} (${slot.label})',
          ),
          backgroundColor: colors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Noget gik galt: $e'),
          backgroundColor: colors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = ref.watch(householdProvider.select((h) => h.mealTypes));
    final today = ref.watch(todayProvider);
    final offset = weeksBetween(today, _weekStart);
    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + sheetBottomInset(context)),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tilføj til madplan',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.recipe.title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.colors.primary),
            ),
            const SizedBox(height: 16),
            _WeekPicker(
              weekStart: _weekStart,
              offset: offset,
              today: today,
              onChanged: (weeks) => setState(() => _weekStart = addWeeks(_weekStart, weeks)),
            ),
            const SizedBox(height: 16),
            Text('Vælg dag', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: days.length,
                itemBuilder: (context, index) {
                  final day = days[index];
                  final isSelected = selectedDay == day;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(day),
                      selected: isSelected,
                      onSelected: (val) => setState(() => selectedDay = val ? day : null),
                      selectedColor: context.colors.primaryContainer,
                      labelStyle: context.text.bodySmall?.copyWith(
                        color: isSelected ? context.colors.onPrimary : context.colors.onSurface,
                        fontSize: 13,
                      ),
                    ),
                  );
                },
              ),
            ),
          
            const SizedBox(height: 24),
            Text('Vælg måltid', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: slots.map((slot) {
                final isSelected = selectedSlot == slot;
                return ChoiceChip(
                  label: Text(slot.label),
                  selected: isSelected,
                  onSelected: (val) => setState(() => selectedSlot = val ? slot : null),
                  selectedColor: context.colors.secondaryContainer,
                  labelStyle: context.text.bodySmall?.copyWith(
                    color: isSelected ? context.colors.onSecondaryContainer : context.colors.onSurface,
                    fontSize: 13,
                  ),
                );
              }).toList(),
            ),
          
            const SizedBox(height: 32),
            FilledButton(
              onPressed: (selectedDay != null && selectedSlot != null && !_saving) ? _confirm : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _saving
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, semanticsLabel: 'Gemmer'))
                  : const Text('Bekræft'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Ugen måltidet gemmes i, med pile til at skifte uge. Samme udtryk som
/// madplanens ugevælger, men den ændrer kun arkets egen uge.
class _WeekPicker extends StatelessWidget {
  final DateTime weekStart;
  final int offset;
  final DateTime today;
  final ValueChanged<int> onChanged;

  const _WeekPicker({
    required this.weekStart,
    required this.offset,
    required this.today,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final badge = weekBadgeLabel(offset);
    final colors = context.colors;
    return Row(
      children: [
        _ArrowButton(
          icon: Icons.chevron_left,
          tooltip: 'Forrige uge',
          onTap: () => onChanged(-1),
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            label: weekSemanticsLabel(weekStart, offset: offset, today: today),
            excludeSemantics: true,
            child: Column(
              children: [
                Text(
                  weekHeaderLabel(weekStart, today: today),
                  textAlign: TextAlign.center,
                  style: context.text.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colors.primaryContainer,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: offset == 0
                          ? colors.primaryFixed
                          : colors.secondaryFixed,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badge,
                      style: context.text.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: offset == 0
                            ? colors.onPrimaryFixedVariant
                            : colors.onSecondaryFixedVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        _ArrowButton(
          icon: Icons.chevron_right,
          tooltip: 'Næste uge',
          onTap: () => onChanged(1),
        ),
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ArrowButton(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 22),
      style: IconButton.styleFrom(
        fixedSize: const Size(48, 48),
        minimumSize: const Size(48, 48),
        foregroundColor: context.colors.primary,
        backgroundColor: context.colors.surfaceContainerLowest,
        side: BorderSide(color: context.colors.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
