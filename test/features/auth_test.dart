import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}
class MockUser extends Mock implements User {}
class MockUserCredential extends Mock implements UserCredential {}

void main() {
  group('AuthNotifier Tests', () {
    late MockFirebaseAuth mockAuth;
    late MockUser mockUser;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockUser = MockUser();
      
      when(() => mockAuth.authStateChanges()).thenAnswer((_) => Stream.value(null));
    });

    test('Initial state is unauthenticated', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => AuthNotifier(auth: mockAuth)),
        ],
      );

      // Initial state should NOT be loading by default in the constructor
      final state = container.read(authProvider);
      expect(state.isLoading, false);
      
      // Wait for init to finish
      await Future.delayed(Duration.zero);
      
      final stateAfterInit = container.read(authProvider);
      expect(stateAfterInit.isAuthenticated, false);
      expect(stateAfterInit.isLoading, false);
    });

    test('login sets user when successful', () async {
      when(() => mockAuth.signInWithEmailAndPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      )).thenAnswer((_) async => MockUserCredential());
      
      // Update stream to emit user after login
      when(() => mockAuth.authStateChanges()).thenAnswer((_) => Stream.value(mockUser));

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => AuthNotifier(auth: mockAuth)),
        ],
      );

      final notifier = container.read(authProvider.notifier);
      await notifier.login('test@example.com', 'password');
      
      // Wait for async state update from authStateChanges
      await Future.delayed(Duration.zero);
      
      final state = container.read(authProvider);
      expect(state.isAuthenticated, true);
    });
  });

  group('sendPasswordReset', () {
    late MockFirebaseAuth mockAuth;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      when(() => mockAuth.authStateChanges()).thenAnswer((_) => const Stream.empty());
      when(() => mockAuth.currentUser).thenReturn(null);
      when(() => mockAuth.setLanguageCode(any())).thenAnswer((_) async {});
    });

    test('sender mailen på dansk og returnerer null', () async {
      when(() => mockAuth.sendPasswordResetEmail(email: any(named: 'email')))
          .thenAnswer((_) async {});
      final notifier = AuthNotifier(auth: mockAuth);

      expect(await notifier.sendPasswordReset(' mig@example.com '), isNull);
      verify(() => mockAuth.setLanguageCode('da')).called(1);
      verify(() => mockAuth.sendPasswordResetEmail(email: 'mig@example.com')).called(1);
    });

    test('afslører ikke om e-mailen har en konto', () async {
      when(() => mockAuth.sendPasswordResetEmail(email: any(named: 'email')))
          .thenThrow(FirebaseAuthException(code: 'user-not-found'));
      final notifier = AuthNotifier(auth: mockAuth);

      expect(await notifier.sendPasswordReset('findes.ikke@example.com'), isNull);
    });

    test('ugyldig e-mail giver en besked', () async {
      when(() => mockAuth.sendPasswordResetEmail(email: any(named: 'email')))
          .thenThrow(FirebaseAuthException(code: 'invalid-email'));
      final notifier = AuthNotifier(auth: mockAuth);

      expect(await notifier.sendPasswordReset('x'), 'Ugyldig e-mailadresse.');
    });

    test('sender stadig, hvis sproget ikke kan sættes', () async {
      when(() => mockAuth.setLanguageCode(any())).thenThrow(Exception('ikke understøttet'));
      when(() => mockAuth.sendPasswordResetEmail(email: any(named: 'email')))
          .thenAnswer((_) async {});
      final notifier = AuthNotifier(auth: mockAuth);

      expect(await notifier.sendPasswordReset('mig@example.com'), isNull);
      verify(() => mockAuth.sendPasswordResetEmail(email: 'mig@example.com')).called(1);
    });
  });
}
