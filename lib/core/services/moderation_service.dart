import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/recipe_report.dart';
import 'recipe_sharing.dart';

/// Rapportering og blokering af delte opskrifter (#52).
///
/// * Rapporter ligger i `reports/{recipeId}_{uid}`: højst én pr. bruger pr.
///   opskrift, og en ny rapport overskriver den gamle. Kun brugeren selv kan
///   læse sine rapporter; administratoren gennemgår dem i Firebase-konsollen.
/// * Blokeringer ligger i `users/{uid}/blocked_authors/{authorUid}`, kun synlige
///   for brugeren selv (profilen kan læses af husstanden, så de ligger ikke dér).
class ModerationService {
  final FirebaseFirestore _firestore;
  final String? _uid;

  ModerationService(
      {required FirebaseFirestore firestore, required String? uid})
      : _firestore = firestore,
        _uid = uid;

  String get _requireUid {
    final uid = _uid;
    if (uid == null) throw StateError('Du skal være logget ind');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _blocked => _firestore
      .collection('users')
      .doc(_requireUid)
      .collection('blocked_authors');

  /// ID på de opskrifter brugeren har rapporteret (de skjules for brugeren).
  Stream<Set<String>> watchReportedRecipeIds() {
    final uid = _uid;
    if (uid == null) return Stream.value(const {});
    return _firestore
        .collection('reports')
        .where('reportedBy', isEqualTo: uid)
        .snapshots()
        .map((snap) => {
              for (final d in snap.docs)
                if (d.data()['recipeId'] is String)
                  d.data()['recipeId'] as String,
            });
  }

  /// De forfattere brugeren har blokeret, nyeste først.
  Stream<List<BlockedAuthor>> watchBlockedAuthors() {
    if (_uid == null) return Stream.value(const []);
    return _blocked.snapshots().map((snap) {
      final docs = snap.docs.toList()
        ..sort((a, b) {
          final ta = a.data()['blockedAt'];
          final tb = b.data()['blockedAt'];
          if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
          return 0;
        });
      return [
        for (final d in docs)
          BlockedAuthor(
              uid: d.id, name: authorFirstName(d.data()['name'] as String?)),
      ];
    });
  }

  /// Rapporterer [recipeId]. En tidligere rapport fra samme bruger overskrives.
  Future<void> reportRecipe({
    required String recipeId,
    required ReportReason reason,
    String comment = '',
  }) {
    final uid = _requireUid;
    final text = comment.trim();
    if (text.length > maxReportCommentLength) {
      throw ArgumentError('Kommentaren er for lang');
    }
    return _firestore.collection('reports').doc('${recipeId}_$uid').set({
      'recipeId': recipeId,
      'reportedBy': uid,
      'reason': reason.key,
      'comment': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Skjuler alle opskrifter fra [authorUid] for brugeren. [name] er
  /// forfatterens fornavn, så blokeringen kan vises i profilen.
  Future<void> blockAuthor({required String authorUid, required String? name}) {
    return _blocked.doc(authorUid).set({
      'name': authorFirstName(name),
      'blockedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unblockAuthor(String authorUid) =>
      _blocked.doc(authorUid).delete();
}
