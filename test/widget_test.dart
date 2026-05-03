import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skafferiet/main.dart';
import 'package:skafferiet/features/auth/login_screen.dart';

void main() {
  testWidgets('App starts on LoginScreen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: MyApp(),
      ),
    );

    // Vent på at routeren initialiserer
    await tester.pumpAndSettle();

    // Verificer at vi ser login-skærmen (velkomst-tekst)
    expect(find.text('Velkommen tilbage'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
