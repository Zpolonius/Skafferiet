import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/theme/app_colors.dart';
import 'package:skafferiet/core/theme/app_theme.dart';

void main() {
  test('temaets colorScheme er præcis designsystemets farver', () {
    final s = AppTheme.colorScheme;
    final pairs = <String, (Color, Color)>{
      'primary': (s.primary, AppColors.primary),
      'onPrimary': (s.onPrimary, AppColors.onPrimary),
      'primaryContainer': (s.primaryContainer, AppColors.primaryContainer),
      'onPrimaryContainer': (s.onPrimaryContainer, AppColors.onPrimaryContainer),
      'secondary': (s.secondary, AppColors.secondary),
      'onSecondary': (s.onSecondary, AppColors.onSecondary),
      'secondaryContainer': (s.secondaryContainer, AppColors.secondaryContainer),
      'onSecondaryContainer': (s.onSecondaryContainer, AppColors.onSecondaryContainer),
      'tertiary': (s.tertiary, AppColors.tertiary),
      'onTertiary': (s.onTertiary, AppColors.onTertiary),
      'tertiaryContainer': (s.tertiaryContainer, AppColors.tertiaryContainer),
      'onTertiaryContainer': (s.onTertiaryContainer, AppColors.onTertiaryContainer),
      'error': (s.error, AppColors.error),
      'onError': (s.onError, AppColors.onError),
      'errorContainer': (s.errorContainer, AppColors.errorContainer),
      'onErrorContainer': (s.onErrorContainer, AppColors.onErrorContainer),
      'surface': (s.surface, AppColors.surface),
      'onSurface': (s.onSurface, AppColors.onSurface),
      'onSurfaceVariant': (s.onSurfaceVariant, AppColors.onSurfaceVariant),
      'surfaceDim': (s.surfaceDim, AppColors.surfaceDim),
      'surfaceBright': (s.surfaceBright, AppColors.surfaceBright),
      'surfaceContainerLowest': (s.surfaceContainerLowest, AppColors.surfaceContainerLowest),
      'surfaceContainerLow': (s.surfaceContainerLow, AppColors.surfaceContainerLow),
      'surfaceContainer': (s.surfaceContainer, AppColors.surfaceContainer),
      'surfaceContainerHigh': (s.surfaceContainerHigh, AppColors.surfaceContainerHigh),
      'surfaceContainerHighest': (s.surfaceContainerHighest, AppColors.surfaceContainerHighest),
      'outline': (s.outline, AppColors.outline),
      'outlineVariant': (s.outlineVariant, AppColors.outlineVariant),
      'inverseSurface': (s.inverseSurface, AppColors.inverseSurface),
      'onInverseSurface': (s.onInverseSurface, AppColors.inverseOnSurface),
      'inversePrimary': (s.inversePrimary, AppColors.inversePrimary),
      'surfaceTint': (s.surfaceTint, AppColors.surfaceTint),
      'primaryFixed': (s.primaryFixed, AppColors.primaryFixed),
      'primaryFixedDim': (s.primaryFixedDim, AppColors.primaryFixedDim),
      'onPrimaryFixed': (s.onPrimaryFixed, AppColors.onPrimaryFixed),
      'onPrimaryFixedVariant': (s.onPrimaryFixedVariant, AppColors.onPrimaryFixedVariant),
      'secondaryFixed': (s.secondaryFixed, AppColors.secondaryFixed),
      'secondaryFixedDim': (s.secondaryFixedDim, AppColors.secondaryFixedDim),
      'onSecondaryFixed': (s.onSecondaryFixed, AppColors.onSecondaryFixed),
      'onSecondaryFixedVariant': (s.onSecondaryFixedVariant, AppColors.onSecondaryFixedVariant),
      'tertiaryFixed': (s.tertiaryFixed, AppColors.tertiaryFixed),
      'tertiaryFixedDim': (s.tertiaryFixedDim, AppColors.tertiaryFixedDim),
      'onTertiaryFixed': (s.onTertiaryFixed, AppColors.onTertiaryFixed),
      'onTertiaryFixedVariant': (s.onTertiaryFixedVariant, AppColors.onTertiaryFixedVariant),
    };
    final wrong = pairs.entries.where((e) => e.value.$1 != e.value.$2).map((e) => e.key).toList();
    expect(wrong, isEmpty, reason: 'Disse roller i AppTheme matcher ikke AppColors');
  });

  test('ingen hardcodede farver uden for lib/core/theme', () {
    // Tilladt: Colors.transparent (ikke en farve). Alt andet skal via
    // context.colors (temaet) eller PhotoOverlay (tekst oven på fotos).
    final forbidden = RegExp(r'AppColors\.|Color\(0x|Colors\.(?!transparent\b)\w+');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final path = f.path.replaceAll('\\', '/');
      if (!path.endsWith('.dart') || path.startsWith('lib/core/theme/')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        if (forbidden.hasMatch(line)) offenders.add('$path:${i + 1}: ${line.trim()}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'Brug context.colors.<rolle> i stedet (se lib/core/theme/theme_context.dart).');
  });
}
