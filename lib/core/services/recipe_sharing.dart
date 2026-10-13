/// Fornavn til visning på en delt opskrift: første ord i navnet, højst 40
/// UTF-16-enheder (reglerne i firestore.rules tæller sådan; et surrogatpar
/// splittes aldrig). Mangler navnet, ligner det en e-mailadresse (profilen
/// falder tilbage til e-mailen) eller kunne udgive sig for appen
/// ("Skafferiet", "Support", "Admin", "Moderator"), bruges "Ukendt".
String authorFirstName(String? displayName) {
  final name = (displayName ?? '').trim();
  if (name.isEmpty || name.contains('@')) return unknownAuthorName;
  var first = name.split(RegExp(r'\s+')).first;
  if (first.length > maxAuthorNameLength) {
    var end = maxAuthorNameLength;
    final last = first.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--; // halvt surrogatpar
    first = first.substring(0, end);
  }
  if (first.isEmpty || isReservedAuthorName(first)) return unknownAuthorName;
  return first;
}

const unknownAuthorName = 'Ukendt';

/// Samme grænse som i firestore.rules (`authorName`).
const maxAuthorNameLength = 40;

const _reservedWords = ['skafferiet', 'support', 'admin', 'moderator'];

/// Navne der ikke må bruges som forfatter (samme liste som i firestore.rules).
bool isReservedAuthorName(String name) {
  final lower = name.toLowerCase();
  return _reservedWords.any(lower.contains);
}
