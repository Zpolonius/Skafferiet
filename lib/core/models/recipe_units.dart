import '../../shared/utils/number_format.dart';

/// Standardenheder der vises som valg, når man tilføjer en ingrediens.
/// Dækker også de enheder, start-opskrifterne bruger.
const List<String> recipeUnits = [
  'g',
  'kg',
  'ml',
  'dl',
  'l',
  'stk',
  'tsk',
  'spsk',
  'fed',
  'dåse',
  'bdt',
  'potte',
  'pk',
];

/// Maks. længde for en selvvalgt enhed ("Anden").
const int maxCustomUnitLength = 12;

// Faktor til gram (vægt) eller milliliter (rumfang).
// tsk og spsk er de danske standardmål: 5 ml og 15 ml.
const Map<String, double> _weightFactors = {'g': 1, 'kg': 1000};
const Map<String, double> _volumeFactors = {
  'ml': 1,
  'cl': 10,
  'dl': 100,
  'l': 1000,
  'tsk': 5,
  'spsk': 15,
};

String _normalize(String unit) => unit.trim().toLowerCase();

/// True hvis enheden er et rumfang (næring angives så pr. 100 ml).
bool isVolumeUnit(String unit) => _volumeFactors.containsKey(_normalize(unit));

/// True hvis mængden kan omregnes til gram eller ml, så næring pr. 100 kan bruges.
bool canConvertUnit(String unit) {
  final u = _normalize(unit);
  return _weightFactors.containsKey(u) || _volumeFactors.containsKey(u);
}

/// Omregner en mængde til gram eller ml. Null hvis enheden ikke kan omregnes
/// (fx "stk" eller "fed", hvor vægten afhænger af varen).
double? toGramsOrMl(double quantity, String unit) {
  final u = _normalize(unit);
  final factor = _weightFactors[u] ?? _volumeFactors[u];
  return factor == null ? null : quantity * factor;
}

/// Enheden med store/små bogstaver og mellemrum fjernet, som den står i
/// [recipeUnits]: "G " -> "g". Ukendte enheder beholdes, som de er skrevet.
String canonicalUnit(String unit) {
  final trimmed = unit.trim();
  for (final u in recipeUnits) {
    if (u.toLowerCase() == trimmed.toLowerCase()) return u;
  }
  return trimmed;
}

final _amountPattern = RegExp(r'^(\d+(?:[.,]\d+)?)\s*(.*)$');

/// Mængdeteksten fra et frit felt ("400g", "1,5 kg", "2 store", "efter smag")
/// som mængde og enhed til en [Ingredient].
///
/// * Tallet læses med [parseDanishNumber] (komma eller punktum).
/// * Kendte enheder skrives som i [recipeUnits] ("400 G" -> 400 g); et tal
///   uden enhed bliver "stk"; en anden kort enhed ("2 store") beholdes.
/// * Uden et læsbart tal større end 0 er mængden 0 (= ingen mængde, som i
///   opskriftsformularen) og enheden tom; teksten kommer så i [note], så den
///   ikke går tabt. Er enheden for lang, bliver den "stk" og teksten en note.
({double quantity, String unit, String? note}) parseIngredientAmount(
    String input) {
  final text = input.trim().replaceAll(RegExp(r'\s+'), ' ');
  final m = _amountPattern.firstMatch(text);
  final number = m == null ? null : parseDanishNumber(m.group(1)!);
  if (m == null || number == null || number <= 0) {
    return (quantity: 0, unit: '', note: text.isEmpty ? null : text);
  }
  final rest = m.group(2)!.trim();
  if (rest.isEmpty) return (quantity: number, unit: 'stk', note: null);
  final known = canonicalUnit(rest);
  if (recipeUnits.contains(known) || canConvertUnit(known)) {
    return (quantity: number, unit: known.toLowerCase(), note: null);
  }
  if (rest.length <= maxCustomUnitLength) {
    return (quantity: number, unit: rest, note: null);
  }
  return (quantity: number, unit: 'stk', note: rest);
}

// Oplæsning for skærmlæsere: (ental, flertal). Forkortelser som "tsk" og
// "spsk" læses ikke som bogstaver.
const Map<String, (String, String)> _spokenUnits = {
  'g': ('gram', 'gram'),
  'kg': ('kilogram', 'kilogram'),
  'ml': ('milliliter', 'milliliter'),
  'cl': ('centiliter', 'centiliter'),
  'dl': ('deciliter', 'deciliter'),
  'l': ('liter', 'liter'),
  'tsk': ('teskefuld', 'teskefulde'),
  'spsk': ('spiseskefuld', 'spiseskefulde'),
  'pk': ('pakke', 'pakker'),
  'bdt': ('bundt', 'bundter'),
  'dåse': ('dåse', 'dåser'),
  'potte': ('potte', 'potter'),
};

/// Enheden skrevet ud til oplæsning: "g" -> "gram", "tsk" -> "teskefulde" (ved
/// flertal). Enheder uden navn her, fx "stk" eller "fed", læses som de står.
String unitSpokenName(String unit, {required bool plural}) {
  final canonical = canonicalUnit(unit);
  final names = _spokenUnits[canonical.toLowerCase()];
  if (names == null) return canonical;
  return plural ? names.$2 : names.$1;
}
