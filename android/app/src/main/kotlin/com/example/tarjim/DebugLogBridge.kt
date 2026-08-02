package com.example.tarjim

import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger

object DebugLogBridge {
    private const val CHANNEL_NAME = "com.example.tarjim/debug"
    private var channel: MethodChannel? = null

    fun setBinaryMessenger(binaryMessenger: BinaryMessenger) {
        channel = MethodChannel(binaryMessenger, CHANNEL_NAME)
    }

    fun log(message: String, source: String, level: String = "INFO") {
        val channelInstance = channel ?: return
        try {
            channelInstance.invokeMethod(
                "log",
                mapOf(
                    "message" to message,
                    "source" to source,
                    "level" to level,
                ),
            )
        } catch (_: Exception) {
        }
    }
}
