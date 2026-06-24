package com.example.simple_voice_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder

class CallNotificationService : Service() {
    private var server = ""
    private var status = ""
    private var muted = false
    private var speaker = false
    private var transientStatus = ""

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopForegroundCompat()
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            SERVICE_STOP -> {
                stopForegroundCompat()
                stopSelf()
                return START_NOT_STICKY
            }
            SERVICE_START, SERVICE_UPDATE -> {
                readState(intent)
                startForeground(NOTIFICATION_ID, buildNotification())
            }
        }
        return START_NOT_STICKY
    }

    private fun readState(intent: Intent) {
        server = intent.getStringExtra(EXTRA_SERVER).orEmpty()
        status = intent.getStringExtra(EXTRA_STATUS).orEmpty()
        muted = intent.getBooleanExtra(EXTRA_MUTED, false)
        speaker = intent.getBooleanExtra(EXTRA_SPEAKER, false)
        transientStatus = intent.getStringExtra(EXTRA_TRANSIENT_STATUS).orEmpty()
    }

    private fun buildNotification(): Notification {
        val title = if (server.isBlank()) {
            "Connected to voice chat"
        } else {
            "Connected to $server"
        }
        val body = transientStatus.ifBlank { status.ifBlank { "Voice chat active" } }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(openAppIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_CALL)
            .addAction(micAction())
            .addAction(routeAction())
            .addAction(replyAction())
            .addAction(hangUpAction())
            .build()
    }

    private fun micAction(): Notification.Action {
        val action = if (muted) ACTION_UNMUTE else ACTION_MUTE
        val title = if (muted) "Unmute" else "Mute"
        return Notification.Action.Builder(
            android.R.drawable.ic_btn_speak_now,
            title,
            actionIntent(action, immutable = true)
        ).build()
    }

    private fun routeAction(): Notification.Action {
        val action = if (speaker) ACTION_EARPIECE else ACTION_SPEAKER
        val title = if (speaker) "Earpiece" else "Speaker"
        return Notification.Action.Builder(
            android.R.drawable.ic_lock_silent_mode_off,
            title,
            actionIntent(action, immutable = true)
        ).build()
    }

    private fun replyAction(): Notification.Action {
        val remoteInput = RemoteInput.Builder(REPLY_KEY)
            .setLabel("Type a message")
            .build()
        return Notification.Action.Builder(
            android.R.drawable.ic_dialog_email,
            "Chat",
            actionIntent(ACTION_REPLY, immutable = false)
        ).addRemoteInput(remoteInput).build()
    }

    private fun hangUpAction(): Notification.Action {
        return Notification.Action.Builder(
            android.R.drawable.sym_call_missed,
            "Hang up",
            actionIntent(ACTION_HANG_UP, immutable = true)
        ).build()
    }

    private fun openAppIntent(): PendingIntent {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            this,
            1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
        )
    }

    private fun actionIntent(action: String, immutable: Boolean): PendingIntent {
        val intent = Intent(this, CallNotificationActionReceiver::class.java)
            .setAction(action)
        val flag = if (immutable) immutableFlag() else mutableFlag()
        return PendingIntent.getBroadcast(
            this,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or flag
        )
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Voice chat",
            NotificationManager.IMPORTANCE_LOW
        )
        channel.description = "Active Simple Voice App call controls"
        notificationManager().createNotificationChannel(channel)
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun notificationManager(): NotificationManager {
        return getSystemService(NOTIFICATION_SERVICE) as NotificationManager
    }

    companion object {
        const val ACTION_MUTE = "simple_voice_app.notification.MUTE"
        const val ACTION_UNMUTE = "simple_voice_app.notification.UNMUTE"
        const val ACTION_SPEAKER = "simple_voice_app.notification.SPEAKER"
        const val ACTION_EARPIECE = "simple_voice_app.notification.EARPIECE"
        const val ACTION_HANG_UP = "simple_voice_app.notification.HANG_UP"
        const val ACTION_REPLY = "simple_voice_app.notification.REPLY"
        const val REPLY_KEY = "simple_voice_app.notification.REPLY_TEXT"

        private const val CHANNEL_ID = "simple_voice_app_voice_chat"
        private const val NOTIFICATION_ID = 24055
        private const val SERVICE_START = "simple_voice_app.notification.START"
        private const val SERVICE_UPDATE = "simple_voice_app.notification.UPDATE"
        private const val SERVICE_STOP = "simple_voice_app.notification.STOP"
        private const val EXTRA_SERVER = "server"
        private const val EXTRA_STATUS = "status"
        private const val EXTRA_MUTED = "muted"
        private const val EXTRA_SPEAKER = "speaker"
        private const val EXTRA_TRANSIENT_STATUS = "transientStatus"

        fun start(context: Context, args: Map<String, Any?>) {
            context.startForegroundServiceCompat(serviceIntent(context, SERVICE_START, args))
        }

        fun update(context: Context, args: Map<String, Any?>) {
            context.startForegroundServiceCompat(serviceIntent(context, SERVICE_UPDATE, args))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CallNotificationService::class.java))
        }

        private fun serviceIntent(
            context: Context,
            action: String,
            args: Map<String, Any?>
        ): Intent {
            return Intent(context, CallNotificationService::class.java).apply {
                this.action = action
                putExtra(EXTRA_SERVER, args["server"]?.toString().orEmpty())
                putExtra(EXTRA_STATUS, args["status"]?.toString().orEmpty())
                putExtra(EXTRA_MUTED, args["muted"] as? Boolean ?: false)
                putExtra(EXTRA_SPEAKER, args["speaker"] as? Boolean ?: false)
                putExtra(
                    EXTRA_TRANSIENT_STATUS,
                    args["transientStatus"]?.toString().orEmpty()
                )
            }
        }

        private fun Context.startForegroundServiceCompat(intent: Intent) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        }

        private fun immutableFlag(): Int {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        }

        private fun mutableFlag(): Int {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE
            } else {
                0
            }
        }
    }
}
