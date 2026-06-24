package com.example.simple_voice_app

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val audioChannelName = "simple_voice_app/audio"
    private val micChannelName = "simple_voice_app/mic"
    private val notificationChannelName = "simple_voice_app/notification"
    private val notificationActionsChannelName = "simple_voice_app/notification_actions"
    private val permissionRequestCode = 4381
    private val notificationPermissionRequestCode = 4382
    private val sampleRate = 48000
    private val packetBytes = 1920
    private val mainHandler = Handler(Looper.getMainLooper())

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private var eventSink: EventChannel.EventSink? = null
    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private var micThread: Thread? = null
    private var speakerphoneRequested = false
    private var lastAudioRouteError = ""
    @Volatile private var micActive = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            audioChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestMicPermission" -> requestMicPermission(result)
                "startMic" -> result.success(startMic())
                "stopMic" -> {
                    stopMic()
                    result.success(null)
                }
                "startPlayback" -> result.success(startPlayback())
                "stopPlayback" -> {
                    stopPlayback()
                    result.success(null)
                }
                "playPcm16" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val channels = call.argument<Int>("channels") ?: 1
                    if (bytes == null) {
                        result.error("bad_args", "Missing PCM bytes.", null)
                    } else {
                        playPcm16(bytes, channels)
                        result.success(null)
                    }
                }
                "setSpeakerphone" -> {
                    val enabled = call.arguments as? Boolean ?: false
                    result.success(setSpeakerphone(enabled))
                }
                "getAudioRoute" -> result.success(getAudioRoute())
                "getAudioDebugInfo" -> result.success(getAudioDebugInfo())
                "resetAudio" -> {
                    resetAudio()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            notificationChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> requestNotificationPermission(result)
                "start" -> {
                    CallNotificationService.start(this, notificationArgs(call.arguments))
                    result.success(null)
                }
                "update" -> {
                    CallNotificationService.update(this, notificationArgs(call.arguments))
                    result.success(null)
                }
                "stop" -> {
                    CallNotificationService.stop(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            micChannelName
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                eventSink = sink
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            notificationActionsChannelName
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                NotificationActionBus.attach(sink)
            }

            override fun onCancel(arguments: Any?) {
                NotificationActionBus.detach()
            }
        })
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notificationPermissionRequestCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingNotificationPermissionResult?.success(granted)
            pendingNotificationPermissionResult = null
            return
        }
        if (requestCode != permissionRequestCode) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    override fun onDestroy() {
        resetAudio()
        CallNotificationService.stop(this)
        super.onDestroy()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        resetAudio()
        CallNotificationService.stop(this)
        NotificationActionBus.detach()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun requestMicPermission(result: MethodChannel.Result) {
        if (hasMicPermission()) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }
        pendingPermissionResult?.success(false)
        pendingPermissionResult = result
        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), permissionRequestCode)
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        pendingNotificationPermissionResult?.success(false)
        pendingNotificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun notificationArgs(arguments: Any?): Map<String, Any?> {
        return arguments as? Map<String, Any?> ?: emptyMap()
    }

    private fun hasMicPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun startMic(): Boolean {
        if (!hasMicPermission()) return false
        if (micActive) return true
        enterCommunicationMode()

        val minBuffer = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        if (minBuffer <= 0) return false

        return try {
            val record = AudioRecord(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                maxOf(minBuffer, packetBytes * 2)
            )
            if (record.state != AudioRecord.STATE_INITIALIZED) {
                record.release()
                return false
            }
            audioRecord = record
            micActive = true
            record.startRecording()
            micThread = Thread({ readMicLoop(record) }, "simple-voice-mic")
            micThread?.start()
            true
        } catch (error: Throwable) {
            reportAudioError("Microphone capture failed: ${error.message}")
            stopMic()
            false
        }
    }

    private fun readMicLoop(record: AudioRecord) {
        val readBuffer = ByteArray(packetBytes)
        val packet = ByteArray(packetBytes)
        var packetOffset = 0
        try {
            while (micActive) {
                val read = record.read(readBuffer, 0, readBuffer.size)
                if (read <= 0) continue
                var readOffset = 0
                while (readOffset < read) {
                    val toCopy = minOf(packetBytes - packetOffset, read - readOffset)
                    System.arraycopy(readBuffer, readOffset, packet, packetOffset, toCopy)
                    packetOffset += toCopy
                    readOffset += toCopy
                    if (packetOffset == packetBytes) {
                        val eventPacket = packet.copyOf()
                        mainHandler.post { eventSink?.success(eventPacket) }
                        packetOffset = 0
                    }
                }
            }
        } catch (error: Throwable) {
            reportAudioError("Microphone read failed: ${error.message}")
        }
    }

    private fun stopMic() {
        micActive = false
        val thread = micThread
        if (thread != null && thread != Thread.currentThread()) {
            try {
                thread.join(300)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }
        micThread = null
        try {
            audioRecord?.stop()
        } catch (_: Throwable) {
        }
        audioRecord?.release()
        audioRecord = null
    }

    private fun startPlayback(): Boolean {
        if (audioTrack?.playState == AudioTrack.PLAYSTATE_PLAYING) return true

        val minBuffer = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_STEREO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        if (minBuffer <= 0) return false

        return try {
            val format = AudioFormat.Builder()
                .setSampleRate(sampleRate)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                .build()
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            val track = AudioTrack.Builder()
                .setAudioAttributes(attributes)
                .setAudioFormat(format)
                .setBufferSizeInBytes(maxOf(minBuffer, packetBytes * 4))
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
            if (track.state != AudioTrack.STATE_INITIALIZED) {
                track.release()
                return false
            }
            audioTrack = track
            track.setVolume(AudioTrack.getMaxVolume())
            applyPlaybackRoute()
            track.play()
            true
        } catch (error: Throwable) {
            reportAudioError("PCM playback failed: ${error.message}")
            stopPlayback()
            false
        }
    }

    private fun playPcm16(bytes: ByteArray, channels: Int) {
        if (audioTrack?.playState != AudioTrack.PLAYSTATE_PLAYING && !startPlayback()) {
            return
        }
        val output = when (channels) {
            1 -> monoToStereo(bytes)
            2 -> if (shouldDownmixPlaybackToMono()) stereoToMonoStereo(bytes) else bytes
            else -> {
                reportAudioError("Unsupported PCM channel count: $channels")
                return
            }
        }
        audioTrack?.write(output, 0, output.size)
    }

    private fun monoToStereo(bytes: ByteArray): ByteArray {
        val output = ByteArray(bytes.size * 2)
        var inputOffset = 0
        var outputOffset = 0
        while (inputOffset + 1 < bytes.size) {
            val low = bytes[inputOffset]
            val high = bytes[inputOffset + 1]
            output[outputOffset] = low
            output[outputOffset + 1] = high
            output[outputOffset + 2] = low
            output[outputOffset + 3] = high
            inputOffset += 2
            outputOffset += 4
        }
        return output
    }

    private fun stereoToMonoStereo(bytes: ByteArray): ByteArray {
        val output = ByteArray(bytes.size)
        var offset = 0
        while (offset + 3 < bytes.size) {
            val left = readPcm16Le(bytes, offset)
            val right = readPcm16Le(bytes, offset + 2)
            val mono = ((left + right) / 2).toShort()
            writePcm16Le(output, offset, mono)
            writePcm16Le(output, offset + 2, mono)
            offset += 4
        }
        return output
    }

    private fun readPcm16Le(bytes: ByteArray, offset: Int): Int {
        return ((bytes[offset].toInt() and 0xff) or
            (bytes[offset + 1].toInt() shl 8)).toShort().toInt()
    }

    private fun writePcm16Le(bytes: ByteArray, offset: Int, value: Short) {
        val intValue = value.toInt()
        bytes[offset] = (intValue and 0xff).toByte()
        bytes[offset + 1] = ((intValue shr 8) and 0xff).toByte()
    }

    private fun shouldDownmixPlaybackToMono(): Boolean {
        if (speakerphoneRequested) return false
        val audioManager = audioManager()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            when (audioManager.communicationDevice?.type) {
                AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> return true
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> return false
                null -> {}
                else -> return false
            }
        } else {
            @Suppress("DEPRECATION")
            if (audioManager.isSpeakerphoneOn) return false
        }
        return !hasExternalStereoOutput(audioManager)
    }

    private fun hasExternalStereoOutput(audioManager: AudioManager): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .any { isExternalOutput(it) }
    }

    private fun stopPlayback() {
        try {
            audioTrack?.pause()
            audioTrack?.flush()
            audioTrack?.stop()
        } catch (_: Throwable) {
        }
        audioTrack?.release()
        audioTrack = null
    }

    private fun resetAudio() {
        stopMic()
        stopPlayback()
        speakerphoneRequested = false
        lastAudioRouteError = ""
        setSpeakerphone(false)
        val audioManager = audioManager()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.clearCommunicationDevice()
        }
        audioManager.mode = AudioManager.MODE_NORMAL
        pendingPermissionResult?.success(false)
        pendingPermissionResult = null
    }

    private fun setSpeakerphone(enabled: Boolean): Boolean {
        speakerphoneRequested = enabled
        enterCommunicationMode()
        return applyAudioRoute(enabled)
    }

    private fun enterCommunicationMode() {
        val audioManager = audioManager()
        audioManager.mode = if (speakerphoneRequested) {
            AudioManager.MODE_NORMAL
        } else {
            AudioManager.MODE_IN_COMMUNICATION
        }
        applyAudioRoute(speakerphoneRequested)
    }

    private fun applyAudioRoute(speaker: Boolean): Boolean {
        val audioManager = audioManager()
        audioManager.mode = if (speaker) {
            AudioManager.MODE_NORMAL
        } else {
            AudioManager.MODE_IN_COMMUNICATION
        }
        val communicationApplied = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val type = if (speaker) {
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
            } else {
                AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
            }
            val device = audioManager.availableCommunicationDevices
                .firstOrNull { it.type == type }
            if (device == null) {
                lastAudioRouteError = "Communication route device unavailable."
                false
            } else {
                val applied = audioManager.setCommunicationDevice(device)
                if (!applied) lastAudioRouteError = "Communication route switch failed."
                applied
            }
        } else {
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = speaker
            true
        }
        val playbackApplied = applyPlaybackRoute()
        if (communicationApplied || playbackApplied) lastAudioRouteError = ""
        return communicationApplied || playbackApplied
    }

    private fun applyPlaybackRoute(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val track = audioTrack ?: return true
        val device = preferredPlaybackDevice()
        return if (device == null) {
            val applied = track.setPreferredDevice(null)
            if (!applied) lastAudioRouteError = "Playback route reset failed."
            applied
        } else {
            val applied = track.setPreferredDevice(device)
            if (!applied) lastAudioRouteError = "Playback route switch failed."
            applied
        }
    }

    private fun preferredPlaybackDevice(): AudioDeviceInfo? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        val audioManager = audioManager()
        val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).toList()
        if (speakerphoneRequested) {
            return outputs.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
        }
        return outputs.firstOrNull { isExternalOutput(it) }
            ?: outputs.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }
    }

    private fun isExternalOutput(device: AudioDeviceInfo): Boolean {
        return when (device.type) {
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_USB_DEVICE,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_ACCESSORY -> true
            else -> false
        }
    }

    private fun getAudioRoute(): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            audioTrack?.preferredDevice?.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
        ) {
            return "speaker"
        }
        val audioManager = audioManager()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return when (audioManager.communicationDevice?.type) {
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
                AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "normal"
                null -> if (speakerphoneRequested) "speaker" else "normal"
                else -> "unavailable"
            }
        }
        @Suppress("DEPRECATION")
        return if (audioManager.isSpeakerphoneOn) "speaker" else "normal"
    }

    private fun getAudioDebugInfo(): String {
        val audioManager = audioManager()
        val preferred = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioTrack?.preferredDevice
        } else {
            null
        }
        return listOf(
            "Audio Devtools",
            "Native audio mode: ${audioModeName(audioManager.mode)}",
            "Playback preferred device: ${deviceLabel(preferred)}",
            "Speaker requested: $speakerphoneRequested",
            "Speaker applied: ${getAudioRoute() == "speaker"}",
            "Media volume: ${audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)}/${audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)}",
            "Call volume: ${audioManager.getStreamVolume(AudioManager.STREAM_VOICE_CALL)}/${audioManager.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)}",
            "Route error: ${lastAudioRouteError.ifEmpty { "none" }}"
        ).joinToString("\n")
    }

    private fun audioModeName(mode: Int): String {
        return when (mode) {
            AudioManager.MODE_NORMAL -> "normal"
            AudioManager.MODE_IN_COMMUNICATION -> "inCommunication"
            AudioManager.MODE_IN_CALL -> "inCall"
            AudioManager.MODE_RINGTONE -> "ringtone"
            else -> mode.toString()
        }
    }

    private fun deviceLabel(device: AudioDeviceInfo?): String {
        if (device == null) return "none"
        val productName = device.productName?.toString()?.takeIf { it.isNotBlank() }
        val type = deviceTypeName(device.type)
        return if (productName == null) type else "$type ($productName)"
    }

    private fun deviceTypeName(type: Int): String {
        return when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "builtInEarpiece"
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "builtInSpeaker"
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "wiredHeadphones"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wiredHeadset"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bluetoothA2dp"
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetoothSco"
            AudioDeviceInfo.TYPE_USB_DEVICE -> "usbDevice"
            AudioDeviceInfo.TYPE_USB_HEADSET -> "usbHeadset"
            AudioDeviceInfo.TYPE_USB_ACCESSORY -> "usbAccessory"
            else -> "type$type"
        }
    }

    private fun audioManager(): AudioManager {
        return getSystemService(AUDIO_SERVICE) as AudioManager
    }

    private fun reportAudioError(message: String) {
        mainHandler.post { eventSink?.error("audio_error", message, null) }
    }
}
