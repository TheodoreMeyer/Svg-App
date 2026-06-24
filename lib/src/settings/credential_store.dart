import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SavedCredentials {
  const SavedCredentials({
    required this.serverUrl,
    required this.username,
    required this.password,
  });

  final String serverUrl;
  final String username;
  final String password;
}

class CredentialStore {
  CredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _serverKey = 'server_url';
  static const _usernameKey = 'username';
  static const _passwordKey = 'password';

  final FlutterSecureStorage _storage;

  Future<SavedCredentials> load() async {
    return SavedCredentials(
      serverUrl: await _storage.read(key: _serverKey) ?? '',
      username: await _storage.read(key: _usernameKey) ?? '',
      password: await _storage.read(key: _passwordKey) ?? '',
    );
  }

  Future<void> save({
    required String serverUrl,
    required String username,
    required String password,
    required bool rememberPassword,
  }) async {
    await _storage.write(key: _serverKey, value: serverUrl);
    await _storage.write(key: _usernameKey, value: username);
    if (rememberPassword) {
      await _storage.write(key: _passwordKey, value: password);
    } else {
      await _storage.delete(key: _passwordKey);
    }
  }
}
