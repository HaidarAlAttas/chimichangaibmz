"""
Stage 5 - Plain-language explanation.

Default is a fixed template built from the computed numbers (always available).
Granite is optional: set GRANITE_URL to an OpenAI-compatible
/v1/chat/completions endpoint. On the 8 GB LinuxONE VM that is llama.cpp's
`llama-server` running Granite 3.3 2B Instruct as a big-endian Q4_K_M GGUF
(see scripts/granite_convert_on_mac.sh and scripts/setup_granite.sh).
Any failure falls back to the template so a scan never fails because of the LLM.

Input is structured JSON only. The model is told not to diagnose or advise on
treatment; the disclaimer is fixed text added here, never generated. This stage
is skipped entirely when signal quality is too low (the scan is rejected first).
"""

from __future__ import annotations

import logging
import os
import re
from dataclasses import dataclass
from typing import List

import httpx

from . import risk
from .risk import AssessmentOut
from .vitals import VitalsEstimate

log = logging.getLogger("pulsepal.reasoning")

DISCLAIMER = ("This is a screening check from a phone camera, not a medical diagnosis, and it "
              "can miss problems. If you feel unwell, or have chest pain or trouble breathing, "
              "contact a doctor or emergency services.")

SYSTEM_PROMPT = """You write one short explanation of a health screening result for a member of the public.
Rules:
- Use ONLY the facts given. Do not add numbers, causes or advice.
- If a reading scores points, it is outside the normal band: never call it normal.
- Never diagnose, never name a condition, never mention medication.
- Plain, calm words. At most 2 sentences, under 45 words.
Reply with the explanation text only."""

_LEVEL_WORDS = {
    "no_urgent_flags": "no urgent flags",
    "watch": "worth a re-check",
    "seek_advice": "seek medical advice",
}
_BANNED = ("diagnos", "disease", "medication", "medicine", "tachycard", "bradycard",
           "arrhythm", "infection", "fever", "hypox", "covid", "heart attack")
_CALLS_NORMAL = ("within the normal", "in the normal range", "inside the normal", "is normal",
                 "are normal", "normal range")
_ALL_FINE = ("all normal", "everything is normal", "perfectly", "healthy", "nothing to worry")
_OUTSIDE = ("above", "below", "outside", "higher", "lower", "scores 1", "scores 2", "scores 3",
            "scoring 1", "scoring 2", "scoring 3")
_ITEM_WORDS = {"heart_rate": ("heart", "pulse"), "respiratory_rate": ("breath", "respirat")}

_LEVEL_SUGGESTION = {
    "no_urgent_flags": ("Re-check after resting if you've just exercised or had caffeine. "
                        "Otherwise, no action needed."),
    "watch": ("Rest for five minutes and scan again. If it's still flagged or you feel unwell, "
              "talk to a doctor."),
    "seek_advice": "Please contact a doctor or clinic soon, especially if you feel unwell.",
}


@dataclass
class ReasoningOut:
    summary: str
    factors: List[str]
    suggestion: str
    disclaimer: str
    method: str


def _fmt(x: float) -> str:
    return f"{x:.0f}"


def template(v: VitalsEstimate, a: AssessmentOut) -> ReasoningOut:
    hr, rr = _fmt(v.heart_rate_bpm), _fmt(v.respiratory_rate_bpm)
    flagged = [i for i in a.items if i.points > 0]
    if not flagged:
        summary = (f"Your heart rate ({hr} bpm) and breathing rate ({rr} per minute) both scored "
                   "0 points on NEWS2, so nothing here needs urgent attention.")
    else:
        parts = " and ".join(f"{i.label.lower()} ({_fmt(i.value)} {i.unit.strip('/') if i.unit != '/min' else 'per minute'})"
                             for i in flagged)
        summary = (f"Your {parts} {'is' if len(flagged) == 1 else 'are'} outside the NEWS2 "
                   f"normal band, giving a partial score of {a.partial_news2}.")
    factors = [f"{i.label}: {i.points} point{'s' if i.points != 1 else ''}" for i in a.items]
    return ReasoningOut(summary, factors, _LEVEL_SUGGESTION[a.level], DISCLAIMER, "template")


def _band(key: str):
    return risk.HR_ZERO_BAND if key == "heart_rate" else risk.RR_ZERO_BAND


def _facts(v: VitalsEstimate, a: AssessmentOut) -> str:
    """Spell every conclusion out so a small model only has to rephrase."""
    lines = []
    for i in a.items:
        lo, hi = _band(i.key)
        name = i.label + (" (experimental, from the camera)" if i.key == "respiratory_rate" else "")
        unit = "bpm" if i.unit == "bpm" else "per minute"
        where = ("inside" if i.points == 0 else
                 "above" if i.value > hi else "below")
        lines.append(f"- {name}: {_fmt(i.value)} {unit}. The NEWS2 normal band is "
                     f"{_fmt(lo)}-{_fmt(hi)}. It is {where} the band and scores {i.points} "
                     f"point{'s' if i.points != 1 else ''}.")
    lines.append(f"- Partial NEWS2 score: {a.partial_news2}. Overall result: "
                 f"{_LEVEL_WORDS[a.level]}.")
    lines.append("- Not measured: " + ", ".join(x.lower() for x in a.not_checked) + ".")
    return "Facts:\n" + "\n".join(lines)


def _check(summary: str, v: VitalsEstimate, a: AssessmentOut) -> str:
    """Reject text that contradicts the computed result. Returns the cleaned text."""
    t = " ".join(summary.replace("\n", " ").split()).strip().strip('"').strip()
    low = t.lower()
    if not (10 <= len(t) <= 400):
        raise ValueError(f"bad length {len(t)}")
    if any(w in low for w in _BANNED):
        raise ValueError("mentions a diagnosis or medication")
    if a.level != "no_urgent_flags" and any(w in low for w in _ALL_FINE):
        raise ValueError("calls a flagged result fine")
    flagged = [i.key for i in a.items if i.points > 0]
    for sentence in re.split(r"(?<=[.!?])\s+", low):
        about_flagged = any(w in sentence for k in flagged for w in _ITEM_WORDS.get(k, ()))
        says_normal = any(w in sentence for w in _CALLS_NORMAL)
        says_outside = any(w in sentence for w in _OUTSIDE)
        if about_flagged and says_normal and not says_outside:
            raise ValueError("calls a flagged reading normal")
    allowed = {_fmt(v.heart_rate_bpm), _fmt(v.respiratory_rate_bpm), str(a.partial_news2),
               "0", "1", "2", "3", "7", "51", "90", "12", "20"}
    for n in re.findall(r"\d+", t):
        if n not in allowed:
            raise ValueError(f"invented number {n}")
    return t


def generate(v: VitalsEstimate, a: AssessmentOut, age: int, sex: str) -> ReasoningOut:  # noqa: ARG001
    """Granite writes only the summary sentence. Factors, suggestion and the
    disclaimer always come from code, so the model can't contradict NEWS2."""
    base = template(v, a)
    url = os.environ.get("GRANITE_URL")
    if not url:
        return base
    try:
        resp = httpx.post(
            url,
            headers={"Authorization": f"Bearer {os.environ.get('GRANITE_API_KEY', '')}"},
            json={
                "model": os.environ.get("GRANITE_MODEL", "granite-3.3-2b-instruct"),
                "temperature": 0.1,
                # Bound CPU time on s390x: one or two sentences is ~30-50 tokens.
                "max_tokens": int(os.environ.get("GRANITE_MAX_TOKENS", "70")),
                "messages": [
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": _facts(v, a)},
                ],
            },
            timeout=float(os.environ.get("GRANITE_TIMEOUT_S", "90")),
        )
        resp.raise_for_status()
        text = resp.json()["choices"][0]["message"]["content"]
        summary = _check(text, v, a)
        return ReasoningOut(summary, base.factors, base.suggestion, DISCLAIMER,
                            "granite-3.3-2b-instruct")
    except Exception as exc:  # never fail a scan because the LLM is down or wrong
        log.warning("Granite summary rejected or failed, using template: %s", exc)
        return base
