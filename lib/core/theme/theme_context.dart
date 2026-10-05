import 'package:flutter/material.dart';

/// Kort vej til Kitchen Harmony-temaet: `context.colors.primary` og
/// `context.text.titleMedium` i stedet for `Theme.of(context).colorScheme…`.
/// Brug dem i stedet for `AppColors`, `Colors.*` og `GoogleFonts` i widgets —
/// så følger alt temaet (og en dag også mørkt tema).
extension ThemeContext on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}
