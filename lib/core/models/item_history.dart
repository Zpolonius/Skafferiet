import 'package:cloud_firestore/cloud_firestore.dart';

/// Grænser for en historikpost. Samme som for indkøbsvarer og faste varer, og
/// de skal holdes i trit med `firestore.rules` (`item_history`).
class ItemHistoryLimits {
  static const maxName = 80;
  static const maxCategory = 40;
  static const maxUnit = 20;
  static const maxQuantity = 10;

  /// Hvor mange af de senest brugte varer der hentes og søges i.
  static const maxEntries = 500;

  /// Hvor mange forslag der vises ad gangen.
  static const maxSuggestions = 5;
}

/// Historikkens nøgle for et varenavn: små bogstaver, trimmet og med enkelt
/// mellemrum (`Hakket  Oksekød ` -> `hakket oksekød`). Nøglen bruges som
/// Firestore-dokument-id, så den må hverken indeholde `/`, være `.`/`..` eller
/// ligne `__navn__`. Giver `null` for et tomt navn – så skrives der ingen
/// historik.
String? itemHistoryKey(String name) {
  var key = name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  if (key.isEmpty) return null;
  key = key.replaceAll(
      '/', '\u2215'); // ∕ (divisionsstreg) – '/' er ikke tilladt i et id
  if (key == '.' || key == '..' || RegExp(r'^__.*__$').hasMatch(key)) {
    key = '~$key';
  }
  return key;
}

/// Én vare husstanden tidligere har brugt, så den kan foreslås igen.
class ItemHistoryEntry {
  final String key;
  final String name;
  final String category;
  final String? unit;
  final String? quantity;
  final int useCount;
  final DateTime? lastUsed;

  const ItemHistoryEntry({
    required this.key,
    required this.name,
    required this.category,
    this.unit,
    this.quantity,
    this.useCount = 1,
    this.lastUsed,
  });

  /// `null` hvis dokumentet mangler navn eller kategori (så ignoreres det).
  static ItemHistoryEntry? fromMap(String key, Map<String, dynamic> map) {
    final name = map['name'];
    final category = map['category'];
    if (name is! String || name.trim().isEmpty) return null;
    if (category is! String || category.trim().isEmpty) return null;
    final unit = map['unit'];
    final quantity = map['quantity'];
    final lastUsed = map['lastUsed'];
    final useCount = map['useCount'];
    return ItemHistoryEntry(
      key: key,
      name: name,
      category: category,
      unit: unit is String && unit.isNotEmpty ? unit : null,
      quantity: quantity is String && quantity.isNotEmpty ? quantity : null,
      useCount: useCount is int ? useCount : 1,
      lastUsed: lastUsed is Timestamp ? lastUsed.toDate() : null,
    );
  }
}

String _normalizeQuery(String s) =>
    s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

final _wordSeparator = RegExp(r'[\s\-/,.()]+');

/// Op til [limit] forslag til det brugeren har skrevet. Matcher på starten af
/// et ord (`hak` og `oks` finder begge `Hakket oksekød`), uanset store/små
/// bogstaver. Mest brugte først, derefter senest brugte. En vare der er
/// identisk med det skrevne foreslås ikke (så er der intet at hjælpe med).
List<ItemHistoryEntry> suggestItems(
  Iterable<ItemHistoryEntry> entries,
  String query, {
  int limit = ItemHistoryLimits.maxSuggestions,
}) {
  final q = _normalizeQuery(query);
  if (q.isEmpty) return const [];

  bool matches(ItemHistoryEntry e) {
    final name = _normalizeQuery(e.name);
    if (name == q) return false;
    final words =
        name.split(_wordSeparator).where((w) => w.isNotEmpty).toList();
    // Søgningen kan række over flere ord ("hakket ok"), så hvert ordstart
    // sammenlignes med resten af navnet derfra.
    var offset = 0;
    for (final word in words) {
      final start = name.indexOf(word, offset);
      offset = start + word.length;
      if (name.substring(start).startsWith(q)) return true;
    }
    return false;
  }

  final hits = entries.where(matches).toList()
    ..sort((a, b) {
      final byCount = b.useCount.compareTo(a.useCount);
      if (byCount != 0) return byCount;
      final al = a.lastUsed, bl = b.lastUsed;
      if (al != null && bl != null) {
        final byTime = bl.compareTo(al);
        if (byTime != 0) return byTime;
      } else if (al != null) {
        return -1;
      } else if (bl != null) {
        return 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return hits.take(limit).toList();
}

/// Egne kategorier fra historikken, dvs. dem der ikke er standardkategorier.
/// Unikke og alfabetisk.
List<String> customCategoriesFrom(
  Iterable<ItemHistoryEntry> entries,
  Iterable<String> defaults,
) {
  final known = defaults.toSet();
  final result = {
    for (final e in entries)
      if (!known.contains(e.category)) e.category,
  }.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return result;
}
