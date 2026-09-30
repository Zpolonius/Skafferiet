import 'package:flutter/services.dart';

/// Læser et tal skrevet af brugeren. Accepterer både dansk komma ("1,5")
/// og punktum ("1.5"). Returnerer null ved tom, ugyldig eller negativ værdi.
double? parseDanishNumber(String input) {
  final text = input.trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final value = double.tryParse(text);
  if (value == null || !value.isFinite || value < 0) return null;
  return value;
}

/// Viser et tal på dansk uden overflødige decimaler: 400 → "400", 1.5 → "1,5".
String formatDanishNumber(double value, {int maxDecimals = 1}) {
  var text = value.toStringAsFixed(maxDecimals);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return text.replaceAll('.', ',');
}

/// Tillader kun cifre og ét decimaltegn (komma eller punktum) i tal-felter.
final List<TextInputFormatter> decimalInputFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*$')),
  LengthLimitingTextInputFormatter(8),
];
