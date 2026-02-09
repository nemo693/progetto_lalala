import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Monitors network connectivity and exposes online/offline state.
///
/// Used to show an offline indicator on the map screen and to inform
/// the OfflineManager when to serve cached tiles.
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  final _controller = StreamController<bool>.broadcast();

  /// Broadcast stream that emits `true` when online, `false` when offline.
  Stream<bool> get onlineStream => _controller.stream;

  /// Initialize connectivity monitoring.
  /// Call once at app startup.
  Future<void> initialize() async {
    final results = await _connectivity.checkConnectivity();
    _isOnline = _hasInternet(results);

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final online = _hasInternet(results);
      if (online != _isOnline) {
        _isOnline = online;
        _controller.add(_isOnline);
      }
    });
  }

  bool _hasInternet(List<ConnectivityResult> results) {
    return results.any((r) =>
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet);
  }

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
