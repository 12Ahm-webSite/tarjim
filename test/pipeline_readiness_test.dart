import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:tarjim/controllers/app_controller.dart';
import 'package:tarjim/models/text_box.dart';
import 'package:tarjim/models/translated_text_box.dart';
import 'package:tarjim/models/translation_model_config.dart';
import 'package:tarjim/services/media_projection_service.dart';
import 'package:tarjim/services/ocr_model_manager.dart';
import 'package:tarjim/services/ocr_service.dart';
import 'package:tarjim/services/overlay_service.dart';
import 'package:tarjim/services/permission_service.dart';
import 'package:tarjim/services/translation_model_manager.dart';
import 'package:tarjim/services/translation_service.dart';

class MockPermissionService extends PermissionService {
  bool notificationsGranted = true;
  bool overlayGranted = true;

  @override
  Future<bool> requestNotifications() async => notificationsGranted;

  @override
  Future<bool> requestOverlay() async => overlayGranted;
}

class MockOverlayService extends OverlayService {
  bool overlayGranted = true;
  bool overlayShown = false;

  @override
  Future<bool> checkOverlayPermission() async => overlayGranted;

  @override
  Future<bool> showOverlay() async {
    overlayShown = true;
    return true;
  }

  @override
  Future<bool> hideOverlay() async {
    overlayShown = false;
    return true;
  }
}

class MockMediaProjectionService extends MediaProjectionService {
  int startCaptureCallCount = 0;
  bool shouldThrow = false;
  // 1x1 transparent PNG bytes
  Uint8List dummyPngBytes = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82
  ]);

  @override
  Future<bool> checkScreenCaptureAvailability() async => true;

  @override
  Future<Uint8List> startScreenCapture() async {
    startCaptureCallCount++;
    if (shouldThrow) {
      throw Exception('Capture failed');
    }
    return dummyPngBytes;
  }

  @override
  Future<bool> stopScreenCapture() async => true;
}

class MockOCRService extends OCRService {
  int processImageCallCount = 0;
  List<TextBox> returnedBoxes = [
    const TextBox(
      text: 'テスト',
      imageWidth: 100,
      imageHeight: 100,
      left: 10,
      top: 10,
      width: 50,
      height: 20,
    ),
  ];

  @override
  Future<List<TextBox>> processImage({
    Uint8List? bytes,
    String? filePath,
    int? imageWidth,
    int? imageHeight,
  }) async {
    processImageCallCount++;
    return returnedBoxes;
  }
}

class MockTranslationService extends TranslationService {
  int translateBoxesCallCount = 0;
  List<TranslatedTextBox> returnedTranslations = [
    const TranslatedTextBox(
      originalText: 'テスト',
      translatedText: 'اختبار',
      imageWidth: 100,
      imageHeight: 100,
      left: 10,
      top: 10,
      width: 50,
      height: 20,
    ),
  ];

  @override
  Future<List<TranslatedTextBox>> translateBoxes(List<TextBox> boxes) async {
    translateBoxesCallCount++;
    return returnedTranslations;
  }
}

class MockMlKitTranslationModelManager extends OnDeviceTranslatorModelManager {
  final Set<String> downloadedModels = {};
  int downloadCallCount = 0;

  @override
  Future<bool> isModelDownloaded(String modelTag) async {
    return downloadedModels.contains(modelTag);
  }

  @override
  Future<bool> downloadModel(String modelTag, {bool isWifiRequired = true}) async {
    downloadCallCount++;
    downloadedModels.add(modelTag);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Pipeline Pre-flight & Readiness Checks', () {
    late MockPermissionService mockPermissions;
    late MockOverlayService mockOverlay;
    late MockMediaProjectionService mockMediaProjection;
    late MockOCRService mockOCR;
    late MockTranslationService mockTranslation;
    late MockMlKitTranslationModelManager mockMlKitTranslation;
    late TranslationModelManager translationModelManager;

    const testTranslationModels = [
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
      mockPermissions = MockPermissionService();
      mockOverlay = MockOverlayService();
      mockMediaProjection = MockMediaProjectionService();
      mockOCR = MockOCRService();
      mockTranslation = MockTranslationService();
      mockMlKitTranslation = MockMlKitTranslationModelManager();

      translationModelManager = TranslationModelManager(
        models: testTranslationModels,
        mlKitModelManager: mockMlKitTranslation,
      );
    });

    test('Translation models missing -> startTranslation stops before screenshot', () async {
      // Only JA and EN downloaded; AR is missing
      mockMlKitTranslation.downloadedModels.addAll(['ja', 'en']);

      final ocrModelManager = OCRModelManager(customProbe: () async => true);

      final controller = AppController(
        permissions: mockPermissions,
        mediaProjection: mockMediaProjection,
        overlay: mockOverlay,
        ocr: mockOCR,
        translation: mockTranslation,
        translationManager: translationModelManager,
        ocrManager: ocrModelManager,
      );

      final error = await controller.startTranslation();

      expect(error, isNotNull);
      expect(error, contains('Missing required translation models'));
      expect(error, contains('Arabic (ar)'));
      // Screenshot capture was NEVER called
      expect(mockMediaProjection.startCaptureCallCount, equals(0));
      expect(mockOCR.processImageCallCount, equals(0));
      expect(mockTranslation.translateBoxesCallCount, equals(0));
      expect(controller.screenCaptureStatus, equals(ServiceStatus.idle));
    });

    test('Translation models ready but OCR model unavailable -> stops before screenshot', () async {
      // All translation models are downloaded
      mockMlKitTranslation.downloadedModels.addAll(['ja', 'en', 'ar']);

      // OCR probe returns false (not ready)
      final ocrModelManager = OCRModelManager(customProbe: () async => false);

      final controller = AppController(
        permissions: mockPermissions,
        mediaProjection: mockMediaProjection,
        overlay: mockOverlay,
        ocr: mockOCR,
        translation: mockTranslation,
        translationManager: translationModelManager,
        ocrManager: ocrModelManager,
      );

      final error = await controller.startTranslation();

      expect(error, isNotNull);
      expect(error, contains('Japanese OCR model is not ready'));
      // Screenshot capture was NEVER called
      expect(mockMediaProjection.startCaptureCallCount, equals(0));
      expect(mockOCR.processImageCallCount, equals(0));
      expect(mockTranslation.translateBoxesCallCount, equals(0));
      expect(controller.screenCaptureStatus, equals(ServiceStatus.idle));
    });

    test('Both OCR and translation models ready -> pipeline proceeds through capture, OCR, and translation', () async {
      // All translation models downloaded
      mockMlKitTranslation.downloadedModels.addAll(['ja', 'en', 'ar']);

      // OCR model is ready
      final ocrModelManager = OCRModelManager(customProbe: () async => true);

      final controller = AppController(
        permissions: mockPermissions,
        mediaProjection: mockMediaProjection,
        overlay: mockOverlay,
        ocr: mockOCR,
        translation: mockTranslation,
        translationManager: translationModelManager,
        ocrManager: ocrModelManager,
      );

      final error = await controller.startTranslation();

      expect(error, isNull);
      // Verify all steps were invoked in sequence
      expect(mockMediaProjection.startCaptureCallCount, equals(1));
      expect(mockOCR.processImageCallCount, equals(1));
      expect(mockTranslation.translateBoxesCallCount, equals(1));
      expect(controller.lastTranslationResult.length, equals(1));
      expect(controller.translationStatus, equals(ServiceStatus.granted));
    });

    test('OCR model download/readiness timeout -> clean failure', () async {
      final ocrModelManager = OCRModelManager(
        customProbe: () async => false,
      );

      final success = await ocrModelManager.prepareOCRModel(
        maxRetries: 2,
        retryDelay: const Duration(milliseconds: 10),
      );

      expect(success, isFalse);
      expect(ocrModelManager.isFailed, isTrue);
      expect(ocrModelManager.lastError, contains('did not complete in time'));
    });

    test('translateBoxes() never triggers a download (pure translation invariant)', () async {
      final mockModelManager = MockMlKitTranslationModelManager();
      final service = TranslationService(modelManager: mockModelManager);

      // Calling translateBoxes should fail immediately with StateError without downloading
      await expectLater(
        () => service.translateBoxes([
          const TextBox(
            text: 'こんにちは',
            imageWidth: 100,
            imageHeight: 100,
            left: 0,
            top: 0,
            width: 50,
            height: 20,
          )
        ]),
        throwsA(isA<StateError>()),
      );

      // Verify zero download attempts were made
      expect(mockModelManager.downloadCallCount, equals(0));
    });
  });
}
