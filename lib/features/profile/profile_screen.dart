import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../auth/auth_provider.dart';
import 'household_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider);
    final auth = ref.watch(authProvider);
    final user = auth.user;
    
    // Sikker håndtering af initialer
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
                    children: [
                      // User Header
                      Center(
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 50,
                              backgroundColor: AppColors.primaryContainer,
                              child: Text(
                                initial,
                                style: const TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
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
                      const SizedBox(height: 32),
                      
                      // Household Section
                      _SectionHeader(title: 'Husholdning'),
                      const SizedBox(height: 12),
                      if (household.householdId == null)
                        const _NoHouseholdCard()
                      else
                        _HouseholdCard(household: household),
                      
                      const SizedBox(height: 32),
                      
                      // Invitations Section
                      if (household.invitations.isNotEmpty) ...[
                        _SectionHeader(title: 'Invitationer'),
                        const SizedBox(height: 12),
                        ...household.invitations.map((invite) => _InvitationCard(invite: invite)),
                        const SizedBox(height: 32),
                      ],
                      
                      // Settings Section
                      _SectionHeader(title: 'Indstillinger'),
                      const SizedBox(height: 12),
                      _ProfileTile(
                        icon: Icons.notifications_none,
                        title: 'Notifikationer',
                      ),
                      _ProfileTile(
                        icon: Icons.dark_mode_outlined,
                        title: 'Mørkt tema',
                        trailing: Switch(value: false, onChanged: (v) {}),
                      ),
                      
                      const SizedBox(height: 40),
                      
                      // Logout Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: () => ref.read(authProvider.notifier).logout(),
                          icon: const Icon(Icons.logout),
                          label: const Text('Log ud'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

class _HouseholdCard extends ConsumerWidget {
  final HouseholdState household;
  const _HouseholdCard({required this.household});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.house_outlined, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      household.householdName ?? 'Min Husholdning',
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
                    ),
                    const Text('Status: Aktiv', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: () {
                  print('DEBUG: Inviter-knap trykket!');
                  _showInviteDialog(context, ref);
                },
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('Inviter'),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              const Icon(Icons.people_outline, size: 16, color: AppColors.outline),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Medlemmer: ${household.members.join(", ")}',
                  style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.outline),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showInviteDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Inviter til husstand'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'e-mail@eksempel.dk'),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuller')),
          FilledButton(
            onPressed: () {
              final email = controller.text.trim();
              if (email.contains('@')) {
                ref.read(householdProvider.notifier).sendInvitation(email);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Invitation sendt til $email'),
                    backgroundColor: AppColors.primary,
                  ),
                );
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}

class _InvitationCard extends ConsumerWidget {
  final Map<String, dynamic> invite;
  const _InvitationCard({required this.invite});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryContainer.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Invitation modtaget!',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: AppColors.primary),
          ),
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
                  onPressed: () => ref.read(householdProvider.notifier).declineInvitation(invite['id']),
                  child: const Text('Afvis'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => ref.read(householdProvider.notifier).acceptInvitation(invite['id']),
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

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _ProfileTile({required this.icon, required this.title, this.trailing, this.onTap});

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
        title: Text(title, style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.w500)),
        trailing: trailing ?? const Icon(Icons.chevron_right, size: 20, color: AppColors.outline),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          const Text('Du er ikke i en husstand endnu', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Bliv inviteret af en ven, eller opret din egen herunder.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.outline)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => ref.read(householdProvider.notifier).createHousehold('Mit Skafferi'),
              child: const Text('Opret nyt Skafferi'),
            ),
          ),
        ],
      ),
    );
  }
}
