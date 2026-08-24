import '../../models/translation_model_config.dart';

/// Application-wide constants for Tarjim.
///
/// Centralizes strings and configuration values so they are never
/// hardcoded across the UI, services, or native channel layers.
abstract final class AppConstants {
  // ─── App identity ────────────────────────────────────────────────
  static const String appName = 'Tarjim';
  static const String appNameArabic = 'ترجم';
  static const String appVersion = '1.0.0';

  // ─── Native interop (Step 5) ─────────────────────────────────────
  /// MethodChannel name shared between Flutter and Android native code.
  static const String methodChannelName = 'com.example.tarjim/core';

  // ─── Translation languages (Steps 7–8) ───────────────────────────
  static const String sourceLanguageJapanese = 'ja';
  static const String sourceLanguageEnglish = 'en';
  static const String targetLanguageArabic = 'ar';

  /// Central list of supported translation models.
  static const List<TranslationModelConfig> supportedTranslationModels = [
    TranslationModelConfig(
      code: sourceLanguageJapanese,
      name: 'Japanese',
      nativeName: '日本語',
      isRequired: true,
    ),
    TranslationModelConfig(
      code: sourceLanguageEnglish,
      name: 'English',
      nativeName: 'English',
      isRequired: true,
    ),
    TranslationModelConfig(
      code: targetLanguageArabic,
      name: 'Arabic',
      nativeName: 'العربية',
      isRequired: true,
    ),
  ];

  // ─── Status labels used by the UI ────────────────────────────────
  static const String statusIdle = 'Idle';
  static const String statusRunning = 'Running';
  static const String statusDenied = 'Denied';
  static const String statusGranted = 'Granted';
}

