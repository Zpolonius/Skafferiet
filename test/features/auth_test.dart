import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skafferiet/features/auth/auth_provider.dart';

void main() {
  group('AuthNotifier Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('Initial state is unauthenticated', () {
      final state = container.read(authProvider);
      expect(state.isAuthenticated, false);
      expect(state.isLoading, false);
    });

    test('login sets isAuthenticated to true', () async {
      final notifier = container.read(authProvider.notifier);
      await notifier.login('test@example.com', 'password');
      
      final state = container.read(authProvider);
      expect(state.isAuthenticated, true);
    });

    test('logout resets state', () async {
      final notifier = container.read(authProvider.notifier);
      await notifier.login('test@example.com', 'password');
      notifier.logout();
      
      final state = container.read(authProvider);
      expect(state.isAuthenticated, false);
    });
  });
}
