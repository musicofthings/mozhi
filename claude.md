# CLAUDE.md — Mozhi Session Handover

## 1) Project Purpose
Mozhi is a production-focused, cross-platform voice bridge that lets a user speak on mobile and inject the transcript into Claude Desktop Cowork input with local STT, low latency, security controls, and auditability.

High-level pipeline:

Mobile Push-to-Talk → Encrypted Uplink (AES-GCM) → Desktop Ingress (WebSocket) → Local STT (Faster-Whisper) → Risk Guard → Claude Desktop Input Injection

---

## 2) Current Repository State (Implemented)

### Desktop Agent (`desktop_agent/mozhi_agent`)

#### 2.1 Startup and Wiring
- `main.py` wires the full runtime:
  - structured logging setup
  - tray bootstrap attempt
  - pairing manager init
  - pairing QR payload generation + rendering
  - STT transcriber init
  - risk filter init
  - platform injector selection
  - websocket server start

#### 2.2 Config and Environment
- `config.py` uses `pydantic-settings` with `.env` support and `MOZHI_` prefix.
- Key runtime envs include:
  - `MOZHI_BIND_HOST`, `MOZHI_BIND_PORT`
  - `MOZHI_ADVERTISED_HOST` (for QR pairing URL on LAN)
  - `MOZHI_MODEL_SIZE`, `MOZHI_COMPUTE_TYPE`, `MOZHI_LANGUAGE`
  - `MOZHI_AUTO_SEND`, `MOZHI_REQUIRE_CONFIRMATION`
  - `MOZHI_ACTION_LOG_PATH`

#### 2.3 Pairing + Transport Security
- `security/pairing.py`:
  - X25519 key agreement for shared secret
  - short-lived token issuance and validation
  - AES-GCM encrypt/decrypt helpers
- `security/pairing_qr.py`:
  - builds JSON pairing payload with `ws_url` and desktop public key
  - renders QR in terminal ASCII + writes `pairing_qr.png`

Pairing payload contract:
```json
{
  "ws_url": "ws://<desktop-ip>:8765",
  "desktop_public_key": "<base64url-x25519-public-key>",
  "version": 1
}
```

#### 2.4 Audio Ingress
- `audio/server.py` provides async websocket ingress:
  - handles `pair` messages and returns `pair_ack`
  - validates token on `audio` messages
  - decrypts packet payload and forwards plaintext audio bytes to pipeline

#### 2.5 STT Pipeline
- `stt/transcriber.py` wraps Faster-Whisper:
  - converts PCM16 mono bytes to WAV in-memory
  - transcribes locally
  - returns transcript text + confidence + latency metadata

#### 2.6 Risk Guard and Audit
- `risk/filter.py` checks destructive keywords:
  - `delete`, `remove`, `overwrite`, `deploy`, `execute`, `run`, `drop`, `purge`
- Audit records append to action log with timestamp/action/transcript/details.
- `ui/confirm.py` displays confirmation prompt for risky transcripts.

#### 2.7 Injection Layer
- Platform abstraction via `injection/base.py` and factory selection in `injection/factory.py`.
- Implementations:
  - Windows: `injection/windows.py` (`pywinauto` + keyboard send)
  - macOS: `injection/macos.py` (AppleScript/`osascript`)

#### 2.8 End-to-End Bridge
- `pipeline/bridge.py` flow per audio chunk:
  1) transcribe
  2) audit + log transcript metrics
  3) risk evaluate
  4) optional confirmation
  5) inject text to Claude input
  6) audit injection result

---

### Mobile App (`mobile_app/lib`)

#### 2.9 Push-to-Talk UI
- `screens/push_to_talk_screen.dart`:
  - pairing button
  - hold-to-talk gesture semantics
  - streaming state indicator
  - snackbar-based runtime error surfacing
  - disconnect on widget dispose

#### 2.10 QR Scan + Pairing
- `screens/qr_scan_screen.dart` uses `mobile_scanner` to capture desktop QR payload.
- `services/pairing_service.dart`:
  - parses QR JSON payload
  - creates X25519 client keypair
  - derives shared secret with desktop public key
  - opens websocket to desktop and sends pairing request
  - stores session token and crypto material on `pair_ack`

#### 2.11 Session State
- `models/pairing_session.dart` stores:
  - ws URL, desktop public key
  - client private/public key bytes
  - shared secret bytes
  - session token
- `services/session_store.dart` provides singleton in-memory session state.

#### 2.12 Audio Capture + Encrypted Uplink
- `services/audio_stream_service.dart`:
  - captures PCM16 mono at 16k using `record`
  - AES-GCM encrypts each chunk with per-packet random nonce
  - serializes encrypted payload + token into websocket `audio` event
  - supports stop/disconnect lifecycle

---

## 3) Dependencies and Packaging

### Desktop dependencies
- Core: `websockets`, `cryptography`, `faster-whisper`, `numpy`, `pydantic`, `pydantic-settings`, `structlog`, `qrcode`, `Pillow`
- Optional:
  - Windows: `pywinauto`, `pywin32`
  - macOS: `pyobjc-core`, `pyobjc-framework-Cocoa`
  - Tray: `pystray`

### Mobile dependencies
- `flutter_webrtc` (present for transport evolution)
- `mobile_scanner`
- `cryptography`
- `websocket_universal` (existing dependency)
- `record` for microphone PCM stream

### Packaging scripts
- Windows: `scripts/build_windows.ps1` (PyInstaller)
- macOS: `scripts/build_macos.sh` (py2app)

---

## 4) Operational Runbook

### Desktop run
1. Set `.env` from `.env.example`.
2. Ensure `MOZHI_ADVERTISED_HOST` points to desktop LAN IP reachable by mobile.
3. Start `mozhi-agent`.
4. Confirm terminal shows ASCII QR and `pairing_qr.png` is created.

### Mobile run
1. `flutter pub get`
2. `flutter run`
3. Tap **Pair Desktop via QR** and scan desktop QR.
4. Hold mic button to stream encrypted audio.

---

## 5) Validation Performed in This Workspace
- Desktop Python modules compile successfully (`python -m compileall desktop_agent`).
- Placeholder scan returned none (`rg -n "TODO|stub|placeholder"`).
- `flutter analyze` was not runnable in container due to missing Flutter SDK.

---

## 6) Known Constraints / Risks
1. Desktop injection is implemented only for Windows and macOS; Linux raises unsupported platform in injector factory.
2. Session state on mobile is in-memory only (no secure persistent trust store).
3. No nonce replay cache on desktop yet.
4. Limited automated tests (compile checks done; full integration tests not yet included).
5. WebSocket uplink is implemented; WebRTC path remains a future extension.

---

## 7) Recommended Next Steps for Next Agent
1. Add secure persistent device trust and revocation on desktop and mobile.
2. Add replay protection window/cache for nonces.
3. Add integration tests:
   - pairing handshake
   - encrypted packet round-trip
   - risk-guard branch coverage
4. Add mobile persistent session storage (secure storage/keychain).
5. Add desktop QR window UI (in addition to terminal + PNG) for better usability.
6. Add telemetry counters/histograms for latency and drop rates.

---

## 8) Quick File Map (Important)
- Desktop entrypoint: `desktop_agent/mozhi_agent/main.py`
- Pairing/crypto: `desktop_agent/mozhi_agent/security/pairing.py`
- Pairing QR: `desktop_agent/mozhi_agent/security/pairing_qr.py`
- WebSocket ingress: `desktop_agent/mozhi_agent/audio/server.py`
- STT wrapper: `desktop_agent/mozhi_agent/stt/transcriber.py`
- Pipeline: `desktop_agent/mozhi_agent/pipeline/bridge.py`
- Risk filter: `desktop_agent/mozhi_agent/risk/filter.py`
- Mobile PTT UI: `mobile_app/lib/screens/push_to_talk_screen.dart`
- Mobile QR scan: `mobile_app/lib/screens/qr_scan_screen.dart`
- Mobile pairing: `mobile_app/lib/services/pairing_service.dart`
- Mobile audio stream: `mobile_app/lib/services/audio_stream_service.dart`
- Mobile session state: `mobile_app/lib/services/session_store.dart`

This document is intended as the authoritative handover baseline for the next coding session.
