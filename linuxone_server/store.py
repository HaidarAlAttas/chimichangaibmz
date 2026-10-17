"""Scan store.

In-memory for the demo. TODO: back this with PostgreSQL (encrypted at rest)
per the architecture: table `scans(id, created_at, status, stage, result_json,
rejection_json, error)` plus an append-only `audit_log`. RGB traces are only
held while a scan is processing and are never persisted; no video exists.
"""

from __future__ import annotations

import threading
import uuid
from datetime import datetime, timezone
from typing import Dict, Optional

from schemas import ScanState, ScanStatus, Stage


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class ScanStore:
    def __init__(self, max_items: int = 500) -> None:
        self._items: Dict[str, ScanState] = {}
        self._lock = threading.Lock()
        self._max = max_items

    def create(self) -> ScanState:
        now = _now()
        state = ScanState(scan_id=uuid.uuid4().hex, status=ScanStatus.queued,
                          stage=Stage.ingest, created_at=now, updated_at=now)
        with self._lock:
            if len(self._items) >= self._max:  # drop the oldest
                self._items.pop(next(iter(self._items)))
            self._items[state.scan_id] = state
        return state

    def get(self, scan_id: str) -> Optional[ScanState]:
        with self._lock:
            s = self._items.get(scan_id)
            return s.model_copy(deep=True) if s else None

    def update(self, scan_id: str, **fields) -> None:
        with self._lock:
            s = self._items.get(scan_id)
            if s is None:
                return
            self._items[scan_id] = s.model_copy(update={**fields, "updated_at": _now()})
