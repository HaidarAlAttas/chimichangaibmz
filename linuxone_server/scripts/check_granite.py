"""
Smoke test for the Granite explanation step.

    cd linuxone_server
    GRANITE_URL=http://127.0.0.1:8081/v1/chat/completions python3 scripts/check_granite.py

Runs three sample results (normal, watch, seek advice) through the same code
the API uses and prints what the app would show, how long Granite took, and
whether it fell back to the template.
"""

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from pipeline import reasoning, risk  # noqa: E402
from pipeline.vitals import VitalsEstimate  # noqa: E402

if not os.environ.get("GRANITE_URL"):
    sys.exit("Set GRANITE_URL first, e.g. http://127.0.0.1:8081/v1/chat/completions")

cases = [("normal", VitalsEstimate(72, 15, "check")),
         ("watch", VitalsEstimate(98, 22, "check")),
         ("seek advice", VitalsEstimate(138, 16, "check"))]

ok = True
for name, v in cases:
    a = risk.assess(v)
    t0 = time.time()
    out = reasoning.generate(v, a, age=34, sex="female")
    dt = time.time() - t0
    used = "GRANITE" if out.method.startswith("granite") else "TEMPLATE (fallback)"
    ok &= out.method.startswith("granite")
    print(f"\n--- {name}: level={a.level}, NEWS2={a.partial_news2} | {used} in {dt:.1f}s")
    print("summary:   ", out.summary)
    print("factors:   ", out.factors)
    print("suggestion:", out.suggestion)

print("\nAll three used Granite." if ok else
      "\nAt least one fell back to the template - check llama-server is running and "
      "GRANITE_URL is right; slow answers may need a higher GRANITE_TIMEOUT_S.")
sys.exit(0 if ok else 1)
