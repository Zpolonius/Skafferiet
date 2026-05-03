import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import 'household_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Center(
            child: CircleAvatar(
              radius: 50,
              backgroundColor: AppColors.primaryContainer,
              child: Icon(Icons.person, size: 50, color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Zacharias Polonius',
              style: Theme.of(context).textTheme.displayMedium,
            ),
          ),
          Center(
            child: Text(
              'zacharias@example.com',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.outline),
            ),
          ),
          const SizedBox(height: 32),
          
          Text('Husholdning', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          
          if (household.householdId == null)
            const _NoHouseholdCard()
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.house_outlined, color: AppColors.primary),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(household.householdName ?? 'Min Husholdning', style: Theme.of(context).textTheme.bodyLarge),
                            Text('ID: ${household.householdId}', style: Theme.of(context).textTheme.labelSmall),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: household.householdId ?? ''));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('ID kopieret til udklipsholder')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 20),
                        tooltip: 'Kopier ID',
                      ),
                      FilledButton(
                        onPressed: () {},
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Text('Del'),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      const Icon(Icons.people_outline, size: 20, color: AppColors.outline),
                      const SizedBox(width: 8),
                      Text(
                        'Medlemmer: ${household.members.join(", ")}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          
          if (household.householdId != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _showJoinDialog(context, ref),
                    icon: const Icon(Icons.group_add_outlined, size: 16),
                    label: const Text('Deltag i en anden'),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => ref.read(householdProvider.notifier).leaveHousehold(),
                    icon: const Icon(Icons.exit_to_app, size: 16),
                    label: const Text('Forlad husholdning'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  ),
                ],
              ),
            ),
          
          const SizedBox(height: 32),
          Text('Indstillinger', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          _ProfileTile(
            icon: Icons.notifications_none,
            title: 'Notifikationer',
            onTap: () {},
          ),
          _ProfileTile(
            icon: Icons.dark_mode_outlined,
            title: 'Mørkt tema',
            trailing: Switch(value: false, onChanged: (v) {}),
          ),
          _ProfileTile(
            icon: Icons.help_outline,
            title: 'Hjælp & Support',
            onTap: () {},
          ),
          
          const SizedBox(height: 40),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.logout),
            label: const Text('Log ud'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }

  void _showJoinDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deltag i husholdning'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Indtast kode (f.eks. SK-1234)',
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuller'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(householdProvider.notifier).joinHousehold(controller.text);
              Navigator.pop(context);
            },
            child: const Text('Deltag'),
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

  const _ProfileTile({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: AppColors.onSurfaceVariant),
      title: Text(
        title,
        style: GoogleFonts.beVietnamPro(
          fontWeight: FontWeight.w500,
          fontSize: 15,
        ),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
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
        color: AppColors.primaryFixed,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.group_add_outlined, size: 40, color: AppColors.primary),
          const SizedBox(height: 12),
          Text(
            'Ingen husholdning endnu',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.primary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Opret en husholdning eller deltag i en eksisterende for at dele indkøbslister og madplaner.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _showJoinDialog(context, ref),
                  child: const Text('Deltag'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => ref.read(householdProvider.notifier).createHousehold('Min Husholdning'),
                  child: const Text('Opret'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showJoinDialog(BuildContext context, WidgetRef ref) {
    // Denne er nu overflødig her, da den er flyttet til ProfileScreen
    // Men vi beholder den hvis den bliver kaldt internt, eller lader den kalde ProfileScreen versionen
    // For nu sletter vi den og lader _NoHouseholdCard kalde ProfileScreen.
  }
}
