import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/settings_list.dart';
import '../auth/auth_provider.dart';
import 'household_dialogs.dart';
import 'household_provider.dart';
import 'invitation_service.dart';
import 'invite_member_card.dart';

/// "Husstand & deling" (design/del_samarbejd_1): inviter, del en kode, se
/// medlemmer og ventende invitationer, skift eller forlad husstand.
class HouseholdScreen extends ConsumerWidget {
  const HouseholdScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider);
    final myUid = ref.watch(authProvider.select((s) => s.user?.uid));
    final colors = Theme.of(context).colorScheme;

    ref.listen(householdProvider.select((s) => s.error), (previous, next) {
      // Kun den øverste skærm viser fejlen (profilen ligger nedenunder).
      if (next != null && next != previous && ModalRoute.of(context)?.isCurrent != false) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next), backgroundColor: colors.error),
        );
      }
    });

    final Widget body;
    if (household.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (household.householdId == null) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Du er ikke i en husstand. Gå tilbage til profilen for at '
            'oprette en eller deltage med en kode.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      body = ListView(
        // 20 px sidemargin (DESIGN.md: container-margin).
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _Header(household: household),
          const SizedBox(height: 24),
          const InviteMemberCard(),
          const SizedBox(height: 16),
          const _JoinCodeCard(),
          const SizedBox(height: 32),
          _Members(household: household, myUid: myUid),
          const SizedBox(height: 32),
          const SectionTitle('Skift husstand'),
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.login_outlined,
                title: 'Deltag i en anden husstand',
                subtitle: 'Med en invitationskode',
                onTap: () => showJoinDialog(context),
              ),
              _LeaveTile(household: household, myUid: myUid),
            ],
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Husstand & deling')),
      body: SafeArea(child: body),
    );
  }
}

class _Header extends StatelessWidget {
  final HouseholdState household;
  const _Header({required this.household});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = household.householdName ?? 'Min husstand';
    final count = household.members.length;

    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: colors.surfaceContainerLow,
          child: Icon(Icons.house_outlined, color: colors.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: text.headlineLarge),
              Text(
                count == 1 ? '1 medlem' : '$count medlemmer',
                style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Omdøb husstand',
          onPressed: () => showRenameHouseholdDialog(context, name),
        ),
      ],
    );
  }
}

/// Lysegrønt kort (mockuppets "Delingslink") med invitationskoden.
class _JoinCodeCard extends StatelessWidget {
  const _JoinCodeCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primaryFixed.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.primaryFixed),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Invitationskode', style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Lav en kode, der kan deles direkte. Den virker i ${joinCodeValidity.inDays} dage.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              backgroundColor: colors.surfaceContainerLowest,
              foregroundColor: colors.primary,
              side: BorderSide(color: colors.outlineVariant),
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const JoinCodeDialog(),
            ),
            icon: const Icon(Icons.vpn_key_outlined),
            label: const Text('Del invitationskode'),
          ),
        ],
      ),
    );
  }
}

/// "Medlemmer (N)": ét kort pr. medlem, efterfulgt af ventende invitationer.
class _Members extends ConsumerWidget {
  final HouseholdState household;
  final String? myUid;
  const _Members({required this.household, required this.myUid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final pending = ref.watch(sentInvitationsProvider).valueOrNull ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Medlemmer (${household.members.length})', style: text.headlineSmall),
        const SizedBox(height: 12),
        for (final uid in household.members)
          _MemberCard(
            uid: uid,
            name: household.memberNames[uid] ?? 'Bruger',
            photoUrl: household.memberPhotos[uid],
            isOwner: uid == household.adminUid,
            isMe: uid == myUid,
            canRemove: myUid != null && household.adminUid == myUid && uid != myUid,
          ),
        for (final invite in pending) _PendingInviteCard(invite: invite),
      ],
    );
  }
}

class _MemberCard extends ConsumerWidget {
  final String uid;
  final String name;
  final String? photoUrl;
  final bool isOwner;
  final bool isMe;
  final bool canRemove;

  const _MemberCard({
    required this.uid,
    required this.name,
    required this.photoUrl,
    required this.isOwner,
    required this.isMe,
    required this.canRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final initial = Text(
      name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?',
      style: text.titleMedium?.copyWith(color: colors.onPrimaryFixedVariant),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: colors.primaryFixed,
          child: ClipOval(
            child: photoUrl != null && photoUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: photoUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => initial,
                  )
                : initial,
          ),
        ),
        title: Text(
          isMe ? '$name (dig)' : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.titleMedium,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOwner) const _OwnerBadge() else Text('Kan redigere', style: text.labelSmall),
            if (canRemove)
              IconButton(
                icon: Icon(Icons.person_remove_outlined, color: colors.error),
                tooltip: 'Fjern $name',
                onPressed: () => _remove(context, ref),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Fjern $name?',
      message: '$name mister adgang til indkøbslisten, madplanen og opskrifterne. '
          'Husstandens aktive invitationskoder holder op med at virke, så '
          '$name ikke kan komme ind igen med en gammel kode.',
      confirmLabel: 'Fjern',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final colors = Theme.of(context).colorScheme;
    final error = await ref.read(householdProvider.notifier).removeMember(uid);
    showResultSnackBar(messenger, colors,
        error: error, success: '$name er fjernet fra husstanden.');
  }
}

/// Pille-mærket "Ejer" fra mockuppet.
class _OwnerBadge extends StatelessWidget {
  const _OwnerBadge();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colors.primaryFixed.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.primaryFixedDim),
      ),
      child: Text(
        'Ejer',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.primary),
      ),
    );
  }
}

/// En invitation, der venter på svar — vises nedtonet under medlemmerne.
class _PendingInviteCard extends ConsumerWidget {
  final SentInvitation invite;
  const _PendingInviteCard({required this.invite});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: colors.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: colors.surfaceContainerHigh,
          child: Icon(Icons.person_outline, color: colors.outline),
        ),
        title: Text(
          'Afventer svar …',
          style: text.titleMedium?.copyWith(
            fontStyle: FontStyle.italic,
            color: colors.onSurfaceVariant,
          ),
        ),
        subtitle: Text(invite.email, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Annullér invitationen til ${invite.email}',
          onPressed: () => _cancel(context, ref),
        ),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final colors = Theme.of(context).colorScheme;
    final error = await ref.read(invitationServiceProvider).cancel(invite.id);
    showResultSnackBar(messenger, colors,
        error: error, success: 'Invitationen til ${invite.email} er annulleret.');
  }
}

class _LeaveTile extends ConsumerWidget {
  final HouseholdState household;
  final String? myUid;
  const _LeaveTile({required this.household, required this.myUid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final others = household.members.where((m) => m != myUid).toList();
    final canLeave = myUid != null && others.isNotEmpty;

    return SettingsTile(
      icon: Icons.logout,
      title: 'Forlad husstand',
      subtitle: canLeave ? null : 'Ikke muligt, når du er eneste medlem',
      destructive: true,
      onTap: canLeave ? () => _leave(context, ref, others) : null,
    );
  }

  Future<void> _leave(BuildContext context, WidgetRef ref, List<String> others) async {
    final name = household.householdName ?? 'husstanden';
    final isOwner = household.adminUid == myUid;
    final successorName = household.memberNames[others.first] ?? 'et andet medlem';

    final confirmed = await showConfirmDialog(
      context,
      title: 'Forlad "$name"?',
      message: 'Du mister adgang til husstandens indkøbsliste, madplan og '
          'opskrifter. Du får din egen, tomme husstand i stedet.'
          '${isOwner ? '\n\n$successorName bliver ny ejer.' : ''}',
      confirmLabel: 'Forlad husstand',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final colors = Theme.of(context).colorScheme;
    final router = GoRouter.maybeOf(context);
    final error = await ref.read(householdProvider.notifier).leaveHousehold();
    showResultSnackBar(messenger, colors, error: error, success: 'Du har forladt "$name".');
    if (error == null && router != null && router.canPop()) router.pop();
  }
}
