enum AppConnectionState {
  idle,
  connecting,
  authenticated,
  connected,
  degraded,
  fatalError,
  disconnected,
}

class DiagnosticsSnapshot {
  const DiagnosticsSnapshot({
    this.serverUrl = '',
    this.websocketUrl = '',
    this.state = AppConnectionState.idle,
    this.lastCloseCode,
    this.lastCloseReason = '',
    this.selectedAudioMode = 'legacy',
    this.decoderStatus = 'not enabled',
    this.malformedFrames = 0,
    this.receivedLegacyFrames = 0,
    this.receivedSvgV2Frames = 0,
    this.unsupportedOpusFrames = 0,
    this.micPacketsSent = 0,
    this.micPermissionGranted = false,
    this.micRunning = false,
    this.playbackRunning = false,
    this.speakerphoneEnabled = false,
    this.audioRoute = 'normal',
    this.audioDebugInfo = '',
    this.lastReceivedPcmChannels = 0,
    this.lastReceivedPcmPeak = 0,
    this.audioError = '',
    this.chatSent = 0,
    this.chatReceived = 0,
  });

  final String serverUrl;
  final String websocketUrl;
  final AppConnectionState state;
  final int? lastCloseCode;
  final String lastCloseReason;
  final String selectedAudioMode;
  final String decoderStatus;
  final int malformedFrames;
  final int receivedLegacyFrames;
  final int receivedSvgV2Frames;
  final int unsupportedOpusFrames;
  final int micPacketsSent;
  final bool micPermissionGranted;
  final bool micRunning;
  final bool playbackRunning;
  final bool speakerphoneEnabled;
  final String audioRoute;
  final String audioDebugInfo;
  final int lastReceivedPcmChannels;
  final int lastReceivedPcmPeak;
  final String audioError;
  final int chatSent;
  final int chatReceived;

  DiagnosticsSnapshot copyWith({
    String? serverUrl,
    String? websocketUrl,
    AppConnectionState? state,
    int? lastCloseCode,
    String? lastCloseReason,
    String? selectedAudioMode,
    String? decoderStatus,
    int? malformedFrames,
    int? receivedLegacyFrames,
    int? receivedSvgV2Frames,
    int? unsupportedOpusFrames,
    int? micPacketsSent,
    bool? micPermissionGranted,
    bool? micRunning,
    bool? playbackRunning,
    bool? speakerphoneEnabled,
    String? audioRoute,
    String? audioDebugInfo,
    int? lastReceivedPcmChannels,
    int? lastReceivedPcmPeak,
    String? audioError,
    int? chatSent,
    int? chatReceived,
  }) {
    return DiagnosticsSnapshot(
      serverUrl: serverUrl ?? this.serverUrl,
      websocketUrl: websocketUrl ?? this.websocketUrl,
      state: state ?? this.state,
      lastCloseCode: lastCloseCode ?? this.lastCloseCode,
      lastCloseReason: lastCloseReason ?? this.lastCloseReason,
      selectedAudioMode: selectedAudioMode ?? this.selectedAudioMode,
      decoderStatus: decoderStatus ?? this.decoderStatus,
      malformedFrames: malformedFrames ?? this.malformedFrames,
      receivedLegacyFrames: receivedLegacyFrames ?? this.receivedLegacyFrames,
      receivedSvgV2Frames: receivedSvgV2Frames ?? this.receivedSvgV2Frames,
      unsupportedOpusFrames:
          unsupportedOpusFrames ?? this.unsupportedOpusFrames,
      micPacketsSent: micPacketsSent ?? this.micPacketsSent,
      micPermissionGranted:
          micPermissionGranted ?? this.micPermissionGranted,
      micRunning: micRunning ?? this.micRunning,
      playbackRunning: playbackRunning ?? this.playbackRunning,
      speakerphoneEnabled:
          speakerphoneEnabled ?? this.speakerphoneEnabled,
      audioRoute: audioRoute ?? this.audioRoute,
      audioDebugInfo: audioDebugInfo ?? this.audioDebugInfo,
      lastReceivedPcmChannels:
          lastReceivedPcmChannels ?? this.lastReceivedPcmChannels,
      lastReceivedPcmPeak: lastReceivedPcmPeak ?? this.lastReceivedPcmPeak,
      audioError: audioError ?? this.audioError,
      chatSent: chatSent ?? this.chatSent,
      chatReceived: chatReceived ?? this.chatReceived,
    );
  }

  String redactedText() {
    return [
      'Server: ${serverUrl.isEmpty ? 'not set' : serverUrl}',
      'WebSocket: ${websocketUrl.isEmpty ? 'not connected' : websocketUrl}',
      'State: ${state.name}',
      'Last close: ${lastCloseCode ?? 'none'} $lastCloseReason'.trim(),
      'Audio: $selectedAudioMode',
      'Decoder: $decoderStatus',
      'Malformed frames: $malformedFrames',
      'Legacy frames: $receivedLegacyFrames',
      'svg-v2 frames: $receivedSvgV2Frames',
      'Unsupported Opus frames: $unsupportedOpusFrames',
      'Mic packets sent: $micPacketsSent',
      'Mic permission: ${micPermissionGranted ? 'granted' : 'not granted'}',
      'Mic running: $micRunning',
      'Playback running: $playbackRunning',
      'Speakerphone: $speakerphoneEnabled',
      'Audio route: $audioRoute',
      if (audioDebugInfo.isNotEmpty) audioDebugInfo,
      'Last received PCM channels: $lastReceivedPcmChannels',
      'Last received PCM peak: $lastReceivedPcmPeak',
      'Audio error: ${audioError.isEmpty ? 'none' : audioError}',
      'Chat sent: $chatSent',
      'Chat received: $chatReceived',
    ].join('\n');
  }
}
