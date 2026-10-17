"""
Stage 5 - Plain-language explanation.

Default is a fixed template built from the computed numbers (always available).
Granite 3 8B Instruct is optional (stretch goal): set GRANITE_URL to an
OpenAI-compatible /v1/chat/completions endpoint (vLLM, Ollama, watsonx gateway).
Any failure falls back to the template so a scan never fails because of the LLM.

Input is structured JSON only. The model is told not to diagnose or advise on
treatment; the disclaimer is fixed text added here, never generated. This stage
is skipped entirely when signal quality is too low (the scan is rejected first).
"""

from __future__ import annotations

import json
import logging
import os
from dataclasses import asdict, dataclass
from typing import List

import httpx

from .risk import AssessmentOut
from .vitals import VitalsEstimate

log = logging.getLogger("pulsepal.reasoning")

DISCLAIMER = ("This is a screening check from a phone camera, not a medical diagnosis, and it "
              "can miss problems. If you feel unwell, or have chest pain or trouble breathing, "
              "contact a doctor or emergency services.")

SYSTEM_PROMPT = """You explain a contactless screening result to a member of the public.
Rules:
- Plain, calm language. Short sentences. No jargon.
- Never diagnose, never name a disease, never mention medication or treatment.
- Only use the numbers given. Do not invent measurements. Blood oxygen was NOT measured.
- Breathing rate from a camera is experimental; say so if you mention it.
Reply with JSON only: {"summary": str (max 2 sentences), "factors": [str, max 3 items, each under 10 words], "suggestion": str (1 sentence)}"""

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


def _facts(v: VitalsEstimate, a: AssessmentOut, age: int, sex: str) -> dict:
    return {
        "person": {"age": age, "sex": sex},
        "measured": {"heart_rate_bpm": v.heart_rate_bpm,
                     "respiratory_rate_per_min_experimental": v.respiratory_rate_bpm},
        "not_measured": a.not_checked,
        "news2_partial": {"level": a.level, "score": a.partial_news2,
                          "items": [asdict(i) for i in a.items]},
    }


def generate(v: VitalsEstimate, a: AssessmentOut, age: int, sex: str) -> ReasoningOut:
    url = os.environ.get("GRANITE_URL")
    if not url:
        return template(v, a)
    try:
        resp = httpx.post(
            url,
            headers={"Authorization": f"Bearer {os.environ.get('GRANITE_API_KEY', '')}"},
            json={
                "model": os.environ.get("GRANITE_MODEL", "ibm-granite/granite-3.0-8b-instruct"),
                "temperature": 0.2,
                "messages": [
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": json.dumps(_facts(v, a, age, sex))},
                ],
            },
            timeout=float(os.environ.get("GRANITE_TIMEOUT_S", "20")),
        )
        resp.raise_for_status()
        text = resp.json()["choices"][0]["message"]["content"].strip()
        data = json.loads(text[text.find("{"): text.rfind("}") + 1])
        summary = str(data["summary"]).strip()
        if not summary:
            raise ValueError("empty summary")
        factors = [str(x).strip() for x in data.get("factors", [])][:3]
        # The suggestion follows the NEWS2 level, never the LLM, so the
        # model can't downplay a flagged result.
        return ReasoningOut(summary, factors, _LEVEL_SUGGESTION[a.level], DISCLAIMER,
                            "granite-3-8b-instruct")
    except Exception as exc:  # never fail a scan because the LLM is down
        log.warning("Granite call failed, using template: %s", exc)
        return template(v, a)
