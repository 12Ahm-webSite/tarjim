package com.example.tarjim.services

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log

/**
 * Foreground service that will hold the MediaProjection screen-capture
 * session. Declared in the manifest with
 * `foregroundServiceType="mediaProjection"` (required on Android 10+,
 * enforced on Android 14+).
 *
 * Capture logic arrives in Step 6 — this is only the compilable shell
 * so the manifest declaration resolves.
 */
class MediaProjectionService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "Service started (stub — capture logic arrives in Step 6)")
        return START_NOT_STICKY
    }

    companion object {
        private const val TAG = "MediaProjectionSvc"
    }
}
