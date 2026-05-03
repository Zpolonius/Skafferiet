import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthState {
  final bool isAuthenticated;
  final String? email;
  final bool isLoading;

  AuthState({
    this.isAuthenticated = false,
    this.email,
    this.isLoading = false,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    String? email,
    bool? isLoading,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      email: email ?? this.email,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState());

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true);
    // Simuler netværkskald til Firebase
    await Future.delayed(const Duration(seconds: 2));
    state = state.copyWith(
      isAuthenticated: true,
      email: email,
      isLoading: false,
    );
  }

  void logout() {
    state = AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
