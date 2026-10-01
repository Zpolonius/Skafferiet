import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'board_note_card.dart';
import 'board_provider.dart';

/// Lille kort på Hjem, der viser seneste seddel og åbner tavlen.
class BoardPreviewCard extends ConsumerWidget {
  const BoardPreviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final notes = ref.watch(boardProvider);

    final subtitle = notes.when(
      data: (list) => list.isEmpty
          ? 'Ingen sedler endnu – sæt den første op'
          : '${list.length} ${list.length == 1 ? 'seddel' : 'sedler'} · ${boardNoteSummary(list.first)}',
      loading: () => 'Henter sedler…',
      error: (_, __) => 'Kunne ikke hente tavlen',
    );

    return Semantics(
      button: true,
      label: 'Opslagstavlen. $subtitle',
      excludeSemantics: true,
      child: Material(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/board'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.push_pin_outlined, color: cs.secondary),
                ),
                const Gap(16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Opslagstavlen',
                        style: textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                      ),
                      const Gap(2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          height: 1.3,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
