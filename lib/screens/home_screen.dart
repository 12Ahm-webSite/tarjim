import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../controllers/app_controller.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/logger_service.dart';
import '../models/translated_text_box.dart';
import '../widgets/app_button.dart';
import '../widgets/status_card.dart';
import '../widgets/translation_overlay.dart';
import 'permissions_screen.dart';
import 'settings_screen.dart';

/// Main dashboard: pipeline status cards + primary actions.
///
/// Owns the single [AppController] instance and passes it to
/// sub-screens that need live status.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AppController()..addListener(_onControllerChanged);
    _controller.refreshStatuses();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  /// Cards re-sync with real native state whenever the app resumes —
  /// e.g. after returning from the overlay permission settings screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.refreshStatuses();
    }
  }

  void _onControllerChanged() => setState(() {});

  Future<void> _onStartPressed() async {
    LoggerService.instance.log('Start Translation button pressed', source: 'HomeScreen');
    final error = await _controller.startTranslation();
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final capture = _controller.lastCapture;
    if (capture != null) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _CapturePreviewSheet(
          bytes: capture,
          filePath: _controller.lastCapturePath ?? '',
          translatedBoxes: _controller.lastTranslationResult,
        ),
      );
    }
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _openPermissions() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PermissionsScreen(controller: _controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_rounded),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const _HeroHeader(),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.45,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                StatusCard(
                  icon: Icons.screenshot_monitor_rounded,
                  title: 'Screen Capture',
                  status: _controller.screenCaptureStatus,
                ),
                StatusCard(
                  icon: Icons.picture_in_picture_alt_rounded,
                  title: 'Overlay',
                  status: _controller.overlayStatus,
                ),
                StatusCard(
                  icon: Icons.document_scanner_rounded,
                  title: 'OCR',
                  status: _controller.ocrStatus,
                ),
                StatusCard(
                  icon: Icons.translate_rounded,
                  title: 'Translation',
                  status: _controller.translationStatus,
                ),
              ],
            ),
            const SizedBox(height: 24),
            AppButton(
              label: 'Request Permissions',
              icon: Icons.verified_user_rounded,
              variant: AppButtonVariant.tonal,
              onPressed: _openPermissions,
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Start Translation',
              icon: Icons.play_arrow_rounded,
              onPressed: _controller.isTranslating ? null : _onStartPressed,
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Stop Translation',
              icon: Icons.stop_rounded,
              variant: AppButtonVariant.danger,
              onPressed: _controller.isTranslating
                  ? _controller.stopTranslation
                  : null,
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Open Settings',
              icon: Icons.tune_rounded,
              variant: AppButtonVariant.ghost,
              onPressed: _openSettings,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bilingual branding header — English wordmark + Arabic in Noto Naskh.
class _HeroHeader extends StatelessWidget {
  const _HeroHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MANGA TRANSLATION ASSISTANT',
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 2.4,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/images/tarjimLogo.svg',
              width: 56,
              height: 56,
              semanticsLabel: 'Tarjim logo',
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppConstants.appName,
                    style: theme.textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppConstants.appNameArabic,
                    style: AppTheme.arabicText(
                      fontSize: 24,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Bottom sheet that previews the captured screenshot and shows
/// verification metadata (byte size, pixel dimensions, temp file path).
///
/// This is Step 6's visual feedback mechanism — it confirms that
/// the native MediaProjection pipeline successfully delivered PNG
/// bytes back to Flutter via the MethodChannel.
class _CapturePreviewSheet extends StatefulWidget {
  const _CapturePreviewSheet({
    required this.bytes,
    required this.filePath,
    this.translatedBoxes = const [],
  });

  final Uint8List bytes;
  final String filePath;
  final List<TranslatedTextBox> translatedBoxes;

  @override
  State<_CapturePreviewSheet> createState() => _CapturePreviewSheetState();
}

class _CapturePreviewSheetState extends State<_CapturePreviewSheet> {
  int? _width;
  int? _height;
  bool _decoding = true;
  String? _decodeError;

  @override
  void initState() {
    super.initState();
    _decodeDimensions();
  }

  Future<void> _decodeDimensions() async {
    try {
      final decoded = await decodeImageFromList(widget.bytes);
      if (!mounted) return;
      setState(() {
        _width = decoded.width;
        _height = decoded.height;
        _decoding = false;
      });
      decoded.dispose();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _decodeError = e.toString();
        _decoding = false;
      });
    }
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(size < 10 && unitIndex > 0 ? 2 : 0)} ${units[unitIndex]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final sheetHeight = mediaQuery.size.height * 0.82;

    return Container(
      height: sheetHeight,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.image_rounded,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Capture Preview',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    constraints: BoxConstraints(
                      maxHeight: sheetHeight * 0.45,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 5,
                      boundaryMargin: const EdgeInsets.all(20),
                      child: LayoutBuilder(
                        builder: (context, imageConstraints) {
                          if (widget.translatedBoxes.isNotEmpty) {
                            return MeasuredTranslationOverlay(
                              imageBytes: widget.bytes,
                              boxes: widget.translatedBoxes,
                              containerConstraints: imageConstraints,
                            );
                          }
                          return Image.memory(
                            widget.bytes,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            errorBuilder: (ctx, err, _) => Padding(
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
                                    err.toString(),
                                    style: theme.textTheme.bodySmall,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Capture Details',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _DetailRow(
                    icon: Icons.sd_storage_rounded,
                    label: 'File size',
                    value: _formatBytes(widget.bytes.lengthInBytes),
                    subValue: '${widget.bytes.lengthInBytes} bytes',
                  ),
                  _DetailRow(
                    icon: Icons.aspect_ratio_rounded,
                    label: 'Dimensions',
                    value: _decoding
                        ? 'Decoding…'
                        : _decodeError != null
                            ? 'Decode failed'
                            : _width != null && _height != null
                                ? '$_width × $_height px'
                                : 'Unknown',
                    subValue: _decodeError,
                    error: _decodeError != null,
                    loading: _decoding,
                  ),
                  _DetailRow(
                    icon: Icons.folder_rounded,
                    label: 'Saved to',
                    value: widget.filePath.isEmpty
                        ? '(not persisted)'
                        : widget.filePath,
                    mono: true,
                  ),
                  _DetailRow(
                    icon: Icons.enhance_photo_translate_rounded,
                    label: 'Format',
                    value: 'PNG · RGBA 8-bit',
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.translatedBoxes.isNotEmpty
                                ? 'Step 9 verified — Full pipeline complete: '
                                  'Capture → OCR → Translation → Display. '
                                  '${widget.translatedBoxes.length} translated '
                                  'text boxes rendered on the captured image.'
                                : 'Step 6 verified — MediaProjection successfully '
                                  'captured one frame and delivered PNG bytes to '
                                  'Flutter through the MethodChannel.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A label / value row used inside the capture preview details list.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.subValue,
    this.mono = false,
    this.error = false,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subValue;
  final bool mono;
  final bool error;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = mono
        ? theme.textTheme.bodyMedium?.copyWith(
            fontFamily: 'monospace',
            color: error ? theme.colorScheme.error : null,
          )
        : theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: error
                ? theme.colorScheme.error
                : loading
                    ? theme.colorScheme.onSurfaceVariant
                    : null,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              icon,
              size: 18,
            color: loading
                ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
                : error
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                if (loading)
                  Row(
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(value, style: valueStyle),
                    ],
                  )
                else
                  Text(value, style: valueStyle),
                if (subValue != null && subValue!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subValue!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: error
                          ? theme.colorScheme.error.withValues(alpha: 0.8)
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
