
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../core/utils/logger.dart';
import '../core/utils/logger_service.dart';
import '../models/text_box.dart';

/// ML Kit Japanese text-recognition wrapper for Step 7 of the pipeline.
///
/// Responsible for converting the raw PNG bytes (or temp file path) from
/// the MediaProjection stage into a structured list of [TextBox] instances
/// with source-image pixel coordinates, suitable for Step 8 (translation)
/// and Step 9 (overlay placement).
///
/// This service is intentionally side-effect free: it does not touch any
/// MethodChannels and does not hold UI state — the controller owns state.
class OCRService {
  static const _tag = 'OCRService';

  /// Japanese script recognizer — the correct script identifier is the
  /// single most important configuration for reading manga speech bubbles.
  /// Using [TextRecognitionScript.latin] here would produce garbage for
  /// hiragana/katakana/kanji text.
  late final TextRecognizer _recognizer = TextRecognizer(
    script: TextRecognitionScript.japanese,
  );

  bool _disposed = false;

  // ── Lifecycle ──────────────────────────────────────────────────────

  /// Releases the underlying ML Kit resources. Call once when the app is
  /// shutting down (e.g. from [AppController.dispose]). Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      _recognizer.close();
      AppLogger.info('OCR recognizer closed', tag: _tag);
    } catch (e) {
      AppLogger.warning('OCR recognizer close threw: $e', tag: _tag);
    }
  }

  // ── Public API ─────────────────────────────────────────────────────

  /// Runs Japanese OCR on the given image.
  ///
  /// Accepts either raw [bytes] or an existing [filePath]. When **both**
  /// are provided, [filePath] wins because `InputImage.fromFilePath` is
  /// the most reliable ingestion path inside ML Kit on Android (it
  /// preserves EXIF rotation metadata automatically).
  ///
  /// Returns an **ordered** list: blocks are sorted top-to-bottom by their
  /// bounding box `top`, then left-to-right by `left` — i.e. natural
  /// reading order for a page with mixed horizontal dialogue.
  Future<List<TextBox>> processImage({
    Uint8List? bytes,
    String? filePath,
    int? imageWidth,
    int? imageHeight,
  }) async {
    if (_disposed) {
      throw StateError('OCRService.processImage called after dispose()');
    }
    if (bytes == null && filePath == null) {
      throw ArgumentError('processImage requires either bytes or filePath');
    }

    // ── Stage 1: OCR started ────────────────────────────────────────
    LoggerService.instance.log(
      'OCR started (filePath=${filePath != null} bytes=${bytes?.lengthInBytes ?? 'n/a'})',
      source: _tag,
    );
    AppLogger.info(
      'OCR started filePath=${filePath != null} bytes=${bytes?.lengthInBytes ?? 'n/a'}',
      tag: _tag,
    );

    final stopwatch = Stopwatch()..start();

    try {
      // ── Stage 2: Input image loaded ──────────────────────────────
      final InputImage inputImage;
      if (filePath != null && File(filePath).existsSync()) {
        inputImage = InputImage.fromFilePath(filePath);
        LoggerService.instance.log(
          'OCR input image loaded from file: $filePath',
          source: _tag,
        );
      } else if (bytes != null) {
        if (imageWidth == null || imageHeight == null) {
          throw ArgumentError(
            'When passing bytes you must also provide imageWidth + imageHeight',
          );
        }
        inputImage = InputImage.fromBytes(
          bytes: bytes,
          metadata: InputImageMetadata(
            size: Size(imageWidth.toDouble(), imageHeight.toDouble()),
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.nv21,
            bytesPerRow: 0,
          ),
        );
        LoggerService.instance.log(
          'OCR input image loaded from bytes (${imageWidth}x$imageHeight)',
          source: _tag,
        );
      } else {
        throw StateError('Unreachable: bytes and filePath are both null');
      }
      AppLogger.info('OCR InputImage prepared', tag: _tag);

      // ── Stage 3: Text recognition started ─────────────────────────
      LoggerService.instance.log('OCR text recognition started (Japanese script)', source: _tag);
      AppLogger.info('OCR processImage() call to ML Kit recognizer', tag: _tag);

      final RecognizedText result = await _recognizer.processImage(inputImage);

      // ── Stage 4–6: Aggregate metrics ──────────────────────────────
      final List<TextBox> boxes = [];
      int totalLines = 0;
      int totalChars = 0;
      final int resolvedW = imageWidth ?? 0;
      final int resolvedH = imageHeight ?? resolvedW;

      for (final TextBlock block in result.blocks) {
        totalLines += block.lines.length;

        for (final TextLine line in block.lines) {
          totalChars += line.text.length;
        }

        final Rect bb = block.boundingBox;
        if (bb.isEmpty) continue; // skip zero-size artefact blocks

        final String cleanText = block.text.trim();
        if (cleanText.isEmpty) continue;

        boxes.add(TextBox(
          text: cleanText,
          imageWidth: resolvedW,
          imageHeight: resolvedH,
          left: bb.left,
          top: bb.top,
          width: bb.width,
          height: bb.height,
          confidence: null,
        ));
      }

      // Sort: top-first, then left-first (natural reading order).
      boxes.sort((TextBox a, TextBox b) {
        final int byTop = a.top.compareTo(b.top);
        if (byTop != 0) return byTop;
        return a.left.compareTo(b.left);
      });

      // ── Stage 4–6 log emission ────────────────────────────────────
      LoggerService.instance.log(
        'OCR blocks detected: ${boxes.length}',
        source: _tag,
      );
      LoggerService.instance.log(
        'OCR lines detected: $totalLines',
        source: _tag,
      );
      LoggerService.instance.log(
        'OCR characters detected: $totalChars',
        source: _tag,
      );
      AppLogger.info(
        'OCR intermediate stats: blocks=${result.blocks.length} '
        'emitted-boxes=$boxes.length lines=$totalLines chars=$totalChars',
        tag: _tag,
      );

      // ── Stage 7: OCR completed ────────────────────────────────────
      stopwatch.stop();
      LoggerService.instance.log(
        'OCR completed in ${stopwatch.elapsedMilliseconds}ms → $boxes.length boxes, $totalChars chars',
        source: _tag,
      );
      AppLogger.info(
        'OCR completed in ${stopwatch.elapsedMilliseconds}ms: '
        '$boxes.length boxes / $totalLines lines / $totalChars chars',
        tag: _tag,
      );

      for (final TextBox box in boxes) {
        AppLogger.debug('  $box', tag: _tag);
      }

      return boxes;
    } catch (e, stack) {
      // ── Stage 8: OCR failed ───────────────────────────────────────
      stopwatch.stop();
      LoggerService.instance.log(
        'OCR FAILED after ${stopwatch.elapsedMilliseconds}ms: ${e.runtimeType}: $e',
        source: _tag,
      );
      AppLogger.error(
        'OCR failed: ${e.runtimeType}: $e',
        tag: _tag,
        stackTrace: stack,
      );
      rethrow;
    }
  }
}
