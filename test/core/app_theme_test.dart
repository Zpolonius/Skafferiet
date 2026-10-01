import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/theme/app_colors.dart';
import 'package:skafferiet/core/theme/app_theme.dart';

// Temaet skal dække alle roller, Flutter selv bruger — ellers falder fx
// dialogtitler og ListTile-tekst tilbage til Roboto og Material-standardfarver
// i stedet for Kitchen Harmony (design/kitchen_harmony/DESIGN.md).

void main() {
  // testWidgets frem for test: Google Fonts forsøger at hente skrifterne i
  // baggrunden, og det tåler kun widget-testmiljøet.
  ThemeData theme() => AppTheme.lightTheme;

  testWidgets('overskrifter bruger Plus Jakarta Sans, al anden tekst Be Vietnam Pro',
      (tester) async {
    final t = theme().textTheme;
    final headings = {
      'displayLarge': t.displayLarge,
      'displayMedium': t.displayMedium,
      'displaySmall': t.displaySmall,
      'headlineLarge': t.headlineLarge,
      'headlineMedium': t.headlineMedium,
      'headlineSmall': t.headlineSmall,
      'titleLarge': t.titleLarge,
      'titleMedium': t.titleMedium,
      'titleSmall': t.titleSmall,
    };
    final body = {
      'bodyLarge': t.bodyLarge,
      'bodyMedium': t.bodyMedium,
      'bodySmall': t.bodySmall,
      'labelLarge': t.labelLarge,
      'labelMedium': t.labelMedium,
      'labelSmall': t.labelSmall,
    };
    headings.forEach(
        (role, style) => expect(style?.fontFamily, startsWith('PlusJakartaSans'), reason: role));
    body.forEach(
        (role, style) => expect(style?.fontFamily, startsWith('BeVietnamPro'), reason: role));
  });

  testWidgets('typografien fra DESIGN.md', (tester) async {
    final t = theme().textTheme;
    expect(t.displayLarge?.fontSize, 32); // h1
    expect(t.displayMedium?.fontSize, 24); // h2
    expect(t.bodyLarge?.fontSize, 18); // body-lg
    expect(t.bodyMedium?.fontSize, 16); // body-md
    expect(t.labelSmall?.fontSize, 13); // label-sm
  });

  testWidgets('alle flade-roller er designets farver, ikke nogen fromSeed har fundet på',
      (tester) async {
    final c = theme().colorScheme;
    expect(c.primary, AppColors.primary);
    expect(c.secondary, AppColors.secondary);
    expect(c.error, AppColors.error);
    expect(c.surface, AppColors.surface);
    expect(c.surfaceContainerLowest, AppColors.surfaceContainerLowest);
    expect(c.surfaceContainerLow, AppColors.surfaceContainerLow);
    expect(c.surfaceContainer, AppColors.surfaceContainer);
    expect(c.surfaceContainerHigh, AppColors.surfaceContainerHigh);
    expect(c.surfaceContainerHighest, AppColors.surfaceContainerHighest);
    expect(c.primaryFixed, AppColors.primaryFixed);
    expect(c.onPrimaryFixedVariant, AppColors.onPrimaryFixedVariant);
    expect(c.tertiaryFixed, AppColors.tertiaryFixed);
  });

  testWidgets('dialoger er hvide (niveau 2 i DESIGN.md)', (tester) async {
    expect(theme().dialogTheme.backgroundColor, Colors.white);
  });
}
