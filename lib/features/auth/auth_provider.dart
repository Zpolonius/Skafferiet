import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_error_messages.dart';

/// Navne gemmes med højst 100 tegn i firestore.rules; vi holder dem kortere,
/// så de kan vises på skærmen.
const maxDisplayNameLength = 50;

/// Firebase kræver mindst 6 tegn — samme grænse som ved oprettelse.
const minPasswordLength = 6;

class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;

  AuthState({this.user, this.isLoading = false, this.error});

  bool get isAuthenticated => user != null;

  AuthState copyWith({User? user, bool? isLoading, String? error}) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final FirebaseAuth _auth;
  final FirebaseFirestore? _firestore;

  AuthNotifier({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore,
        super(AuthState(user: (auth ?? FirebaseAuth.instance).currentUser)) {
    _init();
  }

  void _init() {
    _auth.authStateChanges().listen((user) {
      state = AuthState(user: user, isLoading: false);
    });
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true);
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(isLoading: false, error: _mapError(e));
    }
  }

  Future<void> signUp(String email, String password, String name) async {
    state = state.copyWith(isLoading: true);
    try {
      final credential =
          await _auth.createUserWithEmailAndPassword(email: email, password: password);
      // Opdater profil med navn
      await credential.user?.updateDisplayName(name);
      // Tving Firebase til at hente de nye profil-data (som navnet)
      await credential.user?.reload();
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(isLoading: false, error: _mapError(e));
    }
  }

  /// Sender en mail med et link til at nulstille adgangskoden. Returnerer en
  /// fejlbesked til brugeren, eller null hvis det lykkedes.
  ///
  /// Svaret afslører ikke, om e-mailen har en konto — ellers kunne funktionen
  /// bruges til at finde ud af, hvem der bruger appen.
  Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.setLanguageCode('da');
    } catch (_) {
      // Mailen sendes bare på engelsk.
    }
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      // Samme svar, uanset om e-mailen har en konto.
      if (e.code == 'user-not-found') return null;
      return authErrorMessage(e.code, fallback: 'Mailen kunne ikke sendes. Prøv igen.');
    }
  }

  /// Skifter brugerens navn både i login-kontoen og i profilen, som de andre
  /// i husstanden ser. Returnerer en fejlbesked eller null.
  Future<String?> updateDisplayName(String name) async {
    final user = _auth.currentUser;
    final clean = name.trim();
    if (user == null) return 'Du er ikke logget ind.';
    if (clean.isEmpty) return 'Indtast dit navn.';
    if (clean.length > maxDisplayNameLength) {
      return 'Navnet må højst være $maxDisplayNameLength tegn.';
    }

    try {
      await user.updateDisplayName(clean);
      await user.reload();
      final firestore = _firestore ?? FirebaseFirestore.instance;
      await firestore.collection('users').doc(user.uid).set({
        'displayName': clean,
      }, SetOptions(merge: true));
      state = AuthState(user: _auth.currentUser);
      return null;
    } catch (e) {
      return 'Navnet kunne ikke gemmes. Tjek din forbindelse, og prøv igen.';
    }
  }

  /// Skifter adgangskode. Firebase kræver, at man for nylig har logget ind,
  /// så vi beder om den nuværende adgangskode og logger ind igen med den først.
  /// Returnerer en fejlbesked eller null.
  Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) return 'Du er ikke logget ind.';

    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: currentPassword),
      );
    } on FirebaseAuthException catch (e) {
      return authErrorMessage(
        e.code,
        fallback: _passwordChangeFailed,
        overrides: const {
          'wrong-password': _currentPasswordWrong,
          'invalid-credential': _currentPasswordWrong,
          'INVALID_LOGIN_CREDENTIALS': _currentPasswordWrong,
        },
      );
    }

    try {
      await user.updatePassword(newPassword);
      return null;
    } on FirebaseAuthException catch (e) {
      return authErrorMessage(
        e.code,
        fallback: _passwordChangeFailed,
        overrides: const {'weak-password': 'Den nye adgangskode er for svag.'},
      );
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
  }

  Future<bool> updateProfilePhoto(String photoURL) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    state = state.copyWith(isLoading: true);
    try {
      await user.updatePhotoURL(photoURL);
      await user.reload();

      final firestore = _firestore ?? FirebaseFirestore.instance;
      await firestore.collection('users').doc(user.uid).set({
        'photoURL': photoURL,
      }, SetOptions(merge: true));

      state = state.copyWith(user: _auth.currentUser, isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Kunne ikke opdatere profilbillede.',
      );
      return false;
    }
  }

  Future<bool> removeProfilePhoto() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    state = state.copyWith(isLoading: true);
    try {
      await user.updatePhotoURL(null);
      await user.reload();

      final firestore = _firestore ?? FirebaseFirestore.instance;
      await firestore.collection('users').doc(user.uid).update({
        'photoURL': FieldValue.delete(),
      });

      state = state.copyWith(user: _auth.currentUser, isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Kunne ikke fjerne profilbillede.',
      );
      return false;
    }
  }

  static const _currentPasswordWrong = 'Den nuværende adgangskode er forkert.';
  static const _passwordChangeFailed = 'Adgangskoden kunne ikke skiftes. Prøv igen.';

  /// Ved login siges det ikke, om det var e-mailen eller adgangskoden, der
  /// var forkert — ellers kan man bruge login til at finde ud af, hvem der
  /// har en konto. (Firebase svarer selv 'invalid-credential' i begge tilfælde.)
  String _mapError(FirebaseAuthException e) => authErrorMessage(
        e.code,
        fallback: 'Der skete en fejl. Prøv igen.',
        overrides: const {
          'user-not-found': _wrongLogin,
          'wrong-password': _wrongLogin,
          'invalid-credential': _wrongLogin,
          'INVALID_LOGIN_CREDENTIALS': _wrongLogin,
        },
      );

  static const _wrongLogin = 'Forkert e-mail eller adgangskode.';
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
