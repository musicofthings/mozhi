import '../models/pairing_session.dart';

class SessionStore {
  SessionStore._();

  static final SessionStore instance = SessionStore._();

  PairingSession? _session;

  PairingSession? get session => _session;

  bool get isPaired => _session != null;

  void save(PairingSession session) {
    _session = session;
  }

  void clear() {
    _session = null;
  }
}
