import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';

import '../models/pairing_session.dart';
import '../screens/qr_scan_screen.dart';
import 'session_store.dart';

class PairingService {
  final X25519 _x25519 = X25519();

  Future<bool> pairViaQr(BuildContext context) async {
    final String? qrPayload = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const QrScanScreen()),
    );
    if (qrPayload == null || qrPayload.isEmpty) {
      return false;
    }

    final Map<String, dynamic> decoded = jsonDecode(qrPayload) as Map<String, dynamic>;
    final String wsUrl = decoded['ws_url'] as String;
    final String desktopPublicKeyB64 = decoded['desktop_public_key'] as String;

    final SimpleKeyPair clientKeyPair = await _x25519.newKeyPair();
    final SimpleKeyPairData clientKeyData = await clientKeyPair.extract();
    final SimplePublicKey clientPublic = await clientKeyPair.extractPublicKey();
    final List<int> desktopPublicKey = base64Url.decode(desktopPublicKeyB64);

    final SecretKey secretKey = await _x25519.sharedSecretKey(
      keyPair: clientKeyData,
      remotePublicKey: SimplePublicKey(desktopPublicKey, type: KeyPairType.x25519),
    );
    final List<int> sharedSecret = await secretKey.extractBytes();

    final WebSocket socket = await WebSocket.connect(wsUrl);
    try {
      final Map<String, dynamic> pairMessage = <String, dynamic>{
        'type': 'pair',
        'payload': <String, dynamic>{
          'device_id': '${Platform.operatingSystem}-${DateTime.now().millisecondsSinceEpoch}',
          'device_name': 'Mozhi Mobile ${Platform.operatingSystem}',
          'client_public_key': base64Url.encode(clientPublic.bytes),
        },
      };
      socket.add(jsonEncode(pairMessage));

      final String responseRaw = await socket.first as String;
      final Map<String, dynamic> response = jsonDecode(responseRaw) as Map<String, dynamic>;
      if (response['type'] != 'pair_ack') {
        return false;
      }
      final Map<String, dynamic> payload = response['payload'] as Map<String, dynamic>;
      final String token = payload['session_token'] as String;

      SessionStore.instance.save(
        PairingSession(
          wsUrl: wsUrl,
          desktopPublicKey: desktopPublicKeyB64,
          clientPrivateKey: clientKeyData.bytes,
          clientPublicKey: clientPublic.bytes,
          sharedSecret: sharedSecret,
          sessionToken: token,
        ),
      );
      return true;
    } finally {
      await socket.close();
    }
  }
}
