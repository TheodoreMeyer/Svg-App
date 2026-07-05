import 'dart:typed_data';

import '../diagnostics.dart';
import '../protocol/svg_v2_frame.dart';
import 'audio_bridge.dart';

class IncomingAudioHandler {
  const IncomingAudioHandler(this._bridge);

  final AudioBridge _bridge;

  Future<DiagnosticsSnapshot> handle(
    Uint8List bytes,
    DiagnosticsSnapshot diagnostics,
  ) async {
    if (_looksLikeSvgV2(bytes)) {
      return _handleSvgV2(bytes, diagnostics);
    }

    final channels = bytes.lengthInBytes % 4 == 0 ? 2 : 1;
    await _bridge.playPcm16(bytes, channels: channels);
    return diagnostics.copyWith(
      selectedAudioMode: 'legacy',
      receivedLegacyFrames: diagnostics.receivedLegacyFrames + 1,
      lastReceivedPcmChannels: channels,
      lastReceivedPcmPeak: _pcmPeak(bytes),
    );
  }

  Future<DiagnosticsSnapshot> _handleSvgV2(
    Uint8List bytes,
    DiagnosticsSnapshot diagnostics,
  ) async {
    try {
      final frame = SvgV2Frame.parse(bytes);
      switch (frame.codec) {
        case SvgV2Codec.pcm16le:
          await _bridge.playPcm16(frame.payload, channels: frame.channels);
          return diagnostics.copyWith(
            selectedAudioMode: 'svg-v2',
            receivedSvgV2Frames: diagnostics.receivedSvgV2Frames + 1,
            lastReceivedPcmChannels: frame.channels,
            lastReceivedPcmPeak: _pcmPeak(frame.payload),
          );
        case SvgV2Codec.opus:
          return diagnostics.copyWith(
            state: AppConnectionState.degraded,
            selectedAudioMode: 'svg-v2',
            decoderStatus: 'Opus receive unsupported.',
            unsupportedOpusFrames: diagnostics.unsupportedOpusFrames + 1,
            receivedSvgV2Frames: diagnostics.receivedSvgV2Frames + 1,
          );
      }
    } on FormatException {
      return diagnostics.copyWith(
        malformedFrames: diagnostics.malformedFrames + 1,
      );
    }
  }

  bool _looksLikeSvgV2(Uint8List bytes) {
    return bytes.lengthInBytes >= 3 &&
        bytes[0] == 0x53 &&
        bytes[1] == 0x56 &&
        bytes[2] == 2;
  }

  int _pcmPeak(Uint8List bytes) {
    var peak = 0;
    final data = ByteData.sublistView(bytes);
    for (var offset = 0; offset + 1 < bytes.lengthInBytes; offset += 2) {
      final sample = data.getInt16(offset, Endian.little);
      final magnitude = sample == -32768 ? 32768 : sample.abs();
      if (magnitude > peak) peak = magnitude;
    }
    return peak;
  }
}
