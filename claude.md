# CLAUDE.md — Mozhi Session Handover

## Project Purpose
Mozhi is a production-focused, cross-platform voice bridge that enables users to speak into a mobile app and inject the resulting transcript into Claude Desktop Cowork input with low latency, local speech recognition, and strong transport security.

Primary goals:
- No cloud STT dependency (local Faster-Whisper on desktop)
- Secure pairing + encrypted audio transport
- Risk-aware command gating before text injection
- Enterprise-safe architecture and auditability

---

## What Was Implemented In This Session

### 1) Repository/Foundation
- Initialized a full multi-surface project scaffold for desktop and mobile.
- Added `.gitignore`, `.env.example`, Python packaging metadata, and platform packaging scripts.

### 2) Desktop Agent (Python 3.11+)
Implemented a modular desktop service under `desktop_agent/mozhi_agent`:

- **Configuration**
  - Environment-driven settings via `pydantic-settings` (`config.py`).
  - Runtime controls for bind host/port, model selection, token TTL, risk behavior, and audit path.

- **Observability**
  - Structured logging via `structlog` (`observability/logging_utils.py`).
  - Action-level audit trail support in risk module.

- **Domain Models**
  - Pydantic/dataclass models for pairing, encrypted packet format, transcript events, risk decisions, and audit entries (`models.py`).

- **Secure Pairing + Crypto**
  - X25519 key agreement and short-lived session tokens (`security/pairing.py`).
  - AES-GCM transport helpers for packet encryption/decryption.

- **Encrypted Audio Ingress Server**
  - Async WebSocket server (`audio/server.py`) supporting:
    - Pairing event handshake
    - Token/session validation
    - Encrypted audio packet ingestion and decryption

- **STT Layer**
  - Faster-Whisper wrapper (`stt/transcriber.py`) for local transcription.
  - Confidence and latency extraction for observability.

- **Risk Filter**
  - Keyword detection for destructive terms (`risk/filter.py`):
    - `delete`, `remove`, `overwrite`, `deploy`, `execute`, `run`, `drop`, `purge`
  - Configurable confirmation requirement.
  - Audit append to newline-delimited action log.

- **Injection Layer**
  - Abstract base injector + platform factory.
  - Windows injector using `pywinauto`.
  - macOS injector using AppleScript (`osascript`).

- **Confirmation UI + Tray**
  - Tkinter confirmation dialog for risky transcripts (`ui/confirm.py`).
  - Optional system tray bootstrap (`ui/tray.py`).

- **End-to-End Pipeline**
  - Audio chunk → transcription → risk evaluation → optional confirmation → injection (`pipeline/bridge.py`).
  - Includes audit logging for transcribed/confirmed/blocked/injected actions.

- **Entrypoint**
  - Async main orchestration (`main.py`) wiring server, transcriber, risk filter, and injector.

### 3) Mobile App Scaffold (Flutter)
Implemented foundational mobile structure under `mobile_app/`:

- `main.dart` + `PushToTalkScreen` UI
  - Pairing button
  - Press-and-hold push-to-talk microphone interaction
- `PairingService` stub (QR + key exchange integration placeholder)
- `AudioStreamService` stub (audio capture + encryption + transport placeholder)
- `pubspec.yaml` dependencies for WebRTC, QR scanning, crypto, and websocket support.

### 4) Docs and Build Instructions
- Added `README.md` covering architecture, setup, pairing flow, runtime behavior, security posture, observability, packaging, and Phase 2 design.
- Added packaging scripts:
  - `scripts/build_windows.ps1` (PyInstaller)
  - `scripts/build_macos.sh` (py2app)

### 5) Validation Performed
- Python compilation checks on desktop code paths:
  - `python -m compileall desktop_agent`
  - `python -m compileall desktop_agent/mozhi_agent/risk/filter.py`

---

## Current Capabilities
- End-to-end desktop architecture exists and is runnable after dependency setup.
- Secure handshake and encrypted payload handling are implemented at protocol layer.
- Local STT integration and risk gating are wired into pipeline.
- Platform-specific text injection adapters are present.
- Mobile side is a UI + service scaffold, not yet full audio/crypto transport implementation.

---

## Known Gaps / What Is Still Incomplete
1. **Mobile pairing implementation**
   - QR scanning/parsing and true X25519 handshake logic are TODOs.
2. **Mobile audio streaming implementation**
   - Mic capture, framing, encryption, transport, and reconnect logic are TODOs.
3. **Desktop QR pairing UX**
   - README describes QR flow; desktop-side QR rendering UI has not been implemented yet.
4. **Hardening + resilience**
   - Retry/backoff, heartbeat/keepalive, flow control, chunk buffering, and graceful reconnects need expansion.
5. **Test coverage**
   - No unit/integration test suite yet (crypto/risk/protocol/pipeline/injection adapters).
6. **Operational maturity**
   - Metrics endpoint, health checks, crash recovery strategy, and richer diagnostics still needed.

---

## Primary Use Cases
1. **Hands-free coding in Claude Desktop**
   - Speak task instructions on mobile and inject into Claude Cowork quickly.
2. **Secure enterprise environments**
   - Keep speech recognition local to desktop, avoid cloud STT exposure.
3. **Risk-sensitive command workflows**
   - Require explicit user confirmation when transcripts include destructive terms.
4. **Cross-platform desktop control**
   - Support both Windows and macOS with platform-specific injection adapters.

---

## Suggested Next Steps (Execution Plan)

### Phase A — Complete Core Functionality
1. Implement mobile QR scanner and payload schema.
2. Implement mobile X25519 key generation + session establishment.
3. Implement mobile microphone capture pipeline (PCM16 mono @ 16k/24k).
4. Encrypt frame payloads with AES-GCM and send via websocket/webRTC channel.
5. Add desktop-side pairing QR generation and display mechanism.

### Phase B — Reliability and Security Hardening
1. Add websocket heartbeat, timeout handling, token refresh, and reconnect strategy.
2. Introduce replay protection (nonce tracking/window) and strict packet validation.
3. Add rate limiting and per-device quotas.
4. Add secure persistence for trusted devices and revocation flow.

### Phase C — Production Readiness
1. Add automated tests:
   - Unit: risk filter, crypto helpers, token expiry, packet model validation.
   - Integration: pairing handshake, encrypted round-trip, pipeline branching.
2. Add CI pipelines (lint, type checks, tests, packaging smoke tests).
3. Add metrics and health endpoints (latency histograms, dropped chunk counts, queue depth).
4. Improve desktop process lifecycle (auto-start, tray controls, graceful shutdown).

### Phase D — UX and Injection Quality
1. Improve Claude window detection and input targeting robustness.
2. Add explicit “preview transcript before send” mode.
3. Add per-workspace risk policies and user-tunable keyword severity.

---

## Architecture Improvement Suggestions
1. **Transport abstraction**
   - Introduce a shared `TransportAdapter` interface to support both WebSocket and WebRTC seamlessly.
2. **Chunk aggregation + VAD**
   - Add VAD/endpointing on mobile or desktop to reduce fragmentary transcriptions and latency jitter.
3. **Dependency inversion for platform adapters**
   - Isolate OS-specific injectors behind tested ports/adapters for cleaner unit testing.
4. **Secure key lifecycle**
   - Rotate session keys periodically and persist trust anchors in OS keychain/credential vault.
5. **Observability maturity**
   - Emit trace IDs across pairing/session/transcription/injection chain for forensic debugging.

---

## Phase 2 (Design Reference): Bidirectional TTS
Planned (not fully implemented):
- Capture Claude output from desktop
- Synthesize speech locally (platform TTS abstraction)
- Stream encrypted audio downlink to mobile playback buffer
- Add playback controls + barge-in behavior
- Preserve existing security/auth model and audit trail

---

## Handover Notes for Next AI Coding Tool
- Start by implementing real mobile pairing + streaming (highest impact path to working E2E).
- Then add desktop QR presentation and robust session lifecycle management.
- Before expanding features, add automated tests around crypto, protocol, and risk gating to lock behavior.
- Keep all new modules typed, async where applicable, and with structured logs to align current project conventions.
