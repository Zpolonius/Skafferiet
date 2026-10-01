/// Sedler på husstandens opslagstavle.
///
/// `BoardNote` er en `sealed class`: alle seddeltyper står i denne fil, så
/// en `switch` over dem er udtømmende. Tilføjer man en ny type, peger
/// compileren på hvert sted, der skal tage stilling til den.
///
/// Grænserne i [BoardNoteLimits] håndhæves også i `firestore.rules`. Ret
/// begge steder, hvis de ændres.
library;

/// Fælles grænser for tekstlængder og antal punkter.
class BoardNoteLimits {
  static const int textMax = 500;
  static const int captionMax = 200;
  static const int checklistTitleMax = 80;
  static const int checklistItemMax = 100;
  static const int checklistItemsMax = 20;
}

/// Seddeltyper som de gemmes i Firestore-feltet `type`.
class BoardNoteType {
  static const String text = 'text';
  static const String photo = 'photo';
  static const String checklist = 'checklist';
}

sealed class BoardNote {
  final String id;
  final String authorId;
  final DateTime createdAt;
  final bool isPinned;

  const BoardNote({
    required this.id,
    required this.authorId,
    required this.createdAt,
    this.isPinned = false,
  });

  String get type;

  /// De felter, der er specifikke for seddeltypen.
  Map<String, dynamic> bodyToMap();

  Map<String, dynamic> toMap() => {
        'type': type,
        'authorId': authorId,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'isPinned': isPinned,
        ...bodyToMap(),
      };

  /// Læser en seddel fra Firestore. Returnerer `null` for ukendte typer og
  /// ugyldige data, så én defekt seddel ikke vælter hele tavlen.
  static BoardNote? fromMap(Map<String, dynamic> map, String id) {
    final authorId = map['authorId'];
    final createdAt = map['createdAt'];
    if (authorId is! String || authorId.isEmpty || createdAt is! int) {
      return null;
    }
    final isPinned = map['isPinned'] == true;
    final created = DateTime.fromMillisecondsSinceEpoch(createdAt);

    switch (map['type']) {
      case BoardNoteType.text:
        final text = map['text'];
        if (text is! String || text.trim().isEmpty) return null;
        return TextNote(
          id: id,
          authorId: authorId,
          createdAt: created,
          isPinned: isPinned,
          text: _clip(text, BoardNoteLimits.textMax),
        );
      case BoardNoteType.photo:
        final imageUrl = map['imageUrl'];
        if (imageUrl is! String || !PhotoNote.isAllowedImageUrl(imageUrl)) {
          return null;
        }
        final caption = map['caption'];
        return PhotoNote(
          id: id,
          authorId: authorId,
          createdAt: created,
          isPinned: isPinned,
          imageUrl: imageUrl,
          caption: caption is String ? _clip(caption, BoardNoteLimits.captionMax) : '',
        );
      case BoardNoteType.checklist:
        final title = map['title'];
        final rawItems = map['items'];
        if (title is! String || rawItems is! List) return null;
        final items = rawItems
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .take(BoardNoteLimits.checklistItemsMax)
            .map((s) => _clip(s, BoardNoteLimits.checklistItemMax))
            .toList();
        if (items.isEmpty) return null;
        final rawDone = map['done'];
        final done = rawDone is List
            ? rawDone.whereType<int>().where((i) => i >= 0 && i < items.length).toSet()
            : <int>{};
        return ChecklistNote(
          id: id,
          authorId: authorId,
          createdAt: created,
          isPinned: isPinned,
          title: _clip(title, BoardNoteLimits.checklistTitleMax),
          items: items,
          done: done,
        );
      default:
        return null;
    }
  }

  static String _clip(String s, int max) => s.length <= max ? s : s.substring(0, max);
}

class TextNote extends BoardNote {
  final String text;

  const TextNote({
    required super.id,
    required super.authorId,
    required super.createdAt,
    super.isPinned,
    required this.text,
  });

  @override
  String get type => BoardNoteType.text;

  @override
  Map<String, dynamic> bodyToMap() => {'text': text};
}

class PhotoNote extends BoardNote {
  final String imageUrl;
  final String caption;

  const PhotoNote({
    required super.id,
    required super.authorId,
    required super.createdAt,
    super.isPinned,
    required this.imageUrl,
    this.caption = '',
  });

  /// Kun billeder fra appens egen Firebase Storage må vises. Det forhindrer,
  /// at en seddel peger på en fremmed adresse (fx en sporingspixel).
  static bool isAllowedImageUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'https' && uri.host == 'firebasestorage.googleapis.com';
  }

  @override
  String get type => BoardNoteType.photo;

  @override
  Map<String, dynamic> bodyToMap() => {'imageUrl': imageUrl, 'caption': caption};
}

class ChecklistNote extends BoardNote {
  final String title;
  final List<String> items;

  /// Indeks i [items] for punkter, der er krydset af. Punkterne selv kan
  /// ikke ændres efter oprettelse – kun hvilke der er krydset af.
  final Set<int> done;

  const ChecklistNote({
    required super.id,
    required super.authorId,
    required super.createdAt,
    super.isPinned,
    required this.title,
    required this.items,
    this.done = const {},
  });

  /// Det nye `done`-sæt, når punkt [index] slås til eller fra.
  Set<int> toggled(int index) =>
      done.contains(index) ? ({...done}..remove(index)) : {...done, index};

  @override
  String get type => BoardNoteType.checklist;

  @override
  Map<String, dynamic> bodyToMap() => {
        'title': title,
        'items': items,
        'done': (done.toList()..sort()),
      };
}
