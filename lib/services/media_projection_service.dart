import 'package:flutter/services.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/logger.dart';

/// Flutter endpoint for the native MediaProjection pipeline.
///
/// Every channel call and its response is logged via [AppLogger].
/// Native failures surface as [PlatformException] — callers decide
/// whether `NOT_IMPLEMENTED` (Steps 6+ pending) is expected.
class MediaProjectionService {
  static const _tag = 'MediaProjectionService';
  static const _channel = MethodChannel(AppConstants.methodChannelName);

  /// Asks native to begin a capture session. Step 6 implements the
  /// actual MediaProjection consent + VirtualDisplay.
  Future<void> startScreenCapture() async {
    AppLogger.info('→ startScreenCapture', tag: _tag);
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'startScreenCapture',
      );
      AppLogger.info('← startScreenCapture: $res', tag: _tag);
    } on PlatformException catch (e) {
      AppLogger.warning(
        '✕ startScreenCapture [${e.code}]: ${e.message}',
        tag: _tag,
      );
      rethrow;
    }
  }

  /// Asks native to stop the capture session. Always succeeds natively,
  /// even when no session is active (idempotent cleanup).
  Future<void> stopScreenCapture() async {
    AppLogger.info('→ stopScreenCapture', tag: _tag);
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'stopScreenCapture',
      );
      AppLogger.info('← stopScreenCapture: $res', tag: _tag);
    } on PlatformException catch (e) {
      AppLogger.warning(
        '✕ stopScreenCapture [${e.code}]: ${e.message}',
        tag: _tag,
      );
      rethrow;
    }
  }

  /// Whether the device can run MediaProjection (API level + service).
  Future<bool> checkScreenCaptureAvailability() async {
    AppLogger.info('→ checkScreenCaptureAvailability', tag: _tag);
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'checkScreenCaptureAvailability',
      );
      AppLogger.info('← checkScreenCaptureAvailability: $res', tag: _tag);
      return res?['available'] as bool? ?? false;
    } on PlatformException catch (e) {
      AppLogger.warning(
        '✕ checkScreenCaptureAvailability [${e.code}]: ${e.message}',
        tag: _tag,
      );
      return false;
    }
  }
}
