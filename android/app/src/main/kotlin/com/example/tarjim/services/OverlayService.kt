package com.example.tarjim.services

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
import com.example.tarjim.DebugLogBridge

/**
 * Will host the system overlay window that displays translations above
 * other apps (requires SYSTEM_ALERT_WINDOW granted by the user).
 *
 * Overlay logic arrives in Step 9 — this is only the compilable shell
 * so the manifest declaration resolves.
 */
class OverlayService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        DebugLogBridge.log("Overlay service started", "OverlayService", "INFO")
        Log.d(TAG, "Service started (stub — overlay logic arrives in Step 9)")
        return START_NOT_STICKY
    }

    companion object {
        private const val TAG = "OverlayService"
    }
}
