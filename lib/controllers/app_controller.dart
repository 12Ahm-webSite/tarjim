import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/utils/logger.dart';
import '../core/utils/logger_service.dart';
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

  bool _capturePending = false;

  /// A capture request is awaiting consent or a frame.
  bool get capturePending => _capturePending;

  /// True while any native operation is in flight (disables Start).
  bool get isBusy => _isTranslating || _capturePending;

  /// Last pipeline error, surfaced to the UI as a SnackBar message.
  String? lastError;

  /// Whether the device supports MediaProjection at all.
  bool captureAvailable = false;

  // ─── Capture results (Step 6) ────────────────────────────────────
  /// PNG bytes of the latest screenshot, ready for OCR in Step 7.
  Uint8List? lastCapture;

  /// Temp path where [lastCapture] was written for debugging.
  String? lastCapturePath;

  // ─── Status sync ─────────────────────────────────────────────────
  /// Re-queries real native state. Safe to call on app init and resume —
  /// this is what keeps the status cards honest after the user returns
  /// from system permission screens.
  Future<void> refreshStatuses() async {
    LoggerService.instance.log('Refreshing pipeline statuses', source: 'AppController');
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
    LoggerService.instance.log('Requesting permissions', source: 'AppController');
    await _permissions.requestNotifications();
    await _permissions.requestOverlay();
    await refreshStatuses();
  }

  /// Step 6 pipeline: overlay permission check → system consent dialog
  /// → foreground service → one screenshot → PNG bytes saved to a temp
  /// file and kept in [lastCapture] for the preview sheet / Step 7 OCR.
  ///
  /// Returns an error message for the UI, or null on success.
  Future<String?> startTranslation() async {
    LoggerService.instance.log('Start Translation pressed', source: 'AppController');
    lastError = null;

    if (!await _overlay.checkOverlayPermission()) {
      overlayStatus = ServiceStatus.idle;
      lastError = 'Grant "Display over other apps" first.';
      AppLogger.warning('startTranslation aborted: $lastError', tag: _tag);
      notifyListeners();
      return lastError;
    }
    overlayStatus = ServiceStatus.granted;

    _capturePending = true;
    LoggerService.instance.log('capturePending set to true', source: 'AppController');
    screenCaptureStatus = ServiceStatus.running;
    notifyListeners();

    try {
      final bytes = await _mediaProjection.startScreenCapture();
      lastCapture = bytes;
      lastCapturePath = await _saveTempCapture(bytes);
      LoggerService.instance.log('Screen capture completed', source: 'AppController');
      screenCaptureStatus = ServiceStatus.granted;
      AppLogger.info(
        'Screenshot received: ${bytes.lengthInBytes} bytes '
        '→ $lastCapturePath',
        tag: _tag,
      );
    } on PlatformException catch (e) {
      lastCapture = null;
      screenCaptureStatus = switch (e.code) {
        'DENIED' => ServiceStatus.denied,
        'STOPPED' => ServiceStatus.idle,
        _ => ServiceStatus.error,
      };
      lastError = e.message ?? 'Capture failed (${e.code}).';
      AppLogger.warning(
        'Capture failed [${e.code}]: ${e.message}',
        tag: _tag,
      );
    } finally {
      _capturePending = false;
      LoggerService.instance.log('capturePending reset', source: 'AppController');
      notifyListeners();
    }
    return lastError;
  }

  /// Stops the pipeline: kills the capture service (a pending
  /// screenshot then resolves as STOPPED) and hides the overlay.
  Future<void> stopTranslation() async {
    LoggerService.instance.log('Stop Translation pressed', source: 'AppController');
    if (!isBusy) return;
    await _mediaProjection.stopScreenCapture();
    await _overlay.hideOverlay();
    _isTranslating = false;
    ocrStatus = ServiceStatus.idle;
    translationStatus = ServiceStatus.idle;
    if (!_capturePending) {
      screenCaptureStatus = ServiceStatus.idle;
    }
    AppLogger.info('Translation pipeline stopped', tag: _tag);
    notifyListeners();
  }

  /// Persists a capture for debugging/verification in the app temp dir.
  Future<String> _saveTempCapture(Uint8List bytes) async {
    LoggerService.instance.log('Saving temporary capture file', source: 'AppController');
    final file = File(
      '${Directory.systemTemp.path}/tarjim_capture_'
      '${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
