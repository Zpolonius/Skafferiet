import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/shared/widgets/settings_list.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: child)),
      );

  testWidgets('SettingsGroup sætter skillelinjer mellem rækkerne, ikke rundt om', (tester) async {
    await pump(tester, const SettingsGroup(children: [Text('a'), Text('b'), Text('c')]));

    expect(find.byType(Divider), findsNWidgets(2));
  });

  testWidgets('SettingsTile uden onTap er slået fra', (tester) async {
    await pump(tester, const SettingsTile(icon: Icons.star, title: 'Fra'));

    expect(tester.widget<ListTile>(find.byType(ListTile)).enabled, false);
  });

  testWidgets('destruktive rækker bruger temaets fejlfarve', (tester) async {
    var tapped = false;
    await pump(
      tester,
      SettingsTile(
        icon: Icons.delete_outline,
        title: 'Slet',
        destructive: true,
        onTap: () => tapped = true,
      ),
    );

    final error = AppTheme.lightTheme.colorScheme.error;
    expect(tester.widget<Icon>(find.byIcon(Icons.delete_outline)).color, error);
    expect(tester.widget<Text>(find.text('Slet')).style?.color, error);
    await tester.tap(find.text('Slet'));
    expect(tapped, true);
  });

  testWidgets('showResultSnackBar viser fejl i temaets fejlfarve', (tester) async {
    await pump(tester, const SizedBox());
    final context = tester.element(find.byType(SizedBox));
    final colors = Theme.of(context).colorScheme;

    showResultSnackBar(ScaffoldMessenger.of(context), colors, error: 'Det gik galt', success: 'OK');
    await tester.pump();

    expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, colors.error);
    expect(find.text('Det gik galt'), findsOneWidget);
    expect(find.text('OK'), findsNothing);
  });
}
