"""Runs stages 2-5 for one scan and records progress in the store."""

from __future__ import annotations

import logging
from typing import List

from schemas import (Assessment, News2Item, Reasoning, ReferenceRange, Rejection, ScanRequest,
                     ScanResult, ScanStatus, Stage, Vitals)
from store import ScanStore

from . import dsp, reasoning, risk, vitals

log = logging.getLogger("pulsepal.runner")

SQI_MIN = 0.45          # below this: no numbers, no explanation (retake)
SQI_GOOD = 0.70
DEVICE_SQI_MIN = 0.6    # on-device gate: share of frames with a steady, lit face
MIN_SECONDS = 10.0

_vitals_model = vitals.load_model()


def _reject_reasons(req: ScanRequest, seconds: float) -> List[str]:
    reasons: List[str] = []
    if seconds < MIN_SECONDS:
        reasons.append("too_short")
    n = len(req.traces.r)
    mean_rgb = (sum(req.traces.r) + sum(req.traces.g) + sum(req.traces.b)) / (3 * n)
    if mean_rgb < 40 or mean_rgb > 235:
        reasons.append("lighting")
    if req.device_sqi < DEVICE_SQI_MIN:
        reasons.append("motion")
    return reasons or ["no_pulse"]


def process(scan_id: str, req: ScanRequest, store: ScanStore) -> None:
    try:
        tr = req.traces
        seconds = (tr.t_ms[-1] - tr.t_ms[0]) / 1000.0

        store.update(scan_id, status=ScanStatus.processing, stage=Stage.dsp)
        d = dsp.run(tr.t_ms, tr.r, tr.g, tr.b)
        sqi = round(d.sqi, 3)

        if seconds < MIN_SECONDS or sqi < SQI_MIN or req.device_sqi < DEVICE_SQI_MIN:
            store.update(scan_id, status=ScanStatus.rejected, stage=Stage.complete,
                         rejection=Rejection(
                             sqi=sqi, reasons=_reject_reasons(req, seconds),
                             message="The signal was too weak to give reliable numbers."))
            return

        store.update(scan_id, stage=Stage.vitals)
        v = _vitals_model.predict(d)

        store.update(scan_id, stage=Stage.risk)
        a = risk.assess(v)

        store.update(scan_id, stage=Stage.reasoning)
        g = reasoning.generate(v, a, req.age, req.sex)

        result = ScanResult(
            sqi=sqi,
            quality="good" if sqi >= SQI_GOOD else "fair",
            vitals=Vitals(
                heart_rate_bpm=v.heart_rate_bpm,
                respiratory_rate_bpm=v.respiratory_rate_bpm,
                heart_rate_range=ReferenceRange(low=risk.HR_ZERO_BAND[0], high=risk.HR_ZERO_BAND[1]),
                respiratory_rate_range=ReferenceRange(low=risk.RR_ZERO_BAND[0],
                                                      high=risk.RR_ZERO_BAND[1]),
                method=v.method),
            assessment=Assessment(
                level=a.level, partial_news2=a.partial_news2, checks_used=a.checks_used,
                checks_total=a.checks_total, not_checked=a.not_checked, method=a.method,
                items=[News2Item(**i.__dict__) for i in a.items]),
            reasoning=Reasoning(**g.__dict__),
            is_demo=req.source == "simulated",
        )
        store.update(scan_id, status=ScanStatus.done, stage=Stage.complete, result=result)
    except Exception as exc:  # report, don't crash the worker
        log.exception("scan %s failed", scan_id)
        store.update(scan_id, status=ScanStatus.failed, stage=Stage.complete, error=str(exc))
