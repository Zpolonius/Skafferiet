import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_info.dart';
import '../../shared/widgets/settings_list.dart';

/// Appens version, fx "1.0.0 (1)". Overskrives i tests.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

/// Åbner et link uden for appen (fx mail). Overskrives i tests.
final externalLinkLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

class _Faq {
  final String question;
  final String answer;
  const _Faq(this.question, this.answer);
}

const _faqs = [
  _Faq(
    'Hvordan inviterer jeg nogen til min husstand?',
    'Gå til Profil → Husstand & deling. Vælg "Inviter med e-mail" — personen '
        'ser invitationen, når de logger ind med den e-mail — eller "Del '
        'invitationskode" og send koden til dem.',
  ),
  _Faq(
    'Hvordan deltager jeg i en anden husstand?',
    'Få en invitationskode fra et medlem, og vælg "Deltag i en anden husstand" '
        'under Husstand & deling. Er du inviteret med din e-mail, står '
        'invitationen øverst på din profil.',
  ),
  _Faq(
    'Hvad sker der, hvis jeg forlader en husstand?',
    'Du mister adgang til husstandens indkøbsliste, madplan og opskrifter, og '
        'du får din egen, tomme husstand. De andre medlemmer beholder det hele.',
  ),
  _Faq(
    'Hvem kan se mine opskrifter og lister?',
    'Kun medlemmerne af din husstand. Ingen andre brugere kan se dine '
        'opskrifter, din indkøbsliste eller din madplan.',
  ),
  _Faq(
    'Jeg har glemt min adgangskode',
    'Log ud, og tryk på "Glemt adgangskode?" på login-skærmen. Du får en mail '
        'med et link, hvor du kan vælge en ny.',
  ),
  _Faq(
    'Hvordan sletter jeg min konto?',
    'Gå til Profil → Slet konto. Din konto og dine data slettes med det samme. '
        'Læs mere i privatlivspolitikken.',
  ),
];

/// "Hjælp & Support": ofte stillede spørgsmål, kontakt og version.
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final version = ref.watch(appVersionProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Hjælp & Support')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const SectionTitle('Ofte stillede spørgsmål'),
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final faq in _faqs)
                    ExpansionTile(
                      title: Text(faq.question),
                      shape: const Border(),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      expandedAlignment: Alignment.centerLeft,
                      children: [Text(faq.answer, style: text.bodyMedium)],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionTitle('Kontakt'),
            SettingsGroup(
              children: [
                SettingsTile(
                  icon: Icons.mail_outline,
                  title: 'Skriv til os',
                  subtitle: AppInfo.contactEmail,
                  trailing: Icon(Icons.open_in_new, size: 18, color: colors.outline),
                  onTap: () => _contact(context, ref, version),
                ),
                SettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privatlivspolitik',
                  onTap: () => context.push('/privacy'),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Center(
              child: Text(
                version != null ? 'Skafferiet version $version' : 'Skafferiet',
                key: const Key('app_version'),
                style: text.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Åbner mail-appen med en udfyldt mail. Findes der ingen mail-app (fx på
  /// en simulator), kopieres adressen i stedet, så brugeren ikke står fast.
  Future<void> _contact(BuildContext context, WidgetRef ref, String? version) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri(
      scheme: 'mailto',
      path: AppInfo.contactEmail,
      query: _encodeQuery({
        'subject': 'Skafferiet – hjælp',
        'body': '\n\n\n—\nVersion: ${version ?? 'ukendt'}\n'
            'Enhed: ${defaultTargetPlatform.name}',
      }),
    );

    var opened = false;
    try {
      opened = await ref.read(externalLinkLauncherProvider)(uri);
    } catch (_) {
      opened = false;
    }
    if (opened) return;

    await Clipboard.setData(const ClipboardData(text: AppInfo.contactEmail));
    messenger.showSnackBar(const SnackBar(
      content: Text('Ingen mail-app fundet. E-mailadressen er kopieret.'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// mailto-links skal bruge %20 for mellemrum, ikke "+", som
  /// Uri(queryParameters:) ellers ville give.
  static String _encodeQuery(Map<String, String> params) => params.entries
      .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');
}
