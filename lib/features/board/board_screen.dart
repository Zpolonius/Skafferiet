import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../../core/models/board_note.dart';
import '../../shared/widgets/empty_state_widget.dart';
import '../auth/auth_provider.dart';
import '../profile/household_provider.dart';
import 'add_board_note_sheet.dart';
import 'board_note_card.dart';
import 'board_policy.dart';
import 'board_provider.dart';

/// Husstandens opslagstavle.
class BoardScreen extends ConsumerWidget {
  const BoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final notesAsync = ref.watch(boardProvider);
    final hasNotes = notesAsync.valueOrNull?.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Opslagstavle',
          style: Theme.of(context).textTheme.displayMedium?.copyWith(color: cs.primary),
        ),
      ),
      floatingActionButton: hasNotes
          ? FloatingActionButton.extended(
              onPressed: () => _openAddSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('Ny seddel'),
            )
          : null,
      body: notesAsync.when(
        data: (notes) => notes.isEmpty
            ? EmptyStateWidget(
                icon: Icons.push_pin_outlined,
                title: 'Tavlen er tom',
                message: 'Sæt en seddel op til resten af husstanden – '
                    'en besked, et billede eller en lille tjekliste.',
                actionLabel: 'Sæt en seddel op',
                onAction: () => _openAddSheet(context),
              )
            : _BoardGrid(notes: notes),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Kunne ikke hente opslagstavlen'),
              const Gap(8),
              TextButton(
                onPressed: () => ref.invalidate(boardProvider),
                child: const Text('Prøv igen'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAddSheet(BuildContext context) async {
    final added = await showAddBoardNoteSheet(context);
    if (added == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sedlen er sat op')));
    }
  }
}

/// Sedlerne i kolonner. Rækkefølgen læses fra venstre mod højre, så
/// fastgjorte sedler altid står øverst.
class _BoardGrid extends ConsumerWidget {
  final List<BoardNote> notes;

  const _BoardGrid({required this.notes});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider);
    final currentUid = ref.watch(authProvider).user?.uid;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 900 ? 3 : (width >= 340 ? 2 : 1);

        Widget card(BoardNote note) => BoardNoteCard(
              key: ValueKey(note.id),
              note: note,
              authorName: note.authorId == currentUid
                  ? 'Dig'
                  : household.memberNames[note.authorId] ?? 'Tidligere medlem',
              authorPhotoUrl: household.memberPhotos[note.authorId],
              canDelete: BoardPolicy.canDelete(
                note,
                currentUid: currentUid,
                adminUid: household.adminUid,
              ),
              onTogglePin: () => _run(
                context,
                () => ref.read(boardProvider.notifier).togglePin(note),
                'Kunne ikke opdatere sedlen',
              ),
              onDelete: () => _confirmDelete(context, ref, note),
              onToggleItem: (n, i) => _run(
                context,
                () => ref.read(boardProvider.notifier).toggleChecklistItem(n, i),
                'Kunne ikke opdatere listen',
              ),
            );

        return SingleChildScrollView(
          // Plads i bunden, så FAB'en ikke dækker den sidste seddel.
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var col = 0; col < columns; col++) ...[
                if (col > 0) const Gap(12),
                Expanded(
                  child: Column(
                    children: [
                      for (var i = col; i < notes.length; i += columns) ...[
                        card(notes[i]),
                        const Gap(12),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _run(BuildContext context, Future<void> Function() action, String errorText) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText)));
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, BoardNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slet seddel?'),
        content: const Text('Sedlen forsvinder for hele husstanden.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuller')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Slet'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(boardProvider.notifier).deleteNote(note);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Sedlen er slettet')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Kunne ikke slette sedlen')));
      }
    }
  }
}
