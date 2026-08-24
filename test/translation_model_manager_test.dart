import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:tarjim/models/translation_model_config.dart';
import 'package:tarjim/services/translation_model_manager.dart';

class MockOnDeviceTranslatorModelManager extends OnDeviceTranslatorModelManager {
  final Set<String> downloadedModels = {};
  int downloadCallCount = 0;
  bool shouldFailDownload = false;
  bool shouldTimeout = false;
  Duration simulatedDelay = Duration.zero;

  @override
  Future<bool> isModelDownloaded(String modelTag) async {
    return downloadedModels.contains(modelTag);
  }

  @override
  Future<bool> downloadModel(
    String modelTag, {
    bool isWifiRequired = true,
  }) async {
    downloadCallCount++;
    if (simulatedDelay > Duration.zero) {
      await Future.delayed(simulatedDelay);
    }
    if (shouldTimeout) {
      // Simulate delay longer than timeout
      await Future.delayed(const Duration(seconds: 100));
      return false;
    }
    if (shouldFailDownload) {
      return false;
    }
    downloadedModels.add(modelTag);
    return true;
  }

  @override
  Future<bool> deleteModel(String modelTag) async {
    return downloadedModels.remove(modelTag);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TranslationModelManager', () {
    late MockOnDeviceTranslatorModelManager mockManager;
    late TranslationModelManager manager;

    const testModels = [
      TranslationModelConfig(
        code: 'ja',
        name: 'Japanese',
        nativeName: '日本語',
        isRequired: true,
      ),
      TranslationModelConfig(
        code: 'en',
        name: 'English',
        nativeName: 'English',
        isRequired: true,
      ),
      TranslationModelConfig(
        code: 'ar',
        name: 'Arabic',
        nativeName: 'العربية',
        isRequired: true,
      ),
    ];

    setUp(() {
      mockManager = MockOnDeviceTranslatorModelManager();
      manager = TranslationModelManager(
        models: testModels,
        mlKitModelManager: mockManager,
      );
    });

    test('Initial states are notDownloaded', () {
      expect(manager.states.length, equals(3));
      for (final state in manager.states) {
        expect(state.status, equals(ModelDownloadStatus.notDownloaded));
        expect(state.isDownloaded, isFalse);
      }
    });

    test('checkAllStatuses updates state from disk truth', () async {
      mockManager.downloadedModels.add('ja');
      await manager.checkAllStatuses();

      final jaState = manager.getState('ja');
      final enState = manager.getState('en');

      expect(jaState?.isDownloaded, isTrue);
      expect(enState?.isDownloaded, isFalse);
    });

    test('areAllRequiredModelsDownloaded returns false when any model is missing', () async {
      mockManager.downloadedModels.addAll(['ja', 'en']);
      final ready = await manager.areAllRequiredModelsDownloaded();
      expect(ready, isFalse);

      final missing = await manager.getMissingRequiredModels();
      expect(missing.length, equals(1));
      expect(missing.first.code, equals('ar'));
    });

    test('areAllRequiredModelsDownloaded returns true when all required are downloaded', () async {
      mockManager.downloadedModels.addAll(['ja', 'en', 'ar']);
      final ready = await manager.areAllRequiredModelsDownloaded();
      expect(ready, isTrue);
    });

    test('downloadModel succeeds and verifies disk presence', () async {
      final success = await manager.downloadModel('ja');
      expect(success, isTrue);

      final state = manager.getState('ja');
      expect(state?.status, equals(ModelDownloadStatus.downloaded));
      expect(mockManager.downloadedModels.contains('ja'), isTrue);
    });

    test('downloadModel prevents duplicate parallel downloads', () async {
      mockManager.simulatedDelay = const Duration(milliseconds: 50);

      // Launch two concurrent downloads for 'ja'
      final future1 = manager.downloadModel('ja');
      final future2 = manager.downloadModel('ja');

      final results = await Future.wait([future1, future2]);
      expect(results[0], isTrue);
      expect(results[1], isTrue);
      // Ensure downloadModel was only called once
      expect(mockManager.downloadCallCount, equals(1));
    });

    test('downloadModel handles timeout gracefully and retries', () async {
      mockManager.shouldTimeout = true;

      final success = await manager.downloadModel(
        'ja',
        timeout: const Duration(milliseconds: 100),
        maxRetries: 2,
      );

      expect(success, isFalse);
      final state = manager.getState('ja');
      expect(state?.status, equals(ModelDownloadStatus.failed));
      expect(state?.lastError, contains('Timeout'));
      expect(mockManager.downloadCallCount, equals(2));
    });

    test('downloadModel handles download failure and retries up to maxRetries', () async {
      mockManager.shouldFailDownload = true;

      final success = await manager.downloadModel(
        'en',
        maxRetries: 3,
      );

      expect(success, isFalse);
      final state = manager.getState('en');
      expect(state?.status, equals(ModelDownloadStatus.failed));
      expect(mockManager.downloadCallCount, equals(3));
    });

    test('downloadRequiredModels downloads all missing models sequentially', () async {
      mockManager.downloadedModels.add('ja');

      final success = await manager.downloadRequiredModels();
      expect(success, isTrue);
      expect(mockManager.downloadedModels.contains('ja'), isTrue);
      expect(mockManager.downloadedModels.contains('en'), isTrue);
      expect(mockManager.downloadedModels.contains('ar'), isTrue);
    });
  });
}
