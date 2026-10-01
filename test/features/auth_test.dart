import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skafferiet/features/auth/auth_error_messages.dart';
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

  group('skift navn og adgangskode', () {
    late MockFirebaseAuth mockAuth;
    late MockUser mockUser;

    setUpAll(() {
      registerFallbackValue(EmailAuthProvider.credential(email: 'x', password: 'y'));
    });

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockUser = MockUser();
      when(() => mockAuth.authStateChanges()).thenAnswer((_) => const Stream.empty());
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.uid).thenReturn('me');
      when(() => mockUser.email).thenReturn('me@example.com');
    });

    test('nyt navn gemmes i login-kontoen og i profilen', () async {
      final db = FakeFirebaseFirestore();
      when(() => mockUser.updateDisplayName(any())).thenAnswer((_) async {});
      when(() => mockUser.reload()).thenAnswer((_) async {});
      final notifier = AuthNotifier(auth: mockAuth, firestore: db);

      expect(await notifier.updateDisplayName('  Nyt Navn '), isNull);

      verify(() => mockUser.updateDisplayName('Nyt Navn')).called(1);
      expect((await db.doc('users/me').get()).data()?['displayName'], 'Nyt Navn');
    });

    test('tomt eller for langt navn afvises uden at skrive', () async {
      final notifier = AuthNotifier(auth: mockAuth, firestore: FakeFirebaseFirestore());

      expect(await notifier.updateDisplayName('   '), 'Indtast dit navn.');
      expect(await notifier.updateDisplayName('x' * 51), 'Navnet må højst være 50 tegn.');
      verifyNever(() => mockUser.updateDisplayName(any()));
    });

    test('adgangskode: logger ind igen med den nuværende og sætter den nye', () async {
      when(() => mockUser.reauthenticateWithCredential(any()))
          .thenAnswer((_) async => MockUserCredential());
      when(() => mockUser.updatePassword(any())).thenAnswer((_) async {});
      final notifier = AuthNotifier(auth: mockAuth);

      expect(await notifier.changePassword(currentPassword: 'gammel', newPassword: 'ny-kode'), isNull);

      final credential = verify(() => mockUser.reauthenticateWithCredential(captureAny()))
          .captured.single as AuthCredential;
      expect(credential.providerId, 'password');
      verify(() => mockUser.updatePassword('ny-kode')).called(1);
    });

    test('forkert nuværende adgangskode: den nye sættes ikke', () async {
      when(() => mockUser.reauthenticateWithCredential(any()))
          .thenThrow(FirebaseAuthException(code: 'invalid-credential'));
      final notifier = AuthNotifier(auth: mockAuth);

      expect(
        await notifier.changePassword(currentPassword: 'forkert', newPassword: 'ny-kode'),
        'Den nuværende adgangskode er forkert.',
      );
      verifyNever(() => mockUser.updatePassword(any()));
    });

    test('for svag ny adgangskode giver en forståelig besked', () async {
      when(() => mockUser.reauthenticateWithCredential(any()))
          .thenAnswer((_) async => MockUserCredential());
      when(() => mockUser.updatePassword(any()))
          .thenThrow(FirebaseAuthException(code: 'weak-password'));
      final notifier = AuthNotifier(auth: mockAuth);

      expect(
        await notifier.changePassword(currentPassword: 'gammel', newPassword: '123456'),
        'Den nye adgangskode er for svag.',
      );
    });
  });

  group('fejlbeskeder', () {
    test('samme fejl giver samme besked overalt — med mulighed for en egen formulering', () {
      expect(authErrorMessage('too-many-requests', fallback: 'x'),
          'For mange forsøg. Vent lidt, og prøv igen.');
      expect(authErrorMessage('ukendt-kode', fallback: 'Prøv igen.'), 'Prøv igen.');
      expect(
        authErrorMessage('weak-password', fallback: 'x', overrides: {'weak-password': 'Egen'}),
        'Egen',
      );
    });

    for (final code in ['user-not-found', 'wrong-password', 'invalid-credential']) {
      test('login afslører ikke, om e-mailen har en konto ($code)', () async {
        final mockAuth = MockFirebaseAuth();
        when(() => mockAuth.authStateChanges()).thenAnswer((_) => const Stream.empty());
        when(() => mockAuth.currentUser).thenReturn(null);
        when(() => mockAuth.signInWithEmailAndPassword(
              email: any(named: 'email'),
              password: any(named: 'password'),
            )).thenThrow(FirebaseAuthException(code: code));
        final notifier = AuthNotifier(auth: mockAuth);

        await notifier.login('x@example.com', 'forkert');

        expect(notifier.state.error, 'Forkert e-mail eller adgangskode.');
      });
    }
  });
}
