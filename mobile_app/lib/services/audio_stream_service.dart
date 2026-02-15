import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:record/record.dart';

import 'session_store.dart';

class AudioStreamService {
  AudioStreamService()
      : _audioRecorder = AudioRecorder(),
        _aesGcm = AesGcm.with256bits();

  final AudioRecorder _audioRecorder;
  final AesGcm _aesGcm;

  WebSocket? _socket;
  StreamSubscription<Uint8List>? _audioSubscription;

  Future<void> startStreaming() async {
    final session = SessionStore.instance.session;
    if (session == null) {
      throw StateError('Device is not paired yet.');
    }

    final bool hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      throw StateError('Microphone permission was denied.');
    }

    _socket ??= await WebSocket.connect(session.wsUrl);
    final SecretKey secretKey = SecretKey(session.sharedSecret);

    final Stream<Uint8List> audioStream = await _audioRecorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 256000,
      ),
    );

    _audioSubscription = audioStream.listen((Uint8List chunk) async {
      final List<int> nonce = _randomNonce();
      final SecretBox encrypted = await _aesGcm.encrypt(
        chunk,
        secretKey: secretKey,
        nonce: nonce,
      );

      final Uint8List payload = Uint8List.fromList(<int>[
        ...encrypted.cipherText,
        ...encrypted.mac.bytes,
      ]);

      final Map<String, dynamic> message = <String, dynamic>{
        'type': 'audio',
        'token': session.sessionToken,
        'payload': <String, dynamic>{
          'nonce': base64Url.encode(nonce),
          'ciphertext': base64Url.encode(payload),
          'sent_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
      };
      _socket?.add(jsonEncode(message));
    });
  }

  Future<void> stopStreaming() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    if (await _audioRecorder.isRecording()) {
      await _audioRecorder.stop();
    }
  }

  Future<void> disconnect() async {
    await stopStreaming();
    await _socket?.close();
    _socket = null;
  }

  List<int> _randomNonce() {
    final Random random = Random.secure();
    return List<int>.generate(12, (_) => random.nextInt(256));
  }
}
