import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

class PocTranslationMetrics {
  final int modelLoadingTimeMs;
  final int tokenizationTimeMs;
  final int inferenceTimeMs;
  final int totalTranslationTimeMs;
  final int generatedTokensCount;
  final String translatedText;

  PocTranslationMetrics({
    required this.modelLoadingTimeMs,
    required this.tokenizationTimeMs,
    required this.inferenceTimeMs,
    required this.totalTranslationTimeMs,
    required this.generatedTokensCount,
    required this.translatedText,
  });
}

class OfflineTranslationPocService {
  OrtSession? _encoderSession;
  OrtSession? _decoderSession;
  final OrtRunOptions _runOptions = OrtRunOptions();

  final Map<String, double> _piece2score = {};
  final Map<String, int> _vocab = {};
  final Map<int, String> _id2piece = {};

  bool _isInitialized = false;
  int _lastModelLoadingTimeMs = 0;

  bool get isInitialized => _isInitialized;
  int get lastModelLoadingTimeMs => _lastModelLoadingTimeMs;

  Future<void> init() async {
    if (_isInitialized) return;

    final sw = Stopwatch()..start();
    OrtEnv.instance.init();

    // 1. Copy model files from assets to local storage if needed
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDir.path}/models/en_ar');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    final encoderFile = File('${modelDir.path}/encoder_model.onnx');
    final decoderFile = File('${modelDir.path}/decoder_model.onnx');

    if (!await encoderFile.exists() || await encoderFile.length() < 1000) {
      final byteData = await rootBundle.load('assets/models/en_ar/encoder_model.onnx');
      final buffer = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
      await encoderFile.writeAsBytes(buffer, flush: true);
    }

    if (!await decoderFile.exists() || await decoderFile.length() < 1000) {
      final byteData = await rootBundle.load('assets/models/en_ar/decoder_model.onnx');
      final buffer = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
      await decoderFile.writeAsBytes(buffer, flush: true);
    }

    // 2. Load tokenizer files
    final piecesJsonStr = await rootBundle.loadString('assets/models/en_ar/source_pieces.json');
    final List<dynamic> piecesList = jsonDecode(piecesJsonStr);
    for (final item in piecesList) {
      _piece2score[item['piece'] as String] = (item['score'] as num).toDouble();
    }

    final vocabJsonStr = await rootBundle.loadString('assets/models/en_ar/vocab.json');
    final Map<String, dynamic> vocabMap = jsonDecode(vocabJsonStr);
    vocabMap.forEach((k, v) {
      final id = v as int;
      _vocab[k] = id;
      _id2piece[id] = k;
    });

    // 3. Initialize ONNX Runtime Sessions
    final sessionOptions = OrtSessionOptions()
      ..setInterOpNumThreads(2)
      ..setIntraOpNumThreads(2);

    _encoderSession = OrtSession.fromFile(encoderFile, sessionOptions);
    _decoderSession = OrtSession.fromFile(decoderFile, sessionOptions);

    sw.stop();
    _lastModelLoadingTimeMs = sw.elapsedMilliseconds;
    _isInitialized = true;
  }

  /// Tokenize English text using Viterbi Unigram algorithm
  List<int> _tokenize(String text) {
    final normText = '\u2581${text.replaceAll(' ', '\u2581')}';
    final n = normText.length;

    final bestScore = List<double>.filled(n + 1, -1e9);
    final bestPrev = List<int>.filled(n + 1, -1);
    final bestPiece = List<String>.filled(n + 1, '');

    bestScore[0] = 0.0;

    for (int i = 0; i < n; i++) {
      if (bestScore[i] == -1e9) continue;
      final maxJ = min(n + 1, i + 25);
      for (int j = i + 1; j < maxJ; j++) {
        final sub = normText.substring(i, j);
        final score = _piece2score[sub];
        if (score != null) {
          final total = bestScore[i] + score;
          if (total > bestScore[j]) {
            bestScore[j] = total;
            bestPrev[j] = i;
            bestPiece[j] = sub;
          }
        } else if (j == i + 1) {
          final total = bestScore[i] - 100.0;
          if (total > bestScore[j]) {
            bestScore[j] = total;
            bestPrev[j] = i;
            bestPiece[j] = sub;
          }
        }
      }
    }

    // Backtrack to extract pieces
    int curr = n;
    final pieces = <String>[];
    while (curr > 0) {
      pieces.add(bestPiece[curr]);
      curr = bestPrev[curr];
    }
    final orderedPieces = pieces.reversed.toList();

    // Map pieces to IDs using vocab
    final tokenIds = <int>[];
    for (final p in orderedPieces) {
      final id = _vocab[p];
      if (id != null) {
        tokenIds.add(id);
      }
    }
    // Append eos_token_id (0)
    tokenIds.add(0);
    return tokenIds;
  }

  /// Translate English text to Arabic offline
  Future<PocTranslationMetrics> translate(String englishText) async {
    if (!_isInitialized) {
      await init();
    }

    final totalSw = Stopwatch()..start();

    // 1. Tokenization
    final tokSw = Stopwatch()..start();
    final inputIds = _tokenize(englishText);
    final attentionMask = List<int>.filled(inputIds.length, 1);
    tokSw.stop();

    // 2. Inference
    final infSw = Stopwatch()..start();

    // Run Encoder
    final encInputOrt = OrtValueTensor.createTensorWithDataList(inputIds, [1, inputIds.length]);
    final encMaskOrt = OrtValueTensor.createTensorWithDataList(attentionMask, [1, attentionMask.length]);

    final encOutputs = await _encoderSession!.runAsync(_runOptions, {
      'input_ids': encInputOrt,
      'attention_mask': encMaskOrt,
    });

    final lastHiddenStateList = encOutputs![0]?.value as List;
    encInputOrt.release();

    // Recreate encMaskOrt as needed or reuse
    final encHiddenOrt = OrtValueTensor.createTensorWithDataList(
      lastHiddenStateList,
      [1, inputIds.length, 512],
    );

    // Run Decoder Autoregressive Generation
    final currentDecIds = <int>[62801]; // decoder_start_token_id
    const maxTokens = 50;

    for (int step = 0; step < maxTokens; step++) {
      final decInOrt = OrtValueTensor.createTensorWithDataList(currentDecIds, [1, currentDecIds.length]);
      final decOutputs = await _decoderSession!.runAsync(_runOptions, {
        'input_ids': decInOrt,
        'encoder_hidden_states': encHiddenOrt,
        'encoder_attention_mask': encMaskOrt,
      });

      decInOrt.release();

      // Logits shape: [1, currentDecIds.length, 62802]
      final logits3D = decOutputs![0]?.value as List;
      final step2D = logits3D[0] as List;
      final lastLogits = List<double>.from((step2D.last as List).map((x) => (x as num).toDouble()));

      for (final out in decOutputs) {
        out?.release();
      }

      // Block pad_token_id (62801)
      if (lastLogits.length > 62801) {
        lastLogits[62801] = -1e9;
      }

      // Apply repetition penalty to previously generated tokens
      final generatedSet = currentDecIds.sublist(1).toSet();
      for (final prev in generatedSet) {
        if (prev < lastLogits.length) {
          if (lastLogits[prev] > 0) {
            lastLogits[prev] /= 1.2;
          } else {
            lastLogits[prev] *= 1.2;
          }
        }
      }

      // Argmax
      int bestIdx = 0;
      double maxVal = -1e9;
      for (int i = 0; i < lastLogits.length; i++) {
        if (lastLogits[i] > maxVal) {
          maxVal = lastLogits[i];
          bestIdx = i;
        }
      }

      if (bestIdx == 0) {
        // eos_token_id reached
        break;
      }
      currentDecIds.add(bestIdx);
    }

    encHiddenOrt.release();
    encMaskOrt.release();
    for (final out in encOutputs) {
      out?.release();
    }

    infSw.stop();
    totalSw.stop();

    // 3. Detokenize
    final outPieces = <String>[];
    for (int i = 1; i < currentDecIds.length; i++) {
      final piece = _id2piece[currentDecIds[i]] ?? '';
      outPieces.add(piece);
    }
    final translatedArabic = outPieces.join('').replaceAll('\u2581', ' ').trim();

    return PocTranslationMetrics(
      modelLoadingTimeMs: _lastModelLoadingTimeMs,
      tokenizationTimeMs: tokSw.elapsedMilliseconds,
      inferenceTimeMs: infSw.elapsedMilliseconds,
      totalTranslationTimeMs: totalSw.elapsedMilliseconds,
      generatedTokensCount: currentDecIds.length - 1,
      translatedText: translatedArabic,
    );
  }

  void dispose() {
    _runOptions.release();
    _encoderSession?.release();
    _decoderSession?.release();
    OrtEnv.instance.release();
    _isInitialized = false;
  }
}
