package com.example.tarjim.channels

import android.content.Context
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Single dispatch point for all Flutter → native calls on channel
 * `com.example.tarjim/core`.
 *
 * Contract:
 * - Status/availability queries return real data maps.
 * - Actions not yet implemented (Step 6 capture, Step 9 overlay window)
 *   return `error("NOT_IMPLEMENTED", ...)` — an explicit, testable
 *   response instead of silent fakery.
 * - Stop/hide actions are idempotent and always succeed.
 *
 * Keep this class logic-free: it only routes. Step 6+ delegates real
 * work to the managers (ScreenCaptureManager, OverlayManager).
 */
class MethodChannelHandler(private val context: Context) :
    MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "onMethodCall: ${call.method}")
        when (call.method) {
            "startScreenCapture" -> result.error(
                "NOT_IMPLEMENTED",
                "MediaProjection capture arrives in Step 6.",
                null,
            )

            "stopScreenCapture" -> result.success(
                mapOf("status" to "idle", "message" to "No active capture session.")
            )

            "showOverlay" -> result.error(
                "NOT_IMPLEMENTED",
                "Overlay window arrives in Step 9.",
                null,
            )

            "hideOverlay" -> result.success(
                mapOf("status" to "hidden", "message" to "No active overlay.")
            )

            "checkOverlayPermission" -> result.success(
                mapOf("granted" to Settings.canDrawOverlays(context))
            )

            "checkScreenCaptureAvailability" -> {
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

    companion object {
        private const val TAG = "MethodChannelHandler"
    }
}
