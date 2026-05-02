"""
HHRCS Event Bus — in-process telemetry layer.

Public API
----------
emit(event_type, payload, level="info") -> None
    Append a structured event to the ring buffer. Non-blocking.
    Unknown types are rejected with a warning; bad payloads emit with a warning.

recent(window_seconds=300, types=None) -> list[dict]
    Snapshot of ring-buffer events within the time window, newest last.
    types is an optional list of dotted type strings to filter by.

format_as_log_line(event) -> str
    Render one event as a terse human-readable line for GET /log.

set_session_id(session_id, base_dir=None) -> None
    Update current session. New JSONL file starts in sessions/<id>/events.jsonl,
    or base_dir/events.jsonl if base_dir is provided.
    Ring buffer is NOT cleared — it is system-wide and continuous.
"""

import json
import logging
import threading
import time
from collections import deque
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Optional

logger = logging.getLogger(__name__)

# ── Canonical event type taxonomy ─────────────────────────────────────────────

EVENT_TYPES = frozenset({
    "detector.trigger",
    "state.transition",
    "ble.connected",
    "ble.disconnected",
    "recording.started",
    "recording.stopped",
    "command.sent",
    "command.failed",
    "system.startup",
    "system.error",
})

LEVELS = frozenset({"debug", "info", "warn", "error"})

# Required payload fields per type (soft contract — warns, never blocks)
_REQUIRED: dict = {
    "detector.trigger":  ["confidence", "category", "bbox", "frame_timestamp", "model_version"],
    "state.transition":  ["from_state", "to_state", "reason"],
    "ble.connected":     ["device_name", "address"],
    "ble.disconnected":  ["device_name", "address", "duration_seconds"],
    "recording.started": ["clip_id", "source"],
    "recording.stopped": ["clip_id", "source", "duration_seconds"],
    "command.sent":      ["command", "target"],
    "command.failed":    ["command", "target", "error"],
    "system.startup":    ["subsystem"],
    "system.error":      ["subsystem", "error_type", "message"],
}

# ── Session and path state ─────────────────────────────────────────────────────

_SESSIONS_DIR = Path(__file__).parent / "sessions"

def _default_session_id() -> str:
    return "boot_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")

_current_session_id: str = _default_session_id()
_current_jsonl_path: Optional[Path] = None
_current_base_dir: Optional[Path] = None
_session_lock = threading.Lock()


def set_session_id(session_id: str, base_dir: Optional[Path] = None) -> None:
    """Rotate the on-disk JSONL file to a new session directory."""
    global _current_session_id, _current_jsonl_path, _current_base_dir
    with _session_lock:
        _current_session_id = session_id
        _current_base_dir = base_dir
        _current_jsonl_path = None   # flush thread will open the new path on next write


def _get_jsonl_path() -> Path:
    global _current_jsonl_path
    with _session_lock:
        if _current_jsonl_path is None:
            if _current_base_dir is not None:
                p = _current_base_dir / "events.jsonl"
            else:
                sid = _current_session_id
                p = _SESSIONS_DIR / sid / "events.jsonl"
            p.parent.mkdir(parents=True, exist_ok=True)
            _current_jsonl_path = p
        return _current_jsonl_path


# ── Ring buffer ────────────────────────────────────────────────────────────────

_RING_MAXLEN = 5000
_ring: deque = deque(maxlen=_RING_MAXLEN)
_ring_lock = threading.Lock()

# Track flush position: index of last flushed event count (used to write only new events)
_flush_cursor: int = 0
_flush_lock = threading.Lock()


# ── emit ───────────────────────────────────────────────────────────────────────

def emit(event_type: str, payload: dict, level: str = "info") -> None:
    """Append a structured event. Always returns; never raises."""
    if event_type not in EVENT_TYPES:
        logger.warning(f"[events] Unknown type '{event_type}' — rejected")
        return

    if level not in LEVELS:
        level = "info"

    # Soft payload validation
    required = _REQUIRED.get(event_type, [])
    missing = [f for f in required if f not in payload]
    if missing:
        logger.warning(f"[events] {event_type} payload missing fields: {missing}")

    with _session_lock:
        sid = _current_session_id

    event = {
        "ts": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
        "session_id": sid,
        "type": event_type,
        "level": level,
        "payload": payload,
    }

    with _ring_lock:
        _ring.append(event)


# ── recent ─────────────────────────────────────────────────────────────────────

def recent(
    window_seconds: int = 300,
    types: Optional[List[str]] = None,
) -> List[dict]:
    """Return events from the last window_seconds, newest last."""
    cutoff = time.time() - window_seconds
    with _ring_lock:
        snapshot = list(_ring)

    result = []
    for ev in snapshot:
        try:
            ts = datetime.fromisoformat(ev["ts"]).timestamp()
        except Exception:
            continue
        if ts < cutoff:
            continue
        if types and ev.get("type") not in types:
            continue
        result.append(ev)
    return result   # already oldest-first (deque append order)


# ── format_as_log_line ─────────────────────────────────────────────────────────

_TYPE_LABELS: dict = {
    "detector.trigger":  "TRIGGER",
    "state.transition":  "STATE",
    "ble.connected":     "BLE",
    "ble.disconnected":  "BLE",
    "recording.started": "REC",
    "recording.stopped": "REC",
    "command.sent":      "CMD",
    "command.failed":    "CMD",
    "system.startup":    "SYSTEM",
    "system.error":      "ERROR",
}


def format_as_log_line(event: dict) -> str:
    """
    Render one event as a terse human line for GET /log.

    Format: HH:MM:SS  LABEL     message
    """
    try:
        ts_dt = datetime.fromisoformat(event["ts"]).astimezone()
        ts = ts_dt.strftime("%H:%M:%S")
    except Exception:
        ts = "??:??:??"

    etype = event.get("type", "unknown")
    label = _TYPE_LABELS.get(etype, etype[:7].upper())
    p = event.get("payload", {})
    level = event.get("level", "info")

    msg = _format_payload(etype, p)

    # Annotate warn/error level explicitly; leave info implicit
    if level == "warn":
        msg = f"WARN  {msg}"
    elif level == "error":
        msg = f"ERROR {msg}"

    return f"{ts}  {label:<8s}  {msg}"


def _format_payload(etype: str, p: dict) -> str:
    if etype == "detector.trigger":
        cat  = p.get("category", "?")
        conf = p.get("confidence", 0)
        bbox = p.get("bbox", [])
        if len(bbox) == 4:
            # Render normalized [x1,y1,x2,y2] as integer pixel estimates at 1280×720
            coords = f"[{int(bbox[0]*1280)},{int(bbox[1]*720)},{int(bbox[2]*1280)},{int(bbox[3]*720)}]"
        else:
            coords = str(bbox)
        return f"{cat} ({conf:.2f}) at {coords}"

    if etype == "state.transition":
        frm    = p.get("from_state", "?")
        to     = p.get("to_state", "?")
        reason = p.get("reason", "")
        return f"{frm} → {to}  ({reason})" if reason else f"{frm} → {to}"

    if etype == "ble.connected":
        dev  = p.get("device_name", "?")
        addr = p.get("address", "")
        reconnect = p.get("reconnect_count", 0)
        suffix = f" (reconnect #{reconnect})" if reconnect else ""
        return f"connected  {dev}  {addr}{suffix}"

    if etype == "ble.disconnected":
        dev  = p.get("device_name", "?")
        dur  = p.get("duration_seconds", 0)
        return f"disconnected  {dev}  after {int(dur)}s"

    if etype == "recording.started":
        clip   = p.get("clip_id", "?")
        source = p.get("source", "?")
        return f"start  {clip}  [{source}]"

    if etype == "recording.stopped":
        clip   = p.get("clip_id", "?")
        dur    = p.get("duration_seconds", 0)
        source = p.get("source", "?")
        return f"stop   {clip}  {int(dur)}s  [{source}]"

    if etype == "command.sent":
        cmd    = p.get("command", "?")
        target = p.get("target", "?")
        return f"{cmd}  → {target}"

    if etype == "command.failed":
        cmd   = p.get("command", "?")
        error = p.get("error", "?")
        return f"{cmd} failed ({error})"

    if etype == "system.startup":
        return f"startup  {p.get('subsystem', '?')}"

    if etype == "system.error":
        subsys = p.get("subsystem", "?")
        msg    = p.get("message", "?")
        return f"{subsys}: {msg}"

    # Fallback: dump payload keys
    return "  ".join(f"{k}={v}" for k, v in list(p.items())[:4])


# ── Background JSONL flush ─────────────────────────────────────────────────────

_FLUSH_INTERVAL = 10   # seconds

def _flush_worker() -> None:
    """Write new events to JSONL every _FLUSH_INTERVAL seconds. Never blocks emit."""
    global _flush_cursor
    while True:
        time.sleep(_FLUSH_INTERVAL)
        try:
            with _ring_lock:
                snapshot = list(_ring)

            if not snapshot:
                continue

            path = _get_jsonl_path()
            try:
                path.parent.mkdir(parents=True, exist_ok=True)
                with path.open("a") as fh:
                    for ev in snapshot[_flush_cursor:]:
                        fh.write(json.dumps(ev) + "\n")
                _flush_cursor = len(snapshot)
            except Exception as disk_err:
                # Emit system.error into the ring buffer but never propagate
                _ring.append({
                    "ts": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
                    "session_id": _current_session_id,
                    "type": "system.error",
                    "level": "error",
                    "payload": {
                        "subsystem": "event_bus",
                        "error_type": "flush_failed",
                        "message": str(disk_err),
                    },
                })
        except Exception:
            pass   # silently absorb all errors in flush worker


_flush_thread = threading.Thread(target=_flush_worker, daemon=True, name="events-flush")
_flush_thread.start()
