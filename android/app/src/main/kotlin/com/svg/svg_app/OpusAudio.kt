package com.svg.svg_app

import android.media.MediaCodec
import android.media.MediaFormat
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.ArrayDeque

internal class OpusAudio {
    private var encoder: MediaCodec? = null
    private var decoder: MediaCodec? = null
    private var encoderGeneration = -1
    private var encoderTimestampUs = 0L
    private val encoderCaptureTimes = ArrayDeque<Long>()
    private var decoderChannels = 0

    fun prepare(): Map<String, Boolean> {
        val canEncode = try {
            var valid = false
            repeat(4) { frame ->
                if (encode(ByteArray(1920), 0, frame * 20000L) != null) valid = true
            }
            valid
        } catch (_: Exception) { false }
        close()
        val canDecode = try {
            var valid = false
            repeat(4) {
                if (decode(byteArrayOf(0xf8.toByte(), 0xff.toByte(), 0xfe.toByte()), 1).isNotEmpty()) valid = true
            }
            valid
        } catch (_: Exception) { false }
        close()
        return mapOf("encoder" to canEncode, "decoder" to canDecode)
    }

    fun encode(pcm: ByteArray, generation: Int, timestampUs: Long): ByteArray? {
        require(pcm.size == 1920) { "Opus input must contain 960 PCM16 samples." }
        if (encoder == null || encoderGeneration != generation) {
            release(encoder)
            encoder = null
            val format = MediaFormat.createAudioFormat("audio/opus", 48000, 1)
            format.setInteger(MediaFormat.KEY_BIT_RATE, 32000)
            encoder = create(format, true)
            encoderGeneration = generation
            encoderTimestampUs = 0
            encoderCaptureTimes.clear()
        }
        val codec = encoder!!
        val input = codec.dequeueInputBuffer(0)
        if (input < 0) {
            return drainEncoder(codec, timestampUs)
        }
        codec.getInputBuffer(input)!!.put(pcm)
        // Codec timestamps follow submitted samples; capture gaps must not make fresh audio stale.
        codec.queueInputBuffer(input, 0, pcm.size, encoderTimestampUs, 0)
        encoderTimestampUs += 20000
        encoderCaptureTimes.addLast(timestampUs)
        return drainEncoder(codec, timestampUs)
    }

    private fun drainEncoder(codec: MediaCodec, timestampUs: Long): ByteArray? {
        val info = MediaCodec.BufferInfo()
        var packet: ByteArray? = null
        repeat(4) {
            val output = codec.dequeueOutputBuffer(info, if (it == 0) 5000 else 0)
            if (output >= 0) {
                try {
                    if (info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                        val bytes = read(codec, output, info)
                        require(isVoicePacket(bytes)) { "Native encoder returned incompatible Opus audio." }
                        val captured = encoderCaptureTimes.pollFirst()
                        if (captured != null && timestampUs - captured <= 150000) packet = bytes
                    }
                } finally { codec.releaseOutputBuffer(output, false) }
            }
        }
        return packet
    }

    fun decode(packet: ByteArray, channels: Int): ByteArray {
        require(packet.isNotEmpty() && packet.size <= 1275 && channels in 1..2) { "Invalid Opus frame." }
        if (decoder == null || channels != decoderChannels) {
            release(decoder)
            decoder = null
            val format = MediaFormat.createAudioFormat("audio/opus", 48000, channels)
            val head = ByteBuffer.allocate(19).order(ByteOrder.LITTLE_ENDIAN)
                .put("OpusHead".toByteArray(Charsets.US_ASCII)).put(1.toByte()).put(channels.toByte())
                .putShort(0.toShort()).putInt(48000).putShort(0.toShort()).put(0.toByte())
            head.flip()
            format.setByteBuffer("csd-0", head)
            format.setByteBuffer("csd-1", ByteBuffer.allocate(8).order(ByteOrder.nativeOrder()).apply { putLong(0); flip() })
            format.setByteBuffer("csd-2", ByteBuffer.allocate(8).order(ByteOrder.nativeOrder()).apply { putLong(0); flip() })
            decoder = create(format, false)
            decoderChannels = channels
            decodeTimestampUs = 0
        }
        val codec = decoder!!
        val input = codec.dequeueInputBuffer(0)
        if (input < 0) {
            discardOutput(codec)
            return ByteArray(0)
        }
        codec.getInputBuffer(input)!!.put(packet)
        val timestampUs = decodeTimestampUs
        codec.queueInputBuffer(input, 0, packet.size, timestampUs, 0)
        decodeTimestampUs += 20000
        val pcm = ByteArrayOutputStream()
        val info = MediaCodec.BufferInfo()
        repeat(4) {
            val output = codec.dequeueOutputBuffer(info, if (it == 0) 5000 else 0)
            if (output >= 0) {
                try {
                    if (info.size > 0 && info.presentationTimeUs == timestampUs) {
                        pcm.write(read(codec, output, info))
                    }
                } finally { codec.releaseOutputBuffer(output, false) }
            } else if (output == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                val format = codec.outputFormat
                require(format.getInteger(MediaFormat.KEY_SAMPLE_RATE) == 48000 &&
                    format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) == channels &&
                    (!format.containsKey(MediaFormat.KEY_PCM_ENCODING) ||
                        format.getInteger(MediaFormat.KEY_PCM_ENCODING) == 2)) { "Unsupported decoder PCM format." }
            }
        }
        return pcm.toByteArray()
    }

    private var decodeTimestampUs = 0L

    fun close() {
        release(encoder)
        release(decoder)
        encoder = null
        decoder = null
        encoderGeneration = -1
        encoderTimestampUs = 0
        encoderCaptureTimes.clear()
        decoderChannels = 0
    }

    private fun create(format: MediaFormat, encode: Boolean): MediaCodec {
        val codec = if (encode) MediaCodec.createEncoderByType("audio/opus")
                    else MediaCodec.createDecoderByType("audio/opus")
        try {
            codec.configure(format, null, null, if (encode) MediaCodec.CONFIGURE_FLAG_ENCODE else 0)
            codec.start()
            return codec
        } catch (error: Exception) {
            codec.release()
            throw error
        }
    }

    private fun read(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo): ByteArray {
        val buffer = codec.getOutputBuffer(index)!!
        buffer.position(info.offset)
        buffer.limit(info.offset + info.size)
        return ByteArray(info.size).also { buffer.get(it) }
    }

    private fun release(codec: MediaCodec?) {
        try { codec?.release() } catch (_: Exception) { }
    }

    private fun discardOutput(codec: MediaCodec) {
        val info = MediaCodec.BufferInfo()
        repeat(4) {
            val output = codec.dequeueOutputBuffer(info, 0)
            if (output >= 0) codec.releaseOutputBuffer(output, false)
        }
    }

    private fun isVoicePacket(packet: ByteArray): Boolean {
        if (packet.isEmpty() || packet.size > 1275) return false
        val toc = packet[0].toInt() and 255
        val samples = when {
            toc and 128 != 0 -> (48000 shl ((toc shr 3) and 3)) / 400
            toc and 96 == 96 -> if (toc and 8 != 0) 960 else 480
            (toc shr 3) and 3 == 3 -> 2880
            else -> (48000 shl ((toc shr 3) and 3)) / 100
        }
        val frames = when (toc and 3) {
            0 -> 1
            3 -> if (packet.size > 1) packet[1].toInt() and 63 else 0
            else -> 2
        }
        return samples * frames == 960 && toc and 4 == 0
    }
}
