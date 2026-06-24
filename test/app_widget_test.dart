import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_voice_app/main.dart';
import 'package:simple_voice_app/src/audio/audio_bridge.dart';
import 'package:simple_voice_app/src/notification/call_notification_bridge.dart';
import 'package:simple_voice_app/src/protocol/simple_voice_client.dart';

void main() {
  testWidgets('join screen shows server and credential controls', (tester) async {
    await tester.pumpWidget(const SimpleVoiceApp(showOpeningSplash: false));

    expect(find.text('Simple Voice App'), findsOneWidget);
    expect(find.byKey(const Key('serverUrlField')), findsOneWidget);
    expect(find.byKey(const Key('usernameField')), findsOneWidget);
    expect(find.byKey(const Key('passwordField')), findsOneWidget);
    expect(find.byKey(const Key('passwordVisibilityButton')), findsOneWidget);
    expect(find.byKey(const Key('joinButton')), findsOneWidget);
    expect(find.byKey(const Key('joinSpeakerToggleButton')), findsOneWidget);
    expect(find.text('idle'), findsNothing);
  });

  testWidgets('password eye toggles password visibility', (tester) async {
    await tester.pumpWidget(const SimpleVoiceApp(showOpeningSplash: false));

    var passwordField = tester.widget<TextField>(
      find.byKey(const Key('passwordField')),
    );
    expect(passwordField.obscureText, isTrue);
    expect(find.byTooltip('Show password'), findsOneWidget);

    await tester.tap(find.byKey(const Key('passwordVisibilityButton')));
    await tester.pumpAndSettle();

    passwordField = tester.widget<TextField>(
      find.byKey(const Key('passwordField')),
    );
    expect(passwordField.obscureText, isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  testWidgets('joined shell switches between voice and chat tabs', (tester) async {
    await tester.pumpWidget(SimpleVoiceApp(
      initiallyConnected: true,
      audioBridge: _FakeAudioBridge(),
      showOpeningSplash: false,
    ));

    expect(find.text('Voice'), findsWidgets);
    expect(find.text('Microphone'), findsOneWidget);

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chatInput')), findsOneWidget);
  });

  testWidgets('ptt overlay changes state while pressed', (tester) async {
    await tester.pumpWidget(SimpleVoiceApp(
      initiallyConnected: true,
      audioBridge: _FakeAudioBridge(),
      showOpeningSplash: false,
    ));

    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('openMicSwitch')))
          .value,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('openPttButton')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('openMicSwitch')))
          .value,
      isFalse,
    );
    expect(find.text('Your mic is off'), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('pttHoldZone'))),
    );
    await tester.pump();
    expect(find.text('You are talking'), findsOneWidget);

    await gesture.up();
    await tester.pump();
    expect(find.text('Your mic is off'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('openMicSwitch')))
          .value,
      isTrue,
    );
  });

  testWidgets('ptt overlay restores push to talk mode after closing',
      (tester) async {
    await tester.pumpWidget(SimpleVoiceApp(
      initiallyConnected: true,
      audioBridge: _FakeAudioBridge(),
      showOpeningSplash: false,
    ));

    await tester.tap(find.byKey(const Key('openMicSwitch')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('openMicSwitch')))
          .value,
      isFalse,
    );

    await tester.tap(find.byKey(const Key('openPttButton')));
    await tester.pumpAndSettle();
    expect(find.text('Your mic is off'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('openMicSwitch')))
          .value,
      isFalse,
    );
  });

  testWidgets('diagnostics hides secrets', (tester) async {
    final audio = _FakeAudioBridge(
      audioDebugInfo: 'Audio Devtools\nNative audio mode: normal',
    );
    await tester.pumpWidget(SimpleVoiceApp(
      initiallyConnected: true,
      audioBridge: audio,
      showOpeningSplash: false,
    ));

    await tester.tap(find.byKey(const Key('diagnosticsButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('password'), findsNothing);
    expect(find.textContaining('WebSocket'), findsOneWidget);
    expect(find.textContaining('wss://voice.example.com/ws'), findsOneWidget);
    expect(find.textContaining('Audio Devtools'), findsOneWidget);
    expect(find.textContaining('Native audio mode: normal'), findsOneWidget);
    expect(find.textContaining('Build'), findsNothing);
  });

  testWidgets('invalid server url shows user-facing connection error',
      (tester) async {
    await tester.pumpWidget(const SimpleVoiceApp(showOpeningSplash: false));

    await tester.enterText(
      find.byKey(const Key('serverUrlField')),
      'ftp://host',
    );
    await tester.enterText(find.byKey(const Key('usernameField')), 'PlayerName');
    await tester.enterText(find.byKey(const Key('passwordField')), 'secret');
    final joinButton = find.byKey(const Key('joinButton'));
    await tester.ensureVisible(joinButton);
    await tester.pump();
    await tester.tap(joinButton);
    await tester.pump();

    expect(find.text('Use an http or https server address.'), findsOneWidget);
  });

  testWidgets('minecraft port warning appears below server field and clears',
      (tester) async {
    await tester.pumpWidget(const SimpleVoiceApp(showOpeningSplash: false));

    await tester.enterText(
      find.byKey(const Key('serverUrlField')),
      '192.168.1.64:25565',
    );
    await tester.pump();

    expect(find.byKey(const Key('minecraftPortWarning')), findsOneWidget);
    expect(
      find.text(
        'That looks like the minecraft server port. Use the '
        'SimpleVoice-Geyser port instead.',
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('serverUrlField')),
      '192.168.1.64:8080',
    );
    await tester.pump();

    expect(find.byKey(const Key('minecraftPortWarning')), findsNothing);
  });

  testWidgets('minecraft port join is blocked without snackbar',
      (tester) async {
    await tester.pumpWidget(const SimpleVoiceApp(showOpeningSplash: false));

    await tester.enterText(
      find.byKey(const Key('serverUrlField')),
      '192.168.1.64:25565',
    );
    final joinButton = find.byKey(const Key('joinButton'));
    await tester.ensureVisible(joinButton);
    await tester.pump();
    await tester.tap(joinButton);
    await tester.pump();

    expect(find.byKey(const Key('minecraftPortWarning')), findsOneWidget);
    expect(
      find.text('Enter the server, username, and password to join.'),
      findsNothing,
    );
  });

  testWidgets('empty join fields show inline validation errors',
      (tester) async {
    await tester.pumpWidget(const SimpleVoiceApp(showOpeningSplash: false));

    final joinButton = find.byKey(const Key('joinButton'));
    await tester.ensureVisible(joinButton);
    await tester.pump();
    await tester.tap(joinButton);
    await tester.pump();

    expect(find.text('Please provide a valid server address'), findsOneWidget);
    expect(find.text('Please enter a valid username'), findsOneWidget);
    expect(find.text('Please enter your password'), findsOneWidget);
    expect(
      find.text('Enter the server, username, and password to join.'),
      findsNothing,
    );
    expect(find.text('fatalError'), findsNothing);
  });

  testWidgets('empty join field validates on blur and clears while typing',
      (tester) async {
    await tester.pumpWidget(const SimpleVoiceApp(showOpeningSplash: false));

    await tester.tap(find.byKey(const Key('serverUrlField')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('usernameField')));
    await tester.pump();

    expect(find.text('Please provide a valid server address'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('serverUrlField')),
      'voice.example.com',
    );
    await tester.pump();

    expect(find.text('Please provide a valid server address'), findsNothing);
  });

  testWidgets('connected status opens joined shell and sends capabilities',
      (tester) async {
    final audio = _FakeAudioBridge();
    final notification = _FakeCallNotificationBridge();
    final client = _FakeSimpleVoiceClient(
      controlPacket: {
        'type': ' STATUS ',
        'message': 'Connected as PlayerName.',
      },
    );
    await tester.pumpWidget(SimpleVoiceApp(
      audioBridge: audio,
      notificationBridge: notification,
      clientFactory: (_) => client,
      showOpeningSplash: false,
    ));

    await tester.enterText(
      find.byKey(const Key('serverUrlField')),
      'http://192.168.1.64:24455',
    );
    await tester.enterText(find.byKey(const Key('usernameField')), 'PlayerName');
    await tester.enterText(find.byKey(const Key('passwordField')), 'secret');
    await _tapVisible(tester, find.byKey(const Key('joinButton')));

    expect(find.text('Currently in voicechat'), findsOneWidget);
    expect(find.text('Connecting'), findsNothing);
    expect(client.capabilitiesSent, 1);
    expect(notification.permissionRequests, 1);
    expect(notification.starts, hasLength(1));
    expect(notification.starts.last['server'], 'http://192.168.1.64:24455');

    audio.emit(Uint8List(1920));
    await tester.pump();

    expect(client.micPackets, hasLength(1));
  });

  testWidgets('notification actions control call state and chat',
      (tester) async {
    final audio = _FakeAudioBridge();
    final notification = _FakeCallNotificationBridge();
    final client = _FakeSimpleVoiceClient(
      controlPacket: {
        'type': 'status',
        'message': 'Connected as PlayerName.',
      },
    );
    await tester.pumpWidget(SimpleVoiceApp(
      audioBridge: audio,
      notificationBridge: notification,
      clientFactory: (_) => client,
      showOpeningSplash: false,
    ));

    await tester.enterText(
      find.byKey(const Key('serverUrlField')),
      'http://192.168.1.64:24455',
    );
    await tester.enterText(find.byKey(const Key('usernameField')), 'PlayerName');
    await tester.enterText(find.byKey(const Key('passwordField')), 'secret');
    await _tapVisible(tester, find.byKey(const Key('joinButton')));

    notification.emit(const CallNotificationAction('mute'));
    await tester.pumpAndSettle();
    expect(audio.state.micRunning, isFalse);
    expect(notification.updates.last['muted'], isTrue);

    notification.emit(const CallNotificationAction('speaker'));
    await tester.pumpAndSettle();
    expect(audio.speakerphoneCalls, contains(true));
    expect(notification.updates.last['speaker'], isTrue);

    notification.emit(const CallNotificationAction('reply', message: ' hello '));
    await tester.pumpAndSettle();
    expect(client.chatMessages, ['hello']);
    expect(notification.updates.last['transientStatus'], 'Message sent');

    notification.emit(const CallNotificationAction('reply', message: '   '));
    await tester.pumpAndSettle();
    expect(client.chatMessages, ['hello']);

    notification.emit(const CallNotificationAction('hangUp'));
    await _pumpUntil(
      tester,
      () => client.disconnected && notification.stops > 0,
    );
    expect(client.disconnected, isTrue);
    expect(notification.stops, greaterThan(0));
  });

  testWidgets('notification unmute sends while app mode is push to talk',
      (tester) async {
    final audio = _FakeAudioBridge();
    final notification = _FakeCallNotificationBridge();
    final client = _FakeSimpleVoiceClient(
      controlPacket: {
        'type': 'status',
        'message': 'Connected as PlayerName.',
      },
    );
    await tester.pumpWidget(SimpleVoiceApp(
      audioBridge: audio,
      notificationBridge: notification,
      clientFactory: (_) => client,
      showOpeningSplash: false,
    ));

    await tester.enterText(
      find.byKey(const Key('serverUrlField')),
      'http://192.168.1.64:24455',
    );
    await tester.enterText(find.byKey(const Key('usernameField')), 'PlayerName');
    await tester.enterText(find.byKey(const Key('passwordField')), 'secret');
    await _tapVisible(tester, find.byKey(const Key('joinButton')));

    await tester.tap(find.byKey(const Key('openMicSwitch')));
    await tester.pumpAndSettle();

    audio.emit(Uint8List(1920));
    await tester.pump();
    expect(client.micPackets, isEmpty);

    notification.emit(const CallNotificationAction('unmute'));
    await tester.pumpAndSettle();
    audio.emit(Uint8List(1920));
    await tester.pump();
    expect(client.micPackets, hasLength(1));

    notification.emit(const CallNotificationAction('mute'));
    await tester.pumpAndSettle();
    audio.emit(Uint8List(1920));
    await tester.pump();
    expect(client.micPackets, hasLength(1));
  });

  testWidgets('ptt overlay sends while held from muted state', (tester) async {
    final audio = _FakeAudioBridge();
    final notification = _FakeCallNotificationBridge();
    final client = _FakeSimpleVoiceClient(
      controlPacket: {
        'type': 'status',
        'message': 'Connected as PlayerName.',
      },
    );
    await tester.pumpWidget(SimpleVoiceApp(
      audioBridge: audio,
      notificationBridge: notification,
      clientFactory: (_) => client,
      showOpeningSplash: false,
    ));

    await tester.enterText(
      find.byKey(const Key('serverUrlField')),
      'http://192.168.1.64:24455',
    );
    await tester.enterText(find.byKey(const Key('usernameField')), 'PlayerName');
    await tester.enterText(find.byKey(const Key('passwordField')), 'secret');
    await _tapVisible(tester, find.byKey(const Key('joinButton')));

    final micSwitch = find.widgetWithText(SwitchListTile, 'Microphone');
    await tester.tap(micSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(micSwitch).value, isFalse);
    expect(audio.state.micRunning, isFalse);

    await tester.tap(find.byKey(const Key('openPttButton')));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('pttHoldZone'))),
    );
    await tester.pump();

    audio.emit(Uint8List(1920));
    await tester.pump();
    expect(client.micPackets, hasLength(1));

    await gesture.up();
    await tester.pump();
    audio.emit(Uint8List(1920));
    await tester.pump();
    expect(client.micPackets, hasLength(1));

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(micSwitch).value, isFalse);
    expect(audio.state.micRunning, isFalse);
  });

  testWidgets('join confirmation timeout returns to join screen',
      (tester) async {
    final client = _FakeSimpleVoiceClient();
    await tester.pumpWidget(SimpleVoiceApp(
      audioBridge: _FakeAudioBridge(),
      clientFactory: (_) => client,
      showOpeningSplash: false,
    ));

    await tester.enterText(
      find.byKey(const Key('serverUrlField')),
      'http://192.168.1.64:24455',
    );
    await tester.enterText(find.byKey(const Key('usernameField')), 'PlayerName');
    await tester.enterText(find.byKey(const Key('passwordField')), 'secret');
    final joinButton = find.byKey(const Key('joinButton'));
    await tester.ensureVisible(joinButton);
    await tester.pump();
    await tester.tap(joinButton);
    await tester.pump();

    expect(find.text('Connecting'), findsOneWidget);

    await tester.pump(const Duration(seconds: 9));

    expect(find.text('Join'), findsOneWidget);
    expect(client.disconnected, isTrue);
    expect(
      find.text(
        'Connected to the server, but the app did not receive the login '
        'confirmation. Please try again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('server auth error clears connecting state', (tester) async {
    final client = _FakeSimpleVoiceClient(
      controlPacket: {
        'type': 'ERROR',
        'message': 'Authentication failed: bad password.',
      },
    );
    await tester.pumpWidget(SimpleVoiceApp(
      audioBridge: _FakeAudioBridge(),
      clientFactory: (_) => client,
      showOpeningSplash: false,
    ));

    await tester.enterText(
      find.byKey(const Key('serverUrlField')),
      'http://192.168.1.64:24455',
    );
    await tester.enterText(find.byKey(const Key('usernameField')), 'PlayerName');
    await tester.enterText(find.byKey(const Key('passwordField')), 'wrong');
    final joinButton = find.byKey(const Key('joinButton'));
    await tester.ensureVisible(joinButton);
    await tester.pump();
    await tester.tap(joinButton);
    await tester.pump();

    expect(find.text('Join'), findsOneWidget);
    expect(find.text('Connecting'), findsNothing);
    expect(
      find.text(
        'The server rejected the login. Check the username and password.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('speaker icon updates audio route from voice tab', (tester) async {
    final audio = _FakeAudioBridge();
    await tester.pumpWidget(SimpleVoiceApp(
      initiallyConnected: true,
      audioBridge: audio,
      showOpeningSplash: false,
    ));

    final speakerButton = find.byKey(const Key('voiceSpeakerToggleButton'));
    expect(speakerButton, findsOneWidget);
    expect(
      find.text('Playback: Audio playback off | Phone earpiece'),
      findsOneWidget,
    );
    expect(tester.widget<IconButton>(speakerButton).isSelected, isFalse);

    await tester.tap(speakerButton);
    await tester.pumpAndSettle();

    expect(audio.speakerphoneCalls, [true]);
    expect(find.text('Playback: Audio playback off | Speaker'), findsOneWidget);
    expect(tester.widget<IconButton>(speakerButton).isSelected, isTrue);

    await tester.tap(find.byTooltip('Leave'));
    await _pumpUntil(
      tester,
      () => audio.state.speakerphoneEnabled == false,
    );

    expect(audio.state.speakerphoneEnabled, isFalse);
    expect(audio.state.audioRoute, 'normal');
  });

  testWidgets('speaker icon is available with test audio', (tester) async {
    final audio = _FakeAudioBridge();
    await tester.pumpWidget(SimpleVoiceApp(
      audioBridge: audio,
      showOpeningSplash: false,
    ));

    final speakerButton = find.byKey(const Key('joinSpeakerToggleButton'));
    expect(speakerButton, findsOneWidget);

    await _tapVisible(tester, speakerButton);

    expect(audio.speakerphoneCalls, [true]);
    expect(tester.widget<IconButton>(speakerButton).isSelected, isTrue);
  });

  testWidgets('test audio starts local mic monitor and stops cleanly',
      (tester) async {
    final audio = _FakeAudioBridge();
    await tester.pumpWidget(SimpleVoiceApp(
      audioBridge: audio,
      showOpeningSplash: false,
    ));

    await _tapVisible(tester, find.byKey(const Key('testAudioButton')));

    expect(find.text('Stop audio test'), findsOneWidget);
    expect(audio.state.micRunning, isTrue);
    expect(audio.state.playbackRunning, isTrue);

    audio.emit(Uint8List(1920));
    await _pumpUntilFound(
      tester,
      find.text('Audio test is playing your microphone back.'),
    );

    expect(
      find.text('Audio test is playing your microphone back.'),
      findsOneWidget,
    );
    expect(audio.playedPackets, 1);

    await _tapVisible(tester, find.byKey(const Key('testAudioButton')));

    expect(find.text('Test audio'), findsOneWidget);
    expect(audio.state.micRunning, isFalse);
    expect(audio.state.playbackRunning, isFalse);
  });

  testWidgets('denied mic permission shows human audio message', (tester) async {
    final audio = _FakeAudioBridge(permissionGranted: false);
    await tester.pumpWidget(SimpleVoiceApp(
      audioBridge: audio,
      showOpeningSplash: false,
    ));

    await _tapVisible(tester, find.byKey(const Key('testAudioButton')));

    await _pumpUntilFound(
      tester,
      find.textContaining('Microphone permission was denied'),
    );
    expect(find.text('degraded'), findsNothing);
    expect(
      find.textContaining('Microphone permission was denied'),
      findsWidgets,
    );
    expect(audio.state.micPermissionGranted, isFalse);
  });

  testWidgets('opening splash appears before join screen', (tester) async {
    await tester.pumpWidget(const SimpleVoiceApp());

    expect(find.text('Simple Voice App'), findsOneWidget);
    expect(find.byKey(const Key('serverUrlField')), findsNothing);

    await tester.pump(const Duration(milliseconds: 2100));

    expect(find.byKey(const Key('serverUrlField')), findsOneWidget);
  });
}

class _FakeSimpleVoiceClient extends SimpleVoiceClient {
  _FakeSimpleVoiceClient({this.controlPacket})
      : super(Uri.parse('ws://voice.example.com/ws'));

  final Map<String, Object?>? controlPacket;
  var capabilitiesSent = 0;
  var disconnected = false;
  final micPackets = <Uint8List>[];
  final chatMessages = <String>[];

  @override
  Future<void> connect({
    required String username,
    required String password,
    required void Function(Map<String, Object?> packet) onControlPacket,
    required void Function(Uint8List bytes) onAudioFrame,
    required void Function(int? code, String reason) onClosed,
  }) async {
    final packet = controlPacket;
    if (packet != null) {
      onControlPacket(packet);
    }
  }

  @override
  void sendCapabilities() {
    capabilitiesSent++;
  }

  @override
  void sendMicPacket(Uint8List packet) {
    micPackets.add(packet);
  }

  @override
  void sendChat(String message) {
    chatMessages.add(message);
  }

  @override
  Future<void> disconnect() async {
    disconnected = true;
  }
}

class _FakeCallNotificationBridge implements CallNotificationBridge {
  final _controller = StreamController<CallNotificationAction>.broadcast(
    sync: true,
  );
  final starts = <Map<String, Object?>>[];
  final updates = <Map<String, Object?>>[];
  var stops = 0;
  var permissionRequests = 0;

  void emit(CallNotificationAction action) => _controller.add(action);

  @override
  Stream<CallNotificationAction> get actions => _controller.stream;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> start({
    required String server,
    required String status,
    required bool muted,
    required bool speaker,
    String transientStatus = '',
  }) async {
    starts.add(_payload(
      server: server,
      status: status,
      muted: muted,
      speaker: speaker,
      transientStatus: transientStatus,
    ));
  }

  @override
  Future<void> update({
    required String server,
    required String status,
    required bool muted,
    required bool speaker,
    String transientStatus = '',
  }) async {
    updates.add(_payload(
      server: server,
      status: status,
      muted: muted,
      speaker: speaker,
      transientStatus: transientStatus,
    ));
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  Map<String, Object?> _payload({
    required String server,
    required String status,
    required bool muted,
    required bool speaker,
    required String transientStatus,
  }) {
    return {
      'server': server,
      'status': status,
      'muted': muted,
      'speaker': speaker,
      'transientStatus': transientStatus,
    };
  }
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (finder.evaluate().isNotEmpty) return;
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 50; i++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (condition()) return;
  }
}

class _FakeAudioBridge implements AudioBridge {
  _FakeAudioBridge({
    this.permissionGranted = true,
    String audioDebugInfo = '',
  }) : _state = AudioBridgeState(audioDebugInfo: audioDebugInfo);

  final bool permissionGranted;
  final _controller = StreamController<Uint8List>.broadcast();
  AudioBridgeState _state;
  var playedPackets = 0;
  final speakerphoneCalls = <bool>[];

  void emit(Uint8List packet) => _controller.add(packet);

  @override
  Stream<Uint8List> get micPackets => _controller.stream;

  @override
  AudioBridgeState get state => _state;

  @override
  Future<void> playPcm16(Uint8List bytes, {required int channels}) async {
    playedPackets++;
  }

  @override
  Future<String> refreshAudioRoute() async => _state.audioRoute;

  @override
  Future<String> refreshAudioDebugInfo() async => _state.audioDebugInfo;

  @override
  Future<bool> requestMicPermission() async {
    _state = _state.copyWith(
      micPermissionGranted: permissionGranted,
      lastError: permissionGranted ? '' : 'Microphone permission denied.',
    );
    return permissionGranted;
  }

  @override
  Future<void> resetAudio() async {
    _state = const AudioBridgeState();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  @override
  Future<bool> setSpeakerphone(bool enabled) async {
    speakerphoneCalls.add(enabled);
    _state = _state.copyWith(
      speakerphoneEnabled: enabled,
      audioRoute: enabled ? 'speaker' : 'normal',
    );
    return true;
  }

  @override
  Future<bool> startMic() async {
    _state = _state.copyWith(micRunning: permissionGranted);
    return permissionGranted;
  }

  @override
  Future<bool> startPlayback() async {
    _state = _state.copyWith(playbackRunning: true);
    return true;
  }

  @override
  Future<void> stopMic() async {
    _state = _state.copyWith(micRunning: false);
  }

  @override
  Future<void> stopPlayback() async {
    _state = _state.copyWith(playbackRunning: false);
  }
}
