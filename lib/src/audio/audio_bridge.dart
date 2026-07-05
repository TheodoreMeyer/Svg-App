import 'dart:async';

import 'package:flutter/services.dart';

class AudioBridgeState {
  const AudioBridgeState({
    this.micPermissionGranted = false,
    this.micRunning = false,
    this.playbackRunning = false,
    this.speakerphoneEnabled = false,
    this.audioRoute = 'normal',
    this.audioDebugInfo = '',
    this.lastError = '',
  });

  final bool micPermissionGranted;
  final bool micRunning;
  final bool playbackRunning;
  final bool speakerphoneEnabled;
  final String audioRoute;
  final String audioDebugInfo;
  final String lastError;

  AudioBridgeState copyWith({
    bool? micPermissionGranted,
    bool? micRunning,
    bool? playbackRunning,
    bool? speakerphoneEnabled,
    String? audioRoute,
    String? audioDebugInfo,
    String? lastError,
  }) {
    return AudioBridgeState(
      micPermissionGranted: micPermissionGranted ?? this.micPermissionGranted,
      micRunning: micRunning ?? this.micRunning,
      playbackRunning: playbackRunning ?? this.playbackRunning,
      speakerphoneEnabled: speakerphoneEnabled ?? this.speakerphoneEnabled,
      audioRoute: audioRoute ?? this.audioRoute,
      audioDebugInfo: audioDebugInfo ?? this.audioDebugInfo,
      lastError: lastError ?? this.lastError,
    );
  }
}

abstract interface class AudioBridge {
  Stream<Uint8List> get micPackets;
  AudioBridgeState get state;

  Future<bool> requestMicPermission();
  Future<bool> startMic();
  Future<void> stopMic();
  Future<bool> startPlayback();
  Future<void> stopPlayback();
  Future<void> playPcm16(Uint8List bytes, {required int channels});
  Future<bool> setSpeakerphone(bool enabled);
  Future<String> refreshAudioRoute();
  Future<String> refreshAudioDebugInfo();
  Future<void> resetAudio();
}

class NativeAudioBridge implements AudioBridge {
  NativeAudioBridge({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel = methodChannel ??
            const MethodChannel('simple_voice_app/audio'),
        _eventChannel = eventChannel ??
            const EventChannel('simple_voice_app/mic');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  AudioBridgeState _state = const AudioBridgeState();
  Stream<Uint8List>? _micPackets;

  @override
  AudioBridgeState get state => _state;

  @override
  Stream<Uint8List> get micPackets {
    return _micPackets ??= _eventChannel.receiveBroadcastStream().map((event) {
      if (event is Uint8List) return event;
      if (event is ByteData) return event.buffer.asUint8List();
      if (event is List<int>) return Uint8List.fromList(event);
      throw StateError('Unsupported native mic packet type.');
    });
  }

  @override
  Future<bool> requestMicPermission() async {
    return _boolCall(
      'requestMicPermission',
      onSuccess: (granted) => _state = _state.copyWith(
        micPermissionGranted: granted,
        lastError: granted ? '' : 'Microphone permission denied.',
      ),
    );
  }

  @override
  Future<bool> startMic() async {
    return _boolCall(
      'startMic',
      onSuccess: (started) => _state = _state.copyWith(
        micRunning: started,
        lastError: started ? '' : 'Microphone capture failed to start.',
      ),
    );
  }

  @override
  Future<void> stopMic() async {
    await _voidCall('stopMic');
    _state = _state.copyWith(micRunning: false);
  }

  @override
  Future<bool> startPlayback() async {
    final started = await _boolCall(
      'startPlayback',
      onSuccess: (started) => _state = _state.copyWith(
        playbackRunning: started,
        lastError: started ? '' : 'PCM playback failed to start.',
      ),
    );
    if (started) {
      await refreshAudioRoute();
      await refreshAudioDebugInfo();
    }
    return started;
  }

  @override
  Future<void> stopPlayback() async {
    await _voidCall('stopPlayback');
    _state = _state.copyWith(playbackRunning: false);
  }

  @override
  Future<void> playPcm16(Uint8List bytes, {required int channels}) async {
    if (bytes.isEmpty) return;
    final safeChannels = channels == 2 ? 2 : 1;
    await _voidCall('playPcm16', {
      'bytes': bytes,
      'channels': safeChannels,
    });
  }

  @override
  Future<bool> setSpeakerphone(bool enabled) async {
    final applied = await _boolCall(
      'setSpeakerphone',
      arguments: enabled,
      onSuccess: (result) => _state = _state.copyWith(
        speakerphoneEnabled: result && enabled,
        audioRoute: result ? (enabled ? 'speaker' : 'normal') : 'unavailable',
        lastError: result ? '' : 'Audio route unavailable.',
      ),
    );
    await refreshAudioRoute();
    await refreshAudioDebugInfo();
    return applied;
  }

  @override
  Future<String> refreshAudioRoute() async {
    final route = await _stringCall('getAudioRoute');
    _state = _state.copyWith(
      audioRoute: route,
      speakerphoneEnabled: route == 'speaker',
    );
    return route;
  }

  @override
  Future<String> refreshAudioDebugInfo() async {
    final info = await _stringCall('getAudioDebugInfo');
    _state = _state.copyWith(audioDebugInfo: info);
    return info;
  }

  @override
  Future<void> resetAudio() async {
    await _voidCall('resetAudio');
    _state = const AudioBridgeState();
  }

  Future<bool> _boolCall(
    String method, {
    Object? arguments,
    required void Function(bool result) onSuccess,
  }) async {
    try {
      final result =
          await _methodChannel.invokeMethod<bool>(method, arguments) ?? false;
      onSuccess(result);
      return result;
    } on MissingPluginException catch (error) {
      _state = _state.copyWith(lastError: error.message ?? error.toString());
      return false;
    } on PlatformException catch (error) {
      _state = _state.copyWith(lastError: error.message ?? error.code);
      return false;
    }
  }

  Future<String> _stringCall(String method, [Object? arguments]) async {
    try {
      return await _methodChannel.invokeMethod<String>(method, arguments) ??
          'unavailable';
    } on MissingPluginException catch (error) {
      _state = _state.copyWith(lastError: error.message ?? error.toString());
      return _state.audioRoute;
    } on PlatformException catch (error) {
      _state = _state.copyWith(lastError: error.message ?? error.code);
      return 'unavailable';
    }
  }

  Future<void> _voidCall(String method, [Object? arguments]) async {
    try {
      await _methodChannel.invokeMethod<void>(method, arguments);
    } on MissingPluginException catch (error) {
      _state = _state.copyWith(lastError: error.message ?? error.toString());
    } on PlatformException catch (error) {
      _state = _state.copyWith(lastError: error.message ?? error.code);
    }
  }
}
