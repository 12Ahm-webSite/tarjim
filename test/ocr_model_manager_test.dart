import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tarjim/services/ocr_model_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OCRModelManager', () {
    test('Initial state is notReady', () {
      final manager = OCRModelManager(
        customProbe: () async => false,
      );

      expect(manager.status, equals(OCRModelStatus.notReady));
      expect(manager.isReady, isFalse);
      expect(manager.isDownloading, isFalse);
      expect(manager.isFailed, isFalse);
    });

    test('checkModelStatus returns true and sets ready state when probe succeeds', () async {
      final manager = OCRModelManager(
        customProbe: () async => true,
      );

      final ready = await manager.checkModelStatus();

      expect(ready, isTrue);
      expect(manager.status, equals(OCRModelStatus.ready));
      expect(manager.isReady, isTrue);
      expect(manager.statusMessage, contains('Ready'));
    });

    test('checkModelStatus sets downloading state when probe throws download pending PlatformException', () async {
      final manager = OCRModelManager(
        customProbe: () async {
          throw PlatformException(
            code: 'TextRecognizerError',
            message: 'Waiting for the text optional module to be downloaded. Please wait.',
          );
        },
      );

      final ready = await manager.checkModelStatus();

      expect(ready, isFalse);
      expect(manager.status, equals(OCRModelStatus.downloading));
      expect(manager.isDownloading, isTrue);
      expect(manager.statusMessage, contains('Downloading'));
    });

    test('checkModelStatus sets failed state when probe throws other error', () async {
      final manager = OCRModelManager(
        customProbe: () async {
          throw PlatformException(
            code: 'UnknownError',
            message: 'Fatal native failure',
          );
        },
      );

      final ready = await manager.checkModelStatus();

      expect(ready, isFalse);
      expect(manager.status, equals(OCRModelStatus.failed));
      expect(manager.isFailed, isTrue);
      expect(manager.lastError, contains('Fatal native failure'));
    });

    test('prepareOCRModel succeeds when probe becomes ready', () async {
      int attempts = 0;
      final manager = OCRModelManager(
        customProbe: () async {
          attempts++;
          if (attempts < 2) {
            throw PlatformException(
              code: 'TextRecognizerError',
              message: 'Waiting for the text optional module to be downloaded',
            );
          }
          return true;
        },
      );

      final success = await manager.prepareOCRModel(
        maxRetries: 3,
        retryDelay: const Duration(milliseconds: 10),
      );

      expect(success, isTrue);
      expect(manager.status, equals(OCRModelStatus.ready));
      expect(manager.isReady, isTrue);
      expect(attempts, equals(2));
    });

    test('prepareOCRModel handles timeout and retries exhaustion gracefully', () async {
      int attempts = 0;
      final manager = OCRModelManager(
        customProbe: () async {
          attempts++;
          throw PlatformException(
            code: 'TextRecognizerError',
            message: 'Waiting for the text optional module to be downloaded',
          );
        },
      );

      final success = await manager.prepareOCRModel(
        maxRetries: 2,
        retryDelay: const Duration(milliseconds: 10),
      );

      expect(success, isFalse);
      expect(manager.status, equals(OCRModelStatus.failed));
      expect(manager.isFailed, isTrue);
      expect(manager.lastError, contains('did not complete in time'));
      expect(attempts, equals(2));
    });

    test('prepareOCRModel prevents duplicate concurrent preparation calls', () async {
      int probeCalls = 0;
      final manager = OCRModelManager(
        customProbe: () async {
          probeCalls++;
          await Future.delayed(const Duration(milliseconds: 50));
          return true;
        },
      );

      final future1 = manager.prepareOCRModel(retryDelay: const Duration(milliseconds: 10));
      final future2 = manager.prepareOCRModel(retryDelay: const Duration(milliseconds: 10));

      final results = await Future.wait([future1, future2]);

      expect(results[0], isTrue);
      expect(results[1], isTrue);
      expect(probeCalls, equals(1));
    });
  });
}
