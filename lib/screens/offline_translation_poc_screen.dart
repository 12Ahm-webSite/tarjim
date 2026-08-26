import 'package:flutter/material.dart';
import '../services/offline_translation_poc_service.dart';

class OfflineTranslationPocScreen extends StatefulWidget {
  const OfflineTranslationPocScreen({super.key});

  @override
  State<OfflineTranslationPocScreen> createState() => _OfflineTranslationPocScreenState();
}

class _OfflineTranslationPocScreenState extends State<OfflineTranslationPocScreen> {
  final OfflineTranslationPocService _pocService = OfflineTranslationPocService();
  final TextEditingController _inputController = TextEditingController(
    text: 'I must protect my friends, no matter what happens.',
  );

  bool _isLoading = false;
  String _statusMessage = 'Ready to test offline translation';
  PocTranslationMetrics? _lastMetrics;
  String? _errorMessage;

  @override
  void dispose() {
    _inputController.dispose();
    _pocService.dispose();
    super.dispose();
  }

  Future<void> _runTranslation() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = 'Running offline translation pipeline...';
    });

    try {
      final metrics = await _pocService.translate(text);
      if (!mounted) return;
      setState(() {
        _lastMetrics = metrics;
        _isLoading = false;
        _statusMessage = 'Translation finished successfully (100% Offline)';
      });
    } catch (e, stack) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: $e\n$stack';
        _statusMessage = 'Translation failed';
      });
    }
  }

  void _setPreset(String text) {
    _inputController.text = text;
    setState(() {
      _errorMessage = null;
      _lastMetrics = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Translation PoC'),
        backgroundColor: const Color(0xFF1E1E2C),
        elevation: 0,
      ),
      backgroundColor: const Color(0xFF12121A),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Header
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2C),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isLoading
                      ? Colors.amber
                      : (_errorMessage != null ? Colors.redAccent : Colors.tealAccent.withValues(alpha: 0.5)),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isLoading
                        ? Icons.hourglass_top
                        : (_errorMessage != null ? Icons.error_outline : Icons.offline_bolt),
                    color: _isLoading
                        ? Colors.amber
                        : (_errorMessage != null ? Colors.redAccent : Colors.tealAccent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (_isLoading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Quick Preset Buttons
            const Text(
              'Quick Test Sentences (from User Request):',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.tealAccent,
                      side: const BorderSide(color: Colors.tealAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _isLoading
                        ? null
                        : () => _setPreset('I must protect my friends, no matter what happens.'),
                    child: const Text('Sentence 1', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.amberAccent,
                      side: const BorderSide(color: Colors.amberAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _isLoading ? null : () => _setPreset('Where is the book?'),
                    child: const Text('Sentence 2', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Input TextField
            const Text(
              'Input English Text:',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _inputController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1E1E2C),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                hintText: 'Enter English text to translate...',
                hintStyle: const TextStyle(color: Colors.white38),
              ),
            ),
            const SizedBox(height: 16),

            // Action Button
            ElevatedButton(
              key: const Key('test_offline_translation_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C5CE7),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isLoading ? null : _runTranslation,
              child: const Text(
                'Test Offline Translation',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),

            // Error Display
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent),
                ),
                child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
              const SizedBox(height: 16),
            ],

            // Output Display
            if (_lastMetrics != null) ...[
              const Text(
                'Arabic Translation Output:',
                style: TextStyle(color: Colors.tealAccent, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2C),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.tealAccent, width: 1.5),
                ),
                child: Text(
                  _lastMetrics!.translatedText,
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Metrics Card
              const Text(
                'Real Offline Performance Metrics:',
                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2C),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    _buildMetricRow('Model Loading (cold)', '${_lastMetrics!.modelLoadingTimeMs} ms'),
                    _buildMetricRow('Tokenizer Time', '${_lastMetrics!.tokenizationTimeMs} ms'),
                    _buildMetricRow('ONNX Inference Time', '${_lastMetrics!.inferenceTimeMs} ms'),
                    _buildMetricRow('Total Translation Time', '${_lastMetrics!.totalTranslationTimeMs} ms'),
                    _buildMetricRow('Generated Tokens', '${_lastMetrics!.generatedTokensCount} tokens'),
                    if (_lastMetrics!.generatedTokensCount > 0)
                      _buildMetricRow(
                        'Latency per Token',
                        '${(_lastMetrics!.inferenceTimeMs / _lastMetrics!.generatedTokensCount).toStringAsFixed(1)} ms/tok',
                      ),
                    _buildMetricRow('Network Usage', '0 KB (100% Offline)', valueColor: Colors.tealAccent),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, {Color valueColor = Colors.white}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 13)),
          Text(value, style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
