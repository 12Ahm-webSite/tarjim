import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../controllers/app_controller.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/status_card.dart';
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
    final error = await _controller.startTranslation();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Translation pipeline started.')),
    );
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
