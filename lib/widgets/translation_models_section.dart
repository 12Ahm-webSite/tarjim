import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../core/theme/app_theme.dart';
import '../services/ocr_model_manager.dart';
import '../services/translation_model_manager.dart';

/// Card and list section for viewing and downloading translation models
/// as well as the Japanese OCR model.
class TranslationModelsSection extends StatelessWidget {
  const TranslationModelsSection({
    super.key,
    required this.controller,
  });

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modelManager = controller.modelManager;
    final ocrModelManager = controller.ocrModelManager;
    final states = modelManager.states;
    final ocrState = ocrModelManager.state;
    final hasMissingRequired =
        states.any((s) => s.config.isRequired && !s.isDownloaded);
    final isAllReady = !hasMissingRequired && ocrState.isReady;
    final isAnyDownloading =
        modelManager.isAnyDownloading || ocrModelManager.isDownloading;
    final isBatchDownloading = modelManager.isBatchDownloading;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────
            Row(
              children: [
                Icon(
                  Icons.translate_rounded,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Translation Models',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'نماذج الترجمة والتعرف على الجهاز (On-Device)',
                        style: AppTheme.arabicText(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isAllReady)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: Colors.green.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 14, color: Colors.green),
                        SizedBox(width: 4),
                        Text(
                          'Ready',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // ── Japanese OCR Model Row ───────────────────────────────
            _OcrModelRow(
              state: ocrState,
              isBusy: isAnyDownloading,
              onPrepare: controller.prepareOCRModel,
            ),
            const SizedBox(height: 4),
            const Divider(height: 1),
            const SizedBox(height: 4),

            // ── List of translation models ───────────────────────────
            ...states.map((state) {
              return _ModelRow(
                state: state,
                isBusy: isAnyDownloading,
                onDownload: () => controller.downloadModel(state.config.code),
              );
            }),

            const SizedBox(height: 12),

            // ── Bulk download button ──────────────────────────────────
            if (hasMissingRequired)
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  icon: isBatchDownloading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_for_offline_rounded, size: 18),
                  label: Text(
                    isBatchDownloading
                        ? 'Downloading Required Models...'
                        : 'Download Required Models',
                  ),
                  onPressed: isAnyDownloading
                      ? null
                      : () => controller.downloadRequiredModels(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OcrModelRow extends StatelessWidget {
  const _OcrModelRow({
    required this.state,
    required this.isBusy,
    required this.onPrepare,
  });

  final OCRModelState state;
  final bool isBusy;
  final VoidCallback onPrepare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.document_scanner_rounded,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Japanese OCR',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(التعرف على النص)',
                      style: AppTheme.arabicText(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Required',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                if (state.isDownloading)
                  Text(
                    state.statusMessage ?? 'Preparing OCR model...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else if (state.isFailed)
                  Text(
                    state.lastError ?? 'OCR model failed',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                else if (state.isReady)
                  Text(
                    'Ready for text recognition',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Text(
                    'Google Play Services module pending',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildAction(context),
        ],
      ),
    );
  }

  Widget _buildAction(BuildContext context) {
    final theme = Theme.of(context);

    switch (state.status) {
      case OCRModelStatus.ready:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_rounded,
                size: 16,
                color: Colors.green,
              ),
              SizedBox(width: 4),
              Text(
                'Ready',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        );

      case OCRModelStatus.downloading:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Preparing...',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        );

      case OCRModelStatus.failed:
        return OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
            side: BorderSide(color: theme.colorScheme.error),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.refresh_rounded, size: 14),
          label: const Text('Retry', style: TextStyle(fontSize: 12)),
          onPressed: isBusy ? null : onPrepare,
        );

      case OCRModelStatus.notReady:
        return FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.download_rounded, size: 14),
          label: const Text('Prepare', style: TextStyle(fontSize: 12)),
          onPressed: isBusy ? null : onPrepare,
        );
    }
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.state,
    required this.isBusy,
    required this.onDownload,
  });

  final TranslationModelState state;
  final bool isBusy;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = state.config;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Language icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              config.code.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Name and status text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      config.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${config.nativeName})',
                      style: AppTheme.arabicText(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (config.isRequired) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Required',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                if (state.isDownloading)
                  Text(
                    state.statusMessage ?? 'Downloading...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else if (state.isFailed)
                  Text(
                    state.lastError ?? 'Download failed',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                else if (state.isDownloaded)
                  Text(
                    'Ready for on-device translation',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Text(
                    'Not installed on device',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Action / Status Badge
          _buildAction(context),
        ],
      ),
    );
  }

  Widget _buildAction(BuildContext context) {
    final theme = Theme.of(context);

    switch (state.status) {
      case ModelDownloadStatus.downloaded:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_rounded,
                size: 16,
                color: Colors.green,
              ),
              SizedBox(width: 4),
              Text(
                'Downloaded',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        );

      case ModelDownloadStatus.downloading:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Downloading...',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        );

      case ModelDownloadStatus.failed:
        return OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
            side: BorderSide(color: theme.colorScheme.error),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.refresh_rounded, size: 14),
          label: const Text('Retry', style: TextStyle(fontSize: 12)),
          onPressed: isBusy ? null : onDownload,
        );

      case ModelDownloadStatus.notDownloaded:
        return FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.download_rounded, size: 14),
          label: const Text('Download', style: TextStyle(fontSize: 12)),
          onPressed: isBusy ? null : onDownload,
        );
    }
  }
}
