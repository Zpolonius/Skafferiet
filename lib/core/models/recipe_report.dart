/// Højst så mange tegn i den valgfri kommentar til en rapport (samme grænse
/// som i firestore.rules).
const maxReportCommentLength = 500;

/// Hvorfor en delt opskrift rapporteres. [key] gemmes i Firestore og valideres
/// af firestore.rules; [label] er teksten brugeren ser.
enum ReportReason {
  offensive('offensive', 'Upassende eller stødende indhold'),
  spam('spam', 'Spam eller reklame'),
  wrongInfo(
      'wrong_info', 'Forkerte oplysninger (ingredienser, mængder, næring)'),
  copyright('copyright', 'Kopieret uden tilladelse (tekst eller billede)'),
  other('other', 'Andet');

  final String key;
  final String label;
  const ReportReason(this.key, this.label);
}

/// En forfatter brugeren har blokeret. Gemmes kun hos brugeren selv
/// (`users/{uid}/blocked_authors/{authorUid}`).
class BlockedAuthor {
  /// Forfatterens bruger-ID (`Recipe.createdBy`).
  final String uid;

  /// Forfatterens fornavn, som det blev vist, da blokeringen blev lavet.
  final String name;

  const BlockedAuthor({required this.uid, required this.name});
}
