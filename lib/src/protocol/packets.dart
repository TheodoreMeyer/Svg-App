const String androidClientKind = 'android';
const String androidClientVersion = '1.0.0';
const int androidClientProtocol = 1;
const String legacyAudioMode = 'legacy';
const String svgV2AudioMode = 'svg-v2';

Map<String, Object?> joinPacket({
  required String username,
  required String password,
}) {
  return {
    'type': 'join',
    'username': username.trim(),
    'password': password,
    'client': {
      'kind': androidClientKind,
      'version': androidClientVersion,
      'protocol': androidClientProtocol,
    },
  };
}

Map<String, Object?> capabilitiesPacket() {
  return {
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
  };
}

String selectedAudioModeFromCapabilitiesAck(Map<String, Object?> packet) {
  final selectedMode = packet['selectedMode']?.toString();
  return selectedMode == svgV2AudioMode ? svgV2AudioMode : legacyAudioMode;
}

String controlPacketType(Map<String, Object?> packet) {
  return packet['type']?.toString().trim().toLowerCase() ?? 'info';
}

String controlPacketMessage(Map<String, Object?> packet) {
  return packet['message']?.toString() ?? packet.toString();
}

bool isConnectedStatusPacket(Map<String, Object?> packet) {
  return controlPacketType(packet) == 'status' &&
      controlPacketMessage(packet).toLowerCase().contains('connected as');
}

Map<String, Object?> chatPacket(String message) {
  final normalized = normalizeChatMessage(message);
  if (normalized == null) {
    throw const FormatException('Chat message cannot be empty.');
  }
  return {'type': 'chat', 'message': normalized};
}

String? normalizeChatMessage(String message) {
  final trimmed = message.trim();
  return trimmed.isEmpty ? null : trimmed;
}
