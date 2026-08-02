import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/utils/logger_service.dart';

class DebugConsoleScreen extends StatefulWidget {
  const DebugConsoleScreen({super.key});

  @override
  State<DebugConsoleScreen> createState() => _DebugConsoleScreenState();
}

class _DebugConsoleScreenState extends State<DebugConsoleScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Future<void> _copyLogs() async {
    await Clipboard.setData(
      ClipboardData(text: LoggerService.instance.copyText()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Logs copied to clipboard.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      appBar: AppBar(
        title: const Text('Debug Console'),
        backgroundColor: const Color(0xFF0B0F14),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Copy logs',
            onPressed: _copyLogs,
            icon: const Icon(Icons.copy_all_rounded),
          ),
          IconButton(
            tooltip: 'Clear logs',
            onPressed: () {
              LoggerService.instance.clear();
              setState(() {});
            },
            icon: const Icon(Icons.delete_sweep_rounded),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<LogEntry>>(
        valueListenable: LoggerService.instance.logs,
        builder: (context, logs, _) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scrollToBottom(),
          );
          return Container(
            padding: const EdgeInsets.all(12),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  final entry = logs[index];
                  return Text(
                    '[${entry.formattedTimestamp}] [${entry.source}] [${entry.level}] ${entry.message}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Color(0xFFE5E7EB),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _copyLogs,
        icon: const Icon(Icons.copy_all_rounded),
        label: const Text('Copy logs'),
      ),
    );
  }
}
