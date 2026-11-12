import 'dart:typed_data';

import '../diagnostics.dart';
import '../protocol/svg_v2_frame.dart';
import 'audio_bridge.dart';
import 'pcm.dart';

class IncomingAudioHandler {
  IncomingAudioHandler(this._bridge);

  final AudioBridge _bridge;
  int emptyOpusDecodes = 0;

  Future<DiagnosticsSnapshot> handle(
    Uint8List bytes,
    DiagnosticsSnapshot diagnostics, {
    bool opusDecoder = false,
    bool Function()? isCurrent,
  }) async {
    if (_looksLikeSvgV2(bytes)) {
      return _handleSvgV2(bytes, diagnostics, opusDecoder, isCurrent);
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
    bool opusDecoder,
    bool Function()? isCurrent,
  ) async {
    try {
      final frame = SvgV2Frame.parse(bytes);
      // Simple Voice Chat ends a talk burst with an empty packet, which the plugin forwards as-is.
      if (frame.payload.isEmpty) {
        return diagnostics.copyWith(
          selectedAudioMode: 'svg-v2',
          receivedSvgV2Frames: diagnostics.receivedSvgV2Frames + 1,
        );
      }
      if (frame.codec == SvgV2Codec.opus && !opusDecoder) {
        return diagnostics.copyWith(
          state: AppConnectionState.degraded,
          selectedAudioMode: 'svg-v2',
          decoderStatus: 'Opus receive unsupported.',
          unsupportedOpusFrames: diagnostics.unsupportedOpusFrames + 1,
          receivedSvgV2Frames: diagnostics.receivedSvgV2Frames + 1,
        );
      }
      final pcm = frame.codec == SvgV2Codec.opus
          ? await _bridge.decodeOpus(frame.payload, channels: frame.channels)
          : frame.payload;
      if (isCurrent != null && !isCurrent()) return diagnostics;
      if (frame.codec == SvgV2Codec.opus) {
        if (pcm.isEmpty) {
          emptyOpusDecodes++;
          return diagnostics;
        }
        emptyOpusDecodes = 0;
      }
      final spatial = spatialPcm16(
        pcm,
        channels: frame.channels,
        pan: frame.pan,
        gain: frame.gain,
      );
      await _bridge.playPcm16(spatial, channels: 2);
      return diagnostics.copyWith(
        selectedAudioMode: 'svg-v2',
        decoderStatus: frame.codec == SvgV2Codec.opus
            ? 'Native Opus ready'
            : diagnostics.decoderStatus,
        receivedSvgV2Frames: diagnostics.receivedSvgV2Frames + 1,
        lastReceivedPcmChannels: 2,
        lastReceivedPcmPeak: _pcmPeak(spatial),
      );
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
