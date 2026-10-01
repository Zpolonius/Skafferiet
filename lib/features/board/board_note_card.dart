import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import '../../core/models/board_note.dart';

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

    return Material(
      color:
          note.isPinned ? cs.secondaryContainer.withValues(alpha: 0.18) : cs.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: note.isPinned
              ? cs.secondary.withValues(alpha: 0.4)
              : cs.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 0, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _buildBody(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final initial = authorName.trim().isNotEmpty ? authorName.trim()[0].toUpperCase() : '?';
    final hasPhoto = authorPhotoUrl != null && authorPhotoUrl!.isNotEmpty;

    return Row(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: cs.primaryContainer.withValues(alpha: 0.2),
          foregroundImage: hasPhoto ? CachedNetworkImageProvider(authorPhotoUrl!) : null,
          child: Text(
            initial,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cs.primary),
          ),
        ),
        const Gap(8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              Text(
                boardTimeLabel(note.createdAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  fontSize: 12,
                  height: 1.2,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (note.isPinned)
          Icon(Icons.push_pin, size: 18, color: cs.secondary, semanticLabel: 'Fastgjort'),
        PopupMenuButton<String>(
          tooltip: 'Flere valg',
          icon: Icon(Icons.more_vert, color: cs.onSurfaceVariant),
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
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return switch (note) {
      TextNote(:final text) => Text(text, style: textTheme.bodyMedium),
      PhotoNote(:final imageUrl, :final caption) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
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
              const Gap(8),
              Text(caption, style: textTheme.bodyMedium),
            ],
          ],
        ),
      final ChecklistNote checklist => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              checklist.title,
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              '${checklist.done.length} af ${checklist.items.length} klaret',
              style: textTheme.bodyMedium?.copyWith(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const Gap(4),
            for (var i = 0; i < checklist.items.length; i++)
              _ChecklistRow(
                text: checklist.items[i],
                isDone: checklist.done.contains(i),
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
  final VoidCallback onTap;

  const _ChecklistRow({required this.text, required this.isDone, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Hele rækken er trykbar og mindst 40 px høj, så den er nem at ramme.
    return Semantics(
      checked: isDone,
      label: text,
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
                    color: isDone ? cs.onSurfaceVariant : cs.onSurface,
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
