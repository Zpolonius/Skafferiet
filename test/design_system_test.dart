import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Kitchen Harmony-reglen (CLAUDE.md): farver og skrifter hentes fra
// Theme.of(context) — aldrig hårdkodet. Testen holder de filer, der allerede
// følger reglen, rene. Når en ældre skærm er lagt om, tilføjes den her.
const _followsDesignSystem = [
  'lib/features/profile',
  'lib/features/legal',
  'lib/features/onboarding/household_setup_widgets.dart',
  'lib/shared/widgets/confirm_dialog.dart',
  'lib/shared/widgets/settings_list.dart',
];

final _forbidden = {
  RegExp(r'\bColors\.(?!transparent\b)\w+'): 'Colors.* — brug colorScheme',
  RegExp(r'\bColor\(0x'): 'Color(0x…) — brug colorScheme',
  RegExp(r'\bAppColors\.'): 'AppColors.* — brug colorScheme',
  RegExp(r'\bGoogleFonts\.'): 'GoogleFonts.* — brug textTheme',
};

void main() {
  test('skærme der følger designsystemet, hårdkoder ikke farver eller skrifter', () {
    final files = <File>[
      for (final path in _followsDesignSystem)
        if (FileSystemEntity.isDirectorySync(path))
          ...Directory(path).listSync(recursive: true).whereType<File>()
        else
          File(path),
    ].where((f) => f.path.endsWith('.dart'));

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
