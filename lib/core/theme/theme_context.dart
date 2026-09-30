import 'package:flutter/material.dart';

/// Kort vej til temaets farver: `context.colors.primary` i stedet for
/// `Theme.of(context).colorScheme.primary`.
extension ThemeContext on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
}

/// Farver oven på fotos (opskriftskort, profilbillede). Et foto skifter ikke
/// farve med temaet, så tekst og skygge ovenpå må heller ikke gøre det.
abstract final class PhotoOverlay {
  static const Color foreground = Color(0xFFFFFFFF);
  static const Color scrim = Color(0xFF000000);
}
