package com.example.tarjim.managers

import android.util.Log
import com.example.tarjim.DebugLogBridge
import io.flutter.plugin.common.MethodChannel

/**
 * Holds the Flutter [MethodChannel.Result] of the in-flight capture
 * request across the asynchronous consent → service → frame sequence.
 *
 * The consent dialog and the capture service complete at unpredictable
 * times, so the result is answered exactly once — by whichever of these
 * happens first: frame delivered, consent denied, or stop requested.
 *
 * Thread safety:
 * - Callers may arrive from the MethodChannel dispatcher, the Activity
 *   result callback, the service's main-looper Handler, or the stop
 *   action. Every access to [pendingResult] is therefore guarded by
 *   [Synchronized] on the singleton object.
 * - A double-delivery guard is also present so repeated calls to
 *   [deliverCapture] / [deliverError] after the first are no-ops.
 */
object ScreenCaptureManager {

    private var pendingResult: MethodChannel.Result? = null

    @Volatile private var answered = false

    /** True when a capture request is waiting for a frame or an error. */
    @Synchronized
    fun hasPendingCapture(): Boolean = pendingResult != null

    /**
     * Parks the Flutter result until the capture completes.
     * Returns false (and leaves state untouched) when one is already held.
     */
    @Synchronized
    fun holdResult(result: MethodChannel.Result): Boolean {
        if (pendingResult != null) return false
        pendingResult = result
        answered = false
        DebugLogBridge.log("Capture result parked", "ScreenCaptureManager", "INFO")
        Log.d(TAG, "Capture result parked")
        return true
    }

    /** Answers the parked result with the screenshot bytes. */
    @Synchronized
    fun deliverCapture(bytes: ByteArray) {
        if (answered || pendingResult == null) {
            Log.w(TAG, "deliverCapture dropped (already answered or no pending result)")
            return
        }
        answered = true
        val res = pendingResult!!
        pendingResult = null
        DebugLogBridge.log("deliverCapture() called with ${bytes.size} bytes", "ScreenCaptureManager", "INFO")
        Log.d(TAG, "Delivering capture: ${bytes.size} bytes")
        res.success(bytes)
    }

    /** Answers the parked result with an error (denial, failure, stop). */
    @Synchronized
    fun deliverError(code: String, message: String?) {
        if (answered || pendingResult == null) {
            Log.w(TAG, "deliverError [$code] dropped (already answered or no pending result)")
            return
        }
        answered = true
        val res = pendingResult!!
        pendingResult = null
        DebugLogBridge.log("deliverError() called [$code]: $message", "ScreenCaptureManager", "WARN")
        Log.w(TAG, "Delivering capture error [$code]: $message")
        res.error(code, message, null)
    }

    private const val TAG = "ScreenCaptureManager"
}
