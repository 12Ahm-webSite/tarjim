import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'logger.dart';

class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.message,
    this.source = 'Flutter',
    this.level = 'INFO',
  });

  final DateTime timestamp;
  final String message;
  final String source;
  final String level;

  String get formattedTimestamp {
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final second = timestamp.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

class LoggerService {
  LoggerService._() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static const MethodChannel _channel = MethodChannel('com.example.tarjim/debug');
  static final LoggerService instance = LoggerService._();

  final ValueNotifier<List<LogEntry>> logs = ValueNotifier<List<LogEntry>>(<LogEntry>[]);
  final List<LogEntry> _entries = <LogEntry>[];

  void log(
    String message, {
    String source = 'Flutter',
    String level = 'INFO',
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      message: message,
      source: source,
      level: level,
    );
    _entries.add(entry);
    logs.value = List<LogEntry>.unmodifiable(_entries);

    if (level == 'WARN') {
      AppLogger.warning('[${entry.source}] ${entry.message}');
    } else {
      AppLogger.info('[${entry.source}] ${entry.message}');
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'log') return;
    final args = call.arguments as Map<dynamic, dynamic>?;
    final message = args?['message']?.toString() ?? 'Empty native log';
    final source = args?['source']?.toString() ?? 'Android';
    final level = args?['level']?.toString() ?? 'INFO';
    _appendEntry(
      LogEntry(
        timestamp: DateTime.now(),
        message: message,
        source: source,
        level: level,
      ),
    );
  }

  void _appendEntry(LogEntry entry) {
    _entries.add(entry);
    logs.value = List<LogEntry>.unmodifiable(_entries);
  }

  void clear() {
    _entries.clear();
    logs.value = const <LogEntry>[];
  }

  String copyText() {
    if (_entries.isEmpty) {
      return '';
    }
    return _entries
        .map((entry) => '[${entry.formattedTimestamp}] [${entry.source}] ${entry.message}')
        .join('\n');
  }
}
