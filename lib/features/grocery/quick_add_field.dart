import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/grocery_item.dart';
import '../../core/models/item_history.dart';
import '../../core/models/quick_add.dart';
import '../../core/models/recurring_item.dart';
import '../../core/theme/theme_context.dart';
import '../../shared/widgets/add_grocery_item_sheet.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import '../../shared/widgets/item_suggestion_list.dart';
import 'grocery_provider.dart';
import 'item_history_provider.dart';

/// Feltet øverst på indkøbslisten: skriv en vare og tryk Enter, så ligger den
/// på listen med det samme – og feltet er klar til den næste. "2 l mælk"
/// læses som mængde + enhed + navn. Kendes varen fra husstandens historik, får
/// den sin kategori, ellers "Andet". "Flere valg" åbner det fulde ark.
class QuickAddField extends ConsumerStatefulWidget {
  const QuickAddField({super.key});

  @override
  ConsumerState<QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends ConsumerState<QuickAddField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<ItemHistoryEntry> get _history =>
      ref.read(itemHistoryProvider).valueOrNull ?? const [];

  void _clearAndKeepFocus() {
    _controller.clear();
    setState(() {});
    _focus.requestFocus();
  }

  /// Lægger varen på listen uden at vente på serverens svar (virker også
  /// offline); en fejl vises bagefter som en SnackBar.
  void _add(QuickAddItem item) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final future = ref.read(groceryListProvider.notifier).addItem(
          GroceryItem(
            id: const Uuid().v4(),
            name: item.name,
            category: item.category,
            quantity: item.quantity,
            unit: item.unit,
            source: GroceryItem.sourceManual,
            createdAt: DateTime.now(),
          ),
        );
    HapticFeedback.selectionClick();
    _clearAndKeepFocus();
    unawaited(future.catchError((Object e) {
      developer.log('Kunne ikke tilføje vare', error: e, name: 'quick_add');
      messenger?.showSnackBar(const SnackBar(
        content: Text('Kunne ikke tilføje varen. Tjek din forbindelse.'),
      ));
    }));
  }

  void _submit() {
    final text = _controller.text;
    if (text.trim().isEmpty) {
      _focus.requestFocus();
      return;
    }
    final item = resolveQuickAdd(text, _history);
    if (item == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content:
            Text('Navnet må højst være ${RecurringItem.maxNameLength} tegn.'),
      ));
      _focus.requestFocus();
      return;
    }
    _add(item);
  }

  Future<void> _openFullSheet() async {
    // Samme regler som Enter: et kendt navn får historikkens stavemåde,
    // kategori, enhed og mængde med ind i arket.
    final item = resolveQuickAdd(_controller.text, _history);
    final parsed = parseQuickAdd(_controller.text);
    final added = await showAppBottomSheet<bool>(
      context: context,
      builder: (_) => AddGroceryItemSheet(
        initialName: item?.name ?? parsed.name,
        initialQuantity: item?.quantity ?? parsed.quantity,
        initialUnit: item?.unit ?? parsed.unit,
        initialCategory: item != null && item.known
            ? item.category
            : quickAddFallbackCategory,
      ),
    );
    if (added == true && mounted) _clearAndKeepFocus();
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(itemHistoryProvider).valueOrNull ??
        const <ItemHistoryEntry>[];
    final parsed = parseQuickAdd(_controller.text);
    final suggestions = suggestItems(history, parsed.name);
    final hasText = _controller.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Tilføj vare',
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.sentences,
            maxLength: RecurringItem.maxNameLength + 20,
            // Bevares fokus: uden denne lukker "Done" feltet og tastaturet.
            onEditingComplete: _submit,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              counterText: '',
              // Som widget uden semantik, så skærmlæseren ikke siger det samme
              // to gange (label "Tilføj vare" + pladsholder).
              hint: ExcludeSemantics(
                child: Text(
                  'Tilføj vare…',
                  style: context.text.bodyLarge
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ),
              prefixIcon: Icon(Icons.add, color: context.colors.outline),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasText)
                    IconButton(
                      onPressed: _submit,
                      icon: Icon(Icons.check_rounded,
                          color: context.colors.primary),
                      tooltip: 'Tilføj',
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                    ),
                  IconButton(
                    onPressed: _openFullSheet,
                    icon: Icon(Icons.tune, color: context.colors.outline),
                    tooltip: 'Flere valg',
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                  ),
                ],
              ),
              filled: true,
              fillColor: context.colors.surfaceContainerLowest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.topCenter,
          child: suggestions.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ItemSuggestionList(
                    suggestions: suggestions,
                    onPick: (e) => _add(quickAddFromHistory(
                      e,
                      quantity: parsed.quantity,
                      unit: parsed.unit,
                    )),
                    onRemove: (e) =>
                        ref.read(itemHistoryProvider.notifier).remove(e.key),
                  ),
                ),
        ),
      ],
    );
  }
}
