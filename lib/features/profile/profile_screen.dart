import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/providers/profile_image_provider.dart';
import '../../core/theme/app_colors.dart';
import '../auth/auth_provider.dart';
import '../grocery/grocery_provider.dart';
import '../meal_plan/meal_plan_provider.dart';
import '../recipes/recipes_provider.dart';
import 'household_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider);
    final auth = ref.watch(authProvider);
    final user = auth.user;

    ref.listen(householdProvider.select((s) => s.error), (previous, next) {
      if (next != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next), backgroundColor: Colors.red),
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
      body: household.isLoading
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
                        if (household.householdId == null)
                          const _NoHouseholdCard()
                        else
                          _HouseholdDetailCard(household: household),

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
                          title: 'Delte lister',
                          onTap: household.householdId != null
                              ? () => _showInviteDialog(context, ref)
                              : null,
                        ),
                        _ProfileTile(
                          icon: Icons.notifications_outlined,
                          title: 'Notifikationer',
                          onTap: () =>
                              ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Notifikationer kommer snart!')),
                          ),
                        ),
                        _ProfileTile(
                          icon: Icons.tune_outlined,
                          title: 'Præferencer & Diæt',
                          onTap: () =>
                              ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Kommer snart')),
                          ),
                        ),
                        _ProfileTile(
                          icon: Icons.help_outline,
                          title: 'Hjælp & Support',
                          onTap: () =>
                              ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Kommer snart')),
                          ),
                        ),
                        const SizedBox(height: 40),

                        // ── Logout ───────────────────────────────────────
                        SizedBox(
                          height: 56,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                ref.read(authProvider.notifier).logout(),
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
    );
  }

  void _showInviteDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Inviter til husstand'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'e-mail@eksempel.dk',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Indtast e-mail';
              if (!v.contains('@') || !v.contains('.')) return 'Ugyldig e-mail';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuller')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                final email = controller.text.trim();
                ref.read(householdProvider.notifier).sendInvitation(email);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Invitation sendt til $email'),
                  backgroundColor: AppColors.primary,
                  behavior: SnackBarBehavior.floating,
                ));
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
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

// ── Household detail card ──────────────────────────────────────────────────────

class _HouseholdDetailCard extends ConsumerWidget {
  final HouseholdState household;
  const _HouseholdDetailCard({required this.household});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: icon + name + rename button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.house_outlined,
                      color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        household.householdName ?? 'Min Husholdning',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const Text('Aktiv',
                          style: TextStyle(
                              color: Colors.green,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      size: 18, color: AppColors.outline),
                  tooltip: 'Omdøb husstand',
                  onPressed: () => _showRenameDialog(context, ref),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: Colors.grey[100]),

          // Members section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MEDLEMMER',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.outline,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 10),
                ...household.memberNames.entries.map((entry) {
                  final isOwner = entry.key == household.adminUid;
                  final initial = entry.value.isNotEmpty
                      ? entry.value[0].toUpperCase()
                      : '?';
                  final photoUrl = household.memberPhotos[entry.key];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: isOwner
                              ? AppColors.primaryContainer
                              : Colors.grey[300],
                          child: ClipOval(
                            child: photoUrl != null && photoUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: photoUrl,
                                    width: 36,
                                    height: 36,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) =>
                                        const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                    errorWidget: (context, url, error) => Text(
                                      initial,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isOwner
                                            ? Colors.white
                                            : Colors.black87,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                : Text(
                                    initial,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isOwner
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: GoogleFonts.beVietnamPro(
                                fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isOwner
                                ? AppColors.primaryContainer
                                    .withValues(alpha: 0.12)
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isOwner
                                  ? AppColors.primary.withValues(alpha: 0.25)
                                  : Colors.grey[300]!,
                            ),
                          ),
                          child: Text(
                            isOwner ? 'Ejer' : 'Kan redigere',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isOwner
                                  ? AppColors.primary
                                  : AppColors.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),

          Divider(height: 1, color: Colors.grey[100]),

          // Invite tile
          ListTile(
            leading: const Icon(Icons.person_add_outlined,
                color: AppColors.primary, size: 20),
            title: Text(
              'Inviter et medlem',
              style: GoogleFonts.beVietnamPro(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primary),
            ),
            trailing: const Icon(Icons.chevron_right,
                size: 18, color: AppColors.outline),
            onTap: () => _showInviteDialog(context, ref),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller =
        TextEditingController(text: household.householdName ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Omdøb husstand'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Navn på husstand'),
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuller')),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(householdProvider.notifier).renameHousehold(name);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Gem'),
          ),
        ],
      ),
    );
  }

  void _showInviteDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Inviter til husstand'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'e-mail@eksempel.dk',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Indtast e-mail';
              if (!v.contains('@') || !v.contains('.')) {
                return 'Ugyldig e-mail';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuller')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                final email = controller.text.trim();
                ref.read(householdProvider.notifier).sendInvitation(email);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Invitation sendt til $email'),
                  backgroundColor: AppColors.primary,
                  behavior: SnackBarBehavior.floating,
                ));
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

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

  const _ProfileTile({
    required this.icon,
    required this.title,
    this.onTap,
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
        leading: Icon(icon, color: AppColors.primary, size: 22),
        title: Text(title,
            style: GoogleFonts.beVietnamPro(
                fontSize: 15, fontWeight: FontWeight.w500)),
        trailing:
            const Icon(Icons.chevron_right, size: 20, color: AppColors.outline),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

// ── No household card (unchanged) ─────────────────────────────────────────────

class _InvitationCard extends ConsumerWidget {
  final Map<String, dynamic> invite;
  const _InvitationCard({required this.invite});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            '${invite['fromUserName'] ?? 'Nogen'} har inviteret dig til "${invite['fromHouseholdName'] ?? 'et Skafferi'}".',
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
                  onPressed: () => ref
                      .read(householdProvider.notifier)
                      .acceptInvitation(invite['id']),
                  child: const Text('Accepter'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
                  onPressed: () => _showJoinDialog(context, ref),
                  child: const Text('Indtast kode'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => _showCreateDialog(context, ref),
                  child: const Text('Opret ny'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showJoinDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deltag med kode'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'F.eks. SK-123456',
            prefixIcon: Icon(Icons.vpn_key_outlined),
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuller')),
          FilledButton(
            onPressed: () {
              final code = controller.text.trim().toUpperCase();
              if (code.isNotEmpty) {
                ref.read(householdProvider.notifier).joinHousehold(code);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Deltag'),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: 'Mit Skafferi');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Navngiv dit Skafferi'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Navn på husstand'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuller')),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(householdProvider.notifier).createHousehold(name);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Opret'),
          ),
        ],
      ),
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
