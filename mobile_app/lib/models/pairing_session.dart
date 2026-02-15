class PairingSession {
  PairingSession({
    required this.wsUrl,
    required this.desktopPublicKey,
    required this.clientPrivateKey,
    required this.clientPublicKey,
    required this.sharedSecret,
    required this.sessionToken,
  });

  final String wsUrl;
  final String desktopPublicKey;
  final List<int> clientPrivateKey;
  final List<int> clientPublicKey;
  final List<int> sharedSecret;
  final String sessionToken;
}
