package com.example.tarjim.channels

import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import com.example.tarjim.DebugLogBridge
import com.example.tarjim.managers.ScreenCaptureManager
import com.example.tarjim.services.MediaProjectionService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Single dispatch point for all Flutter → native calls on channel
 * `com.example.tarjim/core`.
 *
 * Contract:
 * - Status/availability queries return real data maps.
 * - startScreenCapture parks its result and delegates to the activity
 *   (consent dialog → foreground service → PNG bytes).
 * - Stop/hide actions are idempotent and always succeed.
 * - The overlay window still answers NOT_IMPLEMENTED (Step 9).
 *
 * Keep this class logic-free: it only routes. Real work lives in the
 * managers (ScreenCaptureManager) and services (MediaProjectionService).
 */
class MethodChannelHandler(
    private val context: Context,
    private val startCaptureLauncher: (MethodChannel.Result) -> Unit,
) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "onMethodCall: ${call.method}")
        logToFlutter("MethodChannel call received: ${call.method}", "MethodChannelHandler", "INFO")
        when (call.method) {
            "startScreenCapture" -> startCaptureLauncher(result)

            "stopScreenCapture" -> {
                logToFlutter("stopScreenCapture requested", "MethodChannelHandler", "INFO")
                context.stopService(
                    Intent(context, MediaProjectionService::class.java),
                )
                // Answer any parked startScreenCapture call as stopped.
                ScreenCaptureManager.deliverError("STOPPED", "Capture stopped.")
                result.success(
                    mapOf("status" to "idle", "message" to "Capture stopped."),
                )
            }

            "showOverlay" -> {
                logToFlutter("showOverlay requested", "MethodChannelHandler", "INFO")
                result.error(
                    "NOT_IMPLEMENTED",
                    "Overlay window arrives in Step 9.",
                    null,
                )
            }

            "hideOverlay" -> {
                logToFlutter("hideOverlay requested", "MethodChannelHandler", "INFO")
                result.success(
                    mapOf("status" to "hidden", "message" to "No active overlay."),
                )
            }

            "checkOverlayPermission" -> {
                logToFlutter("checkOverlayPermission requested", "MethodChannelHandler", "INFO")
                result.success(
                    mapOf("granted" to Settings.canDrawOverlays(context)),
                )
            }

            "checkScreenCaptureAvailability" -> {
                logToFlutter("checkScreenCaptureAvailability requested", "MethodChannelHandler", "INFO")
                val manager = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE)
                        as? MediaProjectionManager
                result.success(
                    mapOf(
                        "available" to (manager != null),
                        "sdkInt" to Build.VERSION.SDK_INT,
                    )
                )
            }

            else -> {
                Log.w(TAG, "Unknown method: ${call.method}")
                result.notImplemented()
            }
        }
    }

    private fun logToFlutter(message: String, source: String, level: String) {
        DebugLogBridge.log(message, source, level)
    }

    companion object {
        private const val TAG = "MethodChannelHandler"
    }
}
