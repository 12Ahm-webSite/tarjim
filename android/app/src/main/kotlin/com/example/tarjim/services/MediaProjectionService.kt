
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
import androidx.core.app.NotificationCompat
import com.example.tarjim.DebugLogBridge
import com.example.tarjim.managers.ScreenCaptureManager
import java.io.ByteArrayOutputStream

class MediaProjectionService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var cleanedUp = false

    @Volatile private var frameDelivered = false
    @Volatile private var callbackHandled = false
    private var projectionCallback: MediaProjection.Callback? = null
    private var imageListener: ImageReader.OnImageAvailableListener? = null

    // Monotonic timestamp (System.currentTimeMillis()) at which the
    // VirtualDisplay was created. Any frame received before
    // `captureStartedAt + PRE_CAPTURE_DELAY_MS` is discarded silently.
    // This gives the user ~2 seconds to switch from the Tarjim UI into
    // the target app (e.g. Mihon) before a frame is considered valid.
    private var captureStartedAt = 0L

    private val timeoutRunnable = Runnable {
        if (!frameDelivered && !cleanedUp) {
            Log.w(TAG, "Capture timed out after ${CAPTURE_TIMEOUT_MS}ms")
            deliverErrorOnce("TIMEOUT", "No frame received within the timeout window.")
            cleanup()
            stopSelf()
        }
    }

    // Second safety net: Even if the delay elapses, we require the
    // VirtualDisplay to have produced at least MIN_VALID_FRAMES frames
    // before accepting one. This avoids returning a stale GraphicsBuffer
    // that still has the Tarjim activity composited (some GPUs keep the
    // first submitted frame for one vsync cycle).
    private val minValidFrames = 2
    @Volatile private var framesObservedSinceReady = 0

    private val preCaptureDelayElapsedRunnable = Runnable {
        DebugLogBridge.log(
            "Pre-capture delay of ${PRE_CAPTURE_DELAY_MS}ms elapsed — frames are now valid",
            TAG, "INFO"
        )
        Log.d(TAG, "Pre-capture delay elapsed, frames from ImageReader will now be accepted")
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

        DebugLogBridge.log("Foreground service started", "MediaProjectionService", "INFO")
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

    private fun beginCapture(resultCode: Int, data: Intent) {
        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE)
            as MediaProjectionManager
        val projection = manager.getMediaProjection(resultCode, data)
        mediaProjection = projection

        if (projection == null) {
            Log.e(TAG, "getMediaProjection returned null (resultCode=$resultCode)")
            deliverErrorOnce(
                "CAPTURE_FAILED",
                "Failed to create MediaProjection — consent token may be stale. Retry the capture.",
            )
            cleanup()
            stopSelf()
            return
        }

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

        val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        imageReader = reader

        val listener = ImageReader.OnImageAvailableListener { r ->
            DebugLogBridge.log("ImageReader callback fired", "MediaProjectionService", "INFO")
            if (callbackHandled) {
                val stray = r.acquireLatestImage()
                stray?.close()
                return@OnImageAvailableListener
            }

            // ─── Pre-capture delay + early-frame discard ─────────────
            val now = System.currentTimeMillis()
            val elapsedSinceStart = now - captureStartedAt
            if (elapsedSinceStart < PRE_CAPTURE_DELAY_MS) {
                // Frame arrived too early — user hasn't had time to switch
                // out of Tarjim. Drain it and keep waiting.
                val early = r.acquireLatestImage()
                early?.close()
                val remain = PRE_CAPTURE_DELAY_MS - elapsedSinceStart
                DebugLogBridge.log(
                    "Frame ignored (too early) — ${remain}ms remaining before capture window",
                    TAG, "INFO"
                )
                Log.d(TAG, "Ignoring early frame after ${elapsedSinceStart}ms; wait ${remain}ms more")
                return@OnImageAvailableListener
            }

            // Frame arrived after the delay window, but also wait for at
            // least minValidFrames so we don't capture a stale buffer
            // that was queued before the user actually switched apps.
            framesObservedSinceReady += 1
            if (framesObservedSinceReady < minValidFrames) {
                val stale = r.acquireLatestImage()
                stale?.close()
                DebugLogBridge.log(
                    "Frame drained (stale buffer) — $framesObservedSinceReady/$minValidFrames observed",
                    TAG, "INFO"
                )
                Log.d(TAG, "Draining stale buffer frame $framesObservedSinceReady/$minValidFrames")
                return@OnImageAvailableListener
            }

            callbackHandled = true
            reader.setOnImageAvailableListener(null, null)
            try {
                val image = r.acquireLatestImage()
                if (image == null) {
                    handler.removeCallbacks(timeoutRunnable)
                    handler.removeCallbacks(preCaptureDelayElapsedRunnable)
                    deliverErrorOnce("FRAME_ERROR", "Failed to acquire image from ImageReader.")
                    cleanup()
                    stopSelf()
                    return@OnImageAvailableListener
                }
                handler.removeCallbacks(timeoutRunnable)
                DebugLogBridge.log("PNG conversion started", "MediaProjectionService", "INFO")
                processImageAndDeliver(image)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to process image frame", e)
                handler.removeCallbacks(preCaptureDelayElapsedRunnable)
                deliverErrorOnce("FRAME_ERROR", e.message)
                cleanup()
                stopSelf()
            }
        }
        imageListener = listener
        reader.setOnImageAvailableListener(listener, handler)

        // ── Commit everything: create display, arm timers, record t0 ──
        Log.d(TAG, "Creating VirtualDisplay ${width}x${height} @${dpi}dpi")
        DebugLogBridge.log(
            "VirtualDisplay W${width}H${height}D${dpi} armed; capture will begin after ${PRE_CAPTURE_DELAY_MS}ms delay",
            TAG, "INFO"
        )
        val vd = try {
            projection.createVirtualDisplay(
                "ScreenCapture",
                width, height, dpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.surface, null, handler
            )
        } catch (se: SecurityException) {
            Log.e(TAG, "createVirtualDisplay threw SecurityException", se)
            deliverErrorOnce(
                "PERMISSION",
                "MediaProjection permission revoked before display creation. Retry.",
            )
            cleanup()
            stopSelf()
            return
        } catch (e: Exception) {
            Log.e(TAG, "createVirtualDisplay failed", e)
            deliverErrorOnce("CAPTURE_FAILED", e.message)
            cleanup()
            stopSelf()
            return
        }

        if (vd == null) {
            Log.e(TAG, "createVirtualDisplay returned null")
            deliverErrorOnce(
                "CAPTURE_FAILED",
                "Failed to create virtual display — try again with a stable foreground app.",
            )
            cleanup()
            stopSelf()
            return
        }
        virtualDisplay = vd

        captureStartedAt = System.currentTimeMillis()
        handler.postDelayed(preCaptureDelayElapsedRunnable, PRE_CAPTURE_DELAY_MS)
        handler.postDelayed(timeoutRunnable, CAPTURE_TIMEOUT_MS)
        Log.d(TAG, "[Timers] pre-capture delay=${PRE_CAPTURE_DELAY_MS}ms, hard timeout=${CAPTURE_TIMEOUT_MS}ms")
    }

    private fun processImageAndDeliver(image: Image) {
        try {
            val planes = image.planes
            if (planes.isEmpty()) {
                image.close()
                deliverErrorOnce("FRAME_ERROR", "Image planes are empty")
                return
            }
            val buffer = planes[0].buffer
            val pixelStride = planes[0].pixelStride
            val rowStride = planes[0].rowStride
            val rowPadding = rowStride - pixelStride * image.width

            val bitmap = Bitmap.createBitmap(
                image.width + rowPadding / pixelStride,
                image.height,
                Bitmap.Config.ARGB_8888
            )
            bitmap.copyPixelsFromBuffer(buffer)

            val cleanBitmap = Bitmap.createBitmap(bitmap, 0, 0, image.width, image.height)
            bitmap.recycle()

            val stream = ByteArrayOutputStream()
            cleanBitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            val byteArray = stream.toByteArray()
            cleanBitmap.recycle()
            image.close()

            DebugLogBridge.log("PNG conversion completed", "MediaProjectionService", "INFO")
            frameDelivered = true
            ScreenCaptureManager.deliverCapture(byteArray)
        } catch (e: Exception) {
            try {
                image.close()
            } catch (_: Exception) {
            }
            Log.e(TAG, "processImageAndDeliver failed", e)
            deliverErrorOnce("FRAME_ERROR", e.message)
        } finally {
            cleanup()
            stopSelf()
        }
    }

    private fun startForegroundWithNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIF_CHANNEL_ID,
                "Screen Capture Service",
                NotificationManager.IMPORTANCE_LOW
            )
            manager.createNotificationChannel(channel)
        }

        val notification: Notification = NotificationCompat.Builder(this, NOTIF_CHANNEL_ID)
            .setContentTitle("Screen Translation Active")
            .setContentText("Capturing screen for translation...")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun deliverErrorOnce(code: String, message: String?) {
        if (!frameDelivered) {
            ScreenCaptureManager.deliverError(code, message ?: "Unknown error")
        }
    }

    private fun cleanup() {
        if (cleanedUp) return
        cleanedUp = true
        handler.removeCallbacks(timeoutRunnable)
        handler.removeCallbacks(preCaptureDelayElapsedRunnable)

        try {
            virtualDisplay?.release()
            imageReader?.setOnImageAvailableListener(null, null)
            imageReader?.close()
            imageReader = null

            if (projectionCallback != null) {
                mediaProjection?.unregisterCallback(projectionCallback!!)
            }
            mediaProjection?.stop()
            mediaProjection = null
        } catch (e: Exception) {
            Log.e(TAG, "Error during resource cleanup", e)
        }
    }

    override fun onDestroy() {
        cleanup()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "MediaProjectionService"
        private const val NOTIFICATION_ID = 101
        private const val NOTIF_CHANNEL_ID = "tarjim_capture_channel"
        private const val CAPTURE_TIMEOUT_MS = 5000L

        // Time between VirtualDisplay creation and when the 1st frame is
        // considered "valid". Gives the user a window to switch from the
        // Tarjim activity into the app they want translated. Must stay
        // well below CAPTURE_TIMEOUT_MS (we use 20% of the budget).
        private const val PRE_CAPTURE_DELAY_MS = 2000L

        const val EXTRA_RESULT_CODE = "EXTRA_RESULT_CODE"
        const val EXTRA_DATA = "EXTRA_DATA"
    }
}
