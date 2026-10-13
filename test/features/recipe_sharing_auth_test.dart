// Deling af opskrifter (#51): hvem er "mig" når brugeren skifter, og hvad
// delings-valget siger til den, der ikke selv har lavet opskriften.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skafferiet/core/theme/app_theme.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/features/recipes/recipe_form_widgets.dart';
import 'package:skafferiet/features/recipes/recipes_provider.dart';

class _Auth extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _Auth(User? user) : super(AuthState(user: user));
  void signInAs(User? user) => state = AuthState(user: user);
}

Widget _switch({required bool canShare, required bool value}) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: ShareRecipeSwitch(
          canShare: canShare,
          value: value,
          onChanged: (_) {},
        ),
      ),
    );

void main() {
  test('currentUserIdProvider følger med, når en anden bruger logger ind', () {
    final auth = _Auth(MockUser(uid: 'anna'));
    final container = ProviderContainer(
      overrides: [authProvider.overrideWith((ref) => auth)],
    );
    addTearDown(container.dispose);

    expect(container.read(currentUserIdProvider), 'anna');
    auth.signInAs(null);
    expect(container.read(currentUserIdProvider), isNull);
    auth.signInAs(MockUser(uid: 'bo'));
    expect(container.read(currentUserIdProvider), 'bo');
  });

  testWidgets(
      'en delt opskrift fortæller ikke-skaberen, at navnet er skaberens',
      (tester) async {
    await tester.pumpWidget(_switch(canShare: false, value: true));
    expect(find.textContaining('dit fornavn'), findsNothing);
    expect(find.textContaining('skaberens fornavn'), findsOneWidget);
    expect(find.textContaining('Du kan slå deling fra'), findsOneWidget);
  });

  testWidgets('skaberen får at vide, at kun husstanden kan redigere',
      (tester) async {
    await tester.pumpWidget(_switch(canShare: true, value: true));
    expect(find.textContaining('dit fornavn'), findsOneWidget);
    expect(find.textContaining('Andre kan ikke redigere'), findsNothing);
    expect(
        find.textContaining('Kun jeres husstand kan redigere'), findsOneWidget);
  });
}
