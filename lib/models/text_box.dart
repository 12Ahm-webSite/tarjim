
/// A single text region detected by OCR, typically corresponding to one
/// speech bubble or paragraph line in the manga frame.
///
/// Coordinates are in **source image pixels** (relative to the PNG that was
/// passed to OCR). They must be re-scaled by the caller using the source
/// image dimensions before being used to position an overlay on the
/// physical device screen.
class TextBox {
  const TextBox({
    required this.text,
    required this.imageWidth,
    required this.imageHeight,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.confidence,
  });

  /// Raw recognized text (for manga this is usually Japanese, possibly
  /// mixed with English loan words, furigana, or punctuation).
  final String text;

  /// Full dimensions of the source image that was OCR'd. These are required
  /// so callers can compute normalized [Rect] later without re-reading the
  /// image header.
  final int imageWidth;
  final int imageHeight;

  /// Bounding box of the detected text region, in image pixels.
  final double left;
  final double top;
  final double width;
  final double height;

  /// ML Kit confidence value for this block, in the range `0.0 – 1.0`.
  ///
  /// ML Kit does not always expose a per-block confidence, so this field
  /// is nullable.
  final double? confidence;

  // ── Convenience helpers ────────────────────────────────────────────

  /// Right edge of the box, in image pixels.
  double get right => left + width;

  /// Bottom edge of the box, in image pixels.
  double get bottom => top + height;

  /// Bounding box as a plain [Rect]-style record.
  ({double left, double top, double right, double bottom}) get rect =>
      (left: left, top: top, right: right, bottom: bottom);

  /// True if the box contains no readable characters (ML Kit sometimes
  /// emits empty-block artefacts from images with heavy noise).
  bool get isEmpty => text.trim().isEmpty;

  /// Creates a copy of this box with some fields replaced. Used by the
  /// translation step (Step 8) to produce an Arabic twin-box with the
  /// same bounding coordinates.
  TextBox copyWith({
    String? text,
    int? imageWidth,
    int? imageHeight,
    double? left,
    double? top,
    double? width,
    double? height,
    double? confidence,
  }) {
    return TextBox(
      text: text ?? this.text,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      left: left ?? this.left,
      top: top ?? this.top,
      width: width ?? this.width,
      height: height ?? this.height,
      confidence: confidence ?? this.confidence,
    );
  }

  @override
  String toString() {
    final c = confidence == null ? '?' : (confidence! * 100).toStringAsFixed(0);
    return 'TextBox(${left.toStringAsFixed(0)},${top.toStringAsFixed(0)} '
        '${width.toStringAsFixed(0)}x${height.toStringAsFixed(0)} '
        'conf=$c% chars=${text.length} "${text.length > 24 ? '${text.substring(0, 24)}…' : text}")';
  }
}
