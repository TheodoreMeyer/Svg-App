import 'dart:typed_data';

enum SvgV2Codec { opus, pcm16le }

class SvgV2Frame {
  const SvgV2Frame({
    required this.flags,
    required this.sequence,
    required this.pan,
    required this.gain,
    required this.sampleRate,
    required this.channels,
    required this.codec,
    required this.payload,
  });

  factory SvgV2Frame.parse(Uint8List bytes) {
    if (bytes.lengthInBytes < 20) {
      throw const FormatException('svg-v2 frame is shorter than 20 bytes.');
    }
    if (bytes[0] != 0x53 || bytes[1] != 0x56 || bytes[2] != 2) {
      throw const FormatException('Not an svg-v2 frame.');
    }

    final data = ByteData.sublistView(bytes);
    final payloadLength = data.getUint32(16, Endian.little);
    final payloadEnd = 20 + payloadLength;
    if (payloadEnd != bytes.lengthInBytes) {
      throw const FormatException('svg-v2 payload length exceeds frame size.');
    }

    final codec = switch (data.getUint8(15)) {
      1 => SvgV2Codec.opus,
      2 => SvgV2Codec.pcm16le,
      _ => throw const FormatException('Unknown svg-v2 codec.'),
    };
    final channels = data.getUint8(14);
    if (data.getUint16(12, Endian.little) != 48000 ||
        (channels != 1 && channels != 2) ||
        (codec == SvgV2Codec.opus && payloadLength > 1275) ||
        (codec == SvgV2Codec.pcm16le && payloadLength % (channels * 2) != 0)) {
      throw const FormatException('Unsupported svg-v2 audio format.');
    }

    return SvgV2Frame(
      flags: data.getUint8(3),
      sequence: data.getUint32(4, Endian.little),
      pan: (data.getInt16(8, Endian.little) / 32767.0).clamp(-1.0, 1.0),
      gain: (data.getInt16(10, Endian.little) / 32767.0).clamp(0.0, 1.0),
      sampleRate: data.getUint16(12, Endian.little),
      channels: channels,
      codec: codec,
      payload: Uint8List.sublistView(bytes, 20, payloadEnd),
    );
  }

  final int flags;
  final int sequence;
  final double pan;
  final double gain;
  final int sampleRate;
  final int channels;
  final SvgV2Codec codec;
  final Uint8List payload;
}
