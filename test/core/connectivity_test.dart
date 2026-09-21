import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:skafferiet/core/services/connectivity_service.dart';
import 'package:skafferiet/core/providers/connectivity_provider.dart';

class MockConnectivity extends Mock implements Connectivity {}

class FakeConnectivityService implements ConnectivityService {
  bool isConnectedValue = true;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  @override
  Future<bool> isConnected() async => isConnectedValue;

  @override
  Stream<bool> get onConnectivityChanged => _controller.stream;

  void emit(bool connected) {
    _controller.add(connected);
  }

  void dispose() {
    _controller.close();
  }
}

void main() {
  group('ConnectivityPlusService mapping', () {
    late MockConnectivity mockConnectivity;
    late ConnectivityPlusService service;

    setUp(() {
      mockConnectivity = MockConnectivity();
      service = ConnectivityPlusService(connectivity: mockConnectivity);
    });

    test('isConnected returns true when wifi is available', () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);

      final result = await service.isConnected();
      expect(result, isTrue);
    });

    test('isConnected returns true when mobile is available', () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.mobile]);

      final result = await service.isConnected();
      expect(result, isTrue);
    });

    test('isConnected returns false when none is present', () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.none]);

      final result = await service.isConnected();
      expect(result, isFalse);
    });

    test('isConnected returns false when empty list', () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => []);

      final result = await service.isConnected();
      expect(result, isFalse);
    });

    test('isConnected returns true on exception as fail-safe', () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenThrow(Exception('Platform error'));

      final result = await service.isConnected();
      expect(result, isTrue);
    });
  });

  group('ConnectivityNotifier', () {
    late FakeConnectivityService fakeService;

    setUp(() {
      fakeService = FakeConnectivityService();
    });

    tearDown(() {
      fakeService.dispose();
    });

    test('Initializes with online status when service is connected', () async {
      fakeService.isConnectedValue = true;
      final notifier = ConnectivityNotifier(service: fakeService);

      // Await microtasks to let _init complete
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state, NetworkStatus.online);
      notifier.dispose();
    });

    test('Initializes with offline status when service is disconnected', () async {
      fakeService.isConnectedValue = false;
      final notifier = ConnectivityNotifier(service: fakeService);

      await Future<void>.delayed(Duration.zero);

      expect(notifier.state, NetworkStatus.offline);
      notifier.dispose();
    });

    test('Transitions from online to offline on connection drop', () async {
      fakeService.isConnectedValue = true;
      final notifier = ConnectivityNotifier(service: fakeService);
      await Future<void>.delayed(Duration.zero);

      fakeService.emit(false);
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state, NetworkStatus.offline);
      notifier.dispose();
    });

    test('Transitions from offline to reconnected, and auto-dismisses to online', () async {
      fakeService.isConnectedValue = false;
      const duration = Duration(milliseconds: 100);
      final notifier = ConnectivityNotifier(
        service: fakeService,
        reconnectDisplayDuration: duration,
      );
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state, NetworkStatus.offline);

      // Reconnect
      fakeService.emit(true);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state, NetworkStatus.reconnected);

      // Wait for the auto-dismiss timer
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(notifier.state, NetworkStatus.online);
      notifier.dispose();
    });
  });
}
