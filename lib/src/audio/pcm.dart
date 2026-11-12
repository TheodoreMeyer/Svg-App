import 'dart:typed_data';
import 'dart:math' as math;

Uint8List spatialPcm16(
  Uint8List bytes, {
  required int channels,
  required double pan,
  required double gain,
}) {
  if (bytes.lengthInBytes % (channels * 2) != 0) {
    throw const FormatException('Incomplete PCM sample.');
  }
  final frames = bytes.lengthInBytes ~/ (channels * 2);
  final input = ByteData.sublistView(bytes);
  final output = Uint8List(frames * 4);
  final view = ByteData.sublistView(output);
  final angle = (pan.clamp(-1.0, 1.0) + 1) * math.pi / 4;
  final left = math.cos(angle) * gain.clamp(0.0, 1.0);
  final right = math.sin(angle) * gain.clamp(0.0, 1.0);
  for (var i = 0; i < frames; i++) {
    final offset = i * channels * 2;
    final mono = channels == 1
        ? input.getInt16(offset, Endian.little).toDouble()
        : (input.getInt16(offset, Endian.little) +
                  input.getInt16(offset + 2, Endian.little)) /
              2;
    view.setInt16(
      i * 4,
      (mono * left).round().clamp(-32768, 32767),
      Endian.little,
    );
    view.setInt16(
      i * 4 + 2,
      (mono * right).round().clamp(-32768, 32767),
      Endian.little,
    );
  }
  return output;
}
