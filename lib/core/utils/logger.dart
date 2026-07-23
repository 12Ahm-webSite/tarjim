import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Severity levels for [AppLogger].
enum LogLevel { debug, info, warning, error }

/// Lightweight logging utility for Tarjim.
///
/// Wraps `dart:developer` log so output is visible in DevTools with
/// proper tags and levels, without pulling in an external package.
/// Debug logs are stripped from release builds.
abstract final class AppLogger {
  /// Minimum level emitted. Verbose in debug builds, quieter in release.
  static LogLevel minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;

  static void debug(String message, {String tag = 'Tarjim'}) =>
      _log(LogLevel.debug, message, tag: tag);

  static void info(String message, {String tag = 'Tarjim'}) =>
      _log(LogLevel.info, message, tag: tag);

  static void warning(String message, {String tag = 'Tarjim'}) =>
      _log(LogLevel.warning, message, tag: tag);

  static void error(
    String message, {
    String tag = 'Tarjim',
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _log(LogLevel.error, message, tag: tag, error: error, stackTrace: stackTrace);

  static void _log(
    LogLevel level,
    String message, {
    required String tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < minLevel.index) return;

    developer.log(
      message,
      time: DateTime.now(),
      level: switch (level) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warning => 900,
        LogLevel.error => 1000,
      },
      name: '$tag.${level.name.toUpperCase()}',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
