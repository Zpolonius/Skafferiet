import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  final FirebaseAuth _auth = FirebaseAuth.instance;

  AuthNotifier() : super(AuthState(isLoading: true)) {
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
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(isLoading: false, error: _mapError(e));
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
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
