package com.example.tarjim

import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import com.example.tarjim.channels.MethodChannelHandler
import com.example.tarjim.managers.ScreenCaptureManager
import com.example.tarjim.services.MediaProjectionService

class MainActivity : FlutterFragmentActivity() {

    private lateinit var screenCaptureConsent: ActivityResultLauncher<Intent>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        screenCaptureConsent = registerForActivityResult(
            ActivityResultContracts.StartActivityForResult()
        ) { result ->
            if (result.resultCode == RESULT_OK && result.data != null) {
                logToFlutter("Consent accepted", "MainActivity", "INFO")
                // ─── Send Tarjim activity to background BEFORE the capture
                // service starts the virtual display. This gives the
                // foreground activity (e.g. Mihon) a full 2000ms window
                // to be the currently-composited screen when the first
                // valid frame is read. Without this call, the user would
                // see Tarjim in the capture preview 100% of the time
                // because Android animates the activity transition for
                // ~250ms.
                DebugLogBridge.log(
                    "Sending Tarjim to background — switch to Mihon now (2s window)",
                    "MainActivity", "INFO"
                )
                Log.d(TAG, "moveTaskToBack(true) — leaving room for target app")
                moveTaskToBack(true)
                startCaptureService(result.resultCode, result.data!!)
            } else {
                logToFlutter("Consent denied", "MainActivity", "WARN")
                ScreenCaptureManager.deliverError(
                    "DENIED", "Screen capture consent denied."
                )
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DebugLogBridge.setBinaryMessenger(flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler(
            MethodChannelHandler(this, ::launchScreenCaptureConsent),
        )
        logToFlutter("MethodChannel registered", "MainActivity", "INFO")
        Log.d(TAG, "MethodChannel registered: $CHANNEL")
    }

    private fun launchScreenCaptureConsent(flutterResult: Result) {
        logToFlutter("MediaProjection dialog shown", "MainActivity", "INFO")
        if (!ScreenCaptureManager.holdResult(flutterResult)) {
            flutterResult.error(
                "BUSY", "A capture request is already in progress.", null,
            )
            return
        }
        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE)
            as MediaProjectionManager
        screenCaptureConsent.launch(manager.createScreenCaptureIntent())
    }

    private fun startCaptureService(resultCode: Int, data: Intent) {
        logToFlutter("Foreground service start requested", "MainActivity", "INFO")
        val intent = Intent(this, MediaProjectionService::class.java)
            .putExtra(MediaProjectionService.EXTRA_RESULT_CODE, resultCode)
            .putExtra(MediaProjectionService.EXTRA_DATA, data)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun logToFlutter(message: String, source: String, level: String) {
        DebugLogBridge.log(message, source, level)
    }

    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.example.tarjim/core"
    }
}
