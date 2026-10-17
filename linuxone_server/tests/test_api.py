import os
import sys

import numpy as np
import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402
from pipeline import dsp  # noqa: E402

client = TestClient(main.app)


def synth(bpm=72.0, rr=15.0, seconds=30, fps=30, noise=0.002, jitter=True, seed=0):
    """Skin-like RGB traces with a pulse, breathing drift and dropped frames."""
    rng = np.random.default_rng(seed)
    t = np.arange(0, seconds, 1 / fps)
    if jitter:  # drop ~10 % of frames like a real phone
        t = np.sort(rng.choice(t, size=int(len(t) * 0.9), replace=False))
    pulse = np.sin(2 * np.pi * bpm / 60 * t) + 0.3 * np.sin(4 * np.pi * bpm / 60 * t + 0.7)
    breath = np.sin(2 * np.pi * rr / 60 * t)
    base = np.array([[150.0], [110.0], [90.0]])
    amp = np.array([[0.0015], [0.004], [0.002]])  # green carries most pulse
    rgb = base * (1 + amp * pulse + 0.003 * breath) + rng.normal(0, noise * 100, (3, len(t)))
    return {"t_ms": [int(x * 1000) for x in t], "r": rgb[0].tolist(),
            "g": rgb[1].tolist(), "b": rgb[2].tolist()}


def body(traces, device_sqi=0.92, **kw):
    return {"age": 28, "sex": "male", "fps": 30, "duration_s": 30, "traces": traces,
            "device_sqi": device_sqi, "source": "camera", **kw}


def test_health():
    r = client.get("/api/v1/health")
    assert r.status_code == 200 and r.json()["status"] == "online"


@pytest.mark.parametrize("bpm", [55, 72, 110])
def test_dsp_recovers_heart_rate(bpm):
    tr = synth(bpm=bpm)
    d = dsp.run(tr["t_ms"], tr["r"], tr["g"], tr["b"])
    assert abs(d.peak_hz * 60 - bpm) < 3
    assert d.sqi > 0.7


def test_dsp_low_sqi_for_noise():
    rng = np.random.default_rng(1)
    t = list(range(0, 30000, 33))
    n = len(t)
    d = dsp.run(t, (150 + rng.normal(0, 2, n)).tolist(), (110 + rng.normal(0, 2, n)).tolist(),
                (90 + rng.normal(0, 2, n)).tolist())
    assert d.sqi < 0.45


def test_full_scan_flow():
    r = client.post("/api/v1/scans", json=body(synth(bpm=74)))
    assert r.status_code == 202
    scan_id = r.json()["scan_id"]
    s = client.get(f"/api/v1/scans/{scan_id}").json()  # TestClient runs background tasks
    assert s["status"] == "done", s
    res = s["result"]
    assert abs(res["vitals"]["heart_rate_bpm"] - 74) < 3
    assert abs(res["vitals"]["respiratory_rate_bpm"] - 15) < 2
    assert res["vitals"]["spo2_pct"] is None
    assert res["vitals"]["spo2_source"] == "not_measured"
    assert res["assessment"]["level"] == "no_urgent_flags"
    assert res["assessment"]["partial_news2"] == 0
    assert res["assessment"]["checks_used"] == 2
    assert "Blood oxygen" in res["assessment"]["not_checked"]
    assert res["reasoning"]["disclaimer"]
    assert res["is_demo"] is False
    assert "confidence" not in str(res).lower()


def test_simulated_source_is_marked_demo():
    r = client.post("/api/v1/scans", json=body(synth(), source="simulated"))
    s = client.get(f"/api/v1/scans/{r.json()['scan_id']}").json()
    assert s["result"]["is_demo"] is True


def test_noisy_scan_is_rejected_without_numbers():
    rng = np.random.default_rng(2)
    t = list(range(0, 30000, 33))
    n = len(t)
    tr = {"t_ms": t, "r": (150 + rng.normal(0, 3, n)).tolist(),
          "g": (110 + rng.normal(0, 3, n)).tolist(), "b": (90 + rng.normal(0, 3, n)).tolist()}
    r = client.post("/api/v1/scans", json=body(tr, device_sqi=0.4))
    s = client.get(f"/api/v1/scans/{r.json()['scan_id']}").json()
    assert s["status"] == "rejected"
    assert s["result"] is None
    assert "motion" in s["rejection"]["reasons"]


@pytest.mark.parametrize("bpm,level,pts", [(98, "watch", 1), (120, "watch", 2), (135, "seek_advice", 3)])
def test_news2_heart_rate_bands(bpm, level, pts):
    r = client.post("/api/v1/scans", json=body(synth(bpm=bpm)))
    a = client.get(f"/api/v1/scans/{r.json()['scan_id']}").json()["result"]["assessment"]
    hr = next(i for i in a["items"] if i["key"] == "heart_rate")
    assert hr["points"] == pts
    assert a["level"] == level


def test_news2_point_boundaries():
    from pipeline import risk
    assert [risk.points(x, risk.HR_BANDS) for x in (40, 41, 50, 51, 90, 91, 110, 111, 130, 131)] \
        == [3, 1, 1, 0, 0, 1, 1, 2, 2, 3]
    assert [risk.points(x, risk.RR_BANDS) for x in (8, 9, 11, 12, 20, 21, 24, 25)] \
        == [3, 1, 1, 0, 0, 2, 2, 3]


def test_minors_rejected():
    assert client.post("/api/v1/scans", json={**body(synth()), "age": 16}).status_code == 422


def test_validation_rejects_mismatched_lengths():
    tr = synth()
    tr["g"] = tr["g"][:-5]
    assert client.post("/api/v1/scans", json=body(tr)).status_code == 422


def test_api_key_enforced(monkeypatch):
    monkeypatch.setenv("PULSEPAL_API_KEY", "secret")
    assert client.post("/api/v1/scans", json=body(synth())).status_code == 401
    ok = client.post("/api/v1/scans", json=body(synth()),
                     headers={"Authorization": "Bearer secret"})
    assert ok.status_code == 202


def test_unknown_scan_404():
    assert client.get("/api/v1/scans/nope").status_code == 404


def test_granite_failure_falls_back_to_template(monkeypatch):
    import httpx
    from pipeline import reasoning, risk
    from pipeline.vitals import VitalsEstimate

    def boom(*a, **k):
        raise httpx.ConnectError("down")

    monkeypatch.setenv("GRANITE_URL", "http://granite.invalid/v1/chat/completions")
    monkeypatch.setattr(reasoning.httpx, "post", boom)
    v = VitalsEstimate(118, 22, "test")
    out = reasoning.generate(v, risk.assess(v), 40, "female")
    assert out.method == "template"
    assert "outside the NEWS2" in out.summary


def _fake_granite(monkeypatch, text):
    from pipeline import reasoning

    class R:
        def raise_for_status(self): pass
        def json(self): return {"choices": [{"message": {"content": text}}]}

    monkeypatch.setenv("GRANITE_URL", "http://granite.local")
    monkeypatch.setattr(reasoning.httpx, "post", lambda *a, **k: R())


def test_granite_writes_summary_only(monkeypatch):
    from pipeline import reasoning, risk
    from pipeline.vitals import VitalsEstimate
    _fake_granite(monkeypatch, "Your heart rate of 140 bpm is above the NEWS2 band and scores 3 points.")
    v = VitalsEstimate(140, 16, "test")
    out = reasoning.generate(v, risk.assess(v), 40, "male")
    assert out.method.startswith("granite")
    assert out.suggestion.startswith("Please contact a doctor")   # from code, not LLM
    assert out.factors == reasoning.template(v, risk.assess(v)).factors


def test_real_granite_answer_is_accepted(monkeypatch):
    from pipeline import reasoning, risk
    from pipeline.vitals import VitalsEstimate
    real = ("Your heart rate is slightly above the normal range, scoring 1 point. Your breathing "
            "rate is within the normal range, scoring 0 points. Given these findings, a re-check "
            "is recommended.")   # Granite 3.3 2B Q4_K_M on LinuxONE, 2026-10-18
    _fake_granite(monkeypatch, real)
    v = VitalsEstimate(98, 16, "test")
    out = reasoning.generate(v, risk.assess(v), 40, "male")
    assert out.method.startswith("granite") and out.summary == real


@pytest.mark.parametrize("text", [
    "The heart rate is within the normal range at 98 beats per minute.",   # real 2B output
    "Your pulse of 98 suggests tachycardia.",
    "Your heart rate of 98 bpm and oxygen of 95 look fine.",
    "Your pulse is in the normal range and your breathing is fine.",
    "Everything is normal, nothing to worry about.",
    "",
])
def test_bad_granite_text_falls_back(monkeypatch, text):
    from pipeline import reasoning, risk
    from pipeline.vitals import VitalsEstimate
    _fake_granite(monkeypatch, text)
    v = VitalsEstimate(98, 16, "test")
    out = reasoning.generate(v, risk.assess(v), 40, "male")
    assert out.method == "template"

def test_model_input_shape():
    tr = synth()
    x = dsp.model_input(dsp.run(tr["t_ms"], tr["r"], tr["g"], tr["b"]))
    assert x.shape == (1, 2, dsp.MODEL_LEN) and x.dtype == np.float32
