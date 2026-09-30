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
