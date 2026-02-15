import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/pairing_session.dart';
import 'crypto_helper.dart';
import 'session_store.dart';

/// Handles QR-based pairing with the Mozhi desktop agent.
///
/// Flow:
/// 1. Caller scans QR -> gets JSON with `ws_url` and `desktop_public_key`.
/// 2. This service generates an X25519 key pair.
/// 3. Opens a WebSocket to the desktop agent.
/// 4. Sends a `pair` message with the client public key.
/// 5. Receives `pair_ack` with session token.
/// 6. Derives the AES-256 key via HKDF and stores the session.
class PairingService {
  WebSocketChannel? _channel;

  /// Pair with the desktop agent using the scanned QR payload JSON string.
  ///
  /// Returns `true` on success.
  Future<bool> pairWithData(String qrJson) async {
    try {
      final qrPayload = jsonDecode(qrJson) as Map<String, dynamic>;
      final wsUrl = qrPayload['ws_url'] as String;
      final desktopPublicKeyB64 = qrPayload['desktop_public_key'] as String;

      // 1. Generate X25519 key pair
      final (:keyPair, :publicKeyBytes) = await CryptoHelper.generateKeyPair();
      final clientPublicKeyB64 = base64Url.encode(publicKeyBytes);

      // 2. Connect to desktop WebSocket
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      await _channel!.ready;

      // 3. Send pairing request
      _channel!.sink.add(jsonEncode({
        'type': 'pair',
        'payload': {
          'device_id': _deviceId(),
          'device_name': 'Mozhi Mobile',
          'client_public_key': clientPublicKeyB64,
        },
      }));

      // 4. Wait for pair_ack
      final response = await _channel!.stream.first;
      final ackMessage = jsonDecode(response as String) as Map<String, dynamic>;
      if (ackMessage['type'] != 'pair_ack') {
        return false;
      }

      final ackPayload = ackMessage['payload'] as Map<String, dynamic>;
      final sessionToken = ackPayload['session_token'] as String;

      // 5. Derive AES key via HKDF (must match desktop HKDF info string)
      final desktopPubKeyBytes = base64Url.decode(desktopPublicKeyB64);
      final aesKey = await CryptoHelper.deriveAesKey(keyPair, desktopPubKeyBytes);
      final aesKeyBytes = await aesKey.extractBytes();

      // 6. Store session
      final session = PairingSession(
        wsUrl: wsUrl,
        desktopPublicKey: desktopPublicKeyB64,
        clientPrivateKey: (await keyPair.extractPrivateKeyBytes()),
        clientPublicKey: publicKeyBytes,
        sharedSecret: aesKeyBytes,
        sessionToken: sessionToken,
      );
      SessionStore.instance.save(session);

      return true;
    } catch (e) {
      await _channel?.sink.close();
      _channel = null;
      rethrow;
    }
  }

  /// Get the active WebSocket channel (established during pairing).
  WebSocketChannel? get channel => _channel;

  /// Close the WebSocket connection.
  Future<void> disconnect() async {
    await _channel?.sink.close();
    _channel = null;
    SessionStore.instance.clear();
  }

  String _deviceId() {
    return 'mozhi-mobile-${DateTime.now().millisecondsSinceEpoch}';
  }
}
