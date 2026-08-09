
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../core/utils/logger.dart';
import '../core/utils/logger_service.dart';
import '../models/text_box.dart';
import '../models/translated_text_box.dart';

/// ML Kit On-Device Translation wrapper for Step 8 of the pipeline.
///
/// Responsible for:
///   1. Ensuring the Japanese → Arabic translation model is available.
///   2. Translating each [TextBox.text] from Japanese to Arabic.
///   3. Returning a [TranslatedTextBox] list with identical bounding boxes.
///   4. Resource cleanup on [dispose].
///
/// This service is intentionally side-effect free: it does not touch any
/// MethodChannels, does not hold UI state, and does not render overlays.
class TranslationService {
  static const _tag = 'TranslationService';

  /// On-device translator: Japanese → Arabic.
  late final OnDeviceTranslator _translator = OnDeviceTranslator(
    sourceLanguage: TranslateLanguage.japanese,
    targetLanguage: TranslateLanguage.arabic,
  );

  /// Model manager for downloading / checking language models.
  final OnDeviceTranslatorModelManager _modelManager =
      OnDeviceTranslatorModelManager();

  bool _disposed = false;

  // ── Lifecycle ──────────────────────────────────────────────────────

  /// Releases the underlying ML Kit resources. Call once when the app is
  /// shutting down (e.g. from [AppController.dispose]). Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _translator.close();
      AppLogger.info('Translator closed', tag: _tag);
    } catch (e) {
      AppLogger.warning('Translator close threw: $e', tag: _tag);
    }
  }

  // ── Public API ─────────────────────────────────────────────────────

  /// Translates a list of OCR [TextBox]es from Japanese to Arabic.
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
    if (boxes.isEmpty) {
      AppLogger.info('translateBoxes called with 0 boxes — nothing to do', tag: _tag);
      return [];
    }

    final stopwatch = Stopwatch()..start();

    // ── Stage 1: Log start ───────────────────────────────────────────
    LoggerService.instance.log('Translation started...', source: _tag);
    AppLogger.info('Translation started...', tag: _tag);

    // ── Stage 2: Ensure models are available ─────────────────────────
    await _ensureModelsDownloaded();

    // ── Stage 3: Translate each box ──────────────────────────────────
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
        final translated = await _translator.translateText(box.text);

        results.add(TranslatedTextBox(
          originalText: box.text,
          translatedText: translated,
          imageWidth: box.imageWidth,
          imageHeight: box.imageHeight,
          left: box.left,
          top: box.top,
          width: box.width,
          height: box.height,
          confidence: box.confidence,
        ));

        // Per-box debug log as requested
        AppLogger.debug(
          '  [${i + 1}/${boxes.length}] '
          'Original: ${box.text}\n'
          '    Translated: $translated\n'
          '    BoundingBox: (${box.left.toStringAsFixed(0)}, ${box.top.toStringAsFixed(0)}, '
          '${box.width.toStringAsFixed(0)}x${box.height.toStringAsFixed(0)})',
          tag: _tag,
        );
        LoggerService.instance.log(
          'Box ${i + 1}/${boxes.length} — '
          'Original: ${box.text} | '
          'Translated: $translated | '
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

    // ── Stage 4: Log completion ──────────────────────────────────────
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
  }

  // ── Helpers ────────────────────────────────────────────────────────

  /// Checks whether both the Japanese and Arabic models are available
  /// on-device. If not, triggers a download and waits for completion.
  Future<void> _ensureModelsDownloaded() async {
    final jaCode = TranslateLanguage.japanese.bcpCode;
    final arCode = TranslateLanguage.arabic.bcpCode;

    final jaReady = await _modelManager.isModelDownloaded(jaCode);
    final arReady = await _modelManager.isModelDownloaded(arCode);

    AppLogger.info(
      'Model status — Japanese ($jaCode): ${jaReady ? 'ready' : 'missing'}, '
      'Arabic ($arCode): ${arReady ? 'ready' : 'missing'}',
      tag: _tag,
    );

    if (!jaReady) {
      LoggerService.instance.log(
        'Downloading Japanese translation model...',
        source: _tag,
      );
      AppLogger.info('Downloading Japanese translation model...', tag: _tag);
      await _modelManager.downloadModel(jaCode);
      LoggerService.instance.log(
        'Downloaded translation model (Japanese)',
        source: _tag,
      );
      AppLogger.info('Downloaded translation model (Japanese)', tag: _tag);
    }

    if (!arReady) {
      LoggerService.instance.log(
        'Downloading Arabic translation model...',
        source: _tag,
      );
      AppLogger.info('Downloading Arabic translation model...', tag: _tag);
      await _modelManager.downloadModel(arCode);
      LoggerService.instance.log(
        'Downloaded translation model (Arabic)',
        source: _tag,
      );
      AppLogger.info('Downloaded translation model (Arabic)', tag: _tag);
    }

    if (jaReady && arReady) {
      LoggerService.instance.log(
        'Translation models already available',
        source: _tag,
      );
    }
  }
}
