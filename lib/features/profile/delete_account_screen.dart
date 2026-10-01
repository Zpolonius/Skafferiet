import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_deletion_service.dart';
import 'household_provider.dart';

/// Lader brugeren slette sin konto (Apple kræver det). Forklarer først præcis
/// hvad der sker, og kræver adgangskoden, så ingen kan slette kontoen ved et
/// uheld eller fra en ulåst telefon.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _deleting = false;
  String? _error;

  /// Husstanden som den så ud, da sletningen startede. Under sletningen
  /// nulstilles husstanden, og teksten må ikke skifte imens.
  HouseholdState? _frozenHousehold;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _deleting = true;
      _error = null;
    });

    // Hentes før sletningen: når kontoen er væk, sender routeren brugeren
    // til login, og denne skærm forsvinder.
    final messenger = ScaffoldMessenger.of(context);
    final household = ref.read(householdProvider.notifier);
    _frozenHousehold = ref.read(householdProvider);
    household.pauseForAccountDeletion();
    try {
      await ref
          .read(accountDeletionServiceProvider)
          .deleteAccount(password: _passwordController.text);
      messenger.showSnackBar(const SnackBar(
        content: Text('Din konto og dine data er slettet.'),
        behavior: SnackBarBehavior.floating,
      ));
    } on AccountDeletionException catch (e) {
      household.resumeAfterFailedAccountDeletion();
      _showError(e.message);
    } catch (_) {
      household.resumeAfterFailedAccountDeletion();
      _showError('Kontoen kunne ikke slettes. Prøv igen.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _deleting = false;
      _error = message;
      _frozenHousehold = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final watched = ref.watch(householdProvider);
    final household = _frozenHousehold ?? watched;
    final isOnlyMember = household.members.length <= 1;
    final householdName = household.householdName ?? 'din husstand';

    return Scaffold(
      appBar: AppBar(title: const Text('Slet konto')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.warning_amber_rounded, size: 48, color: colors.error),
                const SizedBox(height: 12),
                Text(
                  'Er du sikker?',
                  textAlign: TextAlign.center,
                  style: text.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Det kan ikke fortrydes.',
                  textAlign: TextAlign.center,
                  style: text.bodyLarge?.copyWith(color: colors.error),
                ),
                const SizedBox(height: 24),
                Text('Det her bliver slettet:', style: text.titleMedium),
                const SizedBox(height: 8),
                const _Bullet('Din profil: navn, e-mail og profilbillede'),
                const _Bullet('Invitationer til og fra dig'),
                if (household.householdId == null)
                  const SizedBox.shrink()
                else if (isOnlyMember)
                  _Bullet('Hele "$householdName" med opskrifter, '
                      'indkøbsliste og madplaner — du er det eneste medlem')
                else ...[
                  _Bullet('Du meldes ud af "$householdName"'),
                  const _Bullet('Opskrifter du har lavet bliver i husstanden, '
                      'så de andre ikke mister dem'),
                ],
                const SizedBox(height: 24),
                Text('Bekræft med din adgangskode', style: text.titleMedium),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  enabled: !_deleting,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Adgangskode',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword ? 'Vis adgangskode' : 'Skjul adgangskode',
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Indtast din adgangskode' : null,
                  onFieldSubmitted: (_) => _deleting ? null : _delete(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    key: const Key('delete_account_error'),
                    style: text.bodyMedium?.copyWith(color: colors.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _deleting ? null : _delete,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                    minimumSize: const Size(double.infinity, 56),
                  ),
                  child: _deleting
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: colors.onError),
                        )
                      : const Text('Slet min konto permanent'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _deleting ? null : () => Navigator.of(context).maybePop(),
                  child: const Text('Fortryd'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: style),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}
