
/// A [TextBox] that has been translated from Japanese to Arabic.
///
/// Carries the original OCR text alongside the Arabic translation, while
/// preserving the exact bounding-box coordinates from Step 7 so that Step 9
/// (overlay rendering) can position the translated text at the correct
/// screen location.
class TranslatedTextBox {
  const TranslatedTextBox({
    required this.originalText,
    required this.translatedText,
    required this.imageWidth,
    required this.imageHeight,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.confidence,
  });

  /// Raw Japanese text as recognized by OCR.
  final String originalText;

  /// Arabic translation produced by ML Kit On-Device Translation.
  final String translatedText;

  /// Full dimensions of the source image (carried from [TextBox]).
  final int imageWidth;
  final int imageHeight;

  /// Bounding box of the detected text region, in source image pixels
  /// (carried verbatim from [TextBox]).
  final double left;
  final double top;
  final double width;
  final double height;

  /// ML Kit OCR confidence value for the original text block (`0.0 – 1.0`).
  /// Nullable because ML Kit does not always expose per-block confidence.
  final double? confidence;

  // ── Convenience helpers ──────────────────────────────────────────

  /// Right edge of the box, in image pixels.
  double get right => left + width;

  /// Bottom edge of the box, in image pixels.
  double get bottom => top + height;

  /// Bounding box as a plain record.
  ({double left, double top, double right, double bottom}) get rect =>
      (left: left, top: top, right: right, bottom: bottom);

  /// True if the translated text is empty (should not happen but defensive).
  bool get isEmpty => translatedText.trim().isEmpty;

  @override
  String toString() {
    final c = confidence == null ? '?' : (confidence! * 100).toStringAsFixed(0);
    return 'TranslatedTextBox('
        '${left.toStringAsFixed(0)},${top.toStringAsFixed(0)} '
        '${width.toStringAsFixed(0)}x${height.toStringAsFixed(0)} '
        'conf=$c% '
        'orig="${originalText.length > 20 ? '${originalText.substring(0, 20)}…' : originalText}" '
        'trans="${translatedText.length > 30 ? '${translatedText.substring(0, 30)}…' : translatedText}")';
  }
}
