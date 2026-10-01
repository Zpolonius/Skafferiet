import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import '../../core/models/board_note.dart';
import 'board_note_style.dart';

/// Kort tidsangivelse til en seddel: "I dag kl. 14:05", "I går kl. 9:30"
/// eller "3. okt.".
String boardTimeLabel(DateTime createdAt, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final day = DateUtils.dateOnly(createdAt);
  final time = DateFormat('H:mm', 'da_DK').format(createdAt);
  if (day == today) return 'I dag kl. $time';
  if (day == today.subtract(const Duration(days: 1))) return 'I går kl. $time';
  return DateFormat('d. MMM', 'da_DK').format(createdAt);
}

/// Én linje, der beskriver sedlen – bruges i forhåndsvisningen på Hjem.
String boardNoteSummary(BoardNote note) => switch (note) {
      TextNote(:final text) => text,
      PhotoNote(:final caption) => caption.isNotEmpty ? caption : 'Billede',
      ChecklistNote(:final title, :final items, :final done) =>
        '$title (${done.length}/${items.length})',
    };

/// Viser én seddel. Kender intet til Firestore – alle handlinger sendes ud
/// via callbacks, så kortet er let at teste og genbruge.
class BoardNoteCard extends StatelessWidget {
  final BoardNote note;
  final String authorName;
  final String? authorPhotoUrl;
  final bool canDelete;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;
  final void Function(ChecklistNote note, int index) onToggleItem;

  const BoardNoteCard({
    super.key,
    required this.note,
    required this.authorName,
    this.authorPhotoUrl,
    required this.canDelete,
    required this.onTogglePin,
    required this.onDelete,
    required this.onToggleItem,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = BoardNoteStyle.of(note, cs);

    // En seddel hænger lidt skævt med tape eller – hvis den er fastgjort –
    // en knappenål øverst.
    return Transform.rotate(
      angle: style.tilt,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withValues(alpha: 0.10),
                    blurRadius: 10,
                    offset: const Offset(1, 5),
                  ),
                  BoxShadow(
                    color: cs.shadow.withValues(alpha: 0.06),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Material(
                color: style.paper,
                borderRadius: BorderRadius.circular(4),
                clipBehavior: Clip.antiAlias,
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: style.onPaper),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 0, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(alignment: Alignment.topRight, child: _buildMenu(context)),
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: _buildBody(context, style),
                        ),
                        const Gap(12),
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: _buildSignature(context, style),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: note.isPinned ? _PushPin(color: cs.primary) : const _Tape(),
          ),
        ],
      ),
    );
  }

  /// Forfatter og tid nederst på sedlen – som en underskrift.
  Widget _buildSignature(BuildContext context, BoardNoteStyle style) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final initial = authorName.trim().isNotEmpty ? authorName.trim()[0].toUpperCase() : '?';
    final hasPhoto = authorPhotoUrl != null && authorPhotoUrl!.isNotEmpty;
    final muted = style.onPaper.withValues(alpha: 0.7);

    return Row(
      children: [
        CircleAvatar(
          radius: 10,
          backgroundColor: cs.primary.withValues(alpha: 0.12),
          foregroundImage: hasPhoto ? CachedNetworkImageProvider(authorPhotoUrl!) : null,
          child: Text(
            initial,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.primary),
          ),
        ),
        const Gap(6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: muted,
                ),
              ),
              Text(
                boardTimeLabel(note.createdAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(fontSize: 11, height: 1.2, color: muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMenu(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Flere valg',
      icon: Icon(Icons.more_horiz, color: cs.onSurfaceVariant),
      onSelected: (value) {
        if (value == 'pin') onTogglePin();
        if (value == 'delete') onDelete();
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'pin',
          child: Row(
            children: [
              Icon(note.isPinned ? Icons.push_pin_outlined : Icons.push_pin, size: 20),
              const Gap(12),
              Text(note.isPinned ? 'Frigør' : 'Fastgør øverst'),
            ],
          ),
        ),
        if (canDelete)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 20, color: cs.error),
                const Gap(12),
                Text('Slet', style: TextStyle(color: cs.error)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, BoardNoteStyle style) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final body = textTheme.bodyMedium?.copyWith(color: style.onPaper);

    return switch (note) {
      TextNote(:final text) => Text(text, style: body?.copyWith(height: 1.4)),
      PhotoNote(:final imageUrl, :final caption) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Semantics(
                  image: true,
                  label: caption.isNotEmpty ? caption : 'Billede fra $authorName',
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => ColoredBox(color: cs.surfaceContainerHighest),
                    errorWidget: (context, url, error) => ColoredBox(
                      color: cs.surfaceContainerHighest,
                      child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            ),
            if (caption.isNotEmpty) ...[
              const Gap(10),
              Text(caption, style: body),
            ],
          ],
        ),
      final ChecklistNote checklist => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              checklist.title,
              style: body?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              '${checklist.done.length} af ${checklist.items.length} klaret',
              style: body?.copyWith(fontSize: 12, color: style.onPaper.withValues(alpha: 0.7)),
            ),
            const Gap(4),
            for (var i = 0; i < checklist.items.length; i++)
              _ChecklistRow(
                text: checklist.items[i],
                isDone: checklist.done.contains(i),
                textColor: style.onPaper,
                onTap: () => onToggleItem(checklist, i),
              ),
          ],
        ),
    };
  }
}

class _ChecklistRow extends StatelessWidget {
  final String text;
  final bool isDone;
  final Color textColor;
  final VoidCallback onTap;

  const _ChecklistRow({
    required this.text,
    required this.isDone,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Hele rækken er trykbar og mindst 40 px høj, så den er nem at ramme.
    return Semantics(
      checked: isDone,
      label: text,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            children: [
              Icon(
                isDone ? Icons.check_box : Icons.check_box_outline_blank,
                size: 22,
                color: isDone ? cs.primary : cs.outline,
              ),
              const Gap(8),
              Expanded(
                child: Text(
                  text,
                  style: textTheme.bodyMedium?.copyWith(
                    fontSize: 15,
                    height: 1.3,
                    color: isDone ? textColor.withValues(alpha: 0.6) : textColor,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Halvgennemsigtig tapestrimmel øverst på en seddel.
class _Tape extends StatelessWidget {
  const _Tape();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Transform.rotate(
        angle: -0.05,
        child: Container(
          width: 52,
          height: 16,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.8),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6), width: 0.5),
            boxShadow: [
              BoxShadow(color: cs.shadow.withValues(alpha: 0.05), blurRadius: 2),
            ],
          ),
        ),
      ),
    );
  }
}

/// Knappenål – vises på fastgjorte sedler.
class _PushPin extends StatelessWidget {
  final Color color;

  const _PushPin({required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Fastgjort',
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.35, -0.35),
            radius: 0.9,
            colors: [Color.lerp(color, cs.surfaceContainerLowest, 0.45)!, color],
          ),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.3),
              blurRadius: 3,
              offset: const Offset(1, 2),
            ),
          ],
        ),
      ),
    );
  }
}
