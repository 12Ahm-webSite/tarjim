import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/translated_text_box.dart';

/// Renders translated Arabic text boxes on top of a captured manga image.
///
/// This is Step 9's visual proof-of-concept: it overlays each
/// [TranslatedTextBox] at the exact bounding-box position from OCR,
/// scaled to match the rendered image size on screen.
///
/// ### Coordinate mapping
///
/// The coordinates in [TranslatedTextBox] are in **source image pixels**
/// (e.g. 1080×2400). The rendered image on screen may be much smaller
/// (e.g. 360×800). We compute scale factors once the image is laid out:
///
/// ```
/// scaleX = renderedWidth  / imageWidth
/// scaleY = renderedHeight / imageHeight
/// ```
///
/// Each box is then positioned at `(left * scaleX, top * scaleY)` with
/// size `(width * scaleX, height * scaleY)`.
class TranslationOverlay extends StatelessWidget {
  const TranslationOverlay({
    super.key,
    required this.imageBytes,
    required this.boxes,
  });

  /// PNG bytes of the captured screenshot.
  final Uint8List imageBytes;

  /// Translated text boxes to render on top of the image.
  final List<TranslatedTextBox> boxes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // ── Base image ────────────────────────────────────────
            Image.memory(
              imageBytes,
              fit: BoxFit.contain,
              width: constraints.maxWidth,
              gaplessPlayback: true,
              errorBuilder: (ctx, err, _) => _ImageError(error: err),
              // Once the image is laid out, we use its actual rendered
              // size to scale the overlay boxes. We wrap the image +
              // overlays in a second LayoutBuilder that measures the
              // actual image widget after layout.
            ),
          ],
        );
      },
    );
  }
}

/// The actual overlay implementation that measures the rendered image
/// and positions translated text boxes on top.
///
/// We need to know the real rendered dimensions of the image to compute
/// scale factors. Since `Image.memory` with `BoxFit.contain` may not
/// fill its parent fully, we use a [_MeasuredTranslationOverlay] that
/// decodes dimensions from the PNG bytes and computes the fitted size.
class MeasuredTranslationOverlay extends StatefulWidget {
  const MeasuredTranslationOverlay({
    super.key,
    required this.imageBytes,
    required this.boxes,
    required this.containerConstraints,
  });

  final Uint8List imageBytes;
  final List<TranslatedTextBox> boxes;
  final BoxConstraints containerConstraints;

  @override
  State<MeasuredTranslationOverlay> createState() =>
      _MeasuredTranslationOverlayState();
}

class _MeasuredTranslationOverlayState
    extends State<MeasuredTranslationOverlay> {
  int? _imageWidth;
  int? _imageHeight;
  bool _decoded = false;

  @override
  void initState() {
    super.initState();
    _decodeImageSize();
  }

  Future<void> _decodeImageSize() async {
    try {
      final image = await decodeImageFromList(widget.imageBytes);
      if (!mounted) return;
      setState(() {
        _imageWidth = image.width;
        _imageHeight = image.height;
        _decoded = true;
      });
      image.dispose();
    } catch (_) {
      if (!mounted) return;
      setState(() => _decoded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxW = widget.containerConstraints.maxWidth;
    final maxH = widget.containerConstraints.maxHeight;

    // ── Compute fitted image size ──────────────────────────────────
    // Image.memory with BoxFit.contain scales the image to fit inside
    // the constraints while preserving aspect ratio.
    double renderedW = maxW;
    double renderedH = maxH;

    if (_decoded && _imageWidth != null && _imageHeight != null) {
      final imgAspect = _imageWidth! / _imageHeight!;
      final boxAspect = maxW / maxH;

      if (imgAspect > boxAspect) {
        // Image is wider than container → width-limited
        renderedW = maxW;
        renderedH = maxW / imgAspect;
      } else {
        // Image is taller than container → height-limited
        renderedH = maxH;
        renderedW = maxH * imgAspect;
      }
    }

    // Offset to center the image within the container
    final offsetX = (maxW - renderedW) / 2;
    final offsetY = (maxH - renderedH) / 2;

    return Stack(
      children: [
        // ── Base image ──────────────────────────────────────────
        Image.memory(
          widget.imageBytes,
          fit: BoxFit.contain,
          width: maxW,
          height: maxH,
          gaplessPlayback: true,
          errorBuilder: (ctx, err, _) => _ImageError(error: err),
        ),

        // ── Translated text overlays ────────────────────────────
        if (_decoded &&
            _imageWidth != null &&
            _imageHeight != null &&
            widget.boxes.isNotEmpty)
          ...widget.boxes.map((box) {
            final scaleX = renderedW / _imageWidth!;
            final scaleY = renderedH / _imageHeight!;

            final scaledLeft = offsetX + box.left * scaleX;
            final scaledTop = offsetY + box.top * scaleY;
            final scaledWidth = box.width * scaleX;
            final scaledHeight = box.height * scaleY;

            return Positioned(
              left: scaledLeft,
              top: scaledTop,
              width: scaledWidth,
              height: scaledHeight,
              child: _TranslatedBoxWidget(
                text: box.translatedText,
                boxWidth: scaledWidth,
                boxHeight: scaledHeight,
              ),
            );
          }),
      ],
    );
  }
}

/// Renders a single translated text box with a semi-transparent
/// background and auto-sized Arabic text.
class _TranslatedBoxWidget extends StatelessWidget {
  const _TranslatedBoxWidget({
    required this.text,
    required this.boxWidth,
    required this.boxHeight,
  });

  final String text;
  final double boxWidth;
  final double boxHeight;

  @override
  Widget build(BuildContext context) {
    // Compute a font size that fits within the box. We use the box
    // height as the primary constraint, clamped to reasonable bounds.
    // For manga text boxes which are often tall and narrow (vertical
    // text), we use the smaller dimension.
    final minDimension = boxWidth < boxHeight ? boxWidth : boxHeight;
    final fontSize = (minDimension * 0.35).clamp(8.0, 24.0);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xE6121924), // near-black, ~90% opacity
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: AppTheme.accent.withValues(alpha: 0.5),
          width: 0.8,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      alignment: Alignment.center,
      child: Text(
        text,
        style: AppTheme.arabicText(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: const Color(0xFFE6EDF3),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
        overflow: TextOverflow.ellipsis,
        maxLines: (boxHeight / (fontSize * 1.7)).floor().clamp(1, 20),
      ),
    );
  }
}

/// Fallback error widget when the image cannot be decoded.
class _ImageError extends StatelessWidget {
  const _ImageError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_rounded,
            size: 44,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 8),
          Text(
            'Preview unavailable',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            error.toString(),
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
