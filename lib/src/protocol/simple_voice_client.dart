import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'connection_policy.dart';
import 'packets.dart';

typedef VoiceWebSocketConnector = Future<VoiceWebSocket> Function(Uri uri);

abstract interface class VoiceWebSocket {
  int? get closeCode;
  String? get closeReason;

  void add(Object data);

  StreamSubscription<dynamic> listen(
    void Function(dynamic event) onData, {
    void Function()? onDone,
  });

  Future<void> close();
}

class SimpleVoiceClient {
  SimpleVoiceClient(this.websocketUri, {VoiceWebSocketConnector? connector})
    : _connector = connector ?? _connectWebSocket;

  final Uri websocketUri;
  final VoiceWebSocketConnector _connector;
  VoiceWebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  int _attempts = 0;
  bool _manualClose = false;
  bool _authenticated = false;

  Future<void> connect({
    required String username,
    required String password,
    required void Function(Map<String, Object?> packet) onControlPacket,
    required void Function(Uint8List bytes) onAudioFrame,
    required void Function(int? code, String reason) onClosed,
  }) async {
    _manualClose = false;
    _authenticated = false;
    _attempts = 0;
    await _connectWithServerVersion(
      username: username,
      password: password,
      onControlPacket: onControlPacket,
      onAudioFrame: onAudioFrame,
      onClosed: onClosed,
      targetIndex: 0,
    );
  }

  Future<void> _connectWithServerVersion({
    required String username,
    required String password,
    required void Function(Map<String, Object?> packet) onControlPacket,
    required void Function(Uint8List bytes) onAudioFrame,
    required void Function(int? code, String reason) onClosed,
    required int targetIndex,
  }) async {
    final socket = await _connector(websocketUri);
    _socket = socket;
    _subscription = socket.listen(
      (event) {
        if (event is String) {
          final decoded = jsonDecode(event);
          if (decoded is Map) {
            final packet = Map<String, Object?>.from(decoded);
            if (_shouldSuppressRetryableCompatibilityError(
              packet: packet,
              targetIndex: targetIndex,
            )) {
              return;
            }
            if (isConnectedStatusPacket(packet)) {
              _authenticated = true;
            }
            onControlPacket(packet);
          }
        } else if (event is List<int>) {
          onAudioFrame(Uint8List.fromList(event));
        }
      },
      onDone: () {
        final code = socket.closeCode;
        final reason = socket.closeReason ?? '';
        if (_shouldRetryWithNextServerVersion(
          closeCode: code,
          reason: reason,
          targetIndex: targetIndex,
        )) {
          unawaited(
            _connectWithServerVersion(
              username: username,
              password: password,
              onControlPacket: onControlPacket,
              onAudioFrame: onAudioFrame,
              onClosed: onClosed,
              targetIndex: targetIndex + 1,
            ).catchError((Object error) {
              onClosed(null, error.toString());
            }),
          );
          return;
        }
        onClosed(code, reason);
        if (shouldReconnect(
          closeCode: code,
          attempts: _attempts,
          manualClose: _manualClose,
        )) {
          _attempts++;
        }
      },
    );
    socket.add(
      jsonEncode(
        joinPacket(
          username: username,
          password: password,
          serverVersion: supportedTargetServerVersions[targetIndex],
        ),
      ),
    );
  }

  bool _shouldRetryWithNextServerVersion({
    required int? closeCode,
    required String reason,
    required int targetIndex,
  }) {
    return !_manualClose &&
        !_authenticated &&
        closeCode == outdatedClientCloseCode &&
        reason.trim() == appProtocolUnsupportedReason &&
        _hasNextServerVersion(targetIndex);
  }

  bool _shouldSuppressRetryableCompatibilityError({
    required Map<String, Object?> packet,
    required int targetIndex,
  }) {
    return !_manualClose &&
        !_authenticated &&
        controlPacketType(packet) == 'error' &&
        controlPacketMessage(packet) == appProtocolUnsupportedMessage &&
        _hasNextServerVersion(targetIndex);
  }

  bool _hasNextServerVersion(int targetIndex) {
    return targetIndex + 1 < supportedTargetServerVersions.length;
  }

  void sendChat(String message) {
    _socket?.add(jsonEncode(chatPacket(message)));
  }

  void sendCapabilities() {
    _socket?.add(jsonEncode(capabilitiesPacket()));
  }

  void sendMicPacket(Uint8List packet) {
    _socket?.add(packet);
  }

  Future<void> disconnect() async {
    _manualClose = true;
    await _subscription?.cancel();
    await _socket?.close();
    _socket = null;
  }
}

Future<VoiceWebSocket> _connectWebSocket(Uri uri) async {
  final socket = await WebSocket.connect(
    uri.toString(),
    compression: CompressionOptions.compressionOff,
  );
  return _IoVoiceWebSocket(socket);
}

class _IoVoiceWebSocket implements VoiceWebSocket {
  _IoVoiceWebSocket(this._socket);

  final WebSocket _socket;

  @override
  int? get closeCode => _socket.closeCode;

  @override
  String? get closeReason => _socket.closeReason;

  @override
  void add(Object data) => _socket.add(data);

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic event) onData, {
    void Function()? onDone,
  }) {
    return _socket.listen(onData, onDone: onDone);
  }

  @override
  Future<void> close() async {
    await _socket.close();
  }
}
