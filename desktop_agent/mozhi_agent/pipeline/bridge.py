"""End-to-end audio->STT->risk->injection pipeline."""

from __future__ import annotations

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
    """Processes PCM audio frames and executes controlled text injection."""

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

    async def handle_audio(self, pcm_bytes: bytes) -> None:
        """Asynchronously process one decrypted audio chunk."""
        transcript = self._transcriber.transcribe_pcm16_mono(pcm_bytes)
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
            approved = confirm_injection(transcript.text, decision.keyword or "unknown")
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

        self._injector.inject(transcript.text, press_enter=self._settings.auto_send)
        self._risk_filter.append_audit(
            ActionLogEntry(
                ts_utc=datetime.now(UTC),
                action="injected",
                transcript=transcript.text,
                details=f"auto_send={self._settings.auto_send}",
            )
        )
