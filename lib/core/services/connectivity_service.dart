import 'package:connectivity_plus/connectivity_plus.dart';

/// Abstract service defining the network connectivity contract (ISP & DIP).
abstract class ConnectivityService {
  /// Returns whether the device currently has an active network connection.
  Future<bool> isConnected();

  /// Stream emitting changes to the connection state (true = connected, false = disconnected).
  Stream<bool> get onConnectivityChanged;
}

/// Production implementation of [ConnectivityService] using [connectivity_plus].
class ConnectivityPlusService implements ConnectivityService {
  final Connectivity _connectivity;

  ConnectivityPlusService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  @override
  Future<bool> isConnected() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return _isOnline(results);
    } catch (_) {
      // Fail-safe: antag online hvis platform-check fejler
      return true;
    }
  }

  @override
  Stream<bool> get onConnectivityChanged {
    return _connectivity.onConnectivityChanged.map(_isOnline);
  }

  bool _isOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    if (results.contains(ConnectivityResult.none)) return false;
    return results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet ||
        r == ConnectivityResult.vpn ||
        r == ConnectivityResult.other);
  }
}
