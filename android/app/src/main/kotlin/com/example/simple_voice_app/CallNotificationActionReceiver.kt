package com.example.simple_voice_app

import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class CallNotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            CallNotificationService.ACTION_MUTE -> NotificationActionBus.send("mute")
            CallNotificationService.ACTION_UNMUTE -> NotificationActionBus.send("unmute")
            CallNotificationService.ACTION_SPEAKER -> NotificationActionBus.send("speaker")
            CallNotificationService.ACTION_EARPIECE -> NotificationActionBus.send("earpiece")
            CallNotificationService.ACTION_HANG_UP -> NotificationActionBus.send("hangUp")
            CallNotificationService.ACTION_REPLY -> {
                val text = RemoteInput.getResultsFromIntent(intent)
                    ?.getCharSequence(CallNotificationService.REPLY_KEY)
                    ?.toString()
                    ?: ""
                NotificationActionBus.send("reply", text)
            }
        }
    }
}
