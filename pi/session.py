import json
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import List, Optional
from config import config

SESSION_LOG_PATH = Path(__file__).parent / "data" / "sessions.json"
AGENT_LOG_PATH = Path(__file__).parent / "data" / "agent_log.json"
FIELD_NOTES_PATH = Path(__file__).parent / "data" / "field_notes.json"

def _load_json(path: Path) -> list:
    if path.exists():
        try:
            return json.loads(path.read_text())
        except Exception:
            return []
    return []

def _save_json(path: Path, data: list):
    path.write_text(json.dumps(data, indent=2))


# ── Session log ──────────────────────────────────────────────────────────────

def log_session(trigger_type: str, duration_seconds: float, lux_start: float,
                iso: int, nd: str, files: int, braw_filename: Optional[str] = None):
    sessions = _load_json(SESSION_LOG_PATH)
    entry = {
        "id": str(uuid.uuid4()),
        "timestamp": datetime.now().isoformat(),
        "trigger_type": trigger_type,
        "duration_seconds": round(duration_seconds),
        "lux_start": lux_start,
        "iso": iso,
        "nd_filter": nd,
        "files": files,
        "braw_filename": braw_filename,
        "deployment": config.deployment_name,
        "position": config.position_name,
    }
    sessions.insert(0, entry)
    _save_json(SESSION_LOG_PATH, sessions[:200])
    return entry

def get_sessions(limit: int = 50) -> list:
    return _load_json(SESSION_LOG_PATH)[:limit]


# ── Agent log ─────────────────────────────────────────────────────────────────

def log_agent_entry(entry_type: str, content: str, data: Optional[dict] = None):
    """Types: observation, anomaly, window_summary, alert, inference"""
    entries = _load_json(AGENT_LOG_PATH)
    entry = {
        "id": str(uuid.uuid4()),
        "timestamp": datetime.now().isoformat(),
        "type": entry_type,
        "source": "pi_agent",
        "content": content,
        "data": data or {},
    }
    entries.insert(0, entry)
    _save_json(AGENT_LOG_PATH, entries[:500])
    return entry

def get_agent_log(limit: int = 50) -> list:
    return _load_json(AGENT_LOG_PATH)[:limit]


# ── Field notes ───────────────────────────────────────────────────────────────

def save_field_note(author: str, text: str, system_state: Optional[dict] = None):
    notes = _load_json(FIELD_NOTES_PATH)
    note = {
        "id": str(uuid.uuid4()),
        "timestamp": datetime.now().isoformat(),
        "author": author,
        "text": text,
        "deployment": config.deployment_name,
        "position": config.position_name,
        "system_state": system_state or {},
    }
    notes.insert(0, note)
    _save_json(FIELD_NOTES_PATH, notes[:500])
    return note

def get_field_notes(limit: int = 50) -> list:
    return _load_json(FIELD_NOTES_PATH)[:limit]
