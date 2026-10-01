import 'package:flutter/material.dart';

import 'privacy_policy_content.dart';

/// Viser privatlivspolitikken. Kan åbnes både før og efter login.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Privatlivspolitik')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(privacyPolicyTitle, style: text.headlineSmall),
            for (final section in privacyPolicySections) ...[
              const SizedBox(height: 24),
              Text(
                section.title,
                style: text.titleMedium?.copyWith(color: colors.primary),
              ),
              const SizedBox(height: 8),
              for (final line in section.lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: line.startsWith('• ')
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('•  ', style: text.bodyMedium),
                            Expanded(
                              child: SelectableText(line.substring(2),
                                  style: text.bodyMedium),
                            ),
                          ],
                        )
                      : SelectableText(line, style: text.bodyMedium),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
