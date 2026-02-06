import 'dart:async';
import 'dart:io' show Platform;
import 'package:geolocator/geolocator.dart';

/// GPS location handling: permissions, one-shot position, continuous stream.
///
/// Wraps the geolocator package. Exposes a [positionStream] that the UI
/// subscribes to for live location updates.
///
/// When [startListening] is called with `foreground: true` (used during
/// track recording), on Android the stream is backed by a foreground service
/// with a persistent notification so the OS keeps delivering GPS fixes even
/// when the app is in the background.
class LocationService {
  StreamSubscription<Position>? _subscription;
  final _positionController = StreamController<Position>.broadcast();

  /// Broadcast stream of GPS positions. Subscribe from the UI layer.
  Stream<Position> get positionStream => _positionController.stream;

  /// Whether the current stream uses a foreground service.
  bool _isForegroundActive = false;
  bool get isForegroundActive => _isForegroundActive;

  /// Check whether location services are enabled and permissions are granted.
  /// Returns null if ready, or an error message describing the problem.
  Future<String?> checkPermissions() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Location services are disabled. Enable them in system settings.';
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return 'Location permission denied.';
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return 'Location permission permanently denied. '
          'Enable it in app settings.';
    }

    return null; // All good
  }

  /// Get a single position fix.
  Future<Position?> getCurrentPosition() async {
    final error = await checkPermissions();
    if (error != null) return null;

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
  }

  /// Start continuous GPS updates.
  ///
  /// [highAccuracy] — true for track recording (uses more battery),
  /// false for passive display.
  /// [distanceFilter] — minimum distance in meters between updates.
  /// [foreground] — if true AND on Android, starts a foreground service with
  /// a persistent notification so GPS continues in the background.
  /// Use this when recording a track.
  Future<void> startListening({
    bool highAccuracy = false,
    int distanceFilter = 5,
    bool foreground = false,
  }) async {
    final error = await checkPermissions();
    if (error != null) return;

    // Cancel any existing subscription
    await stopListening();

    final accuracy =
        highAccuracy ? LocationAccuracy.best : LocationAccuracy.high;

    late final LocationSettings settings;

    if (foreground && Platform.isAndroid) {
      // Android foreground service: keeps GPS alive when app is backgrounded.
      // The geolocator_android package shows a persistent notification and
      // holds a partial wake-lock so the CPU stays on for GPS callbacks.
      settings = AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'AlpineNav — Recording track',
          notificationText: 'GPS tracking is active',
          notificationChannelName: 'GPS Track Recording',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
      _isForegroundActive = true;
    } else {
      settings = LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      );
      _isForegroundActive = false;
    }

    _subscription =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        _positionController.add(position);
      },
      onError: (error) {
        // Stream errors are non-fatal; the stream continues.
        // The UI can show a stale-position indicator if updates stop.
      },
    );
  }

  /// Stop continuous GPS updates (also stops the foreground service if active).
  Future<void> stopListening() async {
    await _subscription?.cancel();
    _subscription = null;
    _isForegroundActive = false;
  }

  /// Open the device location settings (for the "denied forever" case).
  Future<bool> openSettings() => Geolocator.openLocationSettings();

  /// Clean up.
  void dispose() {
    _subscription?.cancel();
    _positionController.close();
  }
}
