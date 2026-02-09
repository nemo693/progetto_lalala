import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the app process alive during tile downloads by running an Android
/// foreground service with a persistent notification.
///
/// Without this, the OS will throttle network requests and eventually kill
/// the app when the screen is locked or the user switches to another app.
///
/// Usage:
///   await DownloadForegroundService.start();
///   // ... download tiles, update notification with updateProgress() ...
///   await DownloadForegroundService.stop();
class DownloadForegroundService {
  static bool _initialized = false;

  /// Initialize the foreground task configuration. Called once.
  static void _ensureInitialized() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'tile_download',
        channelName: 'Map Download',
        channelDescription: 'Downloading offline map tiles',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
  }

  /// Start the foreground service with a download notification.
  static Future<void> start() async {
    _ensureInitialized();
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'AlpineNav',
      notificationText: 'Downloading map tiles...',
      callback: _downloadServiceCallback,
    );
  }

  /// Update the notification with download progress.
  static void updateProgress(double percent) {
    final pct = (percent * 100).toStringAsFixed(0);
    FlutterForegroundTask.updateService(
      notificationText: 'Downloading map tiles... $pct%',
    );
  }

  /// Stop the foreground service.
  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }
}

// Top-level callback required by flutter_foreground_task.
// Must be a top-level or static function.
@pragma('vm:entry-point')
void _downloadServiceCallback() {
  FlutterForegroundTask.setTaskHandler(_NoOpTaskHandler());
}

/// No-op task handler — we only need the foreground service to keep the
/// process alive; no periodic work is done in the service isolate.
class _NoOpTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
