import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Row(
              children: [
                const Icon(Icons.house_outlined, color: AppColors.primary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hjemme hos Polonius', style: Theme.of(context).textTheme.bodyLarge),
                      Text('ID: HK92-L01X', style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text('Del'),
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
