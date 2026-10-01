import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Kitchen Harmony-reglen (CLAUDE.md): farver og skrifter hentes fra temaet
// (`context.colors` / `context.text`) — aldrig hårdkodet. Kun temaet selv må
// kende de konkrete værdier.
const _checked = ['lib'];
const _themeDefinition = [
  'lib/core/theme/app_theme.dart',
  'lib/core/theme/app_colors.dart',
];

final _forbidden = {
  RegExp(r'\bColors\.(?!transparent\b)\w+'): 'Colors.* — brug colorScheme',
  RegExp(r'\bColor\(0x'): 'Color(0x…) — brug colorScheme',
  RegExp(r'\bAppColors\.'): 'AppColors.* — brug colorScheme',
  RegExp(r'\bGoogleFonts\.'): 'GoogleFonts.* — brug textTheme',
};

void main() {
  test('ingen widgets hårdkoder farver eller skrifter — alt går gennem temaet', () {
    final files = <File>[
      for (final path in _checked) ...Directory(path).listSync(recursive: true).whereType<File>(),
    ].where((f) => f.path.endsWith('.dart') && !_themeDefinition.contains(f.path));

    final violations = <String>[];
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        _forbidden.forEach((pattern, hint) {
          if (pattern.hasMatch(line)) violations.add('${file.path}:${i + 1}  $hint');
        });
      }
    }

    expect(files, isNotEmpty);
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
