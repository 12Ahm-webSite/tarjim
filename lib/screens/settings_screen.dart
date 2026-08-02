import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/logger.dart';
import '../core/utils/logger_service.dart';
import 'debug_console_screen.dart';

/// Settings shell for the MVP.
///
/// Values are local UI state for now — persistence and wiring to the
/// real OCR/translation/overlay services arrive in Steps 7–9.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _tag = 'SettingsScreen';

  String _sourceLanguage = AppConstants.sourceLanguageJapanese;
  double _bubbleOpacity = 0.85;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _SectionLabel(label: 'Translation'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Source language', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: AppConstants.sourceLanguageJapanese,
                          label: Text('Japanese'),
                          icon: Icon(Icons.translate_rounded),
                        ),
                        ButtonSegment(
                          value: AppConstants.sourceLanguageEnglish,
                          label: Text('English'),
                          icon: Icon(Icons.abc_rounded),
                        ),
                      ],
                      selected: {_sourceLanguage},
                      onSelectionChanged: (selection) {
                        setState(() => _sourceLanguage = selection.first);
                        AppLogger.info(
                          'Source language → ${selection.first}',
                          tag: _tag,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Target language',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Fixed for the MVP',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'العربية',
                        style: AppTheme.arabicText(
                          fontSize: 20,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _SectionLabel(label: 'Overlay'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Translation bubble opacity',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Applied when the overlay ships in Step 9',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _bubbleOpacity,
                          min: 0.4,
                          max: 1,
                          onChanged: (value) =>
                              setState(() => _bubbleOpacity = value),
                          onChangeEnd: (value) => AppLogger.info(
                            'Bubble opacity → ${value.toStringAsFixed(2)}',
                            tag: _tag,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${(_bubbleOpacity * 100).round()}%',
                          textAlign: TextAlign.end,
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _SectionLabel(label: 'Debug'),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.bug_report_rounded,
                color: theme.colorScheme.primary,
              ),
              title: const Text('Open Debug Console'),
              subtitle: const Text('Inspect MediaProjection lifecycle logs'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                LoggerService.instance.log('Debug console opened', source: 'Flutter');
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DebugConsoleScreen()),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          _SectionLabel(label: 'About'),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.auto_stories_rounded,
                color: theme.colorScheme.primary,
              ),
              title: const Text(AppConstants.appName),
              subtitle: Text('Version ${AppConstants.appVersion} — MVP'),
              trailing: Text(
                AppConstants.appNameArabic,
                style: AppTheme.arabicText(
                  fontSize: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 2,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
