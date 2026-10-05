import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/settings_list.dart';
import '../auth/auth_provider.dart';

/// Skift det navn, de andre i husstanden ser.
Future<void> showChangeNameDialog(BuildContext context, String currentName) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ChangeNameDialog(currentName: currentName),
  );
}

class _ChangeNameDialog extends ConsumerStatefulWidget {
  final String currentName;
  const _ChangeNameDialog({required this.currentName});

  @override
  ConsumerState<_ChangeNameDialog> createState() => _ChangeNameDialogState();
}

class _ChangeNameDialogState extends ConsumerState<_ChangeNameDialog> {
  late final _controller = TextEditingController(text: widget.currentName);
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final name = _controller.text.trim();
    if (name == widget.currentName.trim()) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final error = await ref.read(authProvider.notifier).updateDisplayName(name);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    final colors = Theme.of(context).colorScheme;
    Navigator.pop(context);
    showResultSnackBar(messenger, colors, error: null, success: 'Dit navn er opdateret.');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Skift navn'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _controller,
              autofocus: true,
              enabled: !_saving,
              maxLength: maxDisplayNameLength,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(hintText: 'Dit navn'),
              onFieldSubmitted: (_) => _save(),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Indtast dit navn' : null,
            ),
            Text(
              'Navnet kan ses af de andre i din husstand.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Annuller'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Gem'),
        ),
      ],
    );
  }
}
