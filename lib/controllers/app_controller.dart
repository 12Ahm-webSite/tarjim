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
import '../services/ocr_model_manager.dart';
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
  AppController({
    PermissionService? permissions,
    MediaProjectionService? mediaProjection,
    OverlayService? overlay,
    OCRService? ocr,
    TranslationService? translation,
    TranslationModelManager? translationManager,
    OCRModelManager? ocrManager,
  })  : _permissions = permissions ?? PermissionService(),
        _mediaProjection = mediaProjection ?? MediaProjectionService(),
        _overlay = overlay ?? OverlayService(),
        _ocr = ocr ?? OCRService(),
        _translation = translation ?? TranslationService(),
        modelManager = translationManager ?? TranslationModelManager(),
        ocrModelManager = ocrManager ?? OCRModelManager() {
    modelManager.addListener(_onModelManagerChanged);
    ocrModelManager.addListener(_onOcrModelManagerChanged);
  }

  static const _tag = 'AppController';

  final PermissionService _permissions;
  final MediaProjectionService _mediaProjection;
  final OverlayService _overlay;
  final OCRService _ocr;
  final TranslationService _translation;

  /// Dedicated model manager for translation model downloading & status.
  final TranslationModelManager modelManager;

  /// Dedicated model manager for Japanese OCR model readiness & download.
  final OCRModelManager ocrModelManager;

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
      modelManager.isAnyDownloading ||
      ocrModelManager.isDownloading;

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
  void _onOcrModelManagerChanged() => notifyListeners();

  @override
  void dispose() {
    modelManager.removeListener(_onModelManagerChanged);
    ocrModelManager.removeListener(_onOcrModelManagerChanged);
    modelManager.dispose();
    ocrModelManager.dispose();
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
    await ocrModelManager.checkModelStatus();
    AppLogger.info(
      'refreshStatuses: overlayGranted=$overlayGranted '
      'captureAvailable=$captureAvailable '
      'ocrReady=${ocrModelManager.isReady}',
      tag: _tag,
    );
    notifyListeners();
  }

  // ─── Model Management Delegations ────────────────────────────────
  /// Downloads an individual translation model with safety and verification.
  Future<bool> downloadModel(String code) => modelManager.downloadModel(code);

  /// Downloads all missing required translation models sequentially.
  Future<bool> downloadRequiredModels() => modelManager.downloadRequiredModels();

  /// Prepares and downloads the Japanese OCR optional model if not ready.
  Future<bool> prepareOCRModel() => ocrModelManager.prepareOCRModel();

  // ─── Intents ─────────────────────────────────────────────────────
  /// Requests runtime permissions, then refreshes card state from truth.
  Future<void> requestPermissions() async {
    LoggerService.instance.log('Requesting permissions', source: 'AppController');
    await _permissions.requestNotifications();
    await _permissions.requestOverlay();
    await refreshStatuses();
  }

  /// Full Step 6 → Step 7 → Step 8 pipeline:
  ///   1. Pre-flight Check A: Translation models (JA → EN → AR)
  ///   2. Pre-flight Check B: Japanese OCR model readiness
  ///   3. Overlay permission check
  ///   4. MediaProjection consent dialog + Foreground service
  ///   5. Single screenshot capture
  ///   6. PNG bytes decoded
  ///   7. Japanese OCR via ML Kit
  ///   8. Japanese → Arabic translation via ML Kit
  ///   9. **STOP** (no Overlay yet).
  ///
  /// Fails immediately BEFORE Capture/OCR if models are missing/not ready.
  /// Returns an error message for the UI SnackBar, or `null` on success.
  Future<String?> startTranslation() async {
    LoggerService.instance.log('Start Translation pressed', source: 'AppController');
    lastError = null;

    // ── Pre-flight Check A: Are required translation models installed? ─
    final translationModelsReady =
        await modelManager.areAllRequiredModelsDownloaded();
    if (!translationModelsReady) {
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

    // ── Pre-flight Check B: Is Japanese OCR model ready? ─────────────
    final ocrReady = await ocrModelManager.isModelReady();
    if (!ocrReady) {
      lastError = 'Japanese OCR model is not ready. Google Play Services is downloading the optional module. '
          'Please tap "Prepare OCR Model" or wait a moment for the download to complete.';
      AppLogger.warning('startTranslation aborted: $lastError', tag: _tag);
      LoggerService.instance.log(lastError!, source: _tag, level: 'WARN');
      screenCaptureStatus = ServiceStatus.idle;
      ocrStatus = ServiceStatus.idle;
      translationStatus = ServiceStatus.idle;
      notifyListeners();
      return lastError;
    }

    // ── Pre-flight Check C: Overlay permission ───────────────────────
    if (!await _overlay.checkOverlayPermission()) {
      overlayStatus = ServiceStatus.idle;
      screenCaptureStatus = ServiceStatus.idle;
      lastError = 'Grant "Display over other apps" first.';
      AppLogger.warning('startTranslation aborted: $lastError', tag: _tag);
      notifyListeners();
      return lastError;
    }
    overlayStatus = ServiceStatus.granted;

    // ── Per-stage lifecycle transitions ─────────────────────────────
    if (!isBusy) {
      screenCaptureStatus = ServiceStatus.running;
      ocrStatus = ServiceStatus.idle;
      translationStatus = ServiceStatus.idle;
      notifyListeners();
    }

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
