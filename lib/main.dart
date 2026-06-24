import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'src/audio/audio_bridge.dart';
import 'src/audio/audio_gate.dart';
import 'src/audio/incoming_audio_handler.dart';
import 'src/diagnostics.dart';
import 'src/notification/call_notification_bridge.dart';
import 'src/protocol/connection_policy.dart';
import 'src/protocol/connection_target.dart';
import 'src/protocol/packets.dart';
import 'src/protocol/simple_voice_client.dart';
import 'src/settings/credential_store.dart';

void main() {
  runApp(const SimpleVoiceApp());
}

typedef SimpleVoiceClientFactory = SimpleVoiceClient Function(Uri uri);

const _joinConfirmationTimeout = Duration(seconds: 8);
const _joinConfirmationTimeoutMessage =
    'Connected to the server, but the app did not receive the login '
    'confirmation. Please try again.';
const _micDiagnosticsBatchSize = 25;
const _serverRequiredMessage = 'Please provide a valid server address';
const _usernameRequiredMessage = 'Please enter a valid username';
const _passwordRequiredMessage = 'Please enter your password';

enum _JoinField { server, username, password }

class SimpleVoiceApp extends StatelessWidget {
  const SimpleVoiceApp({
    super.key,
    this.initiallyConnected = false,
    this.audioBridge,
    this.notificationBridge,
    this.clientFactory,
    this.showOpeningSplash = true,
  });

  final bool initiallyConnected;
  final AudioBridge? audioBridge;
  final CallNotificationBridge? notificationBridge;
  final SimpleVoiceClientFactory? clientFactory;
  final bool showOpeningSplash;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple Voice App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF55C055),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F8F3),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF63A942), width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF55C055),
            foregroundColor: const Color(0xFF102010),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: _OpeningGate(
        showOpeningSplash: showOpeningSplash && !initiallyConnected,
        child: _HomeScreen(
          initiallyConnected: initiallyConnected,
          audioBridge: audioBridge,
          notificationBridge: notificationBridge,
          clientFactory: clientFactory,
        ),
      ),
    );
  }
}

class _OpeningGate extends StatefulWidget {
  const _OpeningGate({
    required this.showOpeningSplash,
    required this.child,
  });

  final bool showOpeningSplash;
  final Widget child;

  @override
  State<_OpeningGate> createState() => _OpeningGateState();
}

class _OpeningGateState extends State<_OpeningGate> {
  late bool _showSplash = widget.showOpeningSplash;

  @override
  Widget build(BuildContext context) {
    if (!_showSplash) return widget.child;
    return _OpeningSplash(
      onFinished: () {
        if (!mounted) return;
        setState(() => _showSplash = false);
      },
    );
  }
}

class _OpeningSplash extends StatefulWidget {
  const _OpeningSplash({required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<_OpeningSplash> createState() => _OpeningSplashState();
}

class _OpeningSplashState extends State<_OpeningSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _iconOpacity;
  late final Animation<Offset> _iconOffset;
  Timer? _startTimer;
  Timer? _finishTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _iconOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.35, curve: Curves.easeOut),
    );
    _iconOffset = Tween<Offset>(
      begin: const Offset(0, 0.55),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    _startTimer = Timer(
      const Duration(milliseconds: 200),
      () => _controller.forward(),
    );
    _finishTimer = Timer(
      const Duration(milliseconds: 2000),
      widget.onFinished,
    );
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _finishTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F3),
      body: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: const Alignment(0, -0.52),
              child: Text(
                'Simple Voice App',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFF1A2413),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Align(
              alignment: const Alignment(0, 0.1),
              child: FadeTransition(
                opacity: _iconOpacity,
                child: SlideTransition(
                  position: _iconOffset,
                  child: Image.asset(
                    'assets/images/icon.png',
                    width: 104,
                    height: 104,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeScreen extends StatefulWidget {
  const _HomeScreen({
    required this.initiallyConnected,
    this.audioBridge,
    this.notificationBridge,
    this.clientFactory,
  });

  final bool initiallyConnected;
  final AudioBridge? audioBridge;
  final CallNotificationBridge? notificationBridge;
  final SimpleVoiceClientFactory? clientFactory;

  @override
  State<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<_HomeScreen> {
  late bool _connected = widget.initiallyConnected;
  bool _muted = false;
  bool _openMic = true;
  bool _pttActive = false;
  bool _notificationOpenMicOverride = false;
  bool _localAudioTest = false;
  bool _localAudioActive = false;
  bool _rememberPassword = false;
  bool _passwordVisible = false;
  bool _busy = false;
  bool _showMinecraftPortWarning = false;
  bool _serverFieldError = false;
  bool _usernameFieldError = false;
  bool _passwordFieldError = false;
  int _tab = 0;
  int _minecraftPortWarningShake = 0;
  int _serverFieldShake = 0;
  int _usernameFieldShake = 0;
  int _passwordFieldShake = 0;
  int _micPacketsSentTotal = 0;
  int _micPacketsSinceDiagnosticsUpdate = 0;
  Timer? _joinConfirmationTimer;
  Timer? _notificationTransientTimer;
  SimpleVoiceClient? _client;
  StreamSubscription<Uint8List>? _micSubscription;
  StreamSubscription<CallNotificationAction>? _notificationSubscription;
  late final AudioBridge _audio = widget.audioBridge ?? NativeAudioBridge();
  late final IncomingAudioHandler _incomingAudio = IncomingAudioHandler(_audio);
  late final CallNotificationBridge _notification =
      widget.notificationBridge ?? NativeCallNotificationBridge();
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _chatController = TextEditingController();
  final _serverFocusNode = FocusNode();
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _store = CredentialStore();
  final List<String> _timeline = [];
  late DiagnosticsSnapshot _diagnostics;

  @override
  void initState() {
    super.initState();
    _diagnostics = DiagnosticsSnapshot(
      serverUrl: 'https://voice.example.com',
      websocketUrl: 'wss://voice.example.com/ws',
      state: widget.initiallyConnected
          ? AppConnectionState.connected
          : AppConnectionState.idle,
    );
    _notificationSubscription = _notification.actions.listen(
      _handleNotificationAction,
      onError: (_) {},
    );
    _serverFocusNode.addListener(
      () => _validateFieldOnBlur(_JoinField.server),
    );
    _usernameFocusNode.addListener(
      () => _validateFieldOnBlur(_JoinField.username),
    );
    _passwordFocusNode.addListener(
      () => _validateFieldOnBlur(_JoinField.password),
    );
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _joinConfirmationTimer?.cancel();
    _notificationTransientTimer?.cancel();
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _chatController.dispose();
    _serverFocusNode.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    unawaited(_micSubscription?.cancel());
    unawaited(_notificationSubscription?.cancel());
    unawaited(_notification.stop());
    unawaited(_audio.resetAudio());
    unawaited(_client?.disconnect());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _connected ? _joinedShell() : _joinScreen();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final saved = await _store.load();
      if (!mounted) return;
      setState(() {
        _serverController.text = saved.serverUrl;
        _usernameController.text = saved.username;
        _passwordController.text = saved.password;
        _rememberPassword = saved.password.isNotEmpty;
        _showMinecraftPortWarning = hasMinecraftServerPort(saved.serverUrl);
      });
    } catch (_) {
      // Secure storage availability varies in tests and early installs.
    }
  }

  void _updateServerPortWarning(String value) {
    _clearRequiredFieldError(_JoinField.server);
    final shouldShow = hasMinecraftServerPort(value);
    if (shouldShow == _showMinecraftPortWarning) return;
    setState(() {
      _showMinecraftPortWarning = shouldShow;
      if (shouldShow) _minecraftPortWarningShake++;
    });
  }

  void _validateFieldOnBlur(_JoinField field) {
    if (_focusNodeFor(field).hasFocus) return;
    if (!_fieldIsEmpty(field)) return;
    _markRequiredFieldError(field);
  }

  void _clearRequiredFieldError(_JoinField field) {
    if (!_hasRequiredFieldError(field) || _fieldIsEmpty(field)) return;
    setState(() => _setRequiredFieldError(field, false));
  }

  bool _validateRequiredJoinFields() {
    final missing = <_JoinField>[
      if (_fieldIsEmpty(_JoinField.server)) _JoinField.server,
      if (_fieldIsEmpty(_JoinField.username)) _JoinField.username,
      if (_fieldIsEmpty(_JoinField.password)) _JoinField.password,
    ];
    if (missing.isEmpty) return true;

    setState(() {
      for (final field in missing) {
        _setRequiredFieldError(field, true);
        _incrementFieldShake(field);
      }
    });
    _focusNodeFor(missing.first).requestFocus();
    return false;
  }

  bool _fieldIsEmpty(_JoinField field) {
    return switch (field) {
      _JoinField.server => _serverController.text.trim().isEmpty,
      _JoinField.username => _usernameController.text.trim().isEmpty,
      _JoinField.password => _passwordController.text.isEmpty,
    };
  }

  FocusNode _focusNodeFor(_JoinField field) {
    return switch (field) {
      _JoinField.server => _serverFocusNode,
      _JoinField.username => _usernameFocusNode,
      _JoinField.password => _passwordFocusNode,
    };
  }

  bool _hasRequiredFieldError(_JoinField field) {
    return switch (field) {
      _JoinField.server => _serverFieldError,
      _JoinField.username => _usernameFieldError,
      _JoinField.password => _passwordFieldError,
    };
  }

  void _setRequiredFieldError(_JoinField field, bool value) {
    switch (field) {
      case _JoinField.server:
        _serverFieldError = value;
        break;
      case _JoinField.username:
        _usernameFieldError = value;
        break;
      case _JoinField.password:
        _passwordFieldError = value;
        break;
    }
  }

  void _markRequiredFieldError(_JoinField field) {
    setState(() {
      _setRequiredFieldError(field, true);
      _incrementFieldShake(field);
    });
  }

  void _incrementFieldShake(_JoinField field) {
    switch (field) {
      case _JoinField.server:
        _serverFieldShake++;
        break;
      case _JoinField.username:
        _usernameFieldShake++;
        break;
      case _JoinField.password:
        _passwordFieldShake++;
        break;
    }
  }

  Widget _shakingField({
    required String shakeKey,
    required int shake,
    required Widget child,
  }) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('$shakeKey:$shake'),
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 180),
      builder: (context, value, child) {
        final offset = math.sin(value * math.pi * 4) * 4;
        return Transform.translate(
          offset: Offset(offset, 0),
          child: child,
        );
      },
      child: child,
    );
  }

  Widget _joinScreen() {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 20),
            Center(
              child: Image.asset(
                'assets/images/icon.png',
                width: 96,
                height: 96,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Simple Voice App',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFF1A2413),
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 28),
            _shakingField(
              shakeKey: 'serverField',
              shake: _serverFieldShake,
              child: TextField(
                key: Key('serverUrlField'),
                controller: _serverController,
                focusNode: _serverFocusNode,
                onChanged: _updateServerPortWarning,
                decoration: InputDecoration(
                  labelText: 'Server',
                  hintText: 'voice.example.com',
                  errorText:
                      _serverFieldError ? _serverRequiredMessage : null,
                ),
                keyboardType: TextInputType.url,
              ),
            ),
            if (_showMinecraftPortWarning) ...[
              const SizedBox(height: 6),
              TweenAnimationBuilder<double>(
                key: ValueKey(_minecraftPortWarningShake),
                tween: Tween(begin: 1, end: 0),
                duration: const Duration(milliseconds: 180),
                builder: (context, value, child) {
                  final offset = math.sin(value * math.pi * 4) * 4;
                  return Transform.translate(
                    offset: Offset(offset, 0),
                    child: child,
                  );
                },
                child: const Text(
                  minecraftServerPortWarning,
                  key: Key('minecraftPortWarning'),
                  style: TextStyle(
                    color: Color(0xFFB3261E),
                    fontSize: 13,
                    height: 1.25,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _shakingField(
              shakeKey: 'usernameField',
              shake: _usernameFieldShake,
              child: TextField(
                key: Key('usernameField'),
                controller: _usernameController,
                focusNode: _usernameFocusNode,
                onChanged: (_) => _clearRequiredFieldError(
                  _JoinField.username,
                ),
                decoration: InputDecoration(
                  labelText: 'Username',
                  errorText:
                      _usernameFieldError ? _usernameRequiredMessage : null,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _shakingField(
              shakeKey: 'passwordField',
              shake: _passwordFieldShake,
              child: TextField(
                key: Key('passwordField'),
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                onChanged: (_) => _clearRequiredFieldError(
                  _JoinField.password,
                ),
                decoration: InputDecoration(
                  labelText: 'Password',
                  errorText:
                      _passwordFieldError ? _passwordRequiredMessage : null,
                  suffixIcon: IconButton(
                    key: const Key('passwordVisibilityButton'),
                    tooltip:
                        _passwordVisible ? 'Hide password' : 'Show password',
                    onPressed: () {
                      setState(() => _passwordVisible = !_passwordVisible);
                    },
                    icon: Icon(
                      _passwordVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                  ),
                ),
                obscureText: !_passwordVisible,
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _rememberPassword,
              onChanged: (value) {
                setState(() => _rememberPassword = value ?? false);
              },
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Remember password'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('joinButton'),
              onPressed: _busy ? null : _connect,
              child: Text(_busy ? 'Connecting' : 'Join'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('testAudioButton'),
              onPressed: _busy ? null : _toggleLocalAudioTest,
              icon: Icon(_localAudioTest ? Icons.stop : Icons.hearing),
              label: Text(_localAudioTest ? 'Stop audio test' : 'Test audio'),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: _speakerToggleButton(
                key: const Key('joinSpeakerToggleButton'),
              ),
            ),
            if (_localAudioTest) ...[
              const SizedBox(height: 8),
              _StatusLine(
                text: _localAudioStatusText(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _joinedShell() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Voice App'),
        actions: [
          IconButton(
            key: const Key('diagnosticsButton'),
            tooltip: 'Diagnostics',
            onPressed: () => unawaited(_showDiagnostics()),
            icon: const Icon(Icons.article_outlined),
          ),
          IconButton(
            tooltip: 'Leave',
            onPressed: _disconnect,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StatusLine(
              text: [
                _connectionStatusText(),
                _diagnostics.selectedAudioMode,
                _micStatusText(),
              ].join(' | '),
            ),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Voice')),
                ButtonSegment(value: 1, label: Text('Chat')),
              ],
              selected: {_tab},
              onSelectionChanged: (value) => setState(() => _tab = value.first),
            ),
            Expanded(child: _tab == 0 ? _voiceTab() : _chatTab()),
          ],
        ),
      ),
    );
  }

  Widget _voiceTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Currently in voicechat',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text('Username ${_displayUsername()}'),
        const SizedBox(height: 8),
        Text('Microphone: ${_micStatusText()}'),
        Text(
          'Playback: ${_playbackStatusText()} | ${_audioRouteText()}',
        ),
        if (_diagnostics.audioError.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _humanReadableAudioError(_diagnostics.audioError),
            style: const TextStyle(color: Color(0xFF8E6308)),
          ),
        ],
        const SizedBox(height: 24),
        SwitchListTile(
          title: const Text('Microphone'),
          subtitle: Text(_muted ? 'Muted' : 'Unmuted'),
          value: !_muted,
          onChanged: _setMicEnabled,
        ),
        SwitchListTile(
          key: const Key('openMicSwitch'),
          title: const Text('Open mic'),
          subtitle: const Text('Disable for push to talk only'),
          value: _openMic,
          onChanged: (value) {
            setState(() {
              _openMic = value;
              _notificationOpenMicOverride = false;
            });
            unawaited(_updateCallNotification());
          },
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: _speakerToggleButton(
            key: const Key('voiceSpeakerToggleButton'),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('openPttButton'),
          onPressed: _showPtt,
          icon: const Icon(Icons.mic),
          label: const Text('Push to talk'),
        ),
      ],
    );
  }

  Widget _chatTab() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                _timeline.isEmpty ? 'Server chat' : _timeline.join('\n'),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('chatInput'),
                  controller: _chatController,
                  decoration: const InputDecoration(hintText: 'Write a message'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _sendChat, child: const Text('Send')),
            ],
          ),
        ),
      ],
    );
  }

  void _showPtt() {
    final previousOpenMic = _openMic;
    final previousMuted = _muted;
    setState(() {
      _openMic = false;
      _muted = false;
      _notificationOpenMicOverride = false;
      _pttActive = false;
    });
    unawaited(_setMicEnabled(true));
    unawaited(_updateCallNotification());
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _PushToTalkOverlay(
        onTalkingChanged: (talking) {
          if (!mounted) return;
          setState(() => _pttActive = talking);
        },
      ),
    ).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _openMic = previousOpenMic;
        _notificationOpenMicOverride = false;
        _pttActive = false;
      });
      unawaited(_setMicEnabled(!previousMuted));
    });
  }

  Future<void> _showDiagnostics() async {
    _flushMicPacketDiagnostics();
    await _audio.refreshAudioDebugInfo();
    if (!mounted) return;
    setState(() => _diagnostics = _withAudioState(_diagnostics));
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: SelectableText(_diagnostics.redactedText()),
        );
      },
    );
  }

  Future<void> _connect() async {
    final server = _serverController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    var websocketText = '';
    if (!_validateRequiredJoinFields()) return;
    if (hasMinecraftServerPort(server)) {
      setState(() {
        _showMinecraftPortWarning = true;
        _minecraftPortWarningShake++;
      });
      return;
    }

    setState(() {
      _busy = true;
      _diagnostics = DiagnosticsSnapshot(
        serverUrl: server,
        state: AppConnectionState.connecting,
      );
    });

    try {
      final websocketUri = await websocketUriForServerWithDiscovery(server);
      websocketText = websocketUri.toString();
      unawaited(_saveCredentials(
        serverUrl: server,
        username: username,
        password: password,
      ));

      final client = widget.clientFactory == null
          ? SimpleVoiceClient(websocketUri)
          : widget.clientFactory!(websocketUri);
      _client = client;
      setState(() {
        _micPacketsSentTotal = 0;
        _micPacketsSinceDiagnosticsUpdate = 0;
        _diagnostics = DiagnosticsSnapshot(
          serverUrl: server,
          websocketUrl: websocketText,
          state: AppConnectionState.connecting,
          selectedAudioMode: 'legacy',
        );
      });
      await client.connect(
        username: username,
        password: password,
        onControlPacket: _handleControlPacket,
        onAudioFrame: (bytes) => unawaited(_handleAudioFrame(bytes)),
        onClosed: _handleClosed,
      );
      if (_busy && !_connected) _startJoinConfirmationTimer();
    } catch (error) {
      _joinConfirmationTimer?.cancel();
      final message = _humanReadableConnectionError(error);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _connected = false;
        _diagnostics = DiagnosticsSnapshot(
          serverUrl: server,
          websocketUrl: websocketText,
          state: AppConnectionState.fatalError,
          lastCloseReason: message,
        );
      });
      _showToast(message);
    }
  }

  void _handleControlPacket(Map<String, Object?> packet) {
    if (!mounted) return;
    final type = controlPacketType(packet);
    final message = controlPacketMessage(packet);
    var becameConnected = false;
    setState(() {
      _timeline.add('$type: $message');
      if (isConnectedStatusPacket(packet)) {
        _joinConfirmationTimer?.cancel();
        _busy = false;
        _connected = true;
        becameConnected = true;
        _diagnostics = _diagnostics.copyWith(
          state: AppConnectionState.connected,
        );
      } else if (type == 'error') {
        _joinConfirmationTimer?.cancel();
        _busy = false;
        _diagnostics = _diagnostics.copyWith(
          state: AppConnectionState.fatalError,
          lastCloseReason: message,
        );
      } else if (type == 'capabilities_ack') {
        _diagnostics = _diagnostics.copyWith(
          selectedAudioMode: selectedAudioModeFromCapabilitiesAck(packet),
        );
      } else if (type == 'chat') {
        _diagnostics = _diagnostics.copyWith(
          chatReceived: _diagnostics.chatReceived + 1,
        );
      }
    });
    if (type == 'error') _showToast(_humanReadableServerError(message));
    if (becameConnected) {
      _client?.sendCapabilities();
      unawaited(_startConnectedAudio());
    }
  }

  Future<void> _handleAudioFrame(List<int> bytes) async {
    if (!mounted) return;
    final unsupportedOpusBefore = _diagnostics.unsupportedOpusFrames;
    final data = Uint8List.fromList(bytes);
    final next = await _incomingAudio.handle(data, _diagnostics);
    if (!mounted) return;
    setState(() => _diagnostics = _withAudioState(next));
    if (next.unsupportedOpusFrames > unsupportedOpusBefore) {
      _showToast('This server sent an audio format the app cannot play yet.');
    }
  }

  void _handleClosed(int? code, String reason) {
    if (!mounted) return;
    _joinConfirmationTimer?.cancel();
    _notificationTransientTimer?.cancel();
    unawaited(_notification.stop());
    unawaited(_stopRuntimeAudio());
    setState(() {
      _busy = false;
      _connected = false;
      _pttActive = false;
      _diagnostics = _diagnostics.copyWith(
        state: AppConnectionState.disconnected,
        lastCloseCode: code,
        lastCloseReason: reason,
      );
    });
    final message = closeMessage(closeCode: code, reason: reason);
    if (message.isNotEmpty) _showToast(message);
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
        ),
      );
  }

  Future<void> _handleNotificationAction(
    CallNotificationAction action,
  ) async {
    switch (action.type) {
      case 'mute':
        await _setMicEnabled(false);
        return;
      case 'unmute':
        await _setMicEnabled(true, notificationOpenMicOverride: true);
        return;
      case 'speaker':
        await _setSpeakerphone(true);
        return;
      case 'earpiece':
        await _setSpeakerphone(false);
        return;
      case 'hangUp':
        await _disconnect();
        return;
      case 'reply':
        final sent = _sendChatMessage(action.message);
        if (sent) {
          await _updateCallNotification(transientStatus: 'Message sent');
        }
        return;
      default:
        return;
    }
  }

  void _startJoinConfirmationTimer() {
    _joinConfirmationTimer?.cancel();
    _joinConfirmationTimer = Timer(_joinConfirmationTimeout, () {
      if (!mounted || !_busy || _connected) return;
      unawaited(_client?.disconnect());
      setState(() {
        _busy = false;
        _connected = false;
        _diagnostics = _diagnostics.copyWith(
          state: AppConnectionState.fatalError,
          lastCloseReason: _joinConfirmationTimeoutMessage,
        );
      });
      _showToast(_joinConfirmationTimeoutMessage);
    });
  }

  Future<void> _saveCredentials({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    try {
      await _store.save(
        serverUrl: serverUrl,
        username: username,
        password: password,
        rememberPassword: _rememberPassword,
      );
    } catch (_) {
      // Credential storage should not block joining a voice server.
    }
  }

  String _humanReadableConnectionError(Object error) {
    if (error is FormatException) {
      switch (error.message) {
        case 'Server URL is required.':
          return 'Enter the server address.';
        case 'Server URL must use http or https.':
          return 'Use an http or https server address.';
        case 'Enter a valid server URL.':
          return 'That server address does not look valid.';
        case minecraftServerPortWarning:
          return minecraftServerPortWarning;
        case invalidDiscoveryMessage:
          return invalidDiscoveryMessage;
      }
      return error.message.isEmpty
          ? 'That server address does not look valid.'
          : error.message;
    }
    final text = error.toString();
    final lower = text.toLowerCase();
    if (lower.contains('connection closed before full header')) {
      return 'The server closed the connection before voice chat could start. '
          'Check that you are using the SimpleVoice-Geyser web port, not the '
          'Minecraft server port.';
    }
    if (lower.contains('handshake') ||
        lower.contains('certificate') ||
        lower.contains('tls') ||
        lower.contains('ssl')) {
      return 'Could not establish a secure connection. Use the HTTPS address '
          'for your SimpleVoice-Geyser web server, or enter http:// only for '
          'trusted local testing.';
    }
    if (lower.contains('connection refused') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('websocket')) {
      return 'Could not connect to the server. Check the address and that '
          'SimpleVoice-Geyser is running.';
    }
    return text;
  }

  String _humanReadableServerError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('password') ||
        lower.contains('unauthorized') ||
        lower.contains('auth') ||
        lower.contains('login')) {
      return 'The server rejected the login. Check the username and '
          'password.';
    }
    return message;
  }

  void _sendChat() {
    final sent = _sendChatMessage(_chatController.text);
    if (!sent) return;
    _chatController.clear();
  }

  bool _sendChatMessage(String rawMessage) {
    final message = rawMessage.trim();
    if (message.isEmpty) return false;
    if (!_connected) return false;
    _client?.sendChat(message);
    setState(() {
      _diagnostics = _diagnostics.copyWith(
        chatSent: _diagnostics.chatSent + 1,
      );
    });
    return true;
  }

  Future<void> _disconnect() async {
    _joinConfirmationTimer?.cancel();
    _flushMicPacketDiagnostics();
    _notificationTransientTimer?.cancel();
    await _client?.disconnect();
    unawaited(_notification.stop());
    await _stopRuntimeAudio();
    if (!mounted) return;
    setState(() {
      _connected = false;
      _busy = false;
      _client = null;
      _pttActive = false;
      _notificationOpenMicOverride = false;
      _localAudioTest = false;
      _localAudioActive = false;
      _diagnostics = _withAudioState(_diagnostics).copyWith(
        state: AppConnectionState.disconnected,
      );
    });
  }

  Future<void> _startConnectedAudio() async {
    await _subscribeMicPackets();
    final playbackStarted = await _audio.startPlayback();
    final micAllowed = await _audio.requestMicPermission();
    var micStarted = false;
    if (micAllowed && !_muted) {
      micStarted = await _audio.startMic();
    }
    if (!mounted) return;
    setState(() {
      _diagnostics = _withAudioState(_diagnostics).copyWith(
        state: micAllowed && micStarted
            ? AppConnectionState.connected
            : AppConnectionState.degraded,
        playbackRunning: playbackStarted,
        micPermissionGranted: micAllowed,
        micRunning: micStarted,
        audioError: _audio.state.lastError,
      );
    });
    if (!micAllowed) {
      _showToast(
        'Microphone permission was denied. You can still listen and use chat.',
      );
    } else if (!micStarted && _audio.state.lastError.isNotEmpty) {
      _showToast(_humanReadableAudioError(_audio.state.lastError));
    } else if (!playbackStarted && _audio.state.lastError.isNotEmpty) {
      _showToast(_humanReadableAudioError(_audio.state.lastError));
    }
    await _startCallNotification();
  }

  Future<void> _subscribeMicPackets() async {
    if (_micSubscription != null) return;
    _micSubscription = _audio.micPackets.listen(
      _handleMicPacket,
      onError: (Object error) {
        if (!mounted) return;
        final message = _humanReadableAudioError(error.toString());
        setState(() {
          _diagnostics = _diagnostics.copyWith(
            state: AppConnectionState.degraded,
            audioError: message,
          );
        });
        _showToast(message);
      },
    );
  }

  void _handleMicPacket(Uint8List packet) {
    if (_localAudioTest) {
      unawaited(_audio.playPcm16(packet, channels: 1));
      if (mounted && !_localAudioActive) {
        setState(() => _localAudioActive = true);
      }
    }

    final gate = AudioGate(
      connected: _connected,
      muted: _muted,
      openMic: _effectiveOpenMic,
      pttActive: _pttActive,
    );
    if (!gate.shouldSend(packet)) return;
    _client?.sendMicPacket(packet);
    _recordMicPacketSent();
  }

  void _recordMicPacketSent() {
    _micPacketsSentTotal++;
    _micPacketsSinceDiagnosticsUpdate++;
    if (!mounted ||
        _micPacketsSinceDiagnosticsUpdate < _micDiagnosticsBatchSize) {
      return;
    }
    _micPacketsSinceDiagnosticsUpdate = 0;
    setState(() {
      _diagnostics = _withAudioState(_diagnostics).copyWith(
        micPacketsSent: _micPacketsSentTotal,
      );
    });
  }

  void _flushMicPacketDiagnostics() {
    if (!mounted ||
        _micPacketsSinceDiagnosticsUpdate == 0 ||
        _diagnostics.micPacketsSent == _micPacketsSentTotal) {
      return;
    }
    _micPacketsSinceDiagnosticsUpdate = 0;
    setState(() {
      _diagnostics = _withAudioState(_diagnostics).copyWith(
        micPacketsSent: _micPacketsSentTotal,
      );
    });
  }

  Future<void> _setMicEnabled(
    bool enabled, {
    bool notificationOpenMicOverride = false,
  }) async {
    setState(() {
      _muted = !enabled;
      _notificationOpenMicOverride =
          enabled ? notificationOpenMicOverride : false;
      if (_muted) _pttActive = false;
    });
    if (!enabled) {
      await _audio.stopMic();
    } else if (_connected || _localAudioTest) {
      await _subscribeMicPackets();
      final allowed = await _audio.requestMicPermission();
      if (allowed) await _audio.startMic();
      if (!allowed) {
        _showToast(
          'Microphone permission was denied. You can still listen and use chat.',
        );
      } else if (_audio.state.lastError.isNotEmpty) {
        _showToast(_humanReadableAudioError(_audio.state.lastError));
      }
    }
    if (!mounted) return;
    setState(() => _diagnostics = _withAudioState(_diagnostics));
    await _updateCallNotification();
  }

  Future<void> _setSpeakerphone(bool enabled) async {
    final applied = await _audio.setSpeakerphone(enabled);
    if (!mounted) return;
    final message = applied
        ? _audio.state.lastError
        : 'This device could not switch audio output.';
    setState(() {
      _diagnostics = _withAudioState(_diagnostics).copyWith(
        speakerphoneEnabled: applied && enabled,
        audioError: applied ? '' : message,
      );
    });
    if (!applied) _showToast(message);
    await _updateCallNotification();
  }

  Future<void> _toggleLocalAudioTest() async {
    if (_localAudioTest) {
      await _stopLocalAudioTest();
      return;
    }
    setState(() {
      _busy = true;
      _localAudioTest = true;
      _localAudioActive = false;
    });
    await _subscribeMicPackets();
    final playbackStarted = await _audio.startPlayback();
    final micAllowed = await _audio.requestMicPermission();
    final micStarted = micAllowed ? await _audio.startMic() : false;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _diagnostics = _withAudioState(_diagnostics).copyWith(
        state: micAllowed && micStarted
            ? _diagnostics.state
            : AppConnectionState.degraded,
        playbackRunning: playbackStarted,
        micPermissionGranted: micAllowed,
        micRunning: micStarted,
        audioError: _audio.state.lastError,
      );
    });
    if (!micAllowed) {
      _showToast(
        'Microphone permission was denied. You can still listen and use chat.',
      );
    } else if (!micStarted && _audio.state.lastError.isNotEmpty) {
      _showToast(_humanReadableAudioError(_audio.state.lastError));
    } else if (!playbackStarted && _audio.state.lastError.isNotEmpty) {
      _showToast(_humanReadableAudioError(_audio.state.lastError));
    }
  }

  Future<void> _stopLocalAudioTest() async {
    setState(() {
      _localAudioTest = false;
      _localAudioActive = false;
    });
    if (!_connected) {
      await _audio.resetAudio();
    }
    if (!mounted) return;
    setState(() => _diagnostics = _withAudioState(_diagnostics));
  }

  Future<void> _stopRuntimeAudio() async {
    _flushMicPacketDiagnostics();
    _notificationTransientTimer?.cancel();
    await _micSubscription?.cancel();
    _micSubscription = null;
    await _audio.resetAudio();
  }

  Future<void> _startCallNotification() async {
    if (!_connected) return;
    await _notification.requestPermission();
    await _notification.start(
      server: _callNotificationServer(),
      status: _micStatusText(),
      muted: _muted,
      speaker: _diagnostics.speakerphoneEnabled,
    );
  }

  Future<void> _updateCallNotification({String transientStatus = ''}) async {
    if (!_connected) return;
    _notificationTransientTimer?.cancel();
    await _notification.update(
      server: _callNotificationServer(),
      status: _micStatusText(),
      muted: _muted,
      speaker: _diagnostics.speakerphoneEnabled,
      transientStatus: transientStatus,
    );
    if (transientStatus.isNotEmpty) {
      _notificationTransientTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted || !_connected) return;
        unawaited(_updateCallNotification());
      });
    }
  }

  String _callNotificationServer() {
    final server = _diagnostics.serverUrl.trim();
    if (server.isNotEmpty) return server;
    return _serverController.text.trim();
  }

  DiagnosticsSnapshot _withAudioState(DiagnosticsSnapshot diagnostics) {
    final audioState = _audio.state;
    return diagnostics.copyWith(
      micPermissionGranted: audioState.micPermissionGranted,
      micRunning: audioState.micRunning,
      playbackRunning: audioState.playbackRunning,
      speakerphoneEnabled: audioState.speakerphoneEnabled,
      audioRoute: audioState.audioRoute,
      audioDebugInfo: audioState.audioDebugInfo,
      audioError: audioState.lastError,
    );
  }

  String _micStatusText() {
    if (_muted) return 'Mic muted';
    if (!_diagnostics.micPermissionGranted) {
      return 'Microphone permission needed';
    }
    if (_diagnostics.micRunning) {
      return _effectiveOpenMic ? 'Open mic on' : 'Push to talk ready';
    }
    return 'Mic is not capturing';
  }

  bool get _effectiveOpenMic => _openMic || _notificationOpenMicOverride;

  String _displayUsername() {
    final username = _usernameController.text.trim();
    return username.isEmpty ? 'user' : username;
  }

  String _localAudioStatusText() {
    if (_diagnostics.audioError.isNotEmpty) {
      return _humanReadableAudioError(_diagnostics.audioError);
    }
    if (_diagnostics.state == AppConnectionState.degraded &&
        !_diagnostics.micPermissionGranted) {
      return 'Microphone permission was denied. You can still listen and use '
          'chat.';
    }
    return _localAudioActive
        ? 'Audio test is playing your microphone back.'
        : 'Waiting for microphone audio...';
  }

  String _connectionStatusText() {
    switch (_diagnostics.state) {
      case AppConnectionState.idle:
        return 'Ready to connect';
      case AppConnectionState.connecting:
        return 'Connecting to server...';
      case AppConnectionState.authenticated:
        return 'Signed in';
      case AppConnectionState.connected:
        return 'Connected';
      case AppConnectionState.degraded:
        return 'Connected, but audio needs attention';
      case AppConnectionState.fatalError:
        return 'Could not connect';
      case AppConnectionState.disconnected:
        return 'Disconnected';
    }
  }

  String _playbackStatusText() {
    return _diagnostics.playbackRunning
        ? 'Audio playback on'
        : 'Audio playback off';
  }

  String _audioRouteText() {
    switch (_diagnostics.audioRoute) {
      case 'speaker':
        return 'Speaker';
      case 'normal':
        return 'Phone earpiece';
      default:
        return 'Audio route unavailable';
    }
  }

  String _humanReadableAudioError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('permission') && lower.contains('denied')) {
      return 'Microphone permission was denied. You can still listen and use '
          'chat.';
    }
    if (lower.contains('microphone capture failed')) {
      return 'Could not start the microphone.';
    }
    if (lower.contains('microphone read failed')) {
      return 'Microphone stopped unexpectedly.';
    }
    if (lower.contains('pcm playback failed')) {
      return 'Could not play voice audio.';
    }
    if (lower.contains('audio route')) {
      return 'This device could not switch audio output.';
    }
    return message;
  }

  Widget _speakerToggleButton({required Key key}) {
    final selected = _diagnostics.speakerphoneEnabled;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          key: key,
          tooltip: selected ? 'Use phone earpiece' : 'Use speaker',
          isSelected: selected,
          selectedIcon: const Icon(Icons.volume_up),
          icon: const Icon(Icons.volume_up_outlined),
          style: IconButton.styleFrom(
            backgroundColor:
                selected ? const Color(0xFF55C055) : const Color(0xFFE8ECDC),
            foregroundColor: const Color(0xFF102010),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () => _setSpeakerphone(!selected),
        ),
        const SizedBox(height: 4),
        const Text('Speaker'),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFE8ECDC),
        border: Border(bottom: BorderSide(color: Color(0xFFD5D9C8))),
      ),
      child: Text(text),
    );
  }
}

class _PushToTalkOverlay extends StatefulWidget {
  const _PushToTalkOverlay({required this.onTalkingChanged});

  final ValueChanged<bool> onTalkingChanged;

  @override
  State<_PushToTalkOverlay> createState() => _PushToTalkOverlayState();
}

class _PushToTalkOverlayState extends State<_PushToTalkOverlay> {
  bool _talking = false;

  void _setTalking(bool talking) {
    if (_talking == talking) return;
    setState(() => _talking = talking);
    widget.onTalkingChanged(talking);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
              ),
            ),
            Expanded(
              child: GestureDetector(
                key: const Key('pttHoldZone'),
                onTapDown: (_) => _setTalking(true),
                onTapUp: (_) => _setTalking(false),
                onTapCancel: () => _setTalking(false),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _talking
                        ? const Color(0xFF55C055)
                        : const Color(0xFF8E6308),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _talking ? 'You are talking' : 'Your mic is off',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
