import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/auth/login_screen.dart';

class _MockAuthNotifier extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _MockAuthNotifier() : super(AuthState());
}

void main() {
  late _MockAuthNotifier auth;

  setUp(() => auth = _MockAuthNotifier());

  Future<void> pumpLogin(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [authProvider.overrideWith((ref) => auth)],
      child: const MaterialApp(home: LoginScreen()),
    ));
  }

  testWidgets('Glemt adgangskode udfylder e-mailen og bekræfter afsendelsen', (tester) async {
    when(() => auth.sendPasswordReset(any())).thenAnswer((_) async => null);
    await pumpLogin(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'E-mail'), 'mig@example.com');
    await tester.tap(find.text('Glemt adgangskode?'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('mig@example.com')), findsOneWidget);

    await tester.tap(find.text('Send link'));
    await tester.pumpAndSettle();

    verify(() => auth.sendPasswordReset('mig@example.com')).called(1);
    expect(find.text('Tjek din indbakke'), findsOneWidget);
  });

  testWidgets('Glemt adgangskode validerer e-mailen før afsendelse', (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.text('Glemt adgangskode?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send link'));
    await tester.pumpAndSettle();

    expect(find.text('Indtast din e-mail'), findsOneWidget);
    verifyNever(() => auth.sendPasswordReset(any()));
  });

  testWidgets('fejl vises i dialogen, så brugeren kan prøve igen', (tester) async {
    when(() => auth.sendPasswordReset(any()))
        .thenAnswer((_) async => 'For mange forsøg. Vent lidt, og prøv igen.');
    await pumpLogin(tester);

    await tester.tap(find.text('Glemt adgangskode?'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)),
        'mig@example.com');
    await tester.tap(find.text('Send link'));
    await tester.pumpAndSettle();

    expect(find.text('For mange forsøg. Vent lidt, og prøv igen.'), findsOneWidget);
    expect(find.text('Send link'), findsOneWidget);
  });

  testWidgets('privatlivspolitikken kan findes fra login og oprettelse', (tester) async {
    await pumpLogin(tester);
    expect(find.text('Privatlivspolitik'), findsOneWidget);

    await tester.tap(find.text('Tilmeld dig'));
    await tester.pumpAndSettle();
    expect(find.textContaining('accepterer du privatlivspolitikken'), findsOneWidget);
  });
}
