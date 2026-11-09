import '../../core/models/recipe_units.dart';
import '../../shared/utils/number_format.dart';

/// Mængden på en indkøbsvare: [text] vises i chippen, [spoken] læses op af
/// skærmlæsere ("500 gram" i stedet for "500 g").
typedef GroceryQuantityLabel = ({String text, String spoken});

/// Bygger mængde-chippen for en vare. Null betyder at varen ikke har en
/// mængde, og så vises der ingen chip.
///
/// Gemte mængder kan være "2.0" (fra opskrifter), "1,5", "½" eller tomme.
/// Tal vises på dansk uden overflødige decimaler, tekst vises som den er
/// skrevet. Mængden 0 regnes som ingen mængde, ligesom i opskriftsformularen.
GroceryQuantityLabel? groceryQuantityLabel(String quantity, String? unit) {
  final raw = quantity.trim();
  if (raw.isEmpty) return null;
  final value = parseDanishNumber(raw);
  if (value == 0) return null;
  final number =
      value == null ? raw : formatDanishNumber(value, maxDecimals: 3);

  final u = unit == null ? '' : canonicalUnit(unit);
  if (u.isEmpty) return (text: number, spoken: number);

  // "1 liter" i ental, men "1,5 liter" og "2 pakker" i flertal.
  final plural = value == null || value != 1;
  final spokenUnit = unitSpokenName(u, plural: plural);
  return (text: '$number $u', spoken: '$number $spokenUnit');
}
