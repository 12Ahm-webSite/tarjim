import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tarjim theme configuration.
///
/// Design direction: dark-first "manga reader" aesthetic —
/// near-black ink surfaces, high-contrast typography, and a
/// green-teal accent. A clean light theme is provided as well,
/// and the app follows the system theme by default.
abstract final class AppTheme {
  // ─── Palette ─────────────────────────────────────────────────────
  /// Green-teal accent used across the whole app.
  static const Color accent = Color(0xFF14B8A6);

  /// Dark "ink" surfaces — the manga-reader backdrop.
  static const Color inkBackground = Color(0xFF0B0F14);
  static const Color inkSurface = Color(0xFF121924);
  static const Color inkSurfaceHigh = Color(0xFF1B2432);

  /// Light surfaces.
  static const Color paperBackground = Color(0xFFF7FAF9);

  // ─── Themes ──────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: accent,
      surface: inkSurface,
      onSurface: const Color(0xFFE6EDF3),
      surfaceContainerHighest: inkSurfaceHigh,
    );

    return _base(scheme).copyWith(
      scaffoldBackgroundColor: inkBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: inkBackground,
        foregroundColor: Color(0xFFE6EDF3),
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: inkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: accent.withValues(alpha: 0.25)),
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: const Color(0xFF0F766E), // deeper teal for light-mode contrast
      surface: Colors.white,
    );

    return _base(scheme).copyWith(
      scaffoldBackgroundColor: paperBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: paperBackground,
        foregroundColor: Color(0xFF10201D),
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: accent.withValues(alpha: 0.35)),
        ),
      ),
    );
  }

  /// Shared Material 3 setup + manga-inspired typography:
  /// extra-bold headings with tight tracking, highly legible body text.
  static ThemeData _base(ColorScheme scheme) {
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = base.textTheme;

    return base.copyWith(
      textTheme: text.copyWith(
        headlineLarge: text.headlineLarge?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.25,
        ),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  // ─── Arabic typography ───────────────────────────────────────────
  /// Noto Naskh Arabic — used for translated manga text and Arabic UI.
  /// [height] gives Arabic script the line breathing room it needs.
  static TextStyle arabicText({
    double fontSize = 18,
    FontWeight fontWeight = FontWeight.w600,
    Color? color,
  }) {
    return GoogleFonts.notoNaskhArabic(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: 1.7,
    );
  }
}
