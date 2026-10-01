import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/widgets/confirm_dialog.dart';
import 'household_dialogs.dart';
import 'household_provider.dart';

// Husstanden, som den vises på profilen. Alt det praktiske ligger på
// "Husstand & deling", som kortet åbner.

/// Kort oversigt over husstanden.
class HouseholdSummaryCard extends StatelessWidget {
  final HouseholdState household;
  final String? myUid;
  const HouseholdSummaryCard({super.key, required this.household, required this.myUid});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final count = household.members.length;
    final isOwner = myUid != null && household.adminUid == myUid;
    final shown = household.members.take(4).toList();

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/profile/household'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: colors.surfaceContainerLow,
                child: Icon(Icons.house_outlined, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      household.householdName ?? 'Min husstand',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        count == 1 ? '1 medlem' : '$count medlemmer',
                        if (isOwner) 'Du er ejer',
                      ].join(' · '),
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final uid in shown)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: _MiniAvatar(
                              name: household.memberNames[uid] ?? '',
                              photoUrl: household.memberPhotos[uid],
                            ),
                          ),
                        if (count > shown.length)
                          Text('+${count - shown.length}', style: text.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  const _MiniAvatar({required this.name, required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final initial = Text(
      name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.onPrimaryFixedVariant,
          ),
    );
    return Tooltip(
      message: name,
      child: CircleAvatar(
        radius: 13,
        backgroundColor: colors.primaryFixed,
        child: ClipOval(
          child: photoUrl != null && photoUrl!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: photoUrl!,
                  width: 26,
                  height: 26,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => initial,
                )
              : initial,
        ),
      ),
    );
  }
}

/// En modtaget invitation med Afvis/Accepter. Orange (secondary) — DESIGN.md
/// reserverer den til det, der skal fange opmærksomheden.
class ReceivedInvitationCard extends ConsumerWidget {
  final Map<String, dynamic> invite;
  const ReceivedInvitationCard({super.key, required this.invite});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final toName = invite['fromHouseholdName'] as String? ?? 'et Skafferi';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.secondaryFixed.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.secondaryFixedDim),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Invitation modtaget!',
            style: text.titleMedium?.copyWith(color: colors.onSecondaryFixed),
          ),
          const SizedBox(height: 4),
          Text(
            '${invite['fromUserName'] ?? 'Nogen'} har inviteret dig til "$toName".',
            style: text.bodyMedium?.copyWith(color: colors.onSecondaryFixedVariant),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      ref.read(householdProvider.notifier).declineInvitation(invite['id']),
                  child: const Text('Afvis'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => _accept(context, ref, toName),
                  child: const Text('Accepter'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Er brugeren allerede i en husstand, forlades den — det skal de vide først.
  Future<void> _accept(BuildContext context, WidgetRef ref, String toName) async {
    final warning = leaveHouseholdWarning(ref.read(householdProvider));
    if (warning != null) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Deltag i "$toName"?',
        message: warning,
        confirmLabel: 'Deltag',
      );
      if (!confirmed) return;
    }
    await ref.read(householdProvider.notifier).acceptInvitation(invite['id']);
  }
}

/// Vises, hvis brugeren ikke er i en husstand.
class NoHouseholdCard extends StatelessWidget {
  const NoHouseholdCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.house_siding_rounded, size: 48, color: colors.outlineVariant),
            const SizedBox(height: 16),
            Text('Du er ikke i en husstand endnu', style: text.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Bliv inviteret via e-mail, indtast en kode eller opret din egen herunder.',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => showJoinDialog(context),
                    child: const Text('Indtast kode'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const _CreateHouseholdDialog(),
                    ),
                    child: const Text('Opret ny'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateHouseholdDialog extends ConsumerStatefulWidget {
  const _CreateHouseholdDialog();

  @override
  ConsumerState<_CreateHouseholdDialog> createState() => _CreateHouseholdDialogState();
}

class _CreateHouseholdDialogState extends ConsumerState<_CreateHouseholdDialog> {
  final _controller = TextEditingController(text: 'Mit Skafferi');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _create() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    ref.read(householdProvider.notifier).createHousehold(name);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Navngiv dit Skafferi'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(hintText: 'Navn på husstand'),
        autofocus: true,
        maxLength: maxHouseholdNameLength,
        onSubmitted: (_) => _create(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuller')),
        FilledButton(onPressed: _create, child: const Text('Opret')),
      ],
    );
  }
}
