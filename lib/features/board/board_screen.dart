import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../../core/models/board_note.dart';
import '../../shared/widgets/empty_state_widget.dart';
import '../../shared/widgets/profile_avatar.dart';
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
    final notesAsync = ref.watch(boardProvider);
    final hasNotes = notesAsync.valueOrNull?.isNotEmpty ?? false;

    return Scaffold(
      floatingActionButton: hasNotes
          ? FloatingActionButton.extended(
              onPressed: () => _openAddSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('Ny seddel'),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            const _BoardHeader(),
            Expanded(child: _buildContent(context, ref, notesAsync)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, WidgetRef ref, AsyncValue<List<BoardNote>> notesAsync) {
    return notesAsync.when(
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
    );
  }

  Future<void> _openAddSheet(BuildContext context) async {
    final added = await showAddBoardNoteSheet(context);
    if (added == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sedlen er sat op')));
    }
  }
}

/// Fanens topbjælke – samme opbygning som de øvrige faner.
class _BoardHeader extends StatelessWidget {
  const _BoardHeader();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Row(
        children: [
          Image.asset('assets/images/logo.png', height: 32),
          const Gap(12),
          Expanded(
            child: Text(
              'Opslagstavle',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.primaryContainer,
                  ),
            ),
          ),
          const ProfileAvatar(),
        ],
      ),
    );
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

        // Prikmønstret ligger fast bag sedlerne, ligesom en tavle.
        return CustomPaint(
          painter: _BoardDotsPainter(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
          child: SingleChildScrollView(
            // Plads i bunden, så FAB'en ikke dækker den sidste seddel.
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var col = 0; col < columns; col++) ...[
                  if (col > 0) const Gap(16),
                  Expanded(
                    child: Column(
                      children: [
                        for (var i = col; i < notes.length; i += columns) ...[
                          card(notes[i]),
                          const Gap(20),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
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

/// Diskret prikmønster, der får baggrunden til at ligne en opslagstavle.
class _BoardDotsPainter extends CustomPainter {
  final Color color;

  const _BoardDotsPainter({required this.color});

  static const double _spacing = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var y = _spacing / 2; y < size.height; y += _spacing) {
      for (var x = _spacing / 2; x < size.width; x += _spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_BoardDotsPainter old) => old.color != color;
}
