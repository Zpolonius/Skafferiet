import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skafferiet/main.dart';
import 'package:skafferiet/features/auth/login_screen.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:mocktail/mocktail.dart';


class MockAuthNotifier extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  MockAuthNotifier() : super(AuthState(isLoading: false));
}

void main() {
  testWidgets('App starts on LoginScreen', (WidgetTester tester) async {
    final mockAuthNotifier = MockAuthNotifier();
    
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => mockAuthNotifier),
        ],
        child: const MyApp(),
      ),
    );

    // Vent på at routeren initialiserer
    await tester.pumpAndSettle();

    // Verificer at vi ser login-skærmen (velkomst-tekst)
    expect(find.text('Velkommen tilbage'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
