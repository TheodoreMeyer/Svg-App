import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_voice_app/src/audio/audio_bridge.dart';
import 'package:simple_voice_app/src/audio/incoming_audio_handler.dart';
import 'package:simple_voice_app/src/diagnostics.dart';

void main() {
  test('legacy PCM frames call playback with inferred channel count', () async {
    final bridge = _FakeAudioBridge();
    final handler = IncomingAudioHandler(bridge);
    final diagnostic = await handler.handle(
      Uint8List.fromList([1, 0, 2, 0, 3, 0, 4, 0]),
      const DiagnosticsSnapshot(),
    );

    expect(bridge.played, hasLength(1));
    expect(bridge.played.single.channels, 2);
    expect(diagnostic.receivedLegacyFrames, 1);
    expect(diagnostic.lastReceivedPcmChannels, 2);
    expect(diagnostic.lastReceivedPcmPeak, 4);
  });

  test('svg-v2 PCM frames call playback and update diagnostics', () async {
    final bridge = _FakeAudioBridge();
    final handler = IncomingAudioHandler(bridge);
    final diagnostic = await handler.handle(
      _svgV2(codec: 2, channels: 1, payload: [1, 0, 2, 0]),
      const DiagnosticsSnapshot(),
    );

    expect(bridge.played, hasLength(1));
    expect(bridge.played.single.channels, 1);
    expect(bridge.played.single.bytes, [1, 0, 2, 0]);
    expect(diagnostic.selectedAudioMode, 'svg-v2');
    expect(diagnostic.receivedSvgV2Frames, 1);
    expect(diagnostic.lastReceivedPcmChannels, 1);
    expect(diagnostic.lastReceivedPcmPeak, 2);
  });

  test('svg-v2 stereo PCM frames preserve channel count for playback',
      () async {
    final bridge = _FakeAudioBridge();
    final handler = IncomingAudioHandler(bridge);
    final diagnostic = await handler.handle(
      _svgV2(codec: 2, channels: 2, payload: [1, 0, 2, 0, 3, 0, 4, 0]),
      const DiagnosticsSnapshot(),
    );

    expect(bridge.played, hasLength(1));
    expect(bridge.played.single.channels, 2);
    expect(bridge.played.single.bytes, [1, 0, 2, 0, 3, 0, 4, 0]);
    expect(diagnostic.selectedAudioMode, 'svg-v2');
  });

  test('svg-v2 Opus frames are counted as unsupported without playback', () async {
    final bridge = _FakeAudioBridge();
    final handler = IncomingAudioHandler(bridge);
    final diagnostic = await handler.handle(
      _svgV2(codec: 1, channels: 1, payload: [1, 2, 3]),
      const DiagnosticsSnapshot(state: AppConnectionState.connected),
    );

    expect(bridge.played, isEmpty);
    expect(diagnostic.state, AppConnectionState.degraded);
    expect(diagnostic.unsupportedOpusFrames, 1);
    expect(diagnostic.decoderStatus, contains('unsupported'));
  });

  test('malformed svg-v2 frames increment diagnostics and are ignored', () async {
    final bridge = _FakeAudioBridge();
    final handler = IncomingAudioHandler(bridge);
    final diagnostic = await handler.handle(
      Uint8List.fromList([0x53, 0x56, 2]),
      const DiagnosticsSnapshot(),
    );

    expect(bridge.played, isEmpty);
    expect(diagnostic.malformedFrames, 1);
  });
}

Uint8List _svgV2({
  required int codec,
  required int channels,
  required List<int> payload,
}) {
  final bytes = Uint8List(20 + payload.length);
  final data = ByteData.sublistView(bytes);
  data.setUint8(0, 0x53);
  data.setUint8(1, 0x56);
  data.setUint8(2, 2);
  data.setUint8(3, 0);
  data.setUint32(4, 1, Endian.little);
  data.setInt16(8, 0, Endian.little);
  data.setUint16(10, 32767, Endian.little);
  data.setUint16(12, 48000, Endian.little);
  data.setUint8(14, channels);
  data.setUint8(15, codec);
  data.setUint32(16, payload.length, Endian.little);
  bytes.setAll(20, payload);
  return bytes;
}

class _FakeAudioBridge implements AudioBridge {
  final played = <_PlayedPcm>[];

  @override
  AudioBridgeState get state => const AudioBridgeState();

  @override
  Stream<Uint8List> get micPackets => const Stream.empty();

  @override
  Future<void> playPcm16(Uint8List bytes, {required int channels}) async {
    played.add(_PlayedPcm(bytes, channels));
  }

  @override
  Future<String> refreshAudioRoute() async => 'normal';

  @override
  Future<String> refreshAudioDebugInfo() async => '';

  @override
  Future<bool> requestMicPermission() async => true;

  @override
  Future<void> resetAudio() async {}

  @override
  Future<bool> setSpeakerphone(bool enabled) async => true;

  @override
  Future<bool> startMic() async => true;

  @override
  Future<bool> startPlayback() async => true;

  @override
  Future<void> stopMic() async {}

  @override
  Future<void> stopPlayback() async {}
}

class _PlayedPcm {
  const _PlayedPcm(this.bytes, this.channels);

  final Uint8List bytes;
  final int channels;
}
