import '../../features/grocery/grocery_defaults.dart';
import '../../shared/utils/number_format.dart';
import 'item_history.dart';

/// Resultatet af at læse en tekst som "2 l mælk": navn, og mængde/enhed hvis
/// brugeren skrev dem.
typedef QuickAddParse = ({String name, String? quantity, String? unit});

/// En vare klar til at komme på indkøbslisten fra hurtig-tilføj-feltet.
typedef QuickAddItem = ({
  String name,
  String category,
  String quantity,
  String unit,

  /// True når varen blev genkendt i husstandens historik.
  bool known,
});

/// Kategorien en vare får når historikken ikke kender den.
const quickAddFallbackCategory = 'Andet';
const quickAddFallbackQuantity = '1';
const quickAddFallbackUnit = 'stk';

/// Enheder der læses ud af teksten: dem fra formularerne plus de, opskrifter
/// også bruger.
const quickAddUnits = [...defaultGroceryUnits, 'dl', 'cl', 'ds', 'bdt', 'fl'];

// Mængde: heltal med ét tusindtalspunktum ("1.000", højst 999.999), eller op
// til 6 cifre + højst 3 decimaler. Efterfulgt af mellemrum eller direkte af resten ("500g").
// Lookahead'en sikrer at "12345678 x" ikke bliver til mængden 123456.
final _quantityPrefix = RegExp(
    r'^([1-9]\d{0,2}(?:\.\d{3})|\d{1,6}(?:[.,]\d{1,3})?)(?![\d.,])(\s*)(.+)$');

String _collapse(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

String? _matchUnit(String token, Iterable<String> units) {
  var t = token.toLowerCase();
  if (t.endsWith('.')) t = t.substring(0, t.length - 1);
  for (final u in units) {
    if (u.toLowerCase() == t) return u;
  }
  return null;
}

/// Læser det brugeren skrev i hurtig-tilføj-feltet.
///
/// * `2 l mælk` -> (mælk, 2, l), `500g ost` -> (ost, 500, g),
///   `1,5 kg kartofler` -> (kartofler, 1,5, kg)
/// * `2 mælk` -> (mælk, 2, ingen enhed) – kalderen vælger enheden
/// * Enheder kommer fra [units] og kendes uanset store/små bogstaver.
/// * Navnet må aldrig gå tabt: `2`, `l`, `2 l`, `500g` og `7up` er navne for
///   sig selv uden mængde. Navnets bogstaver ændres ikke.
QuickAddParse parseQuickAdd(
  String input, {
  Iterable<String> units = quickAddUnits,
}) {
  final text = _collapse(input);
  final whole = (name: text, quantity: null, unit: null);
  final m = _quantityPrefix.firstMatch(text);
  if (m == null) return whole;

  var numberText = m.group(1)!;
  // "1.000" er tusind på dansk; "1.5" er stadig halvanden.
  if (RegExp(r'^[1-9]\d{0,2}(\.\d{3})$').hasMatch(numberText)) {
    numberText = numberText.replaceAll('.', '');
  }
  final number = parseDanishNumber(numberText);
  if (number == null || number <= 0) return whole;
  final quantity = formatDanishNumber(number, maxDecimals: 3);
  final spaced = m.group(2)!.isNotEmpty;
  final rest = m.group(3)!;

  final firstSpace = rest.indexOf(' ');
  final token = firstSpace < 0 ? rest : rest.substring(0, firstSpace);
  final afterToken = firstSpace < 0 ? '' : rest.substring(firstSpace + 1);
  // "2 x mælk" og "2x mælk": x/× betyder bare "antal".
  if ((token == 'x' || token == '×') && afterToken.isNotEmpty) {
    return (name: afterToken, quantity: quantity, unit: null);
  }
  final unit = _matchUnit(token, units);
  if (unit != null) {
    // "2 l" og "500g" uden et navn efter enheden: hele teksten er navnet.
    if (afterToken.isEmpty) return whole;
    return (name: afterToken, quantity: quantity, unit: unit);
  }
  // Tallet skal stå for sig ("2 mælk"); "2mælk" og "7up" er bare et navn.
  if (!spaced) return whole;
  return (name: rest, quantity: quantity, unit: null);
}

String _capitalize(String s) =>
    s.isEmpty ? s : s.substring(0, 1).toUpperCase() + s.substring(1);

/// Navnet som det skal stå på listen: kendes det i [history], bruges dens
/// stavemåde; ellers får et nyt navn stort begyndelsesbogstav. Bruges af både
/// hurtig-tilføj og "Tilføj vare"-arket, så de er ens.
String canonicalItemName(String name, Iterable<ItemHistoryEntry> history) {
  final trimmed = _collapse(name);
  final key = itemHistoryKey(trimmed);
  if (key != null) {
    for (final e in history) {
      if (e.key == key) return e.name;
    }
  }
  return _capitalize(trimmed);
}

/// Gør en tekst til en vare: kendes navnet i [history], bruges dens stavemåde,
/// kategori, enhed og mængde – medmindre brugeren selv skrev mængde/enhed.
/// Ellers bliver det `Andet`, `1 stk` og navnet med stort begyndelsesbogstav.
/// Giver `null` for tom tekst eller et navn der er for langt.
QuickAddItem? resolveQuickAdd(
  String input,
  Iterable<ItemHistoryEntry> history, {
  Iterable<String> units = quickAddUnits,
}) {
  final byKey = {for (final e in history) e.key: e};
  // Hele teksten først: en vare der hedder "2 minutes nudler" er et navn.
  final wholeKey = itemHistoryKey(_collapse(input));
  final wholeHit = wholeKey == null ? null : byKey[wholeKey];
  final parsed = wholeHit != null
      ? (name: wholeHit.name, quantity: null, unit: null)
      : parseQuickAdd(input, units: units);
  final key = itemHistoryKey(parsed.name);
  if (key == null || parsed.name.length > ItemHistoryLimits.maxName) {
    return null;
  }
  final hit = wholeHit ?? byKey[key];
  return (
    name: hit?.name ?? _capitalize(parsed.name),
    known: hit != null,
    category: hit?.category ?? quickAddFallbackCategory,
    quantity: parsed.quantity ?? hit?.quantity ?? quickAddFallbackQuantity,
    unit: parsed.unit ?? hit?.unit ?? quickAddFallbackUnit,
  );
}

/// En vare fra historikken (et tryk på et forslag), evt. med mængde/enhed
/// brugeren allerede har skrevet.
QuickAddItem quickAddFromHistory(
  ItemHistoryEntry e, {
  String? quantity,
  String? unit,
}) =>
    (
      name: e.name,
      category: e.category,
      quantity: quantity ?? e.quantity ?? quickAddFallbackQuantity,
      unit: unit ?? e.unit ?? quickAddFallbackUnit,
      known: true,
    );
