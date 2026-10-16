import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show LicenseRegistry, LicenseEntryWithLineBreaks;
import 'package:flutter/services.dart' show rootBundle, SystemUiOverlayStyle;

import 'l10n/generated/app_localizations.dart';

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
import 'src/ui/minecraft_widgets.dart';

void main() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Press Start 2P',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      'SimpleVoice-Geyser assets and wording',
    ], await rootBundle.loadString('assets/SimpleVoice-Geyser-LICENSE.txt'));
  });
  runApp(const SimpleVoiceApp());
}

typedef SimpleVoiceClientFactory = SimpleVoiceClient Function(Uri uri);

const _joinConfirmationTimeout = Duration(seconds: 8);
const _joinConfirmationTimeoutMessage =
    'Connected to the server, but the app did not receive the login '
    'confirmation. Please try again.';
const _micDiagnosticsBatchSize = 25;

enum _JoinField { server, username, password }

class SimpleVoiceApp extends StatefulWidget {
  const SimpleVoiceApp({
    super.key,
    this.initiallyConnected = false,
    this.audioBridge,
    this.notificationBridge,
    this.clientFactory,
    this.showOpeningSplash = true,
    this.credentialStore,
  });

  final bool initiallyConnected;
  final AudioBridge? audioBridge;
  final CallNotificationBridge? notificationBridge;
  final SimpleVoiceClientFactory? clientFactory;
  final bool showOpeningSplash;
  final CredentialStore? credentialStore;

  @override
  State<SimpleVoiceApp> createState() => _SimpleVoiceAppState();
}

class _SimpleVoiceAppState extends State<SimpleVoiceApp> {
  late final _store = widget.credentialStore ?? CredentialStore();
  String? _language;
  bool _languageSelected = false;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    try {
      final language = await _store.loadLanguage();
      if (!mounted || _languageSelected) return;
      if (AppLocalizations.supportedLocales.any(
        (locale) => locale.languageCode == language,
      )) {
        setState(() => _language = language);
      }
    } catch (_) {
      // Device language remains usable when secure storage is unavailable.
    }
  }

  Future<void> _changeLanguage(String? language) async {
    _languageSelected = true;
    setState(() => _language = language);
    try {
      await _store.saveLanguage(language);
    } catch (_) {
      // The current session can still use the selected language.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Svg-App',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
        ),
        child: child!,
      ),
      locale: _language == null ? null : Locale(_language!),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (locale, supported) => supported.firstWhere(
        (candidate) => candidate.languageCode == locale?.languageCode,
        orElse: () => const Locale('en'),
      ),
      theme: minecraftTheme(),
      home: _OpeningGate(
        showOpeningSplash:
            widget.showOpeningSplash && !widget.initiallyConnected,
        child: _HomeScreen(
          initiallyConnected: widget.initiallyConnected,
          audioBridge: widget.audioBridge,
          notificationBridge: widget.notificationBridge,
          clientFactory: widget.clientFactory,
          store: _store,
          language: _language,
          onLanguageChanged: _changeLanguage,
        ),
      ),
    );
  }
}

class _OpeningGate extends StatefulWidget {
  const _OpeningGate({required this.showOpeningSplash, required this.child});

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
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _startTimer = Timer(
      const Duration(milliseconds: 200),
      () => _controller.forward(),
    );
    _finishTimer = Timer(const Duration(milliseconds: 2000), widget.onFinished);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _startTimer?.cancel();
      _controller.value = 1;
    }
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
      backgroundColor: const Color(0xFF30251C),
      body: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: const Alignment(0, -0.52),
              child: Text(
                'Svg-App',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
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
    required this.store,
    required this.language,
    required this.onLanguageChanged,
  });

  final bool initiallyConnected;
  final AudioBridge? audioBridge;
  final CallNotificationBridge? notificationBridge;
  final SimpleVoiceClientFactory? clientFactory;
  final CredentialStore store;
  final String? language;
  final ValueChanged<String?> onLanguageChanged;

  @override
  State<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<_HomeScreen> {
  late bool _connected = widget.initiallyConnected;
  bool _muted = false;
  bool _openMic = true;
  bool _pttActive = false;
  bool _transferring = false;
  bool _pttOverlayOpen = false;
  int _connectionGeneration = 0;
  final _pttAvailable = ValueNotifier<bool>(true);
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
  CredentialStore get _store => widget.store;
  AppLocalizations get _l => AppLocalizations.of(context);
  Locale? _lastLocale;
  final List<String> _timeline = [];
  late DiagnosticsSnapshot _diagnostics;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (_lastLocale != locale) {
      _lastLocale = locale;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _connected) unawaited(_updateCallNotification());
      });
    }
  }

  void _showLanguages() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_l.language, style: Theme.of(context).textTheme.titleLarge),
              for (final entry in <String, String>{
                'system': _l.systemLanguage,
                'en': 'English',
                'pl': 'Polski',
                'it': 'Italiano',
                'es': 'Español',
              }.entries)
                ListTile(
                  key: Key('locale_${entry.key}'),
                  title: Text(entry.value),
                  selected: (widget.language ?? 'system') == entry.key,
                  trailing: (widget.language ?? 'system') == entry.key
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    widget.onLanguageChanged(
                      entry.key == 'system' ? null : entry.key,
                    );
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _languageButton() => IconButton(
    key: const Key('languageButton'),
    tooltip: _l.language,
    onPressed: _showLanguages,
    icon: const Icon(Icons.language),
  );

  @override
  void initState() {
    super.initState();
    _diagnostics = DiagnosticsSnapshot(
      state: widget.initiallyConnected
          ? AppConnectionState.connected
          : AppConnectionState.idle,
    );
    _notificationSubscription = _notification.actions.listen(
      _handleNotificationAction,
      onError: (_) {},
    );
    _serverFocusNode.addListener(() => _validateFieldOnBlur(_JoinField.server));
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
    ++_connectionGeneration;
    _pttAvailable.dispose();
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
      // Keep manual sign-in available when saved credentials cannot be read.
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
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey('$shakeKey:$shake'),
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 180),
      builder: (context, value, child) {
        final offset = math.sin(value * math.pi * 4) * 4;
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: child,
    );
  }

  Widget _joinScreen() {
    return Scaffold(
      body: DirtBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: BeveledPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            'assets/images/icon.png',
                            width: 40,
                            height: 40,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Svg-App',
                              style: TextStyle(
                                fontFamily: 'PressStart2P',
                                fontSize: 16,
                                height: 1.5,
                              ),
                            ),
                          ),
                          _languageButton(),
                        ],
                      ),
                      const Text(
                        'SimpleVoice-Geyser',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF454545),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _l.joinTitle,
                        style: pixelHeading,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      _shakingField(
                        shakeKey: 'serverField',
                        shake: _serverFieldShake,
                        child: TextField(
                          style: const TextStyle(color: Colors.white),
                          enabled: !_busy,
                          key: Key('serverUrlField'),
                          controller: _serverController,
                          focusNode: _serverFocusNode,
                          onChanged: _updateServerPortWarning,
                          decoration: InputDecoration(
                            labelText: _l.server,
                            hintText: 'voice.example.com',
                            errorText: _serverFieldError
                                ? _l.serverRequired
                                : null,
                          ),
                          keyboardType: TextInputType.url,
                        ),
                      ),
                      if (_showMinecraftPortWarning) ...[
                        const SizedBox(height: 6),
                        _shakingField(
                          shakeKey: 'minecraftPortWarningShake',
                          shake: _minecraftPortWarningShake,
                          child: Text(
                            _l.portWarning,
                            key: Key('minecraftPortWarning'),
                            style: const TextStyle(
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
                          style: const TextStyle(color: Colors.white),
                          enabled: !_busy,
                          key: Key('usernameField'),
                          controller: _usernameController,
                          focusNode: _usernameFocusNode,
                          onChanged: (_) =>
                              _clearRequiredFieldError(_JoinField.username),
                          decoration: InputDecoration(
                            labelText: _l.username,
                            errorText: _usernameFieldError
                                ? _l.usernameRequired
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _shakingField(
                        shakeKey: 'passwordField',
                        shake: _passwordFieldShake,
                        child: TextField(
                          style: const TextStyle(color: Colors.white),
                          enabled: !_busy,
                          key: Key('passwordField'),
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          onChanged: (_) =>
                              _clearRequiredFieldError(_JoinField.password),
                          decoration: InputDecoration(
                            labelText: _l.password,
                            errorText: _passwordFieldError
                                ? _l.passwordRequired
                                : null,
                            suffixIcon: IconButton(
                              key: const Key('passwordVisibilityButton'),
                              tooltip: _passwordVisible
                                  ? _l.hidePassword
                                  : _l.showPassword,
                              onPressed: () {
                                setState(
                                  () => _passwordVisible = !_passwordVisible,
                                );
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
                        title: Text(_l.rememberPassword),
                      ),

                      StoneButton(
                        key: const Key('joinButton'),
                        label: _busy ? _l.connecting : _l.join,
                        primary: true,
                        onPressed: _busy ? null : _connect,
                      ),
                      if (_busy &&
                          _diagnostics.state == AppConnectionState.connecting)
                        TextButton(
                          onPressed: _disconnect,
                          child: Text(_l.cancel),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: StoneButton(
                              key: const Key('testAudioButton'),
                              label: _localAudioTest
                                  ? _l.stopAudioTest
                                  : _l.testAudio,
                              icon: _localAudioTest
                                  ? Icons.stop
                                  : Icons.hearing,
                              onPressed: _busy ? null : _toggleLocalAudioTest,
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 80,
                            child: _speakerToggleButton(
                              key: const Key('joinSpeakerToggleButton'),
                            ),
                          ),
                        ],
                      ),
                      if (_localAudioTest) ...[
                        const SizedBox(height: 12),
                        _StatusLine(text: _localAudioStatusText()),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _joinedShell() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Svg-App', style: pixelHeading),
        actions: [
          _languageButton(),
          IconButton(
            key: const Key('diagnosticsButton'),
            tooltip: _l.diagnostics,
            onPressed: () => unawaited(_showDiagnostics()),
            icon: const Icon(Icons.article_outlined),
          ),
          IconButton(
            tooltip: _l.leave,
            onPressed: _disconnect,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: DirtBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: BeveledPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _l.connectedAs(_displayUsername()),
                        style: pixelHeading.copyWith(
                          color: const Color(0xFF286016),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _callNotificationServer(),
                        style: const TextStyle(fontSize: 13),
                        softWrap: true,
                      ),
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: _StatusLine(text: _connectionStatusText()),
                      ),
                      if (_transferring) ...[
                        const SizedBox(height: 8),
                        Text(_l.transferHint),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: StoneButton(
                              label: _l.voice,
                              primary: _tab == 0,
                              onPressed: () => setState(() => _tab = 0),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: StoneButton(
                              label: _l.chat,
                              primary: _tab == 1,
                              onPressed: () => setState(() => _tab = 1),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _callControls(),
                      const Divider(height: 24, color: Color(0xFF898989)),
                      _tab == 0 ? _voiceTab() : _chatTab(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _callControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_l.microphone),
              subtitle: Text(_muted ? _l.muted : _l.unmuted),
              value: !_muted,
              onChanged: _setMicEnabled,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: _speakerToggleButton(
              key: const Key('voiceSpeakerToggleButton'),
            ),
          ),
        ],
      ),
      SwitchListTile(
        key: const Key('openMicSwitch'),
        contentPadding: EdgeInsets.zero,
        title: Text(_l.openMic),
        subtitle: Text(_l.pttOnly),
        value: _openMic,
        onChanged: (value) {
          setState(() {
            _openMic = value;
            _pttActive = false;
            _notificationOpenMicOverride = false;
          });
          unawaited(_updateCallNotification());
        },
      ),
      if (!_effectiveOpenMic) ...[
        const SizedBox(height: 8),
        HoldToTalk(
          key: const Key('inlinePtt'),
          available: _pttAvailable,
          enabled: !_muted && _diagnostics.micRunning,
          label: _l.holdToTalk,
          talkingLabel: _l.talking,
          hint: _l.pttAccessibleHint,
          onTalkingChanged: (talking) => setState(
            () =>
                _pttActive = talking && !_transferring && _connected && !_muted,
          ),
        ),
        const SizedBox(height: 8),
      ],
      StoneButton(
        key: const Key('openPttButton'),
        label: _l.fullscreenPtt,
        icon: Icons.fullscreen,
        onPressed: _transferring ? null : _showPtt,
      ),
    ],
  );

  Widget _voiceTab() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _l.inVoiceChat,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Text(_l.usernameValue(_displayUsername())),
      const SizedBox(height: 8),
      Text(_l.microphoneValue(_micStatusText())),
      Text(_l.playbackValue(_playbackStatusText(), _audioRouteText())),
      if (_diagnostics.audioError.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          _humanReadableAudioError(_diagnostics.audioError),
          style: const TextStyle(color: Color(0xFF9B211C)),
        ),
      ],
    ],
  );

  Widget _chatTab() => Column(
    children: [
      Container(
        width: double.infinity,
        height: math.max(
          120,
          math.min(280, MediaQuery.sizeOf(context).height * 0.3),
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF252525),
          border: Border.all(color: const Color(0xFF777777), width: 2),
        ),
        child: SingleChildScrollView(
          reverse: true,
          child: SelectableText(
            _timeline.isEmpty ? _l.serverChat : _timeline.join('\n'),
            style: const TextStyle(
              color: Color(0xFFF0F0F0),
              fontSize: 16,
              height: 1.5,
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              style: const TextStyle(color: Colors.white),
              key: const Key('chatInput'),
              controller: _chatController,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(hintText: _l.writeMessage),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendChat(),
            ),
          ),
          const SizedBox(width: 8),
          StoneButton(
            label: _l.send,
            onPressed: _transferring ? null : _sendChat,
          ),
        ],
      ),
    ],
  );

  void _showPtt() {
    if (!_connected || _transferring) return;
    final previousOpenMic = _openMic;
    final previousMuted = _muted;
    setState(() {
      _openMic = false;
      _muted = false;
      _notificationOpenMicOverride = false;
      _pttActive = false;
    });
    _pttOverlayOpen = true;
    unawaited(_setMicEnabled(true));
    unawaited(_updateCallNotification());
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _PushToTalkOverlay(
        available: _pttAvailable,
        onTalkingChanged: (talking) {
          if (!mounted) return;
          setState(() => _pttActive = talking && !_transferring && _connected);
        },
      ),
    ).whenComplete(() {
      _pttOverlayOpen = false;
      if (!mounted || !_connected) return;
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
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_l.diagnostics, style: pixelHeading),
                const SizedBox(height: 12),
                Text(_l.diagnosticsHint),
                const SizedBox(height: 16),
                SelectableText(_diagnostics.redactedText()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _connect() async {
    final generation = ++_connectionGeneration;
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
      if (!mounted || generation != _connectionGeneration) return;
      websocketText = websocketUri.toString();
      unawaited(
        _saveCredentials(
          serverUrl: server,
          username: username,
          password: password,
        ),
      );

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
        onJoinAttempt: () {
          if (mounted && generation == _connectionGeneration) {
            _startJoinConfirmationTimer();
          }
        },
        onControlPacket: (packet) {
          if (generation == _connectionGeneration) _handleControlPacket(packet);
        },
        onAudioFrame: (bytes) {
          if (generation == _connectionGeneration) {
            unawaited(_handleAudioFrame(bytes));
          }
        },
        onClosed: (code, reason) {
          if (generation == _connectionGeneration) _handleClosed(code, reason);
        },
      );
    } catch (error) {
      if (!mounted || generation != _connectionGeneration) return;
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
      if (type == 'chat' ||
          type == 'info' ||
          (type == 'status' &&
              !isConnectedStatusPacket(packet) &&
              !isTransferStatusPacket(packet))) {
        _timeline.add(message);
      }
      if (isConnectedStatusPacket(packet)) {
        _joinConfirmationTimer?.cancel();
        _busy = false;
        becameConnected = !_connected;
        if (becameConnected) {
          _localAudioTest = false;
          _localAudioActive = false;
        }
        final wasTransferring = _transferring;
        _connected = true;
        _transferring = false;
        _pttAvailable.value = !_muted && _diagnostics.micRunning;
        if (becameConnected || wasTransferring) {
          _diagnostics = _diagnostics.copyWith(
            state:
                !becameConnected &&
                    (!_diagnostics.micPermissionGranted ||
                        !_diagnostics.playbackRunning ||
                        _diagnostics.audioError.isNotEmpty)
                ? AppConnectionState.degraded
                : AppConnectionState.connected,
          );
        }
      } else if (_connected && isTransferStatusPacket(packet)) {
        _transferring = true;
        _pttActive = false;
        _pttAvailable.value = false;
        _diagnostics = _diagnostics.copyWith(
          state: AppConnectionState.transferring,
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
    } else if (_connected) {
      unawaited(_updateCallNotification());
    }
  }

  Future<void> _handleAudioFrame(List<int> bytes) async {
    if (!mounted || !_connected) return;
    final generation = _connectionGeneration;
    final unsupportedOpusBefore = _diagnostics.unsupportedOpusFrames;
    final data = Uint8List.fromList(bytes);
    final next = await _incomingAudio.handle(data, _diagnostics);
    if (!mounted || generation != _connectionGeneration || !_connected) return;
    setState(() => _diagnostics = _withAudioState(next));
    if (next.unsupportedOpusFrames > unsupportedOpusBefore) {
      _showToast(_l.unsupportedAudio);
    }
  }

  void _handleClosed(int? code, String reason) {
    if (!mounted) return;
    ++_connectionGeneration;
    if (_pttOverlayOpen) Navigator.of(context).pop();
    _transferring = false;
    _pttAvailable.value = false;
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
    final message =
        code == outdatedClientCloseCode &&
            reason.trim() == appProtocolUnsupportedReason
        ? _l.updateRequired
        : reason.trim().isEmpty
        ? ''
        : _l.serverDisconnected(reason.trim());
    if (message.isNotEmpty) _showToast(message);
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
      );
  }

  Future<void> _handleNotificationAction(CallNotificationAction action) async {
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
          await _updateCallNotification(transientStatus: _l.messageSent);
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
      ++_connectionGeneration;
      unawaited(_client?.disconnect());
      setState(() {
        _busy = false;
        _connected = false;
        _diagnostics = _diagnostics.copyWith(
          state: AppConnectionState.fatalError,
          lastCloseReason: _joinConfirmationTimeoutMessage,
        );
      });
      _showToast(_l.joinTimeout);
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
          return _l.serverRequired;
        case 'Server URL must use http or https.':
          return _l.addressScheme;
        case 'Enter a valid server URL.':
          return _l.invalidAddress;
        case minecraftServerPortWarning:
          return _l.portWarning;
        case invalidDiscoveryMessage:
          return _l.invalidDiscovery;
      }
      return error.message.isEmpty ? _l.invalidAddress : error.message;
    }
    final text = error.toString();
    final lower = text.toLowerCase();
    if (lower.contains('connection closed before full header')) {
      return _l.earlyClose;
    }
    if (lower.contains('handshake') ||
        lower.contains('certificate') ||
        lower.contains('tls') ||
        lower.contains('ssl')) {
      return _l.secureConnectionError;
    }
    if (lower.contains('connection refused') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('websocket')) {
      return _l.connectionError;
    }
    return text;
  }

  String _humanReadableServerError(String message) {
    if (message == appProtocolUnsupportedMessage) return _l.updateRequired;
    final lower = message.toLowerCase();
    if (const {
      'authentication failed: bad password.',
      'invalid username or password.',
      'invalid password.',
      'authentication failed.',
    }.contains(lower)) {
      return _l.loginRejected;
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
    if (!_connected || _transferring) return false;
    _client?.sendChat(message);
    setState(() {
      _diagnostics = _diagnostics.copyWith(chatSent: _diagnostics.chatSent + 1);
    });
    return true;
  }

  Future<void> _disconnect() async {
    if (_pttOverlayOpen) Navigator.of(context).pop();
    ++_connectionGeneration;
    _connected = false;
    _busy = false;
    _transferring = false;
    _pttAvailable.value = false;
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
      _diagnostics = _withAudioState(
        _diagnostics,
      ).copyWith(state: AppConnectionState.disconnected);
    });
  }

  Future<void> _startConnectedAudio() async {
    final generation = _connectionGeneration;
    await _subscribeMicPackets();
    if (!mounted || generation != _connectionGeneration || !_connected) return;
    final playbackStarted = await _audio.startPlayback();
    if (!mounted || generation != _connectionGeneration || !_connected) return;
    final micAllowed = await _audio.requestMicPermission();
    if (!mounted || generation != _connectionGeneration || !_connected) return;
    var micStarted = false;
    if (micAllowed && !_muted) {
      micStarted = await _audio.startMic();
    }
    if (!mounted || generation != _connectionGeneration || !_connected) return;
    _pttAvailable.value = !_muted && !_transferring && micStarted;
    setState(() {
      _diagnostics = _withAudioState(_diagnostics).copyWith(
        state: _transferring
            ? AppConnectionState.transferring
            : playbackStarted && micAllowed && (_muted || micStarted)
            ? AppConnectionState.connected
            : AppConnectionState.degraded,
        playbackRunning: playbackStarted,
        micPermissionGranted: micAllowed,
        micRunning: micStarted,
        audioError: _audio.state.lastError,
      );
    });
    if (!micAllowed) {
      _showToast(_l.micDenied);
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
      connected: _connected && !_transferring,
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
      _diagnostics = _withAudioState(
        _diagnostics,
      ).copyWith(micPacketsSent: _micPacketsSentTotal);
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
      _diagnostics = _withAudioState(
        _diagnostics,
      ).copyWith(micPacketsSent: _micPacketsSentTotal);
    });
  }

  Future<void> _setMicEnabled(
    bool enabled, {
    bool notificationOpenMicOverride = false,
  }) async {
    final generation = _connectionGeneration;
    if (!mounted) return;
    setState(() {
      _muted = !enabled;
      _notificationOpenMicOverride = enabled
          ? notificationOpenMicOverride
          : false;
      if (_muted) _pttActive = false;
    });
    _pttAvailable.value = enabled && _connected && !_transferring;
    if (!enabled) {
      await _audio.stopMic();
    } else if (_connected || _localAudioTest) {
      await _subscribeMicPackets();
      final allowed = await _audio.requestMicPermission();
      if (!mounted || generation != _connectionGeneration) return;
      if (allowed) await _audio.startMic();
      if (!allowed) {
        _showToast(_l.micDenied);
      } else if (_audio.state.lastError.isNotEmpty) {
        _showToast(_humanReadableAudioError(_audio.state.lastError));
      }
    }
    if (!mounted) return;
    _pttAvailable.value =
        !_muted && _connected && !_transferring && _audio.state.micRunning;
    setState(() => _diagnostics = _withAudioState(_diagnostics));
    await _updateCallNotification();
  }

  Future<void> _setSpeakerphone(bool enabled) async {
    final applied = await _audio.setSpeakerphone(enabled);
    if (!mounted) return;
    final message = applied ? _audio.state.lastError : _l.routeError;
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
      _showToast(_l.micDenied);
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
    if (!mounted || !_connected) return;
    await _notification.start(
      server: _callNotificationServer(),
      status: _transferring ? _l.changingServer : _micStatusText(),
      labels: _notificationLabels(),
      muted: _muted,
      speaker: _diagnostics.speakerphoneEnabled,
    );
  }

  Future<void> _updateCallNotification({String transientStatus = ''}) async {
    if (!_connected) return;
    _notificationTransientTimer?.cancel();
    await _notification.update(
      server: _callNotificationServer(),
      status: _transferring ? _l.changingServer : _micStatusText(),
      labels: _notificationLabels(),
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

  Map<String, String> _notificationLabels() => {
    'title': _callNotificationServer().isEmpty
        ? _l.notificationVoiceTitle
        : _l.notificationTitle(_callNotificationServer()),
    'voiceActive': _l.voiceActive,
    'mute': _l.mute,
    'unmute': _l.unmute,
    'earpiece': _l.earpiece,
    'speaker': _l.speaker,
    'chat': _l.chat,
    'replyHint': _l.writeMessage,
    'hangUp': _l.hangUp,
    'channel': _l.notificationChannel,
    'channelDescription': _l.notificationChannelDescription,
  };

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
    if (_muted) return _l.micMuted;
    if (!_diagnostics.micPermissionGranted) {
      return _l.micPermissionNeeded;
    }
    if (_diagnostics.micRunning) {
      return _effectiveOpenMic ? _l.openMicOn : _l.pttReady;
    }
    return _l.micNotCapturing;
  }

  bool get _effectiveOpenMic => _openMic || _notificationOpenMicOverride;

  String _displayUsername() {
    final username = _usernameController.text.trim();
    return username.isEmpty ? _l.user : username;
  }

  String _localAudioStatusText() {
    if (_diagnostics.audioError.isNotEmpty) {
      return _humanReadableAudioError(_diagnostics.audioError);
    }
    if (_diagnostics.state == AppConnectionState.degraded &&
        !_diagnostics.micPermissionGranted) {
      return _l.micDenied;
    }
    return _localAudioActive ? _l.audioTestActive : _l.waitingMic;
  }

  String _connectionStatusText() {
    if (_transferring) return _l.changingServer;
    switch (_diagnostics.state) {
      case AppConnectionState.idle:
        return _l.ready;
      case AppConnectionState.connecting:
        return _l.connectingStatus;
      case AppConnectionState.transferring:
        return _l.changingServer;
      case AppConnectionState.authenticated:
        return _l.signedIn;
      case AppConnectionState.connected:
        return _l.connected;
      case AppConnectionState.degraded:
        return _l.audioAttention;
      case AppConnectionState.fatalError:
        return _l.couldNotConnect;
      case AppConnectionState.disconnected:
        return _l.disconnected;
    }
  }

  String _playbackStatusText() {
    return _diagnostics.playbackRunning ? _l.playbackOn : _l.playbackOff;
  }

  String _audioRouteText() {
    switch (_diagnostics.audioRoute) {
      case 'speaker':
        return _l.speaker;
      case 'normal':
        return _l.earpiece;
      default:
        return _l.routeUnavailable;
    }
  }

  String _humanReadableAudioError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('permission') && lower.contains('denied')) {
      return _l.micDenied;
    }
    if (lower.contains('microphone capture failed')) {
      return _l.micStartError;
    }
    if (lower.contains('microphone read failed')) {
      return _l.micReadError;
    }
    if (lower.contains('pcm playback failed')) {
      return _l.playbackError;
    }
    if (lower.contains('audio route')) {
      return _l.routeError;
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
          tooltip: selected ? _l.useEarpiece : _l.useSpeaker,
          isSelected: selected,
          selectedIcon: const Icon(Icons.volume_up),
          icon: const Icon(Icons.volume_up_outlined),
          style: IconButton.styleFrom(
            backgroundColor: selected
                ? const Color(0xFF326F20)
                : const Color(0xFF666666),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
          onPressed: () => _setSpeakerphone(!selected),
        ),
        const SizedBox(height: 4),
        Text(_l.speaker),
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
        color: Color(0xFFD4D4D4),
        border: Border(bottom: BorderSide(color: Color(0xFF929292))),
      ),
      child: Text(text),
    );
  }
}

class _PushToTalkOverlay extends StatelessWidget {
  const _PushToTalkOverlay({
    required this.onTalkingChanged,
    required this.available,
  });
  final ValueChanged<bool> onTalkingChanged;
  final ValueNotifier<bool> available;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Dialog.fullscreen(
      child: DirtBackground(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: Text(l.back),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  l.holdToTalk,
                  textAlign: TextAlign.center,
                  style: pixelHeading.copyWith(color: Colors.white),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: BeveledPanel(
                    child: HoldToTalk(
                      key: const Key('pttHoldZone'),
                      available: available,
                      enabled: true,
                      label: l.micOff,
                      talkingLabel: l.talking,
                      hint: l.pttAccessibleHint,
                      onTalkingChanged: onTalkingChanged,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
