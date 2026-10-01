import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../auth/auth_provider.dart';
import 'household_dialogs.dart';
import 'household_provider.dart';

/// "Husstand & deling": medlemmer, invitationer og ind- og udmeldelse.
class HouseholdScreen extends ConsumerWidget {
  const HouseholdScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider);
    final myUid = ref.watch(authProvider.select((s) => s.user?.uid));
    final colors = Theme.of(context).colorScheme;

    ref.listen(householdProvider.select((s) => s.error), (previous, next) {
      if (next != null && next != previous && ModalRoute.of(context)?.isCurrent != false) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next), backgroundColor: colors.error),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Husstand & deling')),
      body: SafeArea(
        child: household.isLoading
            ? const Center(child: CircularProgressIndicator())
            : household.householdId == null
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Du er ikke i en husstand. Gå tilbage til profilen for at '
                        'oprette en eller deltage med en kode.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      _Header(household: household),
                      const SizedBox(height: 24),
                      const _SectionTitle('Medlemmer'),
                      _Card(
                        children: [
                          for (final uid in household.members)
                            _MemberTile(
                              uid: uid,
                              name: household.memberNames[uid] ?? 'Bruger',
                              photoUrl: household.memberPhotos[uid],
                              isOwner: uid == household.adminUid,
                              isMe: uid == myUid,
                              canRemove: myUid != null &&
                                  household.adminUid == myUid &&
                                  uid != myUid,
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const _SectionTitle('Inviter'),
                      _Card(
                        children: [
                          ListTile(
                            leading: Icon(Icons.person_add_outlined,
                                color: colors.primary),
                            title: const Text('Inviter med e-mail'),
                            subtitle: const Text(
                                'Personen ser invitationen, når de logger ind'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _invite(context),
                          ),
                          ListTile(
                            leading: Icon(Icons.vpn_key_outlined,
                                color: colors.primary),
                            title: const Text('Del invitationskode'),
                            subtitle: Text(
                                'Koden virker i ${joinCodeValidity.inDays} dage'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (_) => const JoinCodeDialog(),
                            ),
                          ),
                        ],
                      ),
                      const _SentInvitations(),
                      const SizedBox(height: 24),
                      const _SectionTitle('Skift husstand'),
                      _Card(
                        children: [
                          ListTile(
                            leading: Icon(Icons.login_outlined,
                                color: colors.onSurfaceVariant),
                            title: const Text('Deltag i en anden husstand'),
                            subtitle: const Text('Med en invitationskode'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => showJoinDialog(context),
                          ),
                          _LeaveTile(household: household, myUid: myUid),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }

  Future<void> _invite(BuildContext context) async {
    final email = await showInviteDialog(context);
    if (email == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text('$email er inviteret. De ser invitationen, når de logger ind.'),
      behavior: SnackBarBehavior.floating,
    ));
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
          backgroundColor: colors.primaryContainer.withValues(alpha: 0.15),
          child: Icon(Icons.house_outlined, color: colors.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style:
                      text.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              Text(
                count == 1 ? '1 medlem' : '$count medlemmer',
                style:
                    text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
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

class _MemberTile extends ConsumerWidget {
  final String uid;
  final String name;
  final String? photoUrl;
  final bool isOwner;
  final bool isMe;
  final bool canRemove;

  const _MemberTile({
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
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final initialWidget = Text(
      initial,
      style: text.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: isOwner ? colors.onPrimary : colors.onSurface,
      ),
    );

    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor:
            isOwner ? colors.primary : colors.surfaceContainerHighest,
        child: ClipOval(
          child: photoUrl != null && photoUrl!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: photoUrl!,
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => initialWidget,
                )
              : initialWidget,
        ),
      ),
      title: Text(
        isMe ? '$name (dig)' : name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(isOwner ? 'Ejer' : 'Kan redigere'),
      trailing: canRemove
          ? IconButton(
              icon: Icon(Icons.person_remove_outlined, color: colors.error),
              tooltip: 'Fjern $name',
              onPressed: () => _remove(context, ref),
            )
          : null,
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Fjern $name?',
      message:
          '$name mister adgang til indkøbslisten, madplanen og opskrifterne. '
          'Husstandens aktive invitationskoder holder op med at virke, så '
          '$name ikke kan komme ind igen med en gammel kode.',
      confirmLabel: 'Fjern',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final error = await ref.read(householdProvider.notifier).removeMember(uid);
    messenger.showSnackBar(SnackBar(
      content: Text(error ?? '$name er fjernet fra husstanden.'),
      backgroundColor: error != null ? errorColor : null,
      behavior: SnackBarBehavior.floating,
    ));
  }
}

class _SentInvitations extends ConsumerWidget {
  const _SentInvitations();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invitations =
        ref.watch(sentInvitationsProvider).valueOrNull ?? const [];
    if (invitations.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const _SectionTitle('Venter på svar'),
        _Card(
          children: [
            for (final invite in invitations)
              ListTile(
                leading: const Icon(Icons.schedule_outlined),
                title: Text(invite.email,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: invite.fromUserName != null
                    ? Text('Inviteret af ${invite.fromUserName}')
                    : null,
                trailing: TextButton(
                  onPressed: () => _cancel(context, ref, invite),
                  child: const Text('Annullér'),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _cancel(
      BuildContext context, WidgetRef ref, SentInvitation invite) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final error =
        await ref.read(householdProvider.notifier).cancelInvitation(invite.id);
    messenger.showSnackBar(SnackBar(
      content: Text(error ?? 'Invitationen til ${invite.email} er annulleret.'),
      backgroundColor: error != null ? errorColor : null,
      behavior: SnackBarBehavior.floating,
    ));
  }
}

class _LeaveTile extends ConsumerWidget {
  final HouseholdState household;
  final String? myUid;
  const _LeaveTile({required this.household, required this.myUid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final others = household.members.where((m) => m != myUid).toList();
    final canLeave = myUid != null && others.isNotEmpty;

    return ListTile(
      enabled: canLeave,
      leading: Icon(Icons.logout, color: canLeave ? colors.error : null),
      title: Text(
        'Forlad husstand',
        style: canLeave ? TextStyle(color: colors.error) : null,
      ),
      subtitle:
          canLeave ? null : const Text('Ikke muligt, når du er eneste medlem'),
      onTap: canLeave ? () => _leave(context, ref, others) : null,
    );
  }

  Future<void> _leave(
      BuildContext context, WidgetRef ref, List<String> others) async {
    final name = household.householdName ?? 'husstanden';
    final isOwner = household.adminUid == myUid;
    final successorName =
        household.memberNames[others.first] ?? 'et andet medlem';

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
    final errorColor = Theme.of(context).colorScheme.error;
    final router = GoRouter.maybeOf(context);
    final error = await ref.read(householdProvider.notifier).leaveHousehold();
    messenger.showSnackBar(SnackBar(
      content: Text(error ?? 'Du har forladt "$name".'),
      backgroundColor: error != null ? errorColor : null,
      behavior: SnackBarBehavior.floating,
    ));
    if (error == null && router != null && router.canPop()) router.pop();
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
