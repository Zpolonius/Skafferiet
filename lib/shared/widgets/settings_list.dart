import 'package:flutter/material.dart';

// Byggeklodser til lister med indstillinger (profil, husstand, hjælp), som i
// design/profilside_1: hvide kort med rækker, ikon i en blød cirkel og en pil.

/// Lille grøn overskrift over en gruppe, fx "Konto".
class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

/// Et hvidt kort med rækker adskilt af tynde linjer.
class SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const SettingsGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final divider = Divider(
      height: 1,
      thickness: 1,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) divider,
            children[i],
          ],
        ],
      ),
    );
  }
}

/// En række med ikon, titel og pil. [destructive] farver den rød (fx "Slet
/// konto"); uden [onTap] er rækken slået fra.
class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool destructive;
  final Widget? trailing;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.destructive = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final accent = destructive ? colors.error : colors.primary;

    return ListTile(
      enabled: enabled,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: destructive ? colors.errorContainer : colors.surfaceContainerLow,
        child: Icon(icon, size: 22, color: enabled ? accent : colors.outline),
      ),
      title: Text(title, style: destructive && enabled ? TextStyle(color: colors.error) : null),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: trailing ?? Icon(Icons.chevron_right, color: colors.outline),
      onTap: onTap,
    );
  }
}

/// Viser resultatet af en handling: [error] i fejlfarve, ellers [success].
/// Tager [messenger] og [colors], så den kan kaldes efter en `await`, hvor
/// `context` ikke længere må bruges.
void showResultSnackBar(
  ScaffoldMessengerState messenger,
  ColorScheme colors, {
  required String? error,
  required String success,
}) {
  messenger.showSnackBar(SnackBar(
    content: Text(error ?? success),
    backgroundColor: error != null ? colors.error : null,
    behavior: SnackBarBehavior.floating,
  ));
}
