"""End-to-end audio->STT->risk->injection pipeline."""

from __future__ import annotations

import asyncio
import functools
from datetime import UTC, datetime

import structlog

from mozhi_agent.config import AgentSettings
from mozhi_agent.injection.base import BaseInjector
from mozhi_agent.models import ActionLogEntry
from mozhi_agent.risk.filter import RiskFilter
from mozhi_agent.stt.transcriber import WhisperTranscriber
from mozhi_agent.ui.confirm import confirm_injection

logger = structlog.get_logger(__name__)


class VoiceBridgePipeline:
    """Processes PCM audio frames and executes controlled text injection.

    Incoming audio packets are accumulated in a buffer.  Once the buffer
    reaches ``_buffer_threshold`` bytes (default 3 s of PCM16 mono @16 kHz)
    the aggregated chunk is sent to the Whisper transcriber.  Call
    ``flush_buffer()`` when a push-to-talk session ends to process the
    remaining audio.
    """

    # 3 seconds of PCM16 mono @ 16 kHz → 16000 samples/s × 2 bytes × 3 s
    _BUFFER_THRESHOLD = 16000 * 2 * 3

    def __init__(
        self,
        settings: AgentSettings,
        transcriber: WhisperTranscriber,
        risk_filter: RiskFilter,
        injector: BaseInjector,
    ) -> None:
        self._settings = settings
        self._transcriber = transcriber
        self._risk_filter = risk_filter
        self._injector = injector
        self._audio_buffer = bytearray()

    async def handle_audio(self, pcm_bytes: bytes) -> None:
        """Buffer incoming decrypted PCM and transcribe when threshold is met."""
        self._audio_buffer.extend(pcm_bytes)
        if len(self._audio_buffer) < self._BUFFER_THRESHOLD:
            return
        chunk = bytes(self._audio_buffer)
        self._audio_buffer.clear()
        await self._process_chunk(chunk)

    async def flush_buffer(self) -> None:
        """Transcribe any remaining buffered audio (e.g. on PTT release)."""
        if self._audio_buffer:
            chunk = bytes(self._audio_buffer)
            self._audio_buffer.clear()
            await self._process_chunk(chunk)

    async def _process_chunk(self, pcm_bytes: bytes) -> None:
        """Run STT → risk evaluation → optional confirmation → injection.

        CPU-bound work (STT inference, UI confirmation, injection) is
        dispatched via ``run_in_executor`` so the event loop stays responsive.
        """
        loop = asyncio.get_running_loop()
        transcript = await loop.run_in_executor(
            None, self._transcriber.transcribe_pcm16_mono, pcm_bytes,
        )
        if not transcript.text:
            return

        self._risk_filter.append_audit(
            ActionLogEntry(
                ts_utc=datetime.now(UTC),
                action="transcribed",
                transcript=transcript.text,
                details=f"confidence={transcript.confidence:.3f},latency_ms={transcript.latency_ms}",
            )
        )
        logger.info(
            "stt.completed",
            text=transcript.text,
            confidence=transcript.confidence,
            latency_ms=transcript.latency_ms,
        )

        decision = self._risk_filter.evaluate(transcript.text)
        if decision.needs_confirmation:
            approved = await loop.run_in_executor(
                None,
                functools.partial(
                    confirm_injection, transcript.text, decision.keyword or "unknown",
                ),
            )
            self._risk_filter.append_audit(
                ActionLogEntry(
                    ts_utc=datetime.now(UTC),
                    action="confirmed" if approved else "blocked",
                    transcript=transcript.text,
                    details=f"keyword={decision.keyword}",
                )
            )
            if not approved:
                logger.warning("risk.blocked", keyword=decision.keyword)
                return

        await loop.run_in_executor(
            None,
            functools.partial(
                self._injector.inject, transcript.text, press_enter=self._settings.auto_send,
            ),
        )
        self._risk_filter.append_audit(
            ActionLogEntry(
                ts_utc=datetime.now(UTC),
                action="injected",
                transcript=transcript.text,
                details=f"auto_send={self._settings.auto_send}",
            )
        )
