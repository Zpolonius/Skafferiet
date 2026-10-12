import 'package:flutter/material.dart';
import '../../core/models/item_history.dart';
import '../../core/theme/theme_context.dart';

/// Forslag fra husstandens varehistorik under et navnefelt (i "Tilføj vare"
/// og i hurtig-tilføj-feltet). Hver række er mindst
/// 48 dp høj og har en separat "Fjern forslag"-knap, så en stavefejl kan
/// fjernes for altid.
class ItemSuggestionList extends StatelessWidget {
  final List<ItemHistoryEntry> suggestions;
  final ValueChanged<ItemHistoryEntry> onPick;
  final ValueChanged<ItemHistoryEntry> onRemove;

  const ItemSuggestionList({
    super.key,
    required this.suggestions,
    required this.onPick,
    required this.onRemove,
  });

  String _details(ItemHistoryEntry e) {
    final amount = [e.quantity, e.unit].whereType<String>().join(' ');
    return [e.category, if (amount.isNotEmpty) amount].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Column(
        children: [
          for (final e in suggestions)
            Row(
              key: ValueKey('suggestion_${e.key}'),
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Brug tidligere vare: ${e.name}, ${_details(e)}',
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: () => onPick(e),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.name, style: context.text.bodyLarge),
                                Text(
                                  _details(e),
                                  style: context.text.bodySmall?.copyWith(
                                      color: context.colors.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => onRemove(e),
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Fjern forslag',
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
