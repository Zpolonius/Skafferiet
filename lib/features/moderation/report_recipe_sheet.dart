import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/recipe_report.dart';
import '../../core/theme/theme_context.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import 'moderation_provider.dart';

/// Åbner formularen "Rapportér opskrift". Returnerer `true`, når rapporten er
/// gemt.
Future<bool?> showReportRecipeSheet(BuildContext context,
    {required String recipeId}) {
  return showAppBottomSheet<bool>(
    context: context,
    builder: (_) => ReportRecipeSheet(recipeId: recipeId),
  );
}

/// Vælg en årsag og skriv eventuelt en kommentar. En ny rapport fra samme
/// bruger overskriver den forrige (samme dokument).
class ReportRecipeSheet extends ConsumerStatefulWidget {
  final String recipeId;
  const ReportRecipeSheet({super.key, required this.recipeId});

  @override
  ConsumerState<ReportRecipeSheet> createState() => _ReportRecipeSheetState();
}

class _ReportRecipeSheetState extends ConsumerState<ReportRecipeSheet> {
  final _comment = TextEditingController();
  ReportReason? _reason;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(moderationServiceProvider).reportRecipe(
            recipeId: widget.recipeId,
            reason: reason,
            comment: _comment.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on ArgumentError {
      // Feltet tæller tegn, databasen UTF-16-enheder: emoji fylder dobbelt.
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Kommentaren er for lang. Gør den lidt kortere, især hvis '
            'den har mange emoji.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error =
            'Rapporten kunne ikke sendes. Tjek din forbindelse og prøv igen.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      padding: EdgeInsets.only(
        bottom: sheetBottomInset(context) + 24,
        top: 16,
        left: 24,
        right: 24,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text('Rapportér opskrift', style: text.headlineLarge)),
              IconButton(
                tooltip: 'Luk',
                onPressed: _sending ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          // Formularen ruller; "Send rapport" bliver stående i bunden.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Hvorfor skal vi kigge på opskriften?',
                    style: text.bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    container: true,
                    label: 'Årsag',
                    child: RadioGroup<ReportReason>(
                      groupValue: _reason,
                      onChanged: (v) {
                        if (!_sending) setState(() => _reason = v);
                      },
                      child: Column(
                        children: [
                          for (final r in ReportReason.values)
                            RadioListTile<ReportReason>(
                              key: Key('report-reason-${r.key}'),
                              value: r,
                              title: Text(r.label),
                              contentPadding: EdgeInsets.zero,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('report-comment'),
                    controller: _comment,
                    enabled: !_sending,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: maxReportCommentLength,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Kommentar (valgfri)',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: text.bodyMedium?.copyWith(color: colors.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('send-report'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _reason == null || _sending ? null : _send,
            child: _sending
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: colors.onPrimary),
                  )
                : const Text('Send rapport'),
          ),
        ],
      ),
    );
  }
}
