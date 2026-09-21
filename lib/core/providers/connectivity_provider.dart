import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/connectivity_service.dart';

/// Represents the high-level connection state of the app for UI presentation.
enum NetworkStatus {
  /// The app is online with active network connectivity.
  online,

  /// The app is offline (no network connection).
  offline,

  /// The app was previously offline and has just re-established connection.
  reconnected,
}

/// Provider for the abstract [ConnectivityService]. Can be overridden in tests.
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityPlusService();
});

/// Manages UI connectivity status transitions and auto-dismiss timers.
class ConnectivityNotifier extends StateNotifier<NetworkStatus> {
  final ConnectivityService _service;
  final Duration reconnectDisplayDuration;
  StreamSubscription<bool>? _subscription;
  Timer? _reconnectTimer;
  bool _wasOffline = false;

  ConnectivityNotifier({
    required ConnectivityService service,
    this.reconnectDisplayDuration = const Duration(seconds: 3),
  })  : _service = service,
        super(NetworkStatus.online) {
    _init();
  }

  Future<void> _init() async {
    final connected = await _service.isConnected();
    if (!mounted) return;
    if (!connected) {
      _wasOffline = true;
      state = NetworkStatus.offline;
    }
    _subscription = _service.onConnectivityChanged.listen(_handleConnectionChange);
  }

  void _handleConnectionChange(bool isConnected) {
    if (!isConnected) {
      _wasOffline = true;
      _reconnectTimer?.cancel();
      state = NetworkStatus.offline;
    } else if (_wasOffline) {
      _wasOffline = false;
      state = NetworkStatus.reconnected;
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(reconnectDisplayDuration, () {
        if (mounted) {
          state = NetworkStatus.online;
        }
      });
    } else {
      state = NetworkStatus.online;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _reconnectTimer?.cancel();
    super.dispose();
  }
}

/// Main state provider for network status.
final connectivityProvider =
    StateNotifierProvider<ConnectivityNotifier, NetworkStatus>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return ConnectivityNotifier(service: service);
});

/// Convenience provider returning true when the app is currently offline.
final isOfflineProvider = Provider<bool>((ref) {
  return ref.watch(connectivityProvider) == NetworkStatus.offline;
});
