import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/logger.dart';
import '../core/utils/logger_service.dart';
import '../models/text_box.dart';
import '../models/translated_text_box.dart';

/// ML Kit On-Device Translation wrapper for Step 8 of the pipeline.
///
/// Uses explicit two-step translation:
///   Japanese → English → Arabic
///
/// Responsible for:
///   1. Verifying that required translation models (ja, en, ar) are installed.
///   2. Translating each [TextBox.text]: Japanese → English → Arabic.
///   3. Returning a [TranslatedTextBox] list with identical bounding boxes.
///   4. Resource cleanup on [dispose].
///
/// **Design Rule**: This service MUST NEVER initiate network downloads.
/// Model installation is handled independently by [TranslationModelManager].
///
/// **Concurrency**: This service does NOT guard against parallel calls.
/// The caller ([AppController]) is responsible for ensuring only one
/// `translateBoxes` call is active at a time via `_translationInProgress`.
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

  /// Model manager used strictly for checking local model availability.
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
  /// Fails immediately with [StateError] if any required model is not installed.
  /// Does NOT trigger any downloads.
  Future<List<TranslatedTextBox>> translateBoxes(List<TextBox> boxes) async {
    LoggerService.instance.log('translateBoxes() CALLED', source: _tag);
    AppLogger.info('translateBoxes() CALLED with ${boxes.length} boxes', tag: _tag);

    if (_disposed) {
      throw StateError('TranslationService.translateBoxes called after dispose()');
    }

    if (boxes.isEmpty) {
      AppLogger.info('translateBoxes called with 0 boxes — nothing to do', tag: _tag);
      return [];
    }

    final stopwatch = Stopwatch()..start();

    // ── Stage 1: Verify model availability (No download) ───────────
    LoggerService.instance.log('Checking required translation models availability...', source: _tag);
    AppLogger.info('Checking required translation models availability...', tag: _tag);

    final jaReady = await _modelManager.isModelDownloaded(AppConstants.sourceLanguageJapanese);
    final enReady = await _modelManager.isModelDownloaded(AppConstants.sourceLanguageEnglish);
    final arReady = await _modelManager.isModelDownloaded(AppConstants.targetLanguageArabic);

    if (!jaReady || !enReady || !arReady) {
      final missing = <String>[
        if (!jaReady) 'Japanese (${AppConstants.sourceLanguageJapanese})',
        if (!enReady) 'English (${AppConstants.sourceLanguageEnglish})',
        if (!arReady) 'Arabic (${AppConstants.targetLanguageArabic})',
      ];
      final errorMsg = 'Required translation models are missing: ${missing.join(', ')}. '
          'Please download them in the Translation Models section before translating.';
      LoggerService.instance.log(errorMsg, source: _tag, level: 'WARN');
      AppLogger.warning(errorMsg, tag: _tag);
      throw StateError(errorMsg);
    }

    LoggerService.instance.log('All required translation models verified present on disk ✓', source: _tag);
    AppLogger.info('All required translation models verified present on disk ✓', tag: _tag);

    // ── Stage 2: Translate each box (ja → en → ar) ─────────────────
    LoggerService.instance.log(
      'translation START — ${boxes.length} text boxes',
      source: _tag,
    );
    AppLogger.info('translation START — ${boxes.length} text boxes', tag: _tag);

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

    // ── Stage 3: Log completion ────────────────────────────────────
    stopwatch.stop();
    LoggerService.instance.log(
      'translation END — completed in ${stopwatch.elapsedMilliseconds} ms',
      source: _tag,
    );
    AppLogger.info(
      'translation END — completed in ${stopwatch.elapsedMilliseconds} ms — '
      '${results.length}/${boxes.length} boxes translated',
      tag: _tag,
    );

    return results;
  }
}
