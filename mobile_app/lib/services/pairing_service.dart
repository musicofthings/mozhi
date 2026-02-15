class PairingService {
  Future<bool> pairViaQr() async {
    // TODO: Integrate QR scanner, parse desktop endpoint/public key, and perform X25519 handshake.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return true;
  }
}
