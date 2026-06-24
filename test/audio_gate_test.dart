import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_voice_app/src/audio/audio_gate.dart';

void main() {
  final packet = Uint8List(1920);

  test('open mic sends when connected and unmuted', () {
    final gate = AudioGate(
      connected: true,
      muted: false,
      openMic: true,
      pttActive: false,
    );

    expect(gate.shouldSend(packet), isTrue);
  });

  test('gate blocks when muted or disconnected', () {
    expect(
      AudioGate(
        connected: true,
        muted: true,
        openMic: true,
        pttActive: true,
      ).shouldSend(packet),
      isFalse,
    );
    expect(
      AudioGate(
        connected: false,
        muted: false,
        openMic: true,
        pttActive: true,
      ).shouldSend(packet),
      isFalse,
    );
  });

  test('push to talk sends only while active', () {
    expect(
      AudioGate(
        connected: true,
        muted: false,
        openMic: false,
        pttActive: false,
      ).shouldSend(packet),
      isFalse,
    );
    expect(
      AudioGate(
        connected: true,
        muted: false,
        openMic: false,
        pttActive: true,
      ).shouldSend(packet),
      isTrue,
    );
  });

  test('gate blocks malformed mic packets', () {
    expect(
      AudioGate(
        connected: true,
        muted: false,
        openMic: true,
        pttActive: false,
      ).shouldSend(Uint8List(10)),
      isFalse,
    );
  });
}
