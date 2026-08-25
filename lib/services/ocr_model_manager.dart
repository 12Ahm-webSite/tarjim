import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../core/utils/logger.dart';
import '../core/utils/logger_service.dart';

/// Status of the ML Kit Japanese OCR model / optional module.
enum OCRModelStatus {
  notReady,
  downloading,
  ready,
  failed,
}

/// State representation for the Japanese OCR model.
class OCRModelState {
  const OCRModelState({
    this.status = OCRModelStatus.notReady,
    this.statusMessage,
    this.lastError,
    this.currentAttempt = 0,
    this.maxAttempts = 15,
  });

  final OCRModelStatus status;
  final String? statusMessage;
  final String? lastError;
  final int currentAttempt;
  final int maxAttempts;

  bool get isReady => status == OCRModelStatus.ready;
  bool get isDownloading => status == OCRModelStatus.downloading;
  bool get isFailed => status == OCRModelStatus.failed;

  OCRModelState copyWith({
    OCRModelStatus? status,
    String? statusMessage,
    String? lastError,
    int? currentAttempt,
    int? maxAttempts,
    bool clearError = false,
  }) {
    return OCRModelState(
      status: status ?? this.status,
      statusMessage: statusMessage ?? this.statusMessage,
      lastError: clearError ? null : (lastError ?? this.lastError),
      currentAttempt: currentAttempt ?? this.currentAttempt,
      maxAttempts: maxAttempts ?? this.maxAttempts,
    );
  }
}

/// Type definition for custom readiness probe (used in unit tests).
typedef OCRReadinessProbe = Future<bool> Function();

/// Independent manager responsible for the Japanese OCR model:
/// - Probing readiness with lightweight non-blocking checks
/// - Downloading / preparing the model via Google Play Services
/// - Timeout handling (default 45s) and bounded retries
/// - Concurrency protection against duplicate preparation requests
/// - Comprehensive logging and reactive state updates for the UI
class OCRModelManager extends ChangeNotifier {
  OCRModelManager({
    TextRecognizer? recognizer,
    OCRReadinessProbe? customProbe,
  })  : _customProbe = customProbe,
        _recognizer = recognizer,
        _ownsRecognizer = recognizer == null && customProbe == null;

  static const String _tag = 'OCRModelManager';

  /// Default timeout for active OCR model preparation.
  static const Duration defaultPrepareTimeout = Duration(seconds: 45);

  /// Default retry count when actively waiting for Google Play Services.
  static const int defaultMaxRetries = 15;

  /// Default delay between polling attempts.
  static const Duration defaultRetryDelay = Duration(seconds: 3);

  final OCRReadinessProbe? _customProbe;
  TextRecognizer? _recognizer;
  final bool _ownsRecognizer;

  OCRModelState _state = const OCRModelState();
  OCRModelState get state => _state;

  OCRModelStatus get status => _state.status;
  bool get isReady => _state.isReady;
  bool get isDownloading => _state.isDownloading;
  bool get isFailed => _state.isFailed;
  String? get statusMessage => _state.statusMessage;
  String? get lastError => _state.lastError;

  /// In-flight preparation future to prevent duplicate concurrent preparation requests.
  Future<bool>? _activePrepare;

  bool _disposed = false;

  TextRecognizer _getRecognizer() {
    return _recognizer ??= TextRecognizer(script: TextRecognitionScript.japanese);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_ownsRecognizer && _recognizer != null) {
      try {
        _recognizer!.close();
      } catch (e) {
        AppLogger.warning('OCR recognizer close error in OCRModelManager: $e', tag: _tag);
      }
    }
    super.dispose();
  }

  /// Checks whether the Japanese OCR model is currently ready on device.
  ///
  /// Executes a fast, lightweight probe against the recognizer.
  /// If the model is not ready, Google Play Services is automatically
  /// prompted to initiate background download.
  Future<bool> checkModelStatus() async {
    if (_disposed) return false;

    // If active preparation is running, let it continue
    if (_activePrepare != null) {
      return false;
    }

    try {
      final ready = await _probeReadiness();
      if (ready) {
        _state = _state.copyWith(
          status: OCRModelStatus.ready,
          statusMessage: 'Ready (Japanese OCR)',
          clearError: true,
        );
        notifyListeners();
        return true;
      } else {
        _state = _state.copyWith(
          status: OCRModelStatus.notReady,
          statusMessage: 'Not downloaded / downloading',
        );
        notifyListeners();
        return false;
      }
    } on PlatformException catch (e) {
      final isDownloading = _isDownloadPendingException(e);
      if (isDownloading) {
        _state = _state.copyWith(
          status: OCRModelStatus.downloading,
          statusMessage: 'Downloading in Google Play Services...',
          clearError: true,
        );
      } else {
        _state = _state.copyWith(
          status: OCRModelStatus.failed,
          statusMessage: 'OCR check failed',
          lastError: '[${e.code}] ${e.message}',
        );
      }
      notifyListeners();
      return false;
    } catch (e) {
      _state = _state.copyWith(
        status: OCRModelStatus.failed,
        statusMessage: 'OCR check failed',
        lastError: e.toString(),
      );
      notifyListeners();
      return false;
    }
  }

  /// Returns true if the Japanese OCR model is verified ready.
  Future<bool> isModelReady() async {
    return await checkModelStatus();
  }

  /// Actively prepares and waits for the Japanese OCR model to become available.
  ///
  /// Features:
  /// - Concurrency guard: joins existing active prepare future if already running.
  /// - Bounded retries (default 15 attempts with 3s sleep = ~45s max).
  /// - Real-time state updates and logging.
  /// - Clean timeout handling.
  Future<bool> prepareOCRModel({
    Duration timeout = defaultPrepareTimeout,
    int maxRetries = defaultMaxRetries,
    Duration retryDelay = defaultRetryDelay,
  }) async {
    if (_disposed) return false;

    // ── Concurrency guard ───────────────────────────────────────────
    if (_activePrepare != null) {
      AppLogger.info('OCR model preparation already active — joining existing task', tag: _tag);
      return _activePrepare!;
    }

    final future = _executePrepareWithRetry(
      timeout: timeout,
      maxRetries: maxRetries,
      retryDelay: retryDelay,
    );

    _activePrepare = future;
    try {
      return await future;
    } finally {
      _activePrepare = null;
    }
  }

  Future<bool> _executePrepareWithRetry({
    required Duration timeout,
    required int maxRetries,
    required Duration retryDelay,
  }) async {
    LoggerService.instance.log(
      'OCR model preparation started (timeout: ${timeout.inSeconds}s, maxRetries: $maxRetries)',
      source: _tag,
    );
    AppLogger.info(
      'OCR model preparation started (timeout: ${timeout.inSeconds}s, maxRetries: $maxRetries)',
      tag: _tag,
    );

    _state = _state.copyWith(
      status: OCRModelStatus.downloading,
      statusMessage: 'Preparing OCR model (1/$maxRetries)...',
      currentAttempt: 1,
      maxAttempts: maxRetries,
      clearError: true,
    );
    notifyListeners();

    final stopwatch = Stopwatch()..start();

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      if (_disposed) return false;

      if (stopwatch.elapsed > timeout) {
        final errorMsg = 'OCR model preparation timed out after ${timeout.inSeconds}s';
        LoggerService.instance.log(errorMsg, source: _tag, level: 'WARN');
        AppLogger.warning(errorMsg, tag: _tag);

        _state = _state.copyWith(
          status: OCRModelStatus.failed,
          statusMessage: 'Preparation timed out',
          lastError: errorMsg,
          currentAttempt: attempt,
        );
        notifyListeners();
        return false;
      }

      LoggerService.instance.log(
        'Checking Japanese OCR model readiness (attempt $attempt/$maxRetries)...',
        source: _tag,
      );
      AppLogger.info(
        'Checking Japanese OCR model readiness (attempt $attempt/$maxRetries)...',
        tag: _tag,
      );

      _state = _state.copyWith(
        status: OCRModelStatus.downloading,
        statusMessage: 'Waiting for Google Play Services ($attempt/$maxRetries)...',
        currentAttempt: attempt,
        maxAttempts: maxRetries,
      );
      notifyListeners();

      try {
        final ready = await _probeReadiness();
        if (ready) {
          stopwatch.stop();
          LoggerService.instance.log(
            'Japanese OCR model verified ready ✓ (in ${stopwatch.elapsedMilliseconds}ms)',
            source: _tag,
          );
          AppLogger.info(
            'Japanese OCR model verified ready ✓ (in ${stopwatch.elapsedMilliseconds}ms)',
            tag: _tag,
          );

          _state = _state.copyWith(
            status: OCRModelStatus.ready,
            statusMessage: 'Ready ✓',
            clearError: true,
          );
          notifyListeners();
          return true;
        }
      } on PlatformException catch (e) {
        final isDownloading = _isDownloadPendingException(e);
        if (isDownloading) {
          LoggerService.instance.log(
            'Google Play Services is downloading Japanese OCR module (attempt $attempt/$maxRetries)...',
            source: _tag,
          );
          AppLogger.info(
            'Google Play Services is downloading Japanese OCR module (attempt $attempt/$maxRetries)...',
            tag: _tag,
          );
        } else {
          LoggerService.instance.log(
            'OCR probe returned platform error [${e.code}]: ${e.message}',
            source: _tag,
            level: 'WARN',
          );
          AppLogger.warning('OCR probe platform error: $e', tag: _tag);
        }
      } catch (e) {
        LoggerService.instance.log(
          'OCR probe threw error: $e',
          source: _tag,
          level: 'WARN',
        );
        AppLogger.warning('OCR probe error: $e', tag: _tag);
      }

      if (attempt < maxRetries) {
        await Future.delayed(retryDelay);
      }
    }

    stopwatch.stop();
    const timeoutMsg = 'Japanese OCR model download did not complete in time. '
        'Please ensure Google Play Services has internet access and try again.';
    LoggerService.instance.log(timeoutMsg, source: _tag, level: 'WARN');
    AppLogger.warning(timeoutMsg, tag: _tag);

    _state = _state.copyWith(
      status: OCRModelStatus.failed,
      statusMessage: 'Download timed out',
      lastError: timeoutMsg,
    );
    notifyListeners();
    return false;
  }

  /// Lightweight probe to test if the model is ready.
  Future<bool> _probeReadiness() async {
    if (_customProbe != null) {
      return await _customProbe();
    }

    final recognizer = _getRecognizer();
    // Use minimal 1x1 blank image in NV21 format
    final dummyBytes = Uint8List(4);
    final inputImage = InputImage.fromBytes(
      bytes: dummyBytes,
      metadata: InputImageMetadata(
        size: const Size(1, 1),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.nv21,
        bytesPerRow: 1,
      ),
    );

    await recognizer.processImage(inputImage);
    return true;
  }

  bool _isDownloadPendingException(PlatformException e) {
    final message = (e.message ?? '').toLowerCase();
    final details = (e.details ?? '').toString().toLowerCase();
    return e.code == 'TextRecognizerError' &&
        (message.contains('optional module') ||
            message.contains('download') ||
            details.contains('optional module') ||
            details.contains('download'));
  }
}
