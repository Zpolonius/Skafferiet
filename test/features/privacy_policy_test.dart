import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/features/legal/privacy_policy_content.dart';
import 'package:skafferiet/features/legal/privacy_policy_screen.dart';

void main() {
  test('docs/PRIVACY_POLICY.md er i trit med teksten i appen', () {
    // Fejler den: kør `dart run tool/export_privacy_policy.dart`.
    expect(File('docs/PRIVACY_POLICY.md').readAsStringSync(), privacyPolicyMarkdown());
  });

  test('politikken nævner det Apple og GDPR kræver', () {
    final text = privacyPolicyMarkdown();
    expect(text, contains('Slet konto'));
    expect(text, contains('Datatilsynet'));
    expect(text, contains('Google Firebase'));
  });

  testWidgets('skærmen viser alle afsnit', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyScreen()));

    for (final section in privacyPolicySections) {
      // .first: SelectableText har sine egne Scrollables inde i listen.
      await tester.scrollUntilVisible(find.text(section.title), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(section.title), findsOneWidget);
    }
  });
}
