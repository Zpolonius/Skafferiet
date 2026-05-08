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
}
