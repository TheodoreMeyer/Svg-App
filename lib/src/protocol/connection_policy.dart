const int maxReconnectAttempts = 5;
const int outdatedClientCloseCode = 4008;
const String appProtocolUnsupportedReason = 'app_protocol_unsupported';
const String appProtocolUnsupportedMessage =
    'This app version is not compatible with this server. Update the app.';

const Set<int> noReconnectCloseCodes = {
  4001,
  4003,
  4004,
  4005,
  4006,
  4007,
  outdatedClientCloseCode,
};

bool shouldReconnect({
  required int? closeCode,
  required int attempts,
  bool manualClose = false,
  bool fatalError = false,
}) {
  if (manualClose || fatalError || attempts >= maxReconnectAttempts) {
    return false;
  }
  if (closeCode != null && noReconnectCloseCodes.contains(closeCode)) {
    return false;
  }
  return true;
}

String closeMessage({
  required int? closeCode,
  required String reason,
}) {
  final normalizedReason = reason.trim();
  if (closeCode == outdatedClientCloseCode &&
      normalizedReason == appProtocolUnsupportedReason) {
    return appProtocolUnsupportedMessage;
  }
  if (normalizedReason.isEmpty) {
    return '';
  }
  return 'The server disconnected you: $normalizedReason';
}
