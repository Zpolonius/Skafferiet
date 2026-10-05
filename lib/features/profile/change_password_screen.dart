import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// Skift adgangskode. Kræver den nuværende adgangskode, så ingen kan skifte
/// den fra en ulåst telefon.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _repeat = TextEditingController();
  bool _saving = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final error = await ref.read(authProvider.notifier).changePassword(
          currentPassword: _current.text,
          newPassword: _new.text,
        );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    // Ryd felterne, så adgangskoderne ikke bliver liggende i hukommelsen,
    // hvis siden ikke kan lukkes.
    _current.clear();
    _new.clear();
    _repeat.clear();
    setState(() => _saving = false);
    messenger.showSnackBar(const SnackBar(
      content: Text('Din adgangskode er skiftet.'),
      behavior: SnackBarBehavior.floating,
    ));
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final visibilityToggle = IconButton(
      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      tooltip: _obscure ? 'Vis adgangskoder' : 'Skjul adgangskoder',
      onPressed: () => setState(() => _obscure = !_obscure),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Skift adgangskode')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              TextFormField(
                controller: _current,
                obscureText: _obscure,
                enabled: !_saving,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Nuværende adgangskode',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: visibilityToggle,
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Indtast din nuværende adgangskode' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _new,
                obscureText: _obscure,
                enabled: !_saving,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Ny adgangskode',
                  prefixIcon: Icon(Icons.lock_reset_outlined),
                ),
                validator: (v) {
                  if (v == null || v.length < minPasswordLength) {
                    return 'Adgangskoden skal være mindst $minPasswordLength tegn';
                  }
                  if (v == _current.text) {
                    return 'Den nye adgangskode skal være en anden end den nuværende';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _repeat,
                obscureText: _obscure,
                enabled: !_saving,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Gentag ny adgangskode',
                  prefixIcon: Icon(Icons.lock_reset_outlined),
                ),
                validator: (v) => v != _new.text ? 'Adgangskoderne er ikke ens' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  key: const Key('change_password_error'),
                  style: text.bodyMedium?.copyWith(color: colors.error),
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Skift adgangskode'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
