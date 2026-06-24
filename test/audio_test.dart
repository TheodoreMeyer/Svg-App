import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_voice_app/src/audio/pcm.dart';

void main() {
  test('converts float samples to little-endian pcm16', () {
    final pcm = floatsToPcm16(Float32List.fromList([-1, 0, 1]));
    final view = ByteData.sublistView(pcm);

    expect(view.getInt16(0, Endian.little), -32768);
    expect(view.getInt16(2, Endian.little), 0);
    expect(view.getInt16(4, Endian.little), 32767);
  });

  test('converts pcm16 bytes to floats', () {
    final bytes = Uint8List(4);
    ByteData.sublistView(bytes)
      ..setInt16(0, -32768, Endian.little)
      ..setInt16(2, 32767, Endian.little);

    final floats = pcm16ToFloats(bytes);

    expect(floats[0], -1);
    expect(floats[1], closeTo(0.9999, 0.0002));
  });

  test('packetizes samples into 960-sample microphone packets', () {
    final packetizer = PcmPacketizer(packetSamples: 960);
    final first = packetizer.add(Float32List(480));
    final second = packetizer.add(Float32List(480));

    expect(first, isEmpty);
    expect(second, hasLength(1));
    expect(second.single.lengthInBytes, 1920);
  });
}
