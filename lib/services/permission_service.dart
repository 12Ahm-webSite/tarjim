import 'package:permission_handler/permission_handler.dart';

import '../core/utils/logger.dart';

/// Runtime permission requests (permission_handler plugin).
///
/// Note: MediaProjection consent is NOT here — it must go through the
/// native MediaProjectionManager dialog (Step 6), not permission_handler.
class PermissionService {
  static const _tag = 'PermissionService';

  /// Opens the system "Display over other apps" settings screen and
  /// completes after the user returns. True when granted.
  Future<bool> requestOverlay() async {
    AppLogger.info('Requesting SYSTEM_ALERT_WINDOW', tag: _tag);
    final status = await Permission.systemAlertWindow.request();
    AppLogger.info('Overlay permission → $status', tag: _tag);
    return status.isGranted;
  }

  /// POST_NOTIFICATIONS — lets the capture foreground service show its
  /// mandatory ongoing notification on Android 13+.
  Future<bool> requestNotifications() async {
    AppLogger.info('Requesting POST_NOTIFICATIONS', tag: _tag);
    final status = await Permission.notification.request();
    AppLogger.info('Notification permission → $status', tag: _tag);
    return status.isGranted;
  }
}
