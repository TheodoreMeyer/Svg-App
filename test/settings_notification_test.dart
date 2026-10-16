import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_voice_app/src/notification/call_notification_bridge.dart';
import 'package:simple_voice_app/src/settings/credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('language persistence preserves existing credential keys', () async {
    FlutterSecureStorage.setMockInitialValues({
      'server_url': 'https://example.com',
      'username': 'player',
      'password': 'secret',
    });
    final store = CredentialStore();
    await store.saveLanguage('it');
    final saved = await store.load();
    expect(saved.serverUrl, 'https://example.com');
    expect(saved.username, 'player');
    expect(saved.password, 'secret');
    await store.save(
      serverUrl: saved.serverUrl,
      username: saved.username,
      password: saved.password,
      rememberPassword: false,
    );
    expect(await store.loadLanguage(), 'it');
    expect((await store.load()).password, isEmpty);
    await store.saveLanguage(null);
    expect(await store.loadLanguage(), isNull);
  });

  test(
    'native notification receives translated labels on start and update',
    () async {
      const channel = MethodChannel('svg_test/notification');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final bridge = NativeCallNotificationBridge(methodChannel: channel);
      await bridge.start(
        server: 'server',
        status: 'Conectado',
        muted: false,
        speaker: true,
        labels: {
          'title': 'Conectado a server',
          'mute': 'Silenciar',
          'hangUp': 'Colgar',
        },
      );
      await bridge.update(
        server: 'server',
        status: 'Cambiando de servidor',
        muted: true,
        speaker: true,
        labels: {
          'title': 'Conectado a server',
          'unmute': 'Hablar',
          'hangUp': 'Colgar',
        },
      );
      expect(calls.map((call) => call.method), ['start', 'update']);
      expect((calls.first.arguments as Map)['labels']['mute'], 'Silenciar');
      expect((calls.last.arguments as Map)['labels']['unmute'], 'Hablar');
      expect((calls.last.arguments as Map)['status'], 'Cambiando de servidor');
      expect((calls.last.arguments as Map)['muted'], true);
      await bridge.stop();
      expect(calls.last.method, 'stop');
    },
  );
}
