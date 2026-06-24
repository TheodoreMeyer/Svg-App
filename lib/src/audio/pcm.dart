import 'dart:typed_data';

Uint8List floatsToPcm16(Float32List samples) {
  final bytes = Uint8List(samples.length * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < samples.length; i++) {
    final sample = samples[i].clamp(-1.0, 1.0);
    final value = sample < 0 ? sample * 32768 : sample * 32767;
    view.setInt16(i * 2, value.round(), Endian.little);
  }
  return bytes;
}

Float32List pcm16ToFloats(Uint8List bytes) {
  final sampleCount = bytes.lengthInBytes ~/ 2;
  final samples = Float32List(sampleCount);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < sampleCount; i++) {
    samples[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return samples;
}

class PcmPacketizer {
  PcmPacketizer({this.packetSamples = 960});

  final int packetSamples;
  final List<double> _buffer = [];

  List<Uint8List> add(Float32List samples) {
    _buffer.addAll(samples);
    final packets = <Uint8List>[];
    while (_buffer.length >= packetSamples) {
      final packet = Float32List(packetSamples);
      for (var i = 0; i < packetSamples; i++) {
        packet[i] = _buffer.removeAt(0);
      }
      packets.add(floatsToPcm16(packet));
    }
    return packets;
  }

  void clear() => _buffer.clear();
}
