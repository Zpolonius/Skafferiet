// Skriver privatlivspolitikken fra appen til docs/PRIVACY_POLICY.md.
//
//   dart run tool/export_privacy_policy.dart

import 'dart:io';

import 'package:skafferiet/features/legal/privacy_policy_content.dart';

void main() {
  File('docs/PRIVACY_POLICY.md').writeAsStringSync(privacyPolicyMarkdown());
  stdout.writeln('Skrev docs/PRIVACY_POLICY.md');
}
