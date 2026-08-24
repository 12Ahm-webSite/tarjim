import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/logger.dart';
import '../core/utils/logger_service.dart';
import '../models/translation_model_config.dart';

/// Status of an on-device translation model.
enum ModelDownloadStatus {
  notDownloaded,
  downloading,
  downloaded,
  failed,
}

/// State representation for a single translation model.
class TranslationModelState {
  const TranslationModelState({
    required this.config,
    this.status = ModelDownloadStatus.notDownloaded,
    this.statusMessage,
    this.lastError,
    this.currentAttempt = 0,
    this.maxAttempts = 3,
    this.progress,
  });

  final TranslationModelConfig config;
  final ModelDownloadStatus status;
  final String? statusMessage;
  final String? lastError;
  final int currentAttempt;
  final int maxAttempts;
  final double? progress;

  bool get isDownloaded => status == ModelDownloadStatus.downloaded;
  bool get isDownloading => status == ModelDownloadStatus.downloading;
  bool get isFailed => status == ModelDownloadStatus.failed;

  TranslationModelState copyWith({
    ModelDownloadStatus? status,
    String? statusMessage,
    String? lastError,
    int? currentAttempt,
    int? maxAttempts,
    double? progress,
    bool clearError = false,
  }) {
    return TranslationModelState(
      config: config,
      status: status ?? this.status,
      statusMessage: statusMessage ?? this.statusMessage,
      lastError: clearError ? null : (lastError ?? this.lastError),
      currentAttempt: currentAttempt ?? this.currentAttempt,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      progress: progress ?? this.progress,
    );
  }
}

/// Independent manager responsible for translation models:
/// - Checking installation state on disk
/// - Safe downloading with timeout, retries, and network freedom
/// - Verification of physical files before marking as installed
/// - Concurrency protection against duplicate downloads
/// - Comprehensive logging and reactive state updates for the UI
class TranslationModelManager extends ChangeNotifier {
  TranslationModelManager({
    List<TranslationModelConfig>? models,
    OnDeviceTranslatorModelManager? mlKitModelManager,
  })  : _models = models ?? AppConstants.supportedTranslationModels,
        _mlKitModelManager =
            mlKitModelManager ?? OnDeviceTranslatorModelManager() {
    _initStates();
  }

  static const String _tag = 'TranslationModelManager';

  /// Default timeout per download attempt (45 seconds).
  static const Duration defaultDownloadTimeout = Duration(seconds: 45);

  /// Maximum download retry attempts.
  static const int maxDownloadRetries = 3;

  /// Underlying ML Kit model manager.
  final OnDeviceTranslatorModelManager _mlKitModelManager;

  /// Central list of managed models.
  final List<TranslationModelConfig> _models;

  /// In-memory state keyed by model BCP code.
  final Map<String, TranslationModelState> _states = {};

  /// In-flight download futures to prevent duplicate concurrent requests.
  final Map<String, Future<bool>> _activeDownloads = {};

  /// Overall batch download in progress.
  bool _batchDownloading = false;
  bool get isBatchDownloading => _batchDownloading;

  /// Unmodifiable view of all model configurations.
  List<TranslationModelConfig> get models => List.unmodifiable(_models);

  /// Unmodifiable view of all model states.
  List<TranslationModelState> get states =>
      List.unmodifiable(_models.map((m) => _states[m.code]!));

  /// True if any model is currently downloading.
  bool get isAnyDownloading =>
      _states.values.any((s) => s.status == ModelDownloadStatus.downloading);

  void _initStates() {
    for (final model in _models) {
      _states[model.code] = TranslationModelState(config: model);
    }
  }

  /// Gets the current state for a model by code.
  TranslationModelState? getState(String code) => _states[code];

  /// Checks disk truth for all registered models.
  Future<void> checkAllStatuses() async {
    AppLogger.info('Checking status for all translation models...', tag: _tag);
    for (final model in _models) {
      await checkModelStatus(model.code);
    }
    notifyListeners();
  }

  /// Checks disk truth for a single model and updates its state.
  Future<bool> checkModelStatus(String code) async {
    final model = _models.firstWhere(
      (m) => m.code == code,
      orElse: () => throw ArgumentError('Unknown model code: $code'),
    );

    // If currently downloading, don't overwrite with check result unless done
    if (_activeDownloads.containsKey(code)) {
      return false;
    }

    try {
      final isDownloaded =
          await _mlKitModelManager.isModelDownloaded(model.code);
      _states[code] = _states[code]!.copyWith(
        status: isDownloaded
            ? ModelDownloadStatus.downloaded
            : ModelDownloadStatus.notDownloaded,
        statusMessage: isDownloaded ? 'Downloaded' : 'Not downloaded',
        clearError: isDownloaded,
      );
      notifyListeners();
      return isDownloaded;
    } catch (e) {
      AppLogger.warning(
        'Error checking model status for ${model.name} ($code): $e',
        tag: _tag,
      );
      return false;
    }
  }

  /// Returns true if all required models are physically verified as downloaded.
  Future<bool> areAllRequiredModelsDownloaded() async {
    final requiredModels = _models.where((m) => m.isRequired).toList();
    for (final model in requiredModels) {
      try {
        final isDownloaded =
            await _mlKitModelManager.isModelDownloaded(model.code);
        if (!isDownloaded) {
          return false;
        }
      } catch (e) {
        AppLogger.warning(
          'Error querying ${model.name} availability: $e',
          tag: _tag,
        );
        return false;
      }
    }
    return true;
  }

  /// Returns the list of missing required models after checking disk truth.
  Future<List<TranslationModelConfig>> getMissingRequiredModels() async {
    final missing = <TranslationModelConfig>[];
    final requiredModels = _models.where((m) => m.isRequired).toList();
    for (final model in requiredModels) {
      try {
        final isDownloaded =
            await _mlKitModelManager.isModelDownloaded(model.code);
        if (!isDownloaded) {
          missing.add(model);
        }
      } catch (e) {
        missing.add(model);
      }
    }
    return missing;
  }

  /// Returns user-readable names of missing required models.
  Future<List<String>> getMissingRequiredModelNames() async {
    final missing = await getMissingRequiredModels();
    return missing.map((m) => '${m.name} (${m.code})').toList();
  }

  /// Downloads a single model by code.
  ///
  /// Features:
  /// - Concurrency protection: returns existing Future if already in-flight.
  /// - Sets `isWifiRequired: false` so downloads work on cellular & emulators.
  /// - Applies a 45s timeout per attempt.
  /// - Retries up to [maxRetries] times with delay.
  /// - Verifies physical disk presence via [isModelDownloaded] before completion.
  /// - Comprehensive step-by-step logging.
  Future<bool> downloadModel(
    String code, {
    Duration timeout = defaultDownloadTimeout,
    int maxRetries = maxDownloadRetries,
    bool requireWifi = false,
  }) async {
    final model = _models.firstWhere(
      (m) => m.code == code,
      orElse: () => throw ArgumentError('Unknown model code: $code'),
    );

    // ── Concurrency guard: return existing active download if running ──
    if (_activeDownloads.containsKey(code)) {
      AppLogger.info(
        'Download already active for ${model.name} ($code) — joining existing task',
        tag: _tag,
      );
      return _activeDownloads[code]!;
    }

    final future = _executeDownloadWithRetry(
      model,
      timeout: timeout,
      maxRetries: maxRetries,
      requireWifi: requireWifi,
    );

    _activeDownloads[code] = future;
    try {
      return await future;
    } finally {
      _activeDownloads.remove(code);
    }
  }

  Future<bool> _executeDownloadWithRetry(
    TranslationModelConfig model, {
    required Duration timeout,
    required int maxRetries,
    required bool requireWifi,
  }) async {
    final label = '${model.name} (${model.code})';

    // ── Pre-check: is it already downloaded? ─────────────────────────
    try {
      final alreadyDownloaded =
          await _mlKitModelManager.isModelDownloaded(model.code);
      if (alreadyDownloaded) {
        LoggerService.instance.log(
          'Model $label is already downloaded ✓',
          source: _tag,
        );
        AppLogger.info('Model $label is already downloaded ✓', tag: _tag);
        _states[model.code] = _states[model.code]!.copyWith(
          status: ModelDownloadStatus.downloaded,
          statusMessage: 'Downloaded ✓',
          clearError: true,
        );
        notifyListeners();
        return true;
      }
    } catch (e) {
      AppLogger.warning(
        'Pre-download check for $label threw: $e',
        tag: _tag,
      );
    }

    // ── Retry loop ───────────────────────────────────────────────────
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      // 1. Download started
      LoggerService.instance.log(
        'Download started: $label (attempt $attempt/$maxRetries)',
        source: _tag,
      );
      AppLogger.info(
        'Download started: $label (attempt $attempt/$maxRetries, wifiRequired=$requireWifi)',
        tag: _tag,
      );

      _states[model.code] = _states[model.code]!.copyWith(
        status: ModelDownloadStatus.downloading,
        statusMessage: 'Downloading... ($attempt/$maxRetries)',
        currentAttempt: attempt,
        maxAttempts: maxRetries,
        progress: 0.1 * attempt,
        clearError: true,
      );
      notifyListeners();

      String? failureReason;

      try {
        // 2. Download progress logging
        LoggerService.instance.log(
          'Download progress: $label — requesting from ML Kit with ${timeout.inSeconds}s timeout',
          source: _tag,
        );
        AppLogger.info(
          'Download progress: $label — invoking ML Kit downloadModel (isWifiRequired: $requireWifi)',
          tag: _tag,
        );

        final downloadSuccess = await _mlKitModelManager
            .downloadModel(
              model.code,
              isWifiRequired: requireWifi,
            )
            .timeout(
              timeout,
              onTimeout: () => throw TimeoutException(
                'Download timed out after ${timeout.inSeconds} seconds',
              ),
            );

        if (!downloadSuccess) {
          failureReason = 'ML Kit downloadModel returned false';
        }
      } on TimeoutException catch (e) {
        failureReason = 'Timeout: ${e.message}';
      } on PlatformException catch (e) {
        failureReason = 'Platform error: [${e.code}] ${e.message}';
      } catch (e) {
        failureReason = 'Error (${e.runtimeType}): $e';
      }

      if (failureReason != null) {
        LoggerService.instance.log(
          'Download failed: $label (attempt $attempt/$maxRetries) — $failureReason',
          source: _tag,
          level: 'WARN',
        );
        AppLogger.warning(
          'Download failed: $label (attempt $attempt/$maxRetries) — $failureReason',
          tag: _tag,
        );

        if (attempt < maxRetries) {
          _states[model.code] = _states[model.code]!.copyWith(
            status: ModelDownloadStatus.downloading,
            statusMessage: 'Retrying in 2s... ($attempt/$maxRetries)',
            lastError: failureReason,
          );
          notifyListeners();
          await Future.delayed(const Duration(seconds: 2));
          continue;
        } else {
          // Final failure
          _states[model.code] = _states[model.code]!.copyWith(
            status: ModelDownloadStatus.failed,
            statusMessage: 'Download failed',
            lastError: failureReason,
          );
          notifyListeners();
          return false;
        }
      }

      // 3. Download completed signal received from API
      LoggerService.instance.log(
        'Download completed: $label — starting disk verification',
        source: _tag,
      );
      AppLogger.info(
        'Download completed: $label — starting disk verification',
        tag: _tag,
      );

      // 4. Download verification started
      LoggerService.instance.log(
        'Download verification started: $label',
        source: _tag,
      );
      AppLogger.info(
        'Download verification started: $label',
        tag: _tag,
      );

      _states[model.code] = _states[model.code]!.copyWith(
        status: ModelDownloadStatus.downloading,
        statusMessage: 'Verifying files...',
        progress: 0.9,
      );
      notifyListeners();

      // Brief delay to allow Google Play Services to finalize file extraction
      await Future.delayed(const Duration(milliseconds: 300));

      final verified = await _mlKitModelManager.isModelDownloaded(model.code);

      if (verified) {
        // 5. Download verification completed
        LoggerService.instance.log(
          'Download verification completed: $label ✓',
          source: _tag,
        );
        AppLogger.info(
          'Download verification completed: $label ✓',
          tag: _tag,
        );

        _states[model.code] = _states[model.code]!.copyWith(
          status: ModelDownloadStatus.downloaded,
          statusMessage: 'Downloaded ✓',
          progress: 1.0,
          clearError: true,
        );
        notifyListeners();
        return true;
      } else {
        failureReason = 'Verification failed: files not found on disk after download';
        LoggerService.instance.log(
          'Download failed: $label — $failureReason (attempt $attempt/$maxRetries)',
          source: _tag,
          level: 'WARN',
        );
        AppLogger.warning(
          'Download verification failed: $label (attempt $attempt/$maxRetries)',
          tag: _tag,
        );

        if (attempt < maxRetries) {
          _states[model.code] = _states[model.code]!.copyWith(
            status: ModelDownloadStatus.downloading,
            statusMessage: 'Verification failed, retrying... ($attempt/$maxRetries)',
            lastError: failureReason,
          );
          notifyListeners();
          await Future.delayed(const Duration(seconds: 2));
          continue;
        } else {
          _states[model.code] = _states[model.code]!.copyWith(
            status: ModelDownloadStatus.failed,
            statusMessage: 'Verification failed',
            lastError: failureReason,
          );
          notifyListeners();
          return false;
        }
      }
    }

    return false;
  }

  /// Sequentially downloads all missing required models.
  Future<bool> downloadRequiredModels({
    Duration timeout = defaultDownloadTimeout,
    bool requireWifi = false,
  }) async {
    if (_batchDownloading) {
      AppLogger.info('Batch download already in progress', tag: _tag);
      return false;
    }

    _batchDownloading = true;
    notifyListeners();

    LoggerService.instance.log(
      'Starting batch download for all required translation models...',
      source: _tag,
    );
    AppLogger.info(
      'Starting batch download for all required translation models...',
      tag: _tag,
    );

    bool allSuccess = true;
    try {
      final missing = await getMissingRequiredModels();
      if (missing.isEmpty) {
        LoggerService.instance.log(
          'All required translation models are already downloaded ✓',
          source: _tag,
        );
        AppLogger.info(
          'All required translation models are already downloaded ✓',
          tag: _tag,
        );
        return true;
      }

      for (int i = 0; i < missing.length; i++) {
        final model = missing[i];
        LoggerService.instance.log(
          'Batch progress: downloading [${i + 1}/${missing.length}] ${model.name}...',
          source: _tag,
        );
        final success = await downloadModel(
          model.code,
          timeout: timeout,
          requireWifi: requireWifi,
        );
        if (!success) {
          allSuccess = false;
        }
      }
    } finally {
      _batchDownloading = false;
      notifyListeners();
    }

    LoggerService.instance.log(
      allSuccess
          ? 'Batch download completed successfully ✓'
          : 'Batch download finished with some errors',
      source: _tag,
    );

    return allSuccess;
  }

  /// Deletes a model from local storage (useful for testing & resets).
  Future<bool> deleteModel(String code) async {
    final model = _models.firstWhere(
      (m) => m.code == code,
      orElse: () => throw ArgumentError('Unknown model code: $code'),
    );

    LoggerService.instance.log('Deleting model: ${model.name} ($code)', source: _tag);
    AppLogger.info('Deleting model: ${model.name} ($code)', tag: _tag);

    try {
      final deleted = await _mlKitModelManager.deleteModel(model.code);
      await checkModelStatus(code);
      return deleted;
    } catch (e) {
      AppLogger.warning('Failed to delete model ${model.name}: $e', tag: _tag);
      return false;
    }
  }
}
