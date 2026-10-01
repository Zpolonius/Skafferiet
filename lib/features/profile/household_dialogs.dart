import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'household_provider.dart';

// Dialoger til husstanden, som bruges både på profilen og på siden
// "Husstand & deling". Hver dialog ejer sine tekstfelter og rydder dem op.

/// Under reglernes grænse på 100 tegn, så der er plads til visning.
const maxHouseholdNameLength = 60;

/// Advarsel når brugeren er på vej til at forlade sin husstand (ved at
/// deltage i en anden). Null, hvis brugeren ikke er i en husstand.
String? leaveHouseholdWarning(HouseholdState household) {
  final name = household.householdName;
  if (household.householdId == null || name == null) return null;
  if (household.members.length <= 1) {
    return 'Du forlader "$name". Du er eneste medlem, så indkøbslisten, '
        'madplanen og opskrifterne i "$name" kan ikke hentes igen.';
  }
  return 'Du forlader "$name". De andre medlemmer beholder indkøbslisten, '
      'madplanen og opskrifterne.';
}

/// Dialog hvor brugeren indtaster en invitationskode. Er brugeren allerede i
/// en husstand, står det tydeligt, hvad der sker med den.
Future<void> showJoinDialog(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const _JoinDialog());
}

class _JoinDialog extends ConsumerStatefulWidget {
  const _JoinDialog();

  @override
  ConsumerState<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends ConsumerState<_JoinDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _join() {
    final code = _controller.text.trim();
    if (code.isEmpty) return;
    // Fejl (fx en udløbet kode) vises af skærmen, der lytter på husstanden.
    ref.read(householdProvider.notifier).joinHousehold(code);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final warning = leaveHouseholdWarning(ref.watch(householdProvider));
    return AlertDialog(
      title: const Text('Deltag med kode'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'F.eks. ABCDE-FGHJK',
              prefixIcon: Icon(Icons.vpn_key_outlined),
            ),
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            onSubmitted: (_) => _join(),
          ),
          if (warning != null) ...[
            const SizedBox(height: 12),
            Text(
              warning,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuller')),
        FilledButton(onPressed: _join, child: const Text('Deltag')),
      ],
    );
  }
}

/// Omdøb husstanden.
Future<void> showRenameHouseholdDialog(BuildContext context, String currentName) {
  return showDialog<void>(
    context: context,
    builder: (_) => _RenameHouseholdDialog(currentName: currentName),
  );
}

class _RenameHouseholdDialog extends ConsumerStatefulWidget {
  final String currentName;
  const _RenameHouseholdDialog({required this.currentName});

  @override
  ConsumerState<_RenameHouseholdDialog> createState() => _RenameHouseholdDialogState();
}

class _RenameHouseholdDialogState extends ConsumerState<_RenameHouseholdDialog> {
  late final _controller = TextEditingController(text: widget.currentName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    ref.read(householdProvider.notifier).renameHousehold(name);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Omdøb husstand'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(hintText: 'Navn på husstand'),
        autofocus: true,
        maxLength: maxHouseholdNameLength,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuller')),
        FilledButton(onPressed: _save, child: const Text('Gem')),
      ],
    );
  }
}

/// Laver en ny invitationskode og viser den, så den kan kopieres og deles.
class JoinCodeDialog extends ConsumerStatefulWidget {
  const JoinCodeDialog({super.key});

  @override
  ConsumerState<JoinCodeDialog> createState() => _JoinCodeDialogState();
}

class _JoinCodeDialogState extends ConsumerState<JoinCodeDialog> {
  late final Future<String?> _code;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _code = ref.read(householdProvider.notifier).createJoinCode();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return AlertDialog(
      title: const Text('Invitationskode'),
      content: FutureBuilder<String?>(
        future: _code,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final code = snapshot.data;
          if (code == null) {
            return const Text('Koden kunne ikke laves. Tjek din forbindelse og prøv igen.');
          }
          final formatted = formatJoinCode(code);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Del koden med dem, der skal være med. De vælger '
                '"Deltag i en anden husstand" under Husstand & deling.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  formatted,
                  key: const Key('join_code_text'),
                  textAlign: TextAlign.center,
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: colors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Koden virker i ${joinCodeValidity.inDays} dage.',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              // Bekræftelsen vises på knappen: en SnackBar ville ligge
              // bag dialogens mørke baggrund.
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: formatted));
                  if (mounted) setState(() => _copied = true);
                },
                icon: Icon(_copied ? Icons.check : Icons.copy_outlined),
                label: Text(_copied ? 'Kopieret' : 'Kopiér kode'),
              ),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Luk'),
        ),
      ],
    );
  }
}
