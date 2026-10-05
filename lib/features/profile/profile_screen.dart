import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/settings_list.dart';
import '../auth/auth_provider.dart';
import '../meal_plan/meal_types_sheet.dart';
import 'change_name_dialog.dart';
import 'household_provider.dart';
import 'profile_header.dart';
import 'profile_household_section.dart';

/// Profilen (design/profilside_1). Skærmen sætter kun delene sammen; hver
/// del ligger i sin egen fil.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider);
    final user = ref.watch(authProvider).user;
    final hasHousehold = household.householdId != null;
    final colors = Theme.of(context).colorScheme;

    ref.listen(householdProvider.select((s) => s.error), (previous, next) {
      // Kun den øverste skærm viser fejlen — ellers ses den to gange, når
      // "Husstand & deling" ligger oven på profilen.
      if (next != null && ModalRoute.of(context)?.isCurrent != false) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next), backgroundColor: colors.error),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Profil'), centerTitle: true),
      body: SafeArea(
        child: household.isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                // 20 px sidemargin (DESIGN.md: container-margin).
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  ProfileHeader(user: user),
                  const SizedBox(height: 24),
                  const ProfileStatsRow(),
                  const SizedBox(height: 32),

                  const SectionTitle('Husholdning'),
                  if (!hasHousehold)
                    const NoHouseholdCard()
                  else
                    HouseholdSummaryCard(household: household, myUid: user?.uid),

                  if (household.invitations.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const SectionTitle('Invitationer'),
                    for (final invite in household.invitations)
                      ReceivedInvitationCard(invite: invite),
                  ],
                  const SizedBox(height: 32),

                  const SectionTitle('Menu'),
                  SettingsGroup(
                    children: [
                      SettingsTile(
                        icon: Icons.menu_book_outlined,
                        title: 'Mine opskrifter',
                        onTap: () => context.go('/recipes'),
                      ),
                      SettingsTile(
                        icon: Icons.restaurant_outlined,
                        title: 'Mine måltider',
                        onTap: () => MealTypesSheet.show(context),
                      ),
                      SettingsTile(
                        icon: Icons.event_repeat,
                        title: 'Faste varer & indkøbsdag',
                        onTap: hasHousehold ? () => context.go('/grocery/recurring') : null,
                      ),
                      SettingsTile(
                        icon: Icons.people_outlined,
                        title: 'Husstand & deling',
                        onTap: hasHousehold ? () => context.push('/profile/household') : null,
                      ),
                      SettingsTile(
                        icon: Icons.tune_outlined,
                        title: 'Præferencer & Diæt',
                        onTap: hasHousehold ? () => context.push('/profile/preferences') : null,
                      ),
                      SettingsTile(
                        icon: Icons.help_outline,
                        title: 'Hjælp & Support',
                        onTap: () => context.push('/profile/help'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  const SectionTitle('Konto'),
                  SettingsGroup(
                    children: [
                      SettingsTile(
                        icon: Icons.badge_outlined,
                        title: 'Skift navn',
                        onTap: () => showChangeNameDialog(context, user?.displayName ?? ''),
                      ),
                      SettingsTile(
                        icon: Icons.lock_outline,
                        title: 'Skift adgangskode',
                        onTap: () => context.push('/profile/change-password'),
                      ),
                      SettingsTile(
                        icon: Icons.privacy_tip_outlined,
                        title: 'Privatlivspolitik',
                        onTap: () => context.push('/privacy'),
                      ),
                      SettingsTile(
                        icon: Icons.delete_forever_outlined,
                        title: 'Slet konto',
                        destructive: true,
                        onTap: () => context.push('/profile/delete-account'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),

                  // Log ud — lys rød kant som i mockuppet.
                  SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmLogout(context, ref),
                      icon: const Icon(Icons.logout),
                      label: const Text('Log ud'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.error,
                        backgroundColor: colors.surfaceContainerLowest,
                        side: BorderSide(color: colors.errorContainer, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
