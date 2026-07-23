import 'package:flutter/foundation.dart';

import '../core/utils/logger.dart';

/// Lifecycle state of each pipeline stage, mirrored by the status cards.
enum ServiceStatus { idle, granted, denied, running, error }

/// Central application state for the MVP pipeline.
///
/// The UI only reads this controller and calls its intent methods.
/// The Flutter services attach here in later steps:
/// - Step 5: PermissionService + native MethodChannel statuses
/// - Step 6: screen capture state
/// - Steps 7–8: OCR + translation results
class AppController extends ChangeNotifier {
  static const _tag = 'AppController';

  // ─── Pipeline statuses ───────────────────────────────────────────
  ServiceStatus screenCaptureStatus = ServiceStatus.idle;
  ServiceStatus overlayStatus = ServiceStatus.idle;
  ServiceStatus ocrStatus = ServiceStatus.idle;
  ServiceStatus translationStatus = ServiceStatus.idle;

  bool _isTranslating = false;
  bool get isTranslating => _isTranslating;

  /// Step 5 wires this to PermissionService + the native channel.
  void requestPermissions() {
    AppLogger.info(
      'requestPermissions() — native wiring arrives in Step 5',
      tag: _tag,
    );
  }

  /// Toggles the UI pipeline state only — no capture/OCR runs yet.
  /// Step 6 connects real screen capture, Steps 7–8 feed OCR + translation.
  void startTranslation() {
    if (_isTranslating) return;
    _isTranslating = true;
    ocrStatus = ServiceStatus.running;
    translationStatus = ServiceStatus.running;
    AppLogger.info('startTranslation() — pipeline UI state ON', tag: _tag);
    notifyListeners();
  }

  void stopTranslation() {
    if (!_isTranslating) return;
    _isTranslating = false;
    ocrStatus = ServiceStatus.idle;
    translationStatus = ServiceStatus.idle;
    AppLogger.info('stopTranslation() — pipeline UI state OFF', tag: _tag);
    notifyListeners();
  }
}
