import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

// Vælgere til husstandens størrelse og madstil. Bruges både i onboardingen og
// på siden "Præferencer & Diæt", så de to altid ser ens ud.

/// Madstile man kan vælge. Teksten gemmes i Firestore, så en ændring af en
/// label gør, at tidligere valg ikke længere vises som valgt.
const availablePreferences = <({String label, String icon})>[
  (label: 'Børnevenligt', icon: '👶'),
  (label: 'Hurtigt & nemt (<30 min)', icon: '⏱️'),
  (label: 'Grønt & Sundt', icon: '🥗'),
  (label: 'Budgetvenligt', icon: '💰'),
  (label: 'Klassisk hverdagsmad', icon: '🇩🇰'),
  (label: 'Vegetarisk / Plantebaseret', icon: '🌱'),
];

/// Højeste antal voksne eller børn, man kan vælge.
const maxHouseholdCount = 10;

/// Vælg-flere-chips til madstile.
class PreferenceChips extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const PreferenceChips({super.key, required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Wrap(
      spacing: 10,
      runSpacing: 12,
      children: availablePreferences.map((pref) {
        final isSelected = selected.contains(pref.label);
        return Semantics(
          button: true,
          selected: isSelected,
          child: InkWell(
            onTap: () => onToggle(pref.label),
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.primaryContainer.withValues(alpha: 0.12)
                    : colors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? colors.primary : colors.outlineVariant,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: Text(pref.icon, style: const TextStyle(fontSize: 18)),
                  ),
                  const Gap(8),
                  // Flexible: lange navne ombrydes i stedet for at løbe ud af
                  // skærmen ved stor tekst.
                  Flexible(
                    child: Text(
                      pref.label,
                      style: text.titleSmall?.copyWith(
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? colors.primary : colors.onSurface,
                      ),
                    ),
                  ),
                  if (isSelected) ...[
                    const Gap(8),
                    Icon(Icons.check_circle_rounded, size: 16, color: colors.primary),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Et tal med minus- og plusknap, fx antal voksne.
class CounterCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final int count;
  final bool canDecrement;
  final ValueChanged<int> onChanged;

  const CounterCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.count,
    this.canDecrement = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleMedium),
                Text(subtitle, style: text.labelSmall?.copyWith(color: colors.outline)),
              ],
            ),
          ),
          _CircleBtn(
            icon: Icons.remove,
            semanticLabel: '$title: færre',
            onTap: (count > 0 && canDecrement) ? () => onChanged(count - 1) : null,
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$count',
              textAlign: TextAlign.center,
              style: text.titleLarge,
            ),
          ),
          _CircleBtn(
            icon: Icons.add,
            semanticLabel: '$title: flere',
            onTap: count < maxHouseholdCount ? () => onChanged(count + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;

  const _CircleBtn({required this.icon, required this.semanticLabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isEnabled = onTap != null;
    return Semantics(
      button: true,
      enabled: isEnabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isEnabled
                ? colors.primaryContainer.withValues(alpha: 0.1)
                : colors.surfaceContainerHigh,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 20,
            color: isEnabled ? colors.primary : colors.outline,
          ),
        ),
      ),
    );
  }
}
