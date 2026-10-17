"""
Request / response contract between the Flutter app and the LinuxONE core.

    POST /api/v1/scans          -> 202 ScanAccepted   (phone uploads RGB traces)
    GET  /api/v1/scans/{id}     -> 200 ScanState      (phone polls until done)

Keep this file and lib/models/scan_result.dart in sync.
"""

from __future__ import annotations

from enum import Enum
from typing import List, Literal, Optional

from pydantic import BaseModel, Field, model_validator


# ---------------------------------------------------------------------------
# Request
# ---------------------------------------------------------------------------

class RgbTraces(BaseModel):
    """Per-frame mean colour of the face ROIs (forehead + both cheeks).

    No pixels or video are ever sent: only one (r, g, b) triple per frame.
    """

    t_ms: List[int] = Field(..., description="Frame timestamps, ms since capture start")
    r: List[float]
    g: List[float]
    b: List[float]

    @model_validator(mode="after")
    def _same_length(self) -> "RgbTraces":
        n = len(self.t_ms)
        if not (len(self.r) == len(self.g) == len(self.b) == n):
            raise ValueError("t_ms, r, g and b must have the same length")
        if n < 2:
            raise ValueError("need at least 2 frames")
        if any(b <= a for a, b in zip(self.t_ms, self.t_ms[1:])):
            raise ValueError("t_ms must be strictly increasing")
        return self


class ScanRequest(BaseModel):
    age: int = Field(..., ge=18, le=120, description="Adults only (NEWS2 is an adult score)")
    sex: Literal["male", "female"]
    fps: float = Field(30, gt=0, le=120, description="Nominal capture rate")
    duration_s: float = Field(..., gt=0, le=120)
    traces: RgbTraces
    device_sqi: float = Field(..., ge=0, le=1, description="On-device quality gate score")
    source: Literal["camera", "simulated"] = "camera"
    app_version: str = "unknown"


# ---------------------------------------------------------------------------
# Response
# ---------------------------------------------------------------------------

class ScanStatus(str, Enum):
    queued = "queued"
    processing = "processing"
    done = "done"
    rejected = "rejected"  # signal too poor -> app shows the retake screen
    failed = "failed"      # server error


class Stage(str, Enum):
    ingest = "ingest"
    dsp = "dsp"
    vitals = "vitals"
    risk = "risk"
    reasoning = "reasoning"
    complete = "complete"


class ReferenceRange(BaseModel):
    low: float
    high: float


class Vitals(BaseModel):
    heart_rate_bpm: float
    respiratory_rate_bpm: float
    heart_rate_range: ReferenceRange          # NEWS2 0-point band
    respiratory_rate_range: ReferenceRange    # NEWS2 0-point band
    respiratory_rate_experimental: bool = True
    # A phone camera cannot measure SpO2 reliably (architecture review #1),
    # so it is never estimated. Kept as a field so a validated source can
    # fill it later without changing the contract.
    spo2_pct: Optional[float] = None
    spo2_source: Literal["not_measured"] = "not_measured"
    method: str = Field(..., description="Which stage-3 implementation produced these numbers")


class News2Item(BaseModel):
    key: Literal["heart_rate", "respiratory_rate"]
    label: str
    value: float
    unit: str
    points: int = Field(..., ge=0, le=3)


class Assessment(BaseModel):
    """Partial NEWS2 (Royal College of Physicians, 2017) on the parameters a
    camera can provide. Transparent thresholds instead of a trained score."""

    level: Literal["no_urgent_flags", "watch", "seek_advice"]
    partial_news2: int = Field(..., ge=0)
    checks_used: int
    checks_total: int = 7
    items: List[News2Item]
    not_checked: List[str]
    method: str = "news2-partial"


class Reasoning(BaseModel):
    summary: str
    factors: List[str]
    suggestion: str
    disclaimer: str
    method: str  # "granite-3-8b-instruct" | "template"


class ScanResult(BaseModel):
    sqi: float = Field(..., description="Signal quality 0..1. Gates the result; not a confidence")
    quality: Literal["good", "fair"]
    vitals: Vitals
    assessment: Assessment
    reasoning: Reasoning
    is_demo: bool = False


class Rejection(BaseModel):
    sqi: float
    reasons: List[Literal["motion", "lighting", "face_lost", "too_short", "no_pulse"]]
    message: str


class ScanAccepted(BaseModel):
    scan_id: str
    status: ScanStatus
    poll_url: str


class ScanState(BaseModel):
    scan_id: str
    status: ScanStatus
    stage: Stage
    created_at: str
    updated_at: str
    result: Optional[ScanResult] = None
    rejection: Optional[Rejection] = None
    error: Optional[str] = None
