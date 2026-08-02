import 'package:flutter/services.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/logger.dart';
import '../core/utils/logger_service.dart';

/// Flutter endpoint for the native translation overlay.
///
/// `checkOverlayPermission` is fully implemented natively (real
/// `Settings.canDrawOverlays`); show/hide return `NOT_IMPLEMENTED`
/// until Step 9 builds the window.
class OverlayService {
  static const _tag = 'OverlayService';
  static const _channel = MethodChannel(AppConstants.methodChannelName);

  /// Real grant state of SYSTEM_ALERT_WINDOW ("Display over other apps").
  Future<bool> checkOverlayPermission() async {
    LoggerService.instance.log('Checking overlay permission', source: 'OverlayService');
    AppLogger.info('→ checkOverlayPermission', tag: _tag);
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'checkOverlayPermission',
      );
      AppLogger.info('← checkOverlayPermission: $res', tag: _tag);
      return res?['granted'] as bool? ?? false;
    } on PlatformException catch (e) {
      AppLogger.warning(
        '✕ checkOverlayPermission [${e.code}]: ${e.message}',
        tag: _tag,
      );
      return false;
    }
  }

  /// Shows the translation overlay above other apps. Step 9 implements.
  Future<void> showOverlay() async {
    LoggerService.instance.log('MethodChannel.showOverlay()', source: 'OverlayService');
    AppLogger.info('→ showOverlay', tag: _tag);
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'showOverlay',
      );
      AppLogger.info('← showOverlay: $res', tag: _tag);
    } on PlatformException catch (e) {
      AppLogger.warning('✕ showOverlay [${e.code}]: ${e.message}', tag: _tag);
      rethrow;
    }
  }

  /// Hides the overlay. Idempotent — succeeds even when nothing is shown.
  Future<void> hideOverlay() async {
    LoggerService.instance.log('MethodChannel.hideOverlay()', source: 'OverlayService');
    AppLogger.info('→ hideOverlay', tag: _tag);
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'hideOverlay',
      );
      AppLogger.info('← hideOverlay: $res', tag: _tag);
    } on PlatformException catch (e) {
      AppLogger.warning('✕ hideOverlay [${e.code}]: ${e.message}', tag: _tag);
      rethrow;
    }
  }
}
