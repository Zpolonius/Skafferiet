import '../../core/models/board_note.dart';

/// Opslagstavlens regler samlet ét sted, så formularen og provideren
/// validerer ens. Firestore-reglerne håndhæver de samme grænser på serveren.
class BoardPolicy {
  /// Fejltekst til en tekstseddel, eller `null` hvis teksten er gyldig.
  static String? validateText(String text) {
    final t = text.trim();
    if (t.isEmpty) return 'Skriv noget på sedlen';
    if (t.length > BoardNoteLimits.textMax) {
      return 'Højst ${BoardNoteLimits.textMax} tegn';
    }
    return null;
  }

  static String? validateCaption(String caption) {
    if (caption.trim().length > BoardNoteLimits.captionMax) {
      return 'Højst ${BoardNoteLimits.captionMax} tegn';
    }
    return null;
  }

  static String? validateChecklist(String title, List<String> items) {
    final t = title.trim();
    if (t.isEmpty) return 'Giv listen en overskrift';
    if (t.length > BoardNoteLimits.checklistTitleMax) {
      return 'Overskriften må højst være ${BoardNoteLimits.checklistTitleMax} tegn';
    }
    final filled = cleanItems(items);
    if (filled.isEmpty) return 'Tilføj mindst ét punkt';
    if (filled.length > BoardNoteLimits.checklistItemsMax) {
      return 'Højst ${BoardNoteLimits.checklistItemsMax} punkter';
    }
    if (filled.any((i) => i.length > BoardNoteLimits.checklistItemMax)) {
      return 'Hvert punkt må højst være ${BoardNoteLimits.checklistItemMax} tegn';
    }
    return null;
  }

  /// Punkterne uden tomme linjer og overflødige mellemrum.
  static List<String> cleanItems(List<String> items) =>
      items.map((i) => i.trim()).where((i) => i.isNotEmpty).toList();

  /// Forfatteren og husstandens admin må slette en seddel.
  static bool canDelete(BoardNote note, {String? currentUid, String? adminUid}) {
    if (currentUid == null) return false;
    return note.authorId == currentUid || adminUid == currentUid;
  }

  /// Fastgjorte sedler først, derefter nyeste først.
  static List<BoardNote> sorted(Iterable<BoardNote> notes) {
    return notes.toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
  }
}
