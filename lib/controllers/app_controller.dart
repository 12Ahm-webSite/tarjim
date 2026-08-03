import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/utils/logger.dart';
import '../core/utils/logger_service.dart';
import '../models/text_box.dart';
import '../services/media_projection_service.dart';
import '../services/ocr_service.dart';
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
  final OCRService _ocr = OCRService();

  // ─── Pipeline statuses ───────────────────────────────────────────
  ServiceStatus screenCaptureStatus = ServiceStatus.idle;
  ServiceStatus overlayStatus = ServiceStatus.idle;
  ServiceStatus ocrStatus = ServiceStatus.idle;
  ServiceStatus translationStatus = ServiceStatus.idle;

  bool _isTranslating = false;
  bool get isTranslating => _isTranslating;

  bool _capturePending = false;
  bool _ocrInProgress = false;

  /// A capture request is awaiting consent or a frame.
  bool get capturePending => _capturePending;

  /// True while any stage is in flight (disables Start button).
  bool get isBusy => _isTranslating || _capturePending || _ocrInProgress;

  /// Last pipeline error, surfaced to the UI as a SnackBar message.
  String? lastError;

  /// Whether the device supports MediaProjection at all.
  bool captureAvailable = false;

  // ─── Capture results (Step 6) ────────────────────────────────────
  /// PNG bytes of the latest screenshot, ready for OCR in Step 7.
  Uint8List? lastCapture;

  /// Temp path where [lastCapture] was written for debugging.
  String? lastCapturePath;

  // ─── OCR results (Step 7) ────────────────────────────────────────
  /// Structured text regions detected in [lastCapture].
  ///
  /// Populated immediately after a successful screen capture in the
  /// same `startTranslation` pipeline. Empty list means either OCR ran
  /// and found no readable Japanese text, or the stage has not been
  /// reached yet (check [ocrStatus] to distinguish).
  List<TextBox> lastOcrResult = [];

  @override
  void dispose() {
    _ocr.dispose();
    super.dispose();
  }

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

  /// Full Step 6 → Step 7 pipeline:
  ///   Overlay permission check
  ///   → MediaProjection consent dialog
  ///   → Foreground service + single screenshot
  ///   → PNG bytes decoded
  ///   → Japanese OCR via ML Kit
  ///   → **STOP** (no Translation / Overlay yet).
  ///
  /// After this method returns, callers can read:
  ///   * [screenCaptureStatus] — screenshot outcome
  ///   * [lastCapture] + [lastCapturePath] — raw image payload
  ///   * [ocrStatus] — OCR outcome
  ///   * [lastOcrResult] — structured list of detected text regions
  ///
  /// Returns an error message for the UI SnackBar, or `null` on success.
  Future<String?> startTranslation() async {
    LoggerService.instance.log('Start Translation pressed', source: 'AppController');
    lastError = null;

    // ── Per-stage lifecycle transitions (no bulk Idle reset) ─────────
    //
    // Design rule: leave "Granted" values from prior runs alone so the
    // UI can surface last successful result. At the START of a new run,
    // transition ONLY the stages that are *about* to execute:
    //
    //   [Start pressed]
    //     screenCaptureStatus := Running   ← capture is about to begin
    //     ocrStatus           := Idle      ← hasn't started yet (clear
    //                                        any stale error from last run)
    //     translationStatus   := Idle      ← hasn't started yet
    if (!isBusy) {
      screenCaptureStatus = ServiceStatus.running;
      ocrStatus = ServiceStatus.idle;
      translationStatus = ServiceStatus.idle;
      notifyListeners();
    }

    if (!await _overlay.checkOverlayPermission()) {
      overlayStatus = ServiceStatus.idle;
      lastError = 'Grant "Display over other apps" first.';
      AppLogger.warning('startTranslation aborted: $lastError', tag: _tag);
      notifyListeners();
      return lastError;
    }
    overlayStatus = ServiceStatus.granted;

    _capturePending = true;
    // Don't override screenCaptureStatus to Running again if it was
    // already set above the overlay check (it was). Just make sure the
    // UI reflects the new pending flag.
    if (screenCaptureStatus != ServiceStatus.running) {
      screenCaptureStatus = ServiceStatus.running;
    }
    notifyListeners();

    try {
      // ── Step 6: Screen capture ──────────────────────────────────
      LoggerService.instance.log('capturePending set to true', source: 'AppController');
      final bytes = await _mediaProjection.startScreenCapture();
      lastCapture = bytes;
      lastCapturePath = await _saveTempCapture(bytes);

      // After capture SUCCESS:
      //   screenCaptureStatus := Granted   ← image available
      //   ocrStatus           := Running   ← OCR is about to begin
      screenCaptureStatus = ServiceStatus.granted;
      ocrStatus = ServiceStatus.running;
      _capturePending = false;
      LoggerService.instance.log('Screen capture completed', source: 'AppController');
      AppLogger.info(
        'Step 6 capture OK: ${bytes.lengthInBytes} bytes → $lastCapturePath',
        tag: _tag,
      );
      notifyListeners();

      // ── Step 7: Japanese OCR ────────────────────────────────────
      LoggerService.instance.log('Advancing pipeline to Step 7 (OCR)', source: 'AppController');
      _ocrInProgress = true;
      // Note: ocrStatus already = Running from the post-capture transition
      // above. We just notify once more here so OCR "started" is logged
      // at the right moment in the UI.
      notifyListeners();

      try {
        // Decode the PNG header to recover the real source dimensions.
        // ML Kit's `block.boundingBox` is expressed in these pixels,
        // so we must keep them alongside every [TextBox] for later
        // overlay scaling in Step 9.
        //
        // Note: dart:ui's decodeImageFromList uses a callback in this
        // Dart version, so we bridge it to a Future via Completer.
        final completer = Completer<Image>();
        decodeImageFromList(bytes, (Image img) {
          completer.complete(img);
        });
        final decoded = await completer.future;
        final imgW = decoded.width;
        final imgH = decoded.height;
        decoded.dispose();
        LoggerService.instance.log(
          'PNG dimensions decoded: ${imgW}x$imgH',
          source: _tag,
        );

        final boxes = await _ocr.processImage(
          filePath: lastCapturePath,
          bytes: bytes,
          imageWidth: imgW,
          imageHeight: imgH,
        );
        lastOcrResult = boxes;
        // After OCR SUCCESS:
        //   ocrStatus := Granted
        ocrStatus = ServiceStatus.granted;
        AppLogger.info(
          'Step 7 OCR OK: stored ${boxes.length} boxes in lastOcrResult',
          tag: _tag,
        );
        LoggerService.instance.log(
          'OCR pipeline step completed: ${boxes.length} boxes stored',
          source: _tag,
        );
      } catch (e) {
        lastOcrResult = [];
        ocrStatus = ServiceStatus.error;
        lastError = lastError ?? 'OCR failed: ${e.runtimeType}';
        AppLogger.warning('Step 7 OCR failed: $e', tag: _tag);
        LoggerService.instance.log(
          'OCR pipeline step failed: ${e.runtimeType}: $e',
          source: _tag,
        );
      } finally {
        _ocrInProgress = false;
      }
    } on PlatformException catch (e) {
      _capturePending = false;
      _ocrInProgress = false;
      lastCapture = null;
      screenCaptureStatus = switch (e.code) {
        'DENIED' => ServiceStatus.denied,
        'STOPPED' => ServiceStatus.idle,
        _ => ServiceStatus.error,
      };
      ocrStatus = ServiceStatus.idle;
      lastOcrResult = [];
      lastError = e.message ?? 'Capture failed (${e.code}).';
      AppLogger.warning(
        'Capture failed [${e.code}]: ${e.message}',
        tag: _tag,
      );
    } finally {
      _capturePending = false;
      _ocrInProgress = false;
      LoggerService.instance.log('capturePending reset, ocrInProgress reset', source: 'AppController');
      notifyListeners();
    }
    return lastError;
  }

  /// Stops the pipeline: kills the capture service (a pending
  /// screenshot then resolves as STOPPED) and hides the overlay.
  Future<void> stopTranslation() async {
    LoggerService.instance.log('Stop Translation pressed', source: 'AppController');
    if (!isBusy) {
      // Reset in-progress stages to idle even if nothing is running, so
      // tapping Stop always clears prior Granted/Error transient state.
      screenCaptureStatus = ServiceStatus.idle;
      ocrStatus = ServiceStatus.idle;
      translationStatus = ServiceStatus.idle;
      notifyListeners();
      return;
    }
    await _mediaProjection.stopScreenCapture();
    await _overlay.hideOverlay();
    _isTranslating = false;
    _ocrInProgress = false;
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
