import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'crypto_helper.dart';
import 'session_store.dart';

/// Captures microphone audio, encrypts it with AES-GCM, and streams
/// encrypted packets over the paired WebSocket connection.
class AudioStreamService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<List<int>>? _audioSub;
  WebSocketChannel? _channel;

  // Buffer PCM bytes until we have enough for a meaningful chunk
  final _pcmBuffer = BytesBuilder(copy: false);

  /// ~1 second of PCM16 mono @ 16 kHz = 32 000 bytes
  static const int _chunkSize = 16000 * 2;

  /// Start capturing microphone audio and streaming encrypted packets.
  ///
  /// [channel] is the WebSocket already opened during pairing.
  Future<void> startStreaming(WebSocketChannel channel) async {
    final session = SessionStore.instance.session;
    if (session == null) {
      throw StateError('Not paired — call PairingService.pairWithData first');
    }

    _channel = channel;

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );

    _audioSub = stream.listen((chunk) {
      _pcmBuffer.add(chunk);
      if (_pcmBuffer.length >= _chunkSize) {
        final bytes = _pcmBuffer.takeBytes();
        _sendEncrypted(bytes, session.sessionToken, session.sharedSecret);
      }
    });
  }

  /// Stop streaming, flush remaining buffer, and release microphone.
  Future<void> stopStreaming() async {
    await _audioSub?.cancel();
    _audioSub = null;

    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }

    // Flush any remaining buffered audio
    final session = SessionStore.instance.session;
    if (_pcmBuffer.length > 0 && session != null) {
      final remaining = _pcmBuffer.takeBytes();
      await _sendEncrypted(
        remaining,
        session.sessionToken,
        session.sharedSecret,
      );
    }
    _pcmBuffer.clear();

    // Signal desktop to flush its buffer
    _channel?.sink.add(jsonEncode({'type': 'flush'}));
  }

  /// Encrypt a PCM chunk and send it over the WebSocket.
  Future<void> _sendEncrypted(
    List<int> pcmBytes,
    String token,
    List<int> aesKeyBytes,
  ) async {
    if (_channel == null) return;

    final aesKey = SecretKeyData(Uint8List.fromList(aesKeyBytes));
    final (:nonceB64, :ciphertextB64) = await CryptoHelper.encrypt(
      aesKey,
      pcmBytes,
    );

    _channel!.sink.add(jsonEncode({
      'type': 'audio',
      'token': token,
      'payload': {
        'nonce': nonceB64,
        'ciphertext': ciphertextB64,
        'sent_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
    }));
  }

  /// Release all resources.
  void dispose() {
    _audioSub?.cancel();
    _recorder.dispose();
    _pcmBuffer.clear();
  }
}
