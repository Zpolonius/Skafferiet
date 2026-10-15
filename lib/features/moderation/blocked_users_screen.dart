import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/recipe_report.dart';
import '../../core/theme/theme_context.dart';
import '../../shared/widgets/settings_list.dart';
import 'moderation_provider.dart';

/// Profil → Blokerede brugere: de forfattere, hvis opskrifter er skjult i
/// Fællesskab, med mulighed for at fjerne blokeringen igen.
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  Future<void> _unblock(
      BuildContext context, WidgetRef ref, BlockedAuthor a) async {
    final messenger = ScaffoldMessenger.of(context);
    final colors = context.colors;
    try {
      await ref.read(moderationServiceProvider).unblockAuthor(a.uid);
      messenger.showSnackBar(SnackBar(
        content: Text('Blokeringen af ${a.name} er fjernet'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: const Text('Blokeringen kunne ikke fjernes. Prøv igen.'),
        backgroundColor: colors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedAuthorsProvider);
    final colors = context.colors;
    final text = context.text;

    return Scaffold(
      appBar: AppBar(title: const Text('Blokerede brugere'), centerTitle: true),
      body: SafeArea(
        child: blocked.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Kunne ikke hente blokerede brugere'),
            ),
          ),
          data: (list) {
            if (list.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.block_outlined,
                          size: 48, color: colors.outline),
                      const SizedBox(height: 12),
                      Text('Du har ikke blokeret nogen',
                          style: text.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        'Blokerer du en bruger fra en opskrift i Fællesskab, '
                        'kan du fjerne blokeringen her.',
                        textAlign: TextAlign.center,
                        style: text.bodyMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                const SectionTitle('Skjult for dig'),
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 4, bottom: 12),
                  child: Text(
                    'Opskrifter fra disse brugere vises ikke i Fællesskab. '
                    'Opskrifter, du allerede har gemt, er upåvirkede.',
                    style: text.bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
                SettingsGroup(
                  children: [
                    for (final a in list)
                      ConstrainedBox(
                        key: Key('blocked-${a.uid}'),
                        constraints: const BoxConstraints(minHeight: 56),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16, right: 8),
                          child: Row(
                            children: [
                              Icon(Icons.block_outlined, color: colors.outline),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(a.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.titleSmall),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                    minimumSize: const Size(48, 48)),
                                onPressed: () => _unblock(context, ref, a),
                                child: Text('Fjern blokering',
                                    semanticsLabel:
                                        'Fjern blokering af ${a.name}'),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
