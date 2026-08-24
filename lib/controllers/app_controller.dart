import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/utils/logger.dart';
import '../core/utils/logger_service.dart';
import '../models/text_box.dart';
import '../models/translated_text_box.dart';
import '../services/media_projection_service.dart';
import '../services/ocr_service.dart';
import '../services/overlay_service.dart';
import '../services/permission_service.dart';
import '../services/translation_model_manager.dart';
import '../services/translation_service.dart';

/// Lifecycle state of each pipeline stage, mirrored by the status cards.
enum ServiceStatus { idle, granted, denied, running, error }

/// Central application state for the MVP pipeline.
///
/// Owns the Flutter services and translates their results into status
/// card state. The UI only reads this controller and calls its intents;
/// it never touches MethodChannels directly.
class AppController extends ChangeNotifier {
  AppController() {
    modelManager.addListener(_onModelManagerChanged);
  }

  static const _tag = 'AppController';

  final PermissionService _permissions = PermissionService();
  final MediaProjectionService _mediaProjection = MediaProjectionService();
  final OverlayService _overlay = OverlayService();
  final OCRService _ocr = OCRService();
  final TranslationService _translation = TranslationService();

  /// Dedicated model manager for translation model downloading & status.
  final TranslationModelManager modelManager = TranslationModelManager();

  // ─── Pipeline statuses ───────────────────────────────────────────
  ServiceStatus screenCaptureStatus = ServiceStatus.idle;
  ServiceStatus overlayStatus = ServiceStatus.idle;
  ServiceStatus ocrStatus = ServiceStatus.idle;
  ServiceStatus translationStatus = ServiceStatus.idle;

  bool _isTranslating = false;
  bool get isTranslating => _isTranslating;

  bool _capturePending = false;
  bool _ocrInProgress = false;
  bool _translationInProgress = false;

  /// A capture request is awaiting consent or a frame.
  bool get capturePending => _capturePending;

  /// True while any stage is in flight (disables Start button).
  bool get isBusy =>
      _isTranslating ||
      _capturePending ||
      _ocrInProgress ||
      _translationInProgress ||
      modelManager.isAnyDownloading;

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
  List<TextBox> lastOcrResult = [];

  // ─── Translation results (Step 8) ────────────────────────────────
  /// Translated text boxes produced by the translation stage.
  List<TranslatedTextBox> lastTranslationResult = [];

  void _onModelManagerChanged() => notifyListeners();

  @override
  void dispose() {
    modelManager.removeListener(_onModelManagerChanged);
    modelManager.dispose();
    _ocr.dispose();
    _translation.dispose();
    super.dispose();
  }

  // ─── Status sync ─────────────────────────────────────────────────
  /// Re-queries real native state. Safe to call on app init and resume —
  /// this is what keeps the status cards and model badges honest.
  Future<void> refreshStatuses() async {
    LoggerService.instance.log('Refreshing pipeline and model statuses', source: 'AppController');
    final overlayGranted = await _overlay.checkOverlayPermission();
    overlayStatus =
        overlayGranted ? ServiceStatus.granted : ServiceStatus.idle;
    captureAvailable =
        await _mediaProjection.checkScreenCaptureAvailability();
    await modelManager.checkAllStatuses();
    AppLogger.info(
      'refreshStatuses: overlayGranted=$overlayGranted '
      'captureAvailable=$captureAvailable',
      tag: _tag,
    );
    notifyListeners();
  }

  // ─── Model Management Delegations ────────────────────────────────
  /// Downloads an individual model with safety and verification.
  Future<bool> downloadModel(String code) => modelManager.downloadModel(code);

  /// Downloads all missing required models sequentially.
  Future<bool> downloadRequiredModels() => modelManager.downloadRequiredModels();

  // ─── Intents ─────────────────────────────────────────────────────
  /// Requests runtime permissions, then refreshes card state from truth.
  Future<void> requestPermissions() async {
    LoggerService.instance.log('Requesting permissions', source: 'AppController');
    await _permissions.requestNotifications();
    await _permissions.requestOverlay();
    await refreshStatuses();
  }

  /// Full Step 6 → Step 7 → Step 8 pipeline:
  ///   1. Pre-flight model readiness check
  ///   2. Overlay permission check
  ///   3. MediaProjection consent dialog
  ///   4. Foreground service + single screenshot
  ///   5. PNG bytes decoded
  ///   6. Japanese OCR via ML Kit
  ///   7. Japanese → Arabic translation via ML Kit
  ///   8. **STOP** (no Overlay yet).
  ///
  /// Fails immediately BEFORE Capture/OCR if required models are missing.
  /// Returns an error message for the UI SnackBar, or `null` on success.
  Future<String?> startTranslation() async {
    LoggerService.instance.log('Start Translation pressed', source: 'AppController');
    lastError = null;

    // ── Pre-flight Check: Are required translation models installed? ─
    final modelsReady = await modelManager.areAllRequiredModelsDownloaded();
    if (!modelsReady) {
      final missing = await modelManager.getMissingRequiredModelNames();
      lastError = 'Missing required translation models: ${missing.join(', ')}. '
          'Please download them in the Translation Models section.';
      AppLogger.warning('startTranslation aborted: $lastError', tag: _tag);
      LoggerService.instance.log(lastError!, source: _tag, level: 'WARN');
      screenCaptureStatus = ServiceStatus.idle;
      ocrStatus = ServiceStatus.idle;
      translationStatus = ServiceStatus.idle;
      notifyListeners();
      return lastError;
    }

    // ── Per-stage lifecycle transitions ─────────────────────────────
    if (!isBusy) {
      screenCaptureStatus = ServiceStatus.running;
      ocrStatus = ServiceStatus.idle;
      translationStatus = ServiceStatus.idle;
      notifyListeners();
    }

    if (!await _overlay.checkOverlayPermission()) {
      overlayStatus = ServiceStatus.idle;
      screenCaptureStatus = ServiceStatus.idle;
      lastError = 'Grant "Display over other apps" first.';
      AppLogger.warning('startTranslation aborted: $lastError', tag: _tag);
      notifyListeners();
      return lastError;
    }
    overlayStatus = ServiceStatus.granted;

    _capturePending = true;
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
      notifyListeners();

      try {
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
        ocrStatus = ServiceStatus.granted;
        AppLogger.info(
          'Step 7 OCR OK: stored ${boxes.length} boxes in lastOcrResult',
          tag: _tag,
        );
        LoggerService.instance.log(
          'OCR pipeline step completed: ${boxes.length} boxes stored',
          source: _tag,
        );
        notifyListeners();

        // ── Step 8: Translation (Japanese → Arabic) ────────────────
        LoggerService.instance.log('Advancing pipeline to Step 8 (Translation)', source: _tag);
        _translationInProgress = true;
        translationStatus = ServiceStatus.running;
        notifyListeners();

        try {
          final translatedBoxes = await _translation.translateBoxes(boxes);
          lastTranslationResult = translatedBoxes;
          translationStatus = ServiceStatus.granted;
          AppLogger.info(
            'Step 8 Translation OK: ${translatedBoxes.length} boxes translated',
            tag: _tag,
          );
          LoggerService.instance.log(
            'Translation pipeline step completed: ${translatedBoxes.length} boxes translated',
            source: _tag,
          );
        } catch (e) {
          lastTranslationResult = [];
          translationStatus = ServiceStatus.error;
          lastError = lastError ?? 'Translation failed: ${e.runtimeType}';
          AppLogger.warning('Step 8 Translation failed: $e', tag: _tag);
          LoggerService.instance.log(
            'Translation pipeline step failed: ${e.runtimeType}: $e',
            source: _tag,
          );
        } finally {
          _translationInProgress = false;
        }
      } catch (e) {
        lastOcrResult = [];
        lastTranslationResult = [];
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
      _translationInProgress = false;
      lastCapture = null;
      screenCaptureStatus = switch (e.code) {
        'DENIED' => ServiceStatus.denied,
        'STOPPED' => ServiceStatus.idle,
        _ => ServiceStatus.error,
      };
      ocrStatus = ServiceStatus.idle;
      translationStatus = ServiceStatus.idle;
      lastOcrResult = [];
      lastTranslationResult = [];
      lastError = e.message ?? 'Capture failed (${e.code}).';
      AppLogger.warning(
        'Capture failed [${e.code}]: ${e.message}',
        tag: _tag,
      );
    } finally {
      _capturePending = false;
      _ocrInProgress = false;
      _translationInProgress = false;
      LoggerService.instance.log('capturePending reset, ocrInProgress reset, translationInProgress reset', source: 'AppController');
      notifyListeners();
    }
    return lastError;
  }

  /// Stops the pipeline: kills the capture service and hides the overlay.
  Future<void> stopTranslation() async {
    LoggerService.instance.log('Stop Translation pressed', source: 'AppController');
    if (!isBusy) {
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
    _translationInProgress = false;
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
