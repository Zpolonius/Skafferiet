import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/settings_list.dart';
import 'household_provider.dart';
import 'invitation_service.dart';

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// "Inviter et medlem" som kort øverst på Husstand & deling (design/del_samarbejd_1).
class InviteMemberCard extends ConsumerStatefulWidget {
  const InviteMemberCard({super.key});

  @override
  ConsumerState<InviteMemberCard> createState() => _InviteMemberCardState();
}

class _InviteMemberCardState extends ConsumerState<InviteMemberCard> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || !_formKey.currentState!.validate()) return;
    final household = ref.read(householdProvider);
    final householdId = household.householdId;
    if (householdId == null) return;

    setState(() {
      _sending = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final colors = Theme.of(context).colorScheme;
    final email = _controller.text.trim().toLowerCase();
    final error = await ref.read(invitationServiceProvider).send(
          householdId: householdId,
          householdName: household.householdName,
          email: email,
        );
    if (!mounted) return;
    setState(() {
      _sending = false;
      _error = error;
    });
    if (error != null) return;

    _controller.clear();
    FocusScope.of(context).unfocus();
    showResultSnackBar(
      messenger,
      colors,
      error: null,
      success: '$email er inviteret. De ser invitationen, når de logger ind.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Inviter et medlem', style: text.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Del madplan, opskrifter og indkøbsliste med familie eller venner.',
                style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _controller,
                enabled: !_sending,
                decoration: const InputDecoration(
                  hintText: 'Indtast e-mailadresse',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.send,
                onFieldSubmitted: (_) => _send(),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return 'Indtast en e-mail';
                  if (value.length > 254 || !_emailPattern.hasMatch(value)) {
                    return 'Ugyldig e-mail';
                  }
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const Key('invite_error'),
                  style: text.bodySmall?.copyWith(color: colors.error),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: const Text('Send invitation'),
              ),
              const SizedBox(height: 8),
              Text(
                'Personen ser invitationen, når de logger ind med e-mailen. '
                'Der sendes ikke en mail.',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
