class AudioStreamService {
  Future<void> startStreaming() async {
    // TODO: Capture mic PCM -> encrypt AES-GCM -> send over WebRTC/WebSocket.
  }

  Future<void> stopStreaming() async {
    // TODO: Flush audio buffer and close stream gracefully.
  }
}
