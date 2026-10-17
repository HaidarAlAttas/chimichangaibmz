"""
PulsePal - IBM LinuxONE (s390x) ingest gateway.

    GET  /api/v1/health
    POST /api/v1/scans          RGB traces + age/sex  -> 202 {scan_id}
    GET  /api/v1/scans/{id}     poll: status, current stage, result

Auth: set PULSEPAL_API_KEY to require `Authorization: Bearer <key>` on /scans.
Run:  uvicorn main:app --host 0.0.0.0 --port 8000
      (behind TLS in production: --ssl-keyfile/--ssl-certfile or a proxy)
"""

from __future__ import annotations

import hmac
import os
import platform
from datetime import datetime, timezone

from fastapi import BackgroundTasks, Depends, FastAPI, Header, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware

from pipeline import runner
from schemas import ScanAccepted, ScanRequest, ScanState
from store import ScanStore

API_VERSION = "1.1.0"
MAX_BODY_BYTES = 2_000_000  # 30 s x 30 fps x 4 floats is ~60 kB; leave headroom

app = FastAPI(title="PulsePal - LinuxONE core", version=API_VERSION)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["GET", "POST"],
                   allow_headers=["Authorization", "Content-Type"])
store = ScanStore()


def require_key(authorization: str | None = Header(default=None)) -> None:
    key = os.environ.get("PULSEPAL_API_KEY")
    if not key:
        return
    token = (authorization or "").removeprefix("Bearer ").strip()
    if not hmac.compare_digest(token, key):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid or missing API key")


@app.middleware("http")
async def limit_body(request: Request, call_next):
    length = request.headers.get("content-length")
    if length and int(length) > MAX_BODY_BYTES:
        from fastapi.responses import JSONResponse
        return JSONResponse({"detail": "Payload too large"}, status_code=413)
    return await call_next(request)


@app.get("/api/v1/health")
def health():
    return {
        "status": "online",
        "api_version": API_VERSION,
        "arch": platform.machine(),          # "s390x" on LinuxONE
        "auth_required": bool(os.environ.get("PULSEPAL_API_KEY")),
        "models": {
            "vitals": runner._vitals_model.__class__.__name__,
            "flags": "news2-partial",
            "reasoning": "granite" if os.environ.get("GRANITE_URL") else "template-fallback",
        },
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.post("/api/v1/scans", response_model=ScanAccepted, status_code=202,
          dependencies=[Depends(require_key)])
def create_scan(req: ScanRequest, background: BackgroundTasks):
    state = store.create()
    background.add_task(runner.process, state.scan_id, req, store)
    return ScanAccepted(scan_id=state.scan_id, status=state.status,
                        poll_url=f"/api/v1/scans/{state.scan_id}")


@app.get("/api/v1/scans/{scan_id}", response_model=ScanState,
         dependencies=[Depends(require_key)])
def get_scan(scan_id: str):
    state = store.get(scan_id)
    if state is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Scan not found")
    return state


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8000")))
