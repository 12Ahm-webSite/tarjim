
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../core/utils/logger.dart';
import '../core/utils/logger_service.dart';
import '../models/text_box.dart';
import '../models/translated_text_box.dart';

/// ML Kit On-Device Translation wrapper for Step 8 of the pipeline.
///
/// Uses explicit two-step translation:
///   Japanese → English → Arabic
///
/// This mirrors the pipeline that was previously proven to work and gives
/// us full control over model downloads (ja + en + ar) rather than
/// relying on ML Kit's implicit English pivot.
///
/// Responsible for:
///   1. Ensuring all 3 language models (ja, en, ar) are downloaded.
///   2. Translating each [TextBox.text]: Japanese → English → Arabic.
///   3. Returning a [TranslatedTextBox] list with identical bounding boxes.
///   4. Resource cleanup on [dispose].
///
/// This service is intentionally side-effect free: it does not touch any
/// MethodChannels, does not hold UI state, and does not render overlays.
class TranslationService {
  static const _tag = 'TranslationService';

  // ── Two-step translators ───────────────────────────────────────────
  /// Step 1: Japanese → English
  late final OnDeviceTranslator _jaToEn = OnDeviceTranslator(
    sourceLanguage: TranslateLanguage.japanese,
    targetLanguage: TranslateLanguage.english,
  );

  /// Step 2: English → Arabic
  late final OnDeviceTranslator _enToAr = OnDeviceTranslator(
    sourceLanguage: TranslateLanguage.english,
    targetLanguage: TranslateLanguage.arabic,
  );

  /// Model manager for downloading / checking language models.
  final OnDeviceTranslatorModelManager _modelManager =
      OnDeviceTranslatorModelManager();

  bool _disposed = false;

  /// Guard: prevents parallel translation runs.
  bool _isRunning = false;

  /// Maximum retry attempts for model download.
  static const int _maxDownloadRetries = 3;

  // ── Lifecycle ──────────────────────────────────────────────────────

  /// Releases the underlying ML Kit resources. Call once when the app is
  /// shutting down (e.g. from [AppController.dispose]). Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _jaToEn.close();
      await _enToAr.close();
      AppLogger.info('Both translators closed (ja→en, en→ar)', tag: _tag);
    } catch (e) {
      AppLogger.warning('Translator close threw: $e', tag: _tag);
    }
  }

  // ── Public API ─────────────────────────────────────────────────────

  /// Translates a list of OCR [TextBox]es from Japanese to Arabic
  /// via explicit two-step pipeline: Japanese → English → Arabic.
  ///
  /// Returns a list of [TranslatedTextBox] with the same ordering and
  /// bounding coordinates as the input. Boxes with empty text are
  /// skipped (their indices are dropped from the result).
  ///
  /// On the very first invocation the underlying language models may
  /// need to be downloaded from Google Play Services. This method
  /// handles the download automatically and logs progress.
  Future<List<TranslatedTextBox>> translateBoxes(List<TextBox> boxes) async {
    if (_disposed) {
      throw StateError('TranslationService.translateBoxes called after dispose()');
    }

    // ── Guard: prevent parallel runs ─────────────────────────────────
    if (_isRunning) {
      AppLogger.warning(
        'translateBoxes called while already running — skipping',
        tag: _tag,
      );
      LoggerService.instance.log(
        'Translation skipped: already in progress',
        source: _tag,
      );
      return [];
    }

    if (boxes.isEmpty) {
      AppLogger.info('translateBoxes called with 0 boxes — nothing to do', tag: _tag);
      return [];
    }

    _isRunning = true;

    try {
      final stopwatch = Stopwatch()..start();

      // ── Stage 1: Log start ─────────────────────────────────────────
      LoggerService.instance.log('Translation started...', source: _tag);
      AppLogger.info('Translation started...', tag: _tag);

      // ── Stage 2: Ensure all 3 models are available ─────────────────
      await _ensureModelsDownloaded();

      // ── Stage 3: Translate each box (ja → en → ar) ─────────────────
      LoggerService.instance.log(
        'Translating ${boxes.length} text boxes...',
        source: _tag,
      );
      AppLogger.info('Translating ${boxes.length} text boxes...', tag: _tag);

      final List<TranslatedTextBox> results = [];

      for (int i = 0; i < boxes.length; i++) {
        final box = boxes[i];
        if (box.isEmpty) continue;

        try {
          // Step 1: Japanese → English
          final english = await _jaToEn.translateText(box.text);

          // Step 2: English → Arabic
          final arabic = await _enToAr.translateText(english);

          results.add(TranslatedTextBox(
            originalText: box.text,
            translatedText: arabic,
            imageWidth: box.imageWidth,
            imageHeight: box.imageHeight,
            left: box.left,
            top: box.top,
            width: box.width,
            height: box.height,
            confidence: box.confidence,
          ));

          // Per-box debug log
          AppLogger.debug(
            '  [${i + 1}/${boxes.length}] '
            'Original: ${box.text}\n'
            '    → English: $english\n'
            '    → Arabic: $arabic\n'
            '    BoundingBox: (${box.left.toStringAsFixed(0)}, ${box.top.toStringAsFixed(0)}, '
            '${box.width.toStringAsFixed(0)}x${box.height.toStringAsFixed(0)})',
            tag: _tag,
          );
          LoggerService.instance.log(
            'Box ${i + 1}/${boxes.length} — '
            'Original: ${box.text} | '
            'English: $english | '
            'Arabic: $arabic | '
            'BoundingBox: (${box.left.toStringAsFixed(0)}, ${box.top.toStringAsFixed(0)}, '
            '${box.width.toStringAsFixed(0)}x${box.height.toStringAsFixed(0)})',
            source: _tag,
          );
        } catch (e) {
          // Log the failure for this box but continue with remaining boxes
          AppLogger.warning(
            'Translation failed for box ${i + 1}/${boxes.length}: $e — '
            'text="${box.text}"',
            tag: _tag,
          );
          LoggerService.instance.log(
            'Translation failed for box ${i + 1}: ${e.runtimeType}: $e',
            source: _tag,
          );
        }
      }

      // ── Stage 4: Log completion ────────────────────────────────────
      stopwatch.stop();
      LoggerService.instance.log(
        'Translation completed in ${stopwatch.elapsedMilliseconds} ms',
        source: _tag,
      );
      AppLogger.info(
        'Translation completed in ${stopwatch.elapsedMilliseconds} ms — '
        '${results.length}/${boxes.length} boxes translated',
        tag: _tag,
      );

      return results;
    } finally {
      _isRunning = false;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────

  /// Downloads all 3 language models sequentially: ja → en → ar.
  ///
  /// For each model:
  ///   1. Check if already downloaded
  ///   2. If not, download with up to [_maxDownloadRetries] attempts
  ///   3. Verify with [isModelDownloaded] after download
  Future<void> _ensureModelsDownloaded() async {
    final jaCode = TranslateLanguage.japanese.bcpCode;
    final enCode = TranslateLanguage.english.bcpCode;
    final arCode = TranslateLanguage.arabic.bcpCode;

    LoggerService.instance.log(
      'Checking all 3 translation models (ja, en, ar)...',
      source: _tag,
    );

    await _ensureSingleModel(jaCode, 'Japanese (ja)');
    await _ensureSingleModel(enCode, 'English (en)');
    await _ensureSingleModel(arCode, 'Arabic (ar)');

    LoggerService.instance.log(
      'All 3 translation models ready',
      source: _tag,
    );
    AppLogger.info('All 3 translation models ready', tag: _tag);
  }

  /// Checks and downloads a single language model with retry and
  /// verification.
  Future<void> _ensureSingleModel(String bcpCode, String label) async {
    // ── Check ────────────────────────────────────────────────────────
    LoggerService.instance.log(
      'Checking $label model',
      source: _tag,
    );
    AppLogger.info('Checking $label model', tag: _tag);

    final alreadyDownloaded = await _modelManager.isModelDownloaded(bcpCode);

    if (alreadyDownloaded) {
      LoggerService.instance.log(
        '$label already downloaded ✓',
        source: _tag,
      );
      AppLogger.info('$label already downloaded ✓', tag: _tag);
      return;
    }

    LoggerService.instance.log(
      '$label not downloaded — starting download',
      source: _tag,
    );
    AppLogger.info('$label not downloaded — starting download', tag: _tag);

    // ── Download with retry ──────────────────────────────────────────
    for (int attempt = 1; attempt <= _maxDownloadRetries; attempt++) {
      LoggerService.instance.log(
        'Starting $label download (attempt $attempt/$_maxDownloadRetries)',
        source: _tag,
      );
      AppLogger.info(
        'Starting $label download (attempt $attempt/$_maxDownloadRetries)',
        tag: _tag,
      );

      try {
        final success = await _modelManager.downloadModel(bcpCode);

        if (!success) {
          AppLogger.warning(
            '$label downloadModel returned false (attempt $attempt/$_maxDownloadRetries)',
            tag: _tag,
          );
          LoggerService.instance.log(
            '$label download returned false (attempt $attempt/$_maxDownloadRetries)',
            source: _tag,
          );

          if (attempt >= _maxDownloadRetries) {
            throw StateError(
              '$label model download failed after $_maxDownloadRetries attempts '
              '(downloadModel returned false)',
            );
          }

          // Wait before retry
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
      } catch (e) {
        if (e is StateError) rethrow;

        AppLogger.warning(
          '$label download threw exception (attempt $attempt/$_maxDownloadRetries): '
          '${e.runtimeType}: $e',
          tag: _tag,
        );
        LoggerService.instance.log(
          '$label download exception (attempt $attempt/$_maxDownloadRetries): '
          '${e.runtimeType}: $e',
          source: _tag,
        );

        if (attempt >= _maxDownloadRetries) {
          throw StateError(
            '$label model download failed after $_maxDownloadRetries attempts: $e',
          );
        }

        // Wait before retry
        await Future.delayed(const Duration(seconds: 2));
        continue;
      }

      // ── Verify after download ────────────────────────────────────
      final verified = await _modelManager.isModelDownloaded(bcpCode);
      if (verified) {
        LoggerService.instance.log(
          '$label download completed ✓ (verified)',
          source: _tag,
        );
        AppLogger.info('$label download completed ✓ (verified)', tag: _tag);
        return;
      }

      AppLogger.warning(
        '$label downloadModel succeeded but isModelDownloaded is still false '
        '(attempt $attempt/$_maxDownloadRetries)',
        tag: _tag,
      );
      LoggerService.instance.log(
        '$label download succeeded but verification failed '
        '(attempt $attempt/$_maxDownloadRetries)',
        source: _tag,
      );

      if (attempt >= _maxDownloadRetries) {
        throw StateError(
          '$label model verification failed after $_maxDownloadRetries attempts',
        );
      }

      // Wait before retry
      await Future.delayed(const Duration(seconds: 2));
    }
  }
}
