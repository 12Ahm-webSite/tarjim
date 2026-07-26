package com.example.tarjim.services

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import com.example.tarjim.managers.ScreenCaptureManager
import java.io.ByteArrayOutputStream

/**
 * Foreground service that owns the MediaProjection session.
 *
 * Flow (single-shot MVP):
 * 1. Started with the consent token (resultCode + data Intent).
 * 2. Calls startForeground(mediaProjection type) — mandatory before
 *    createVirtualDisplay() on Android 14+.
 * 3. Creates a VirtualDisplay backed by an ImageReader.
 * 4. First available frame → PNG bytes → answered to Flutter via
 *    [ScreenCaptureManager] → everything is torn down.
 *
 * Fail-safe mechanisms:
 * - [frameDelivered] guard ensures exactly one result is delivered even
 *   if ImageReader surfaces several frames in quick succession.
 * - [timeoutRunnable] fires after [CAPTURE_TIMEOUT_MS] if no frame ever
 *   arrives (DRM-protected content, OEM secure-flagged windows, or a
 *   silent VirtualDisplay failure).
 *
 * The foreground notification is required the whole time the
 * projection lives; it disappears with the service.
 */
class MediaProjectionService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var cleanedUp = false

    @Volatile private var frameDelivered = false
    private var projectionCallback: MediaProjection.Callback? = null
    private var imageListener: ImageReader.OnImageAvailableListener? = null

    private val timeoutRunnable = Runnable {
        if (!frameDelivered && !cleanedUp) {
            Log.w(TAG, "Capture timed out after ${CAPTURE_TIMEOUT_MS}ms")
            deliverErrorOnce("TIMEOUT", "No frame received within the timeout window.")
            stopSelf()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val resultCode = intent?.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
            ?: Activity.RESULT_CANCELED
        val data: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent?.getParcelableExtra(EXTRA_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION") intent?.getParcelableExtra(EXTRA_DATA)
        }

        if (resultCode != Activity.RESULT_OK || data == null) {
            ScreenCaptureManager.deliverError(
                "DENIED", "Screen capture consent was not granted.",
            )
            stopSelf()
            return START_NOT_STICKY
        }

        startForegroundWithNotification()
        try {
            beginCapture(resultCode, data)
        } catch (e: Exception) {
            Log.e(TAG, "beginCapture failed", e)
            deliverErrorOnce("CAPTURE_FAILED", e.message)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    // ─── Capture ───────────────────────────────────────────────────

    private fun beginCapture(resultCode: Int, data: Intent) {
        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE)
            as MediaProjectionManager
        val projection = manager.getMediaProjection(resultCode, data)
        mediaProjection = projection

        val callback = object : MediaProjection.Callback() {
            override fun onStop() {
                Log.d(TAG, "MediaProjection stopped by system")
                if (!frameDelivered) {
                    deliverErrorOnce("STOPPED", "MediaProjection stopped before a frame was captured.")
                }
                cleanup()
            }
        }
        projectionCallback = callback
        projection.registerCallback(callback, handler)

        val metrics = resources.displayMetrics
        val width = metrics.widthPixels
        val height = metrics.heightPixels
        val dpi = metrics.densityDpi
        Log.d(TAG, "VirtualDisplay ${width}x$height @${dpi}dpi")

        val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        imageReader = reader

        val listener = ImageReader.OnImageAvailableListener { r ->
            if (frameDelivered) {
                // Single-shot semantics: ignore any frames after the first.
                val stray = r.acquireLatestImage()
                stray?.close()
                return@OnImageAvailableListener
            }

            val image = r.acquireLatestImage()
            if (image == null) {
                Log.w(TAG, "OnImageAvailableListener fired but acquireLatestImage returned null")
                return@OnImageAvailableListener
            }

            handler.removeCallbacks(timeoutRunnable)
            try {
                val bytes = imageToPngBytes(image, width, height)
                frameDelivered = true
                ScreenCaptureManager.deliverCapture(bytes)
                Log.d(TAG, "Delivered single capture frame (${bytes.size} bytes)")
            } catch (e: Exception) {
                Log.e(TAG, "Frame encode failed", e)
                deliverErrorOnce("ENCODE_FAILED", e.message)
            } finally {
                image.close()
            }
            stopSelf()
        }
        imageListener = listener
        reader.setOnImageAvailableListener(listener, handler)

        virtualDisplay = projection.createVirtualDisplay(
            "tarjim_capture",
            width, height, dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.surface, null, handler,
        )

        handler.postDelayed(timeoutRunnable, CAPTURE_TIMEOUT_MS)
        Log.d(TAG, "Capture timeout armed: ${CAPTURE_TIMEOUT_MS}ms")
    }

    /** RGBA ImageReader frame → cropped PNG bytes (handles row padding). */
    private fun imageToPngBytes(image: Image, width: Int, height: Int): ByteArray {
        val plane = image.planes[0]
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        val rowPadding = rowStride - pixelStride * width

        val padded = Bitmap.createBitmap(
            width + rowPadding / pixelStride, height, Bitmap.Config.ARGB_8888,
        )
        padded.copyPixelsFromBuffer(plane.buffer)

        val cropped = Bitmap.createBitmap(padded, 0, 0, width, height)
        padded.recycle()

        val out = ByteArrayOutputStream()
        cropped.compress(Bitmap.CompressFormat.PNG, 100, out)
        cropped.recycle()
        return out.toByteArray()
    }

    /** Thread-safe error forwarder that honours the single-shot promise. */
    @Synchronized
    private fun deliverErrorOnce(code: String, message: String?) {
        if (frameDelivered) return
        frameDelivered = true
        handler.removeCallbacks(timeoutRunnable)
        ScreenCaptureManager.deliverError(code, message)
    }

    // ─── Foreground requirement ────────────────────────────────────

    private fun startForegroundWithNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Screen capture", NotificationManager.IMPORTANCE_LOW,
            )
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        val notification = builder
            .setContentTitle("Tarjim")
            .setContentText("Capturing the screen…")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    // ─── Teardown ──────────────────────────────────────────────────

    @Synchronized
    private fun cleanup() {
        if (cleanedUp) return
        cleanedUp = true
        handler.removeCallbacks(timeoutRunnable)

        val reader = imageReader
        if (reader != null && imageListener != null) {
            try {
                reader.setOnImageAvailableListener(null, null)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to clear ImageReader listener", e)
            }
        }
        imageListener = null

        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.close()
        imageReader = null

        val proj = mediaProjection
        val cb = projectionCallback
        if (proj != null && cb != null) {
            try {
                proj.unregisterCallback(cb)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to unregister projection callback", e)
            }
        }
        projectionCallback = null
        try {
            mediaProjection?.stop()
        } catch (e: IllegalStateException) {
            Log.w(TAG, "Projection already stopped")
        }
        mediaProjection = null
    }

    override fun onDestroy() {
        cleanup()
        Log.d(TAG, "Service destroyed (frameDelivered=$frameDelivered)")
        super.onDestroy()
    }

    companion object {
        private const val TAG = "MediaProjectionSvc"
        private const val CHANNEL_ID = "tarjim_capture"
        private const val NOTIFICATION_ID = 1001

        /** Maximum wait time (ms) for the first frame before giving up. */
        private const val CAPTURE_TIMEOUT_MS = 5000L

        const val EXTRA_RESULT_CODE = "com.example.tarjim.extra.RESULT_CODE"
        const val EXTRA_DATA = "com.example.tarjim.extra.RESULT_DATA"
    }
}
