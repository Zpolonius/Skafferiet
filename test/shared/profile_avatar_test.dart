import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';
import 'package:skafferiet/shared/widgets/profile_avatar.dart';

class _MockUser extends Mock implements User {}

class _MockAuthNotifier extends StateNotifier<AuthState> with Mock implements AuthNotifier {
  _MockAuthNotifier(super.state);
}

void main() {
  testWidgets('ProfileAvatar shows initial letter when photoURL is null', (tester) async {
    final mockUser = _MockUser();
    when(() => mockUser.displayName).thenReturn('Sofia');
    when(() => mockUser.photoURL).thenReturn(null);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _MockAuthNotifier(AuthState(user: mockUser))),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(child: ProfileAvatar()),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('S'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });

  testWidgets('ProfileAvatar shows CachedNetworkImage when photoURL is present', (tester) async {
    final mockUser = _MockUser();
    when(() => mockUser.displayName).thenReturn('Sofia');
    when(() => mockUser.photoURL).thenReturn('https://example.com/avatar.jpg');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _MockAuthNotifier(AuthState(user: mockUser))),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(child: ProfileAvatar()),
          ),
        ),
      ),
    );

    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });
}
