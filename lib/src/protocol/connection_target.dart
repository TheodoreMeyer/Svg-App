import 'dart:convert';
import 'dart:io';

typedef DiscoveryFetcher = Future<String?> Function(Uri uri);

const minecraftServerPortWarning =
    'That looks like the minecraft server port. Use the SimpleVoice-Geyser port instead.';
const invalidDiscoveryMessage =
    "The server's SimpleVoice-Geyser app information is invalid.";
const discoveryPath = '/.well-known/simplevoice-geyser.json';

Uri websocketUriForServer(String input) {
  final base = parseServerBaseUri(input);
  final path = base.path.endsWith('/') ? base.path : '${base.path}/';
  final scheme = base.scheme == 'https' ? 'wss' : 'ws';
  return base.replace(scheme: scheme, path: '${path}ws');
}

Future<Uri> websocketUriForServerWithDiscovery(
  String input, {
  DiscoveryFetcher? fetchDiscovery,
}) async {
  if (hasMinecraftServerPort(input)) {
    throw const FormatException(minecraftServerPortWarning);
  }
  if (!_shouldTryDiscovery(input)) return websocketUriForServer(input);

  final discoveryUri = Uri.https(input.trim(), discoveryPath);
  final fetcher = fetchDiscovery ?? _fetchDiscovery;
  final body = await fetcher(discoveryUri);
  if (body == null) return websocketUriForServer(input);
  return _websocketUriFromDiscovery(body);
}

Uri parseServerBaseUri(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Server URL is required.');
  }
  if (hasMinecraftServerPort(trimmed)) {
    throw const FormatException(minecraftServerPortWarning);
  }
  final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final uri = Uri.parse(withScheme);
  if (!uri.hasScheme || uri.host.isEmpty) {
    throw const FormatException('Enter a valid server URL.');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw const FormatException('Server URL must use http or https.');
  }
  return uri;
}

bool hasMinecraftServerPort(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return false;
  try {
    final uri = Uri.parse(
      trimmed.contains('://') ? trimmed : 'https://$trimmed',
    );
    return uri.hasPort && uri.port == 25565;
  } on FormatException {
    return false;
  }
}

bool _shouldTryDiscovery(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty || trimmed.contains('://')) return false;
  final uri = Uri.parse('https://$trimmed');
  return !uri.hasPort && (uri.path.isEmpty || uri.path == '/');
}

Future<String?> _fetchDiscovery(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri).timeout(
          const Duration(seconds: 3),
        );
    final response = await request.close().timeout(
          const Duration(seconds: 3),
        );
    if (response.statusCode == HttpStatus.notFound) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    return utf8.decodeStream(response).timeout(const Duration(seconds: 3));
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

Uri _websocketUriFromDiscovery(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException();
    }
    final websocket = decoded['websocket'];
    if (websocket is! String || websocket.trim().isEmpty) {
      throw const FormatException();
    }
    final uri = Uri.parse(websocket.trim());
    if ((uri.scheme != 'ws' && uri.scheme != 'wss') || uri.host.isEmpty) {
      throw const FormatException();
    }
    return uri;
  } on Object {
    throw const FormatException(invalidDiscoveryMessage);
  }
}
