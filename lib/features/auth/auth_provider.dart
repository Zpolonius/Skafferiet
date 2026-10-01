import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      final credential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
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
      switch (e.code) {
        case 'user-not-found':
          return null;
        case 'invalid-email':
          return 'Ugyldig e-mailadresse.';
        case 'too-many-requests':
          return 'For mange forsøg. Vent lidt, og prøv igen.';
        case 'network-request-failed':
          return 'Ingen forbindelse. Tjek dit internet, og prøv igen.';
        default:
          return 'Mailen kunne ikke sendes. Prøv igen.';
      }
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
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
        case 'INVALID_LOGIN_CREDENTIALS':
          return 'Den nuværende adgangskode er forkert.';
        default:
          return _passwordErrorFor(e.code);
      }
    }

    try {
      await user.updatePassword(newPassword);
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') return 'Den nye adgangskode er for svag.';
      return _passwordErrorFor(e.code);
    }
  }

  String _passwordErrorFor(String code) {
    switch (code) {
      case 'too-many-requests':
        return 'For mange forsøg. Vent lidt, og prøv igen.';
      case 'network-request-failed':
        return 'Ingen forbindelse. Tjek dit internet, og prøv igen.';
      default:
        return 'Adgangskoden kunne ikke skiftes. Prøv igen.';
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

  String _mapError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found': return 'Ingen bruger fundet med denne e-mail.';
      case 'wrong-password': return 'Forkert adgangskode.';
      case 'email-already-in-use': return 'Denne e-mail er allerede i brug.';
      case 'weak-password': return 'Adgangskoden er for svag.';
      default: return 'Der skete en fejl. Prøv igen.';
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
