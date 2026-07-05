import 'dart:typed_data';

class AudioGate {
  const AudioGate({
    required this.connected,
    required this.muted,
    required this.openMic,
    required this.pttActive,
  });

  static const packetBytes = 1920;

  final bool connected;
  final bool muted;
  final bool openMic;
  final bool pttActive;

  bool shouldSend(Uint8List packet) {
    if (!connected || muted || packet.lengthInBytes != packetBytes) {
      return false;
    }
    return openMic || pttActive;
  }
}
