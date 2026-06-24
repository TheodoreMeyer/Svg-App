package com.example.simple_voice_app

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object NotificationActionBus {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    fun attach(eventSink: EventChannel.EventSink?) {
        sink = eventSink
    }

    fun detach() {
        sink = null
    }

    fun send(type: String, message: String = "") {
        mainHandler.post {
            sink?.success(
                mapOf(
                    "type" to type,
                    "message" to message
                )
            )
        }
    }
}
