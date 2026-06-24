import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_voice_app/src/protocol/connection_policy.dart';
import 'package:simple_voice_app/src/protocol/connection_target.dart';
import 'package:simple_voice_app/src/protocol/packets.dart';
import 'package:simple_voice_app/src/protocol/simple_voice_client.dart';
import 'package:simple_voice_app/src/protocol/svg_v2_frame.dart';

void main() {
  group('connection target', () {
    test('derives websocket url from http root server url', () {
      final uri = websocketUriForServer('http://voice.example.com:8080');

      expect(uri.toString(), 'ws://voice.example.com:8080/ws');
    });

    test('derives secure websocket url from https server url', () {
      final uri = websocketUriForServer('https://voice.example.com');

      expect(uri.toString(), 'wss://voice.example.com/ws');
    });

    test('preserves subpath when deriving websocket url', () {
      final uri = websocketUriForServer('http://example.com/voice/');

      expect(uri.toString(), 'ws://example.com/voice/ws');
    });

    test('defaults missing scheme to secure websocket', () {
      final uri = websocketUriForServer('voice.example.com:8080');

      expect(uri.toString(), 'wss://voice.example.com:8080/ws');
    });

    test('uses explicit http for trusted local websocket tests', () {
      final uri = websocketUriForServer('http://192.168.1.64:8080');

      expect(uri.toString(), 'ws://192.168.1.64:8080/ws');
    });

    test('rejects minecraft server port', () {
      expect(
        () => websocketUriForServer('192.168.1.64:25565'),
        throwsA(isA<FormatException>()),
      );
      expect(hasMinecraftServerPort('192.168.1.64:25565'), true);
      expect(hasMinecraftServerPort('192.168.1.64:8080'), false);
    });

    test('uses discovery websocket for host-only input', () async {
      Uri? requestedDiscovery;
      final uri = await websocketUriForServerWithDiscovery(
        'voice.example.com',
        fetchDiscovery: (uri) async {
          requestedDiscovery = uri;
          return '{"version":1,"androidProtocol":1,'
              '"websocket":"wss://voice.example.com:8443/ws"}';
        },
      );

      expect(
        requestedDiscovery.toString(),
        'https://voice.example.com/.well-known/simplevoice-geyser.json',
      );
      expect(uri.toString(), 'wss://voice.example.com:8443/ws');
    });

    test('falls back to direct websocket when discovery is missing', () async {
      final uri = await websocketUriForServerWithDiscovery(
        'voice.example.com',
        fetchDiscovery: (_) async => null,
      );

      expect(uri.toString(), 'wss://voice.example.com/ws');
    });

    test('skips discovery for explicit local address', () async {
      var triedDiscovery = false;
      final uri = await websocketUriForServerWithDiscovery(
        'http://192.168.1.64:8080',
        fetchDiscovery: (_) async {
          triedDiscovery = true;
          return null;
        },
      );

      expect(triedDiscovery, false);
      expect(uri.toString(), 'ws://192.168.1.64:8080/ws');
    });

    test('skips discovery for explicit custom port', () async {
      var triedDiscovery = false;
      final uri = await websocketUriForServerWithDiscovery(
        'voice.example.com:8443',
        fetchDiscovery: (_) async {
          triedDiscovery = true;
          return null;
        },
      );

      expect(triedDiscovery, false);
      expect(uri.toString(), 'wss://voice.example.com:8443/ws');
    });

    test('rejects invalid discovery json', () async {
      await expectLater(
        websocketUriForServerWithDiscovery(
          'voice.example.com',
          fetchDiscovery: (_) async => '{"websocket":"https://bad.example"}',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects invalid server urls', () {
      expect(
        () => websocketUriForServer(''),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => websocketUriForServer('ftp://example.com'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('packets', () {
    test('builds Android native join packet for plugin websocket auth', () {
      final packet = joinPacket(
        username: 'PlayerName',
        password: 'secret',
      );

      expect(packet, {
        'type': 'join',
        'username': 'PlayerName',
        'password': 'secret',
        'client': {
          'kind': androidClientKind,
          'version': androidClientVersion,
          'protocol': androidClientProtocol,
        },
      });
      expect(packet.containsKey('build'), false);
    });

    test('builds conservative legacy capabilities packet', () {
      expect(capabilitiesPacket(), {
        'type': 'capabilities',
        'audio': {
          'protocols': [legacyAudioMode],
          'supportsOpusDecoder': false,
          'secureContext': true,
          'decoder': {
            'nativeOpus': false,
            'opusWasm': false,
            'webCodecs': false,
          },
        },
      });
    });

    test('parses capabilities ack selected mode with legacy fallback', () {
      expect(
        selectedAudioModeFromCapabilitiesAck({
          'type': 'capabilities_ack',
          'selectedMode': 'legacy',
        }),
        legacyAudioMode,
      );
      expect(
        selectedAudioModeFromCapabilitiesAck({
          'type': 'capabilities_ack',
          'selectedMode': 'svg-v2',
        }),
        svgV2AudioMode,
      );
      expect(
        selectedAudioModeFromCapabilitiesAck({'type': 'capabilities_ack'}),
        legacyAudioMode,
      );
      expect(
        selectedAudioModeFromCapabilitiesAck({
          'type': 'capabilities_ack',
          'selectedMode': 'opus',
        }),
        legacyAudioMode,
      );
    });

    test('normalizes control packet types and detects connected status', () {
      final packet = {
        'type': ' STATUS ',
        'message': 'Connected as PlayerName.',
      };

      expect(controlPacketType(packet), 'status');
      expect(controlPacketMessage(packet), 'Connected as PlayerName.');
      expect(isConnectedStatusPacket(packet), true);
      expect(isConnectedStatusPacket({'type': 'chat', 'message': 'hi'}), false);
    });

    test('trims and rejects empty chat messages', () {
      expect(normalizeChatMessage('  hello  '), 'hello');
      expect(normalizeChatMessage('   '), isNull);
    });
  });

  group('simple voice client', () {
    test('installs websocket listener before sending join packet', () async {
      final socket = _FakeVoiceWebSocket();
      final client = SimpleVoiceClient(
        Uri.parse('ws://voice.example.com/ws'),
        connector: (_) async => socket,
      );

      await client.connect(
        username: 'PlayerName',
        password: 'secret',
        onControlPacket: (_) {},
        onAudioFrame: (_) {},
        onClosed: (code, reason) {
          throw StateError('Unexpected close: $code $reason');
        },
      );

      expect(socket.calls.take(2).toList(), ['listen', 'add']);
      final sentJoin = jsonDecode(socket.sent.single as String)
          as Map<String, Object?>;
      final clientInfo = sentJoin['client'] as Map<String, Object?>;
      expect(sentJoin['type'], 'join');
      expect(clientInfo['kind'], androidClientKind);
    });
  });

  group('reconnect policy', () {
    test('allows generic close to reconnect while attempts remain', () {
      expect(shouldReconnect(closeCode: 1001, attempts: 0), true);
    });

    test('blocks auth, fatal, shutdown, and outdated reconnects', () {
      for (final code in [4001, 4003, 4004, 4005, 4006, 4008]) {
        expect(shouldReconnect(closeCode: code, attempts: 0), false);
      }
    });

    test('humanizes unsupported Android protocol close reason', () {
      expect(
        closeMessage(
          closeCode: 4008,
          reason: appProtocolUnsupportedReason,
        ),
        appProtocolUnsupportedMessage,
      );
      expect(
        closeMessage(closeCode: 1001, reason: 'server_restart'),
        'The server disconnected you: server_restart',
      );
    });

    test('stops after five attempts', () {
      expect(shouldReconnect(closeCode: 1001, attempts: 5), false);
    });
  });

  group('svg-v2 parser', () {
    test('parses a pcm16le svg-v2 frame', () {
      final payload = Uint8List.fromList([0, 0, 255, 127]);
      final bytes = BytesBuilder()
        ..add([0x53, 0x56, 2, 0])
        ..add(_u32(7))
        ..add(_i16(0))
        ..add(_u16(32767))
        ..add(_u16(48000))
        ..add([1, 2])
        ..add(_u32(payload.length))
        ..add(payload);

      final frame = SvgV2Frame.parse(bytes.toBytes());

      expect(frame.sequence, 7);
      expect(frame.codec, SvgV2Codec.pcm16le);
      expect(frame.payload, payload);
    });

    test('rejects short frames and invalid payload length', () {
      expect(() => SvgV2Frame.parse(Uint8List(4)), throwsFormatException);

      final bad = BytesBuilder()
        ..add([0x53, 0x56, 2, 0])
        ..add(_u32(1))
        ..add(_i16(0))
        ..add(_u16(1))
        ..add(_u16(48000))
        ..add([1, 2])
        ..add(_u32(99));

      expect(() => SvgV2Frame.parse(bad.toBytes()), throwsFormatException);
    });

    test('rejects unknown codec', () {
      final bytes = BytesBuilder()
        ..add([0x53, 0x56, 2, 0])
        ..add(_u32(1))
        ..add(_i16(0))
        ..add(_u16(1))
        ..add(_u16(48000))
        ..add([1, 9])
        ..add(_u32(0));

      expect(() => SvgV2Frame.parse(bytes.toBytes()), throwsFormatException);
    });
  });
}

class _FakeVoiceWebSocket implements VoiceWebSocket {
  final _events = StreamController<dynamic>();
  final calls = <String>[];
  final sent = <Object>[];

  @override
  int? closeCode;

  @override
  String? closeReason;

  @override
  void add(Object data) {
    calls.add('add');
    sent.add(data);
  }

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic event) onData, {
    void Function()? onDone,
  }) {
    calls.add('listen');
    return _events.stream.listen(onData, onDone: onDone);
  }

  @override
  Future<void> close() async {
    await _events.close();
  }
}

List<int> _u16(int value) {
  final data = ByteData(2)..setUint16(0, value, Endian.little);
  return data.buffer.asUint8List();
}

List<int> _i16(int value) {
  final data = ByteData(2)..setInt16(0, value, Endian.little);
  return data.buffer.asUint8List();
}

List<int> _u32(int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  return data.buffer.asUint8List();
}
