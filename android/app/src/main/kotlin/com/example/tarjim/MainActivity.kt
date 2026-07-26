package com.example.tarjim

import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import com.example.tarjim.channels.MethodChannelHandler
import com.example.tarjim.managers.ScreenCaptureManager
import com.example.tarjim.services.MediaProjectionService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private lateinit var screenCaptureConsent: ActivityResultLauncher<Intent>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Initialize the launcher safely inside onCreate to prevent compilation and lifecycle errors
        screenCaptureConsent = registerForActivityResult(
            ActivityResultContracts.StartActivityForResult()
        ) { result ->
            if (result.resultCode == RESULT_OK && result.data != null) {
                startCaptureService(result.resultCode, result.data!!)
            } else {
                ScreenCaptureManager.deliverError(
                    "DENIED", "Screen capture consent denied."
                )
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler(
            MethodChannelHandler(this, ::launchScreenCaptureConsent),
        )
        Log.d(TAG, "MethodChannel registered: $CHANNEL")
    }

    /**
     * Entry point for the channel's startScreenCapture call. Parks the
     * Flutter result, then shows the system consent dialog. The call is
     * answered later — with PNG bytes or an error.
     */
    private fun launchScreenCaptureConsent(flutterResult: MethodChannel.Result) {
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
        val intent = Intent(this, MediaProjectionService::class.java)
            .putExtra(MediaProjectionService.EXTRA_RESULT_CODE, resultCode)
            .putExtra(MediaProjectionService.EXTRA_DATA, data)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    companion object {
        private const val TAG = "MainActivity"

        /** Must match AppConstants.methodChannelName on the Flutter side. */
        private const val CHANNEL = "com.example.tarjim/core"
    }
}
