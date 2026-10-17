"""
Stage 4 - Early-warning flags (partial NEWS2).

Per the architecture review (#3): training XGBoost on labels derived from
reference ranges would only re-learn the rules, so the risk stage uses the
published NEWS2 thresholds directly. A camera gives 2 of the 7 NEWS2
parameters (pulse, respiration), so the score is reported as *partial*.

Snap ML / XGBoost remains a stretch goal: only worth adding if trained on real
outcomes (e.g. the eICU demo) and reported honestly. Keep the AssessmentOut
shape if you swap it in.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Tuple

from .vitals import VitalsEstimate

# (upper bound inclusive, points). NEWS2 chart, RCP 2017.
HR_BANDS = [(40, 3), (50, 1), (90, 0), (110, 1), (130, 2), (10_000, 3)]
RR_BANDS = [(8, 3), (11, 1), (20, 0), (24, 2), (10_000, 3)]
HR_ZERO_BAND: Tuple[float, float] = (51, 90)
RR_ZERO_BAND: Tuple[float, float] = (12, 20)

NOT_CHECKED = ["Blood oxygen", "Blood pressure", "Temperature", "Alertness", "Oxygen therapy"]


def points(value: float, bands) -> int:
    v = round(value)
    for upper, pts in bands:
        if v <= upper:
            return pts
    return bands[-1][1]


@dataclass
class ItemOut:
    key: str
    label: str
    value: float
    unit: str
    points: int


@dataclass
class AssessmentOut:
    level: str
    partial_news2: int
    checks_used: int
    items: List[ItemOut]
    not_checked: List[str] = field(default_factory=lambda: list(NOT_CHECKED))
    checks_total: int = 7
    method: str = "news2-partial"


def assess(v: VitalsEstimate) -> AssessmentOut:
    items = [
        ItemOut("heart_rate", "Heart rate", v.heart_rate_bpm, "bpm",
                points(v.heart_rate_bpm, HR_BANDS)),
        ItemOut("respiratory_rate", "Breathing rate", v.respiratory_rate_bpm, "/min",
                points(v.respiratory_rate_bpm, RR_BANDS)),
    ]
    total = sum(i.points for i in items)
    if total >= 5 or any(i.points == 3 for i in items):
        level = "seek_advice"
    elif total >= 1:
        level = "watch"
    else:
        level = "no_urgent_flags"
    return AssessmentOut(level=level, partial_news2=total, checks_used=len(items), items=items)
