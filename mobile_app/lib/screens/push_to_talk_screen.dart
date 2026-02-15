import 'package:flutter/material.dart';

import '../services/audio_stream_service.dart';
import '../services/pairing_service.dart';

class PushToTalkScreen extends StatefulWidget {
  const PushToTalkScreen({super.key});

  @override
  State<PushToTalkScreen> createState() => _PushToTalkScreenState();
}

class _PushToTalkScreenState extends State<PushToTalkScreen> {
  final PairingService _pairingService = PairingService();
  final AudioStreamService _audioService = AudioStreamService();

  bool _paired = false;
  bool _streaming = false;

  Future<void> _pair() async {
    final paired = await _pairingService.pairViaQr();
    if (!mounted) return;
    setState(() => _paired = paired);
  }

  Future<void> _togglePtt(bool active) async {
    if (!_paired) return;
    try {
      if (active) {
        await _audioService.startStreaming();
      } else {
        await _audioService.stopStreaming();
      }
    } catch (e) {
      debugPrint('PTT error: $e');
    }
    if (!mounted) return;
    setState(() => _streaming = active);
  }

  @override
  void dispose() {
    _audioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mozhi Push-to-Talk')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_paired ? 'Paired ✅' : 'Not paired'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _pair,
              child: const Text('Pair Desktop via QR'),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTapDown: (_) => _togglePtt(true),
              onTapUp: (_) => _togglePtt(false),
              onTapCancel: () => _togglePtt(false),
              child: CircleAvatar(
                radius: 70,
                backgroundColor: _streaming ? Colors.red : Colors.teal,
                child: const Icon(Icons.mic, size: 52),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Press and hold to stream audio securely'),
          ],
        ),
      ),
    );
  }
}
