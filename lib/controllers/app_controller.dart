import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/utils/logger.dart';
import '../services/media_projection_service.dart';
import '../services/overlay_service.dart';
import '../services/permission_service.dart';

/// Lifecycle state of each pipeline stage, mirrored by the status cards.
enum ServiceStatus { idle, granted, denied, running, error }

/// Central application state for the MVP pipeline.
///
/// Owns the Flutter services and translates their results into status
/// card state. The UI only reads this controller and calls its intents;
/// it never touches MethodChannels directly.
class AppController extends ChangeNotifier {
  static const _tag = 'AppController';

  final PermissionService _permissions = PermissionService();
  final MediaProjectionService _mediaProjection = MediaProjectionService();
  final OverlayService _overlay = OverlayService();

  // ─── Pipeline statuses ───────────────────────────────────────────
  ServiceStatus screenCaptureStatus = ServiceStatus.idle;
  ServiceStatus overlayStatus = ServiceStatus.idle;
  ServiceStatus ocrStatus = ServiceStatus.idle;
  ServiceStatus translationStatus = ServiceStatus.idle;

  bool _isTranslating = false;
  bool get isTranslating => _isTranslating;

  /// Last pipeline error, surfaced to the UI as a SnackBar message.
  String? lastError;

  /// Whether the device supports MediaProjection at all.
  bool captureAvailable = false;

  // ─── Status sync ─────────────────────────────────────────────────
  /// Re-queries real native state. Safe to call on app init and resume —
  /// this is what keeps the status cards honest after the user returns
  /// from system permission screens.
  Future<void> refreshStatuses() async {
    final overlayGranted = await _overlay.checkOverlayPermission();
    overlayStatus =
        overlayGranted ? ServiceStatus.granted : ServiceStatus.idle;
    captureAvailable =
        await _mediaProjection.checkScreenCaptureAvailability();
    AppLogger.info(
      'refreshStatuses: overlayGranted=$overlayGranted '
      'captureAvailable=$captureAvailable',
      tag: _tag,
    );
    notifyListeners();
  }

  // ─── Intents ─────────────────────────────────────────────────────
  /// Requests runtime permissions, then refreshes card state from truth.
  Future<void> requestPermissions() async {
    await _permissions.requestNotifications();
    await _permissions.requestOverlay();
    await refreshStatuses();
  }

  /// Step 5 handshake: checks overlay permission, then exercises the
  /// native channel methods in pipeline order. Capture (Step 6) and the
  /// overlay window (Step 9) answer NOT_IMPLEMENTED for now; on any
  /// failure we run idempotent cleanup so native state stays consistent.
  ///
  /// Returns an error message for the UI, or null once the real
  /// pipeline starts successfully (future steps).
  Future<String?> startTranslation() async {
    lastError = null;

    if (!await _overlay.checkOverlayPermission()) {
      overlayStatus = ServiceStatus.idle;
      lastError = 'Grant "Display over other apps" first.';
      AppLogger.warning('startTranslation aborted: $lastError', tag: _tag);
      notifyListeners();
      return lastError;
    }
    overlayStatus = ServiceStatus.granted;

    String? failure;
    try {
      await _overlay.showOverlay(); // Step 9 implements the window.
    } on PlatformException catch (e) {
      failure = e.message;
    }
    try {
      await _mediaProjection.startScreenCapture(); // Step 6 implements.
    } on PlatformException catch (e) {
      failure = e.message;
    }

    if (failure != null) {
      await _overlay.hideOverlay();
      await _mediaProjection.stopScreenCapture();
      lastError = failure;
      notifyListeners();
      return failure;
    }

    _isTranslating = true;
    screenCaptureStatus = ServiceStatus.running;
    ocrStatus = ServiceStatus.running;
    translationStatus = ServiceStatus.running;
    AppLogger.info('Translation pipeline started', tag: _tag);
    notifyListeners();
    return null;
  }

  /// Stops the pipeline and resets stage statuses.
  Future<void> stopTranslation() async {
    if (!_isTranslating) return;
    await _mediaProjection.stopScreenCapture();
    await _overlay.hideOverlay();
    _isTranslating = false;
    screenCaptureStatus = ServiceStatus.idle;
    ocrStatus = ServiceStatus.idle;
    translationStatus = ServiceStatus.idle;
    AppLogger.info('Translation pipeline stopped', tag: _tag);
    notifyListeners();
  }
}
