"""Encrypted WebSocket audio ingestion server."""

from __future__ import annotations

import asyncio
import json
from collections.abc import Awaitable, Callable

import structlog
import websockets
from websockets.asyncio.server import ServerConnection

from mozhi_agent.models import EncryptedAudioPacket, PairingRequest
from mozhi_agent.security.pairing import PairingManager, SessionContext, TransportCrypto

logger = structlog.get_logger(__name__)

AudioCallback = Callable[[bytes], Awaitable[None]]


class AudioIngressServer:
    """Handles pairing, authentication, and encrypted audio packet receipt."""

    def __init__(self, pairing: PairingManager, on_audio: AudioCallback) -> None:
        self._pairing = pairing
        self._on_audio = on_audio

    async def handler(self, websocket: ServerConnection) -> None:
        """Websocket lifecycle entrypoint."""
        session: SessionContext | None = None
        async for payload in websocket:
            try:
                message = json.loads(payload)
            except (json.JSONDecodeError, TypeError) as exc:
                logger.warning("ws.invalid_payload", error=str(exc))
                await websocket.send(json.dumps({"type": "error", "message": "invalid_json"}))
                continue
            event_type = message.get("type")
            if event_type == "pair":
                session = await self._handle_pairing(websocket, message)
                continue
            if event_type == "audio":
                if session is None:
                    token = message.get("token", "")
                    session = self._pairing.validate_token(token)
                    if session is None:
                        await websocket.send(json.dumps({"type": "error", "message": "invalid_token"}))
                        continue
                await self._handle_audio_packet(message, session)

    async def _handle_pairing(self, websocket: ServerConnection, message: dict) -> SessionContext:
        req = PairingRequest.model_validate(message["payload"])
        session = self._pairing.create_session(req.device_id, req.client_public_key)
        response = {
            "type": "pair_ack",
            "payload": {
                "desktop_public_key": self._pairing.desktop_public_key_b64(),
                "session_token": session.token,
                "expires_at_utc": session.expires_at_utc.isoformat(),
            },
        }
        await websocket.send(json.dumps(response))
        logger.info("pairing.completed", device_id=req.device_id, device_name=req.device_name)
        return session

    async def _handle_audio_packet(self, message: dict, session: SessionContext) -> None:
        packet = EncryptedAudioPacket.model_validate(message["payload"])
        plaintext = TransportCrypto.decrypt(session.aes_key, packet.nonce, packet.ciphertext)
        await self._on_audio(plaintext)


async def run_server(host: str, port: int, server: AudioIngressServer) -> None:
    """Start audio server and run forever."""
    async with websockets.serve(server.handler, host, port, max_size=2**22):
        logger.info("audio.server.started", host=host, port=port)
        await asyncio.Future()
