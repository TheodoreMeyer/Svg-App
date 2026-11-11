const String svgAppClientType = 'Svg-App';
const String targetServerVersion = '0.1.5';
const String baselineTargetServerVersion = '0.1.3';
const List<String> supportedTargetServerVersions = [
  targetServerVersion,
  '0.1.4',
  baselineTargetServerVersion,
];
const String legacyAudioMode = 'legacy';
const String svgV2AudioMode = 'svg-v2';

List<String> serverVersionTargets(String? discovered) => [
  if (supportedTargetServerVersions.contains(discovered)) discovered!,
  ...supportedTargetServerVersions.where((version) => version != discovered),
];

final _projectVersion = RegExp(
  r'''PROJECT_VERSION\s*=\s*["'](\d+\.\d+\.\d+)["']''',
);

String? parseProjectVersion(String html) =>
    _projectVersion.firstMatch(html)?.group(1);

Map<String, Object?> joinPacket({
  required String username,
  required String password,
  String serverVersion = targetServerVersion,
}) {
  return {
    'type': 'join',
    'username': username.trim(),
    'password': password,
    'clientType': {'type': svgAppClientType, 'serverVersion': serverVersion},
  };
}

Map<String, Object?> capabilitiesPacket({
  bool opusEncoder = false,
  bool opusDecoder = false,
}) {
  return {
    'type': 'capabilities',
    'audio': {
      'protocols': [legacyAudioMode, if (opusDecoder) svgV2AudioMode],
      'supportsOpusDecoder': opusDecoder,
      'secureContext': true,
      'decoder': {
        'nativeOpus': opusDecoder,
        'opusWasm': false,
        'webCodecs': false,
      },
      'micFormats': [if (opusEncoder) 'opus', 'pcm16le'],
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

bool isOpusMicrophoneRequired(String message) => const {
  'opus microphone audio required',
  'opus microphone audio required.',
  'opus microphone audio is required',
  'opus microphone audio is required.',
  'this server requires opus microphone audio. use an opus-capable client.',
}.contains(message.trim().toLowerCase());

bool isFatalServerError(Map<String, Object?> packet) {
  if (packet['fatal'] == true) return true;
  if (controlPacketType(packet) != 'error') return false;
  final message = controlPacketMessage(packet).toLowerCase();
  return const [
    'bedrock player to join',
    'use /svg pswd',
    'access denied:',
    'timeout',
    'left the game.',
  ].any(message.contains);
}

bool isConnectedStatusPacket(Map<String, Object?> packet) {
  return controlPacketType(packet) == 'status' &&
      controlPacketMessage(packet).toLowerCase().contains('connected as');
}

bool isTransferStatusPacket(Map<String, Object?> packet) {
  return controlPacketType(packet) == 'status' &&
      controlPacketMessage(packet).trim() == 'Changing server';
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
