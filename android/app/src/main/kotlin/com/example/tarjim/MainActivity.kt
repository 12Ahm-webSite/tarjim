package com.example.tarjim

import android.util.Log
import com.example.tarjim.channels.MethodChannelHandler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler(MethodChannelHandler(this))
        Log.d(TAG, "MethodChannel registered: $CHANNEL")
    }

    companion object {
        private const val TAG = "MainActivity"

        /** Must match AppConstants.methodChannelName on the Flutter side. */
        private const val CHANNEL = "com.example.tarjim/core"
    }
}
