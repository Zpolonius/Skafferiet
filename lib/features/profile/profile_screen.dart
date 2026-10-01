import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/providers/profile_image_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../auth/auth_provider.dart';
import '../grocery/grocery_provider.dart';
import '../meal_plan/meal_plan_provider.dart';
import '../recipes/recipes_provider.dart';
import 'household_dialogs.dart';
import 'household_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider);
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final hasHousehold = household.householdId != null;

    ref.listen(householdProvider.select((s) => s.error), (previous, next) {
      // Kun den øverste skærm viser fejlen — ellers ses den to gange, når
      // "Husstand & deling" ligger oven på profilen.
      if (next != null && ModalRoute.of(context)?.isCurrent != false) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    });

    String initial = 'U';
    if (user?.displayName != null && user!.displayName!.isNotEmpty) {
      initial = user.displayName![0].toUpperCase();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9F8),
      appBar: AppBar(
        title: const Text('Profil'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: household.isLoading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── User header ──────────────────────────────────
                        Center(
                          child: Column(
                            children: [
                              _ProfileHeaderAvatar(
                                user: user,
                                initial: initial,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                user?.displayName ?? 'Bruger',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryContainer,
                                ),
                              ),
                              Text(
                                user?.email ?? '',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 14,
                                  color: AppColors.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Stats row ────────────────────────────────────
                        const _StatsRow(),
                        const SizedBox(height: 32),

                        // ── Husholdning ──────────────────────────────────
                        const _SectionHeader(title: 'Husholdning'),
                        const SizedBox(height: 12),
                        if (!hasHousehold)
                          const _NoHouseholdCard()
                        else
                          _HouseholdSummaryCard(
                            household: household,
                            myUid: user?.uid,
                          ),

                        // Pending invitations
                        if (household.invitations.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const _SectionHeader(title: 'Invitationer'),
                          const SizedBox(height: 12),
                          ...household.invitations
                              .map((invite) => _InvitationCard(invite: invite)),
                        ],
                        const SizedBox(height: 32),

                        // ── Menu ─────────────────────────────────────────
                        const _SectionHeader(title: 'Menu'),
                        const SizedBox(height: 12),
                        _ProfileTile(
                          icon: Icons.restaurant_menu_outlined,
                          title: 'Mine opskrifter',
                          onTap: () => context.go('/recipes'),
                        ),
                        _ProfileTile(
                          icon: Icons.people_outlined,
                          title: 'Husstand & deling',
                          onTap: hasHousehold
                              ? () => context.push('/profile/household')
                              : null,
                        ),
                        _ProfileTile(
                          icon: Icons.tune_outlined,
                          title: 'Præferencer & Diæt',
                          onTap: hasHousehold
                              ? () => context.push('/profile/preferences')
                              : null,
                        ),
                        _ProfileTile(
                          icon: Icons.help_outline,
                          title: 'Hjælp & Support',
                          onTap: () => context.push('/profile/help'),
                        ),
                        const SizedBox(height: 32),

                        // ── Konto ────────────────────────────────────────
                        const _SectionHeader(title: 'Konto'),
                        const SizedBox(height: 12),
                        _ProfileTile(
                          icon: Icons.badge_outlined,
                          title: 'Skift navn',
                          onTap: () => showDialog<void>(
                            context: context,
                            builder: (_) => _ChangeNameDialog(
                              currentName: user?.displayName ?? '',
                            ),
                          ),
                        ),
                        _ProfileTile(
                          icon: Icons.lock_outline,
                          title: 'Skift adgangskode',
                          onTap: () => context.push('/profile/change-password'),
                        ),
                        _ProfileTile(
                          icon: Icons.privacy_tip_outlined,
                          title: 'Privatlivspolitik',
                          onTap: () => context.push('/privacy'),
                        ),
                        _ProfileTile(
                          icon: Icons.delete_forever_outlined,
                          title: 'Slet konto',
                          color: Theme.of(context).colorScheme.error,
                          onTap: () => context.push('/profile/delete-account'),
                        ),
                        const SizedBox(height: 40),

                        // ── Logout ───────────────────────────────────────
                        SizedBox(
                          height: 56,
                          child: OutlinedButton.icon(
                            onPressed: () => _confirmLogout(context, ref),
                            icon: const Icon(Icons.logout),
                            label: const Text('Log ud'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: const BorderSide(color: AppColors.error),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Log ud?',
      message: 'Du skal bruge din e-mail og adgangskode for at logge ind igen.',
      confirmLabel: 'Log ud',
    );
    if (confirmed) await ref.read(authProvider.notifier).logout();
  }
}

// ── Stats row ──────────────────────────────────────────────────────────────────

class _StatsRow extends ConsumerWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipeCount = ref.watch(recipesProvider).value?.length;
    final mealDays = ref.watch(mealPlanProvider).value?.days.length;
    final groceryCount = ref.watch(groceryListProvider).value?.length;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _StatCard(value: recipeCount, label: 'OPSKRIFTER'),
          _VerticalDivider(),
          _StatCard(value: mealDays, label: 'MADPLANER'),
          _VerticalDivider(),
          _StatCard(value: groceryCount, label: 'GEMTE VARER'),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final int? value;
  final String label;
  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value?.toString() ?? '–',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.beVietnamPro(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.outline,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 40, color: Colors.grey[200]);
  }
}

// ── Household summary card ─────────────────────────────────────────────────────

/// Kort oversigt over husstanden. Alt det praktiske (medlemmer, invitationer,
/// forlad husstand) ligger på siden "Husstand & deling", som kortet åbner.
class _HouseholdSummaryCard extends StatelessWidget {
  final HouseholdState household;
  final String? myUid;
  const _HouseholdSummaryCard({required this.household, required this.myUid});

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
                backgroundColor: colors.primaryContainer.withValues(alpha: 0.15),
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
                      style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        count == 1 ? '1 medlem' : '$count medlemmer',
                        if (isOwner) 'Du er ejer',
                      ].join(' · '),
                      style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
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
              Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
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
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colors.onSurface),
    );
    return Tooltip(
      message: name,
      child: CircleAvatar(
        radius: 13,
        backgroundColor: colors.surfaceContainerHighest,
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

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  /// Farve på ikon og tekst, fx fejlfarven til "Slet konto".
  final Color? color;

  const _ProfileTile({
    required this.icon,
    required this.title,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        enabled: onTap != null,
        leading: Icon(icon, color: color ?? AppColors.primary, size: 22),
        title: Text(title,
            style: GoogleFonts.beVietnamPro(
                fontSize: 15, fontWeight: FontWeight.w500, color: color)),
        trailing:
            const Icon(Icons.chevron_right, size: 20, color: AppColors.outline),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

// ── Invitations ────────────────────────────────────────────────────────────────

class _InvitationCard extends ConsumerWidget {
  final Map<String, dynamic> invite;
  const _InvitationCard({required this.invite});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toName = invite['fromHouseholdName'] as String? ?? 'et Skafferi';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.secondaryContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.secondaryContainer.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Invitation modtaget!',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 4),
          Text(
            '${invite['fromUserName'] ?? 'Nogen'} har inviteret dig til "$toName".',
            style: GoogleFonts.beVietnamPro(fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => ref
                      .read(householdProvider.notifier)
                      .declineInvitation(invite['id']),
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

class _NoHouseholdCard extends ConsumerWidget {
  const _NoHouseholdCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        children: [
          const Icon(Icons.house_siding_rounded,
              size: 48, color: AppColors.outlineVariant),
          const SizedBox(height: 16),
          const Text('Du er ikke i en husstand endnu',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Bliv inviteret via e-mail, indtast en kode eller opret din egen herunder.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.outline),
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

// ── Skift navn ─────────────────────────────────────────────────────────────────

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
    Navigator.pop(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('Dit navn er opdateret.'),
      behavior: SnackBarBehavior.floating,
    ));
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
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Indtast dit navn' : null,
            ),
            Text(
              'Navnet kan ses af de andre i din husstand.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: colors.error)),
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

class _ProfileHeaderAvatar extends ConsumerStatefulWidget {
  final User? user;
  final String initial;

  const _ProfileHeaderAvatar({
    required this.user,
    required this.initial,
  });

  @override
  ConsumerState<_ProfileHeaderAvatar> createState() =>
      _ProfileHeaderAvatarState();
}

class _ProfileHeaderAvatarState extends ConsumerState<_ProfileHeaderAvatar> {
  bool _isUploading = false;

  Future<void> _handleAvatarTap() async {
    final user = widget.user;
    if (user == null) return;

    final imageService = ref.read(profileImageServiceProvider);
    String? photoUrl;
    try {
      photoUrl = user.photoURL;
    } catch (_) {}

    setState(() => _isUploading = true);
    try {
      final newUrl = await imageService.pickAndUploadProfileImage(
        context,
        userId: user.uid,
        showDeleteOption: photoUrl != null && photoUrl.isNotEmpty,
      );

      if (!mounted) return;

      if (newUrl == '') {
        // Bruger valgte at fjerne billedet
        final success =
            await ref.read(authProvider.notifier).removeProfilePhoto();
        if (mounted && success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profilbillede fjernet'),
              backgroundColor: AppColors.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else if (newUrl != null && newUrl.isNotEmpty) {
        // Nyt billede uploadet
        final success =
            await ref.read(authProvider.notifier).updateProfilePhoto(newUrl);
        if (mounted && success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profilbillede opdateret'),
              backgroundColor: AppColors.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String? photoUrl;
    try {
      photoUrl = widget.user?.photoURL;
    } catch (_) {}

    return GestureDetector(
      onTap: _isUploading ? null : _handleAvatarTap,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: AppColors.primaryContainer,
            child: ClipOval(
              child: photoUrl != null && photoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photoUrl,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      errorWidget: (context, url, error) => Text(
                        widget.initial,
                        style: const TextStyle(
                          fontSize: 32,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : Text(
                      widget.initial,
                      style: const TextStyle(
                        fontSize: 32,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          if (_isUploading)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
