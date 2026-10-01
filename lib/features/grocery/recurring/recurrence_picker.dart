import 'package:flutter/material.dart';
import '../../../core/models/recurrence.dart';
import '../../../core/services/recurring_schedule.dart';
import '../../../shared/utils/danish_dates.dart';

/// Valg af interval for en fast vare: hver 1.–4. uge eller hver måned på en
/// fast dato. Bruges både når en vare oprettes og når den redigeres.
class RecurrencePicker extends StatelessWidget {
  final Recurrence recurrence;
  final ValueChanged<Recurrence> onChanged;

  /// Husstandens indkøbsdag. Er den ikke valgt, vises ugedage, så den kan
  /// vælges her – ugentlige varer kræver den.
  final int? householdWeekday;
  final int? chosenWeekday;
  final ValueChanged<int> onWeekdayChanged;

  final DateTime today;

  /// Den allerede planlagte indkøbsdato, når en eksisterende vare redigeres
  /// uden at intervallet ændres.
  final Recurrence? savedRecurrence;
  final DateTime? savedNextDate;

  final bool enabled;

  const RecurrencePicker({
    super.key,
    required this.recurrence,
    required this.onChanged,
    required this.householdWeekday,
    required this.chosenWeekday,
    required this.onWeekdayChanged,
    required this.today,
    this.savedRecurrence,
    this.savedNextDate,
    this.enabled = true,
  });

  static const _options = <Recurrence>[
    WeeklyRecurrence(1),
    WeeklyRecurrence(2),
    WeeklyRecurrence(3),
    WeeklyRecurrence(4),
  ];

  int? get _effectiveWeekday => householdWeekday ?? chosenWeekday;

  DateTime? _nextShoppingDate() {
    if (savedNextDate != null && recurrence == savedRecurrence) {
      return savedNextDate;
    }
    final weekday = _effectiveWeekday;
    if (recurrence is WeeklyRecurrence && weekday == null) return null;
    return recurrence.firstDate(today, shoppingWeekday: weekday);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final current = recurrence;
    final monthlyDay = current is MonthlyRecurrence ? current.dayOfMonth : 1;
    final next = _nextShoppingDate();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hvor ofte?', style: textTheme.labelSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in _options)
              ChoiceChip(
                label: Text(option.label),
                selected: current == option,
                onSelected: enabled ? (_) => onChanged(option) : null,
              ),
            ChoiceChip(
              label: const Text('Hver måned'),
              selected: current is MonthlyRecurrence,
              onSelected: enabled
                  ? (_) => onChanged(MonthlyRecurrence(monthlyDay))
                  : null,
            ),
          ],
        ),
        if (current is MonthlyRecurrence) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            key: const Key('recurrence_day_of_month'),
            initialValue: current.dayOfMonth,
            decoration: const InputDecoration(labelText: 'Dato i måneden'),
            items: [
              for (var day = 1; day <= 31; day++)
                DropdownMenuItem(value: day, child: Text('Den $day.')),
            ],
            onChanged:
                enabled ? (day) => onChanged(MonthlyRecurrence(day!)) : null,
          ),
          if (current.dayOfMonth > 28) ...[
            const SizedBox(height: 4),
            Text(
              'I kortere måneder bruges månedens sidste dag.',
              style: textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ],
        if (current is WeeklyRecurrence && householdWeekday == null) ...[
          const SizedBox(height: 16),
          Text('Hvilken dag handler I ind?', style: textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            'Gælder for hele husstanden og kan ændres under Faste varer.',
            style: textTheme.bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var day = DateTime.monday; day <= DateTime.sunday; day++)
                ChoiceChip(
                  label: Text(weekdayName(day).substring(0, 3)),
                  tooltip: weekdayName(day),
                  selected: chosenWeekday == day,
                  onSelected: enabled ? (_) => onWeekdayChanged(day) : null,
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _PreviewBox(
          text: next == null
              ? 'Vælg jeres indkøbsdag for at se, hvornår varen kommer på listen.'
              // Ingen afsluttende punktum: datoen kan selv ende på "okt."
              : 'Kommer på indkøbslisten '
                  '${formatShortDate(addToListDate(next), today: today)} '
                  '(dagen før indkøb ${formatShortDate(next, today: today)})',
        ),
      ],
    );
  }
}

class _PreviewBox extends StatelessWidget {
  final String text;

  const _PreviewBox({required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.event_repeat, size: 20, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
