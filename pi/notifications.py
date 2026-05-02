"""
HHRCS Layer 1 notification queue.
Persists to data/notifications.json (newest first, capped at NOTIFICATIONS_MAX_STORED).
Thread-safe via a module-level lock.
"""

import json
import threading
import uuid
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from pathlib import Path

from config import NOTIFICATIONS_MAX_STORED

_DATA_FILE = Path(__file__).parent / "data" / "notifications.json"
_lock = threading.Lock()


@dataclass
class Notification:
    id: str
    timestamp: str
    type: str
    title: str
    body: str
    deployment_id: str
    read: bool = False


def _load() -> list:
    try:
        if _DATA_FILE.exists():
            with open(_DATA_FILE) as f:
                return json.load(f)
    except Exception:
        pass
    return []


def _save(items: list) -> None:
    _DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(_DATA_FILE, "w") as f:
        json.dump(items, f)


def emit(type_: str, title: str, body: str) -> None:
    """Non-blocking. Never raises."""
    try:
        from deployment import get_active_deployment
        dep = get_active_deployment()
        dep_id = dep["id"] if dep else ""
        n = Notification(
            id=str(uuid.uuid4()),
            timestamp=datetime.now(timezone.utc).isoformat(),
            type=type_,
            title=title,
            body=body,
            deployment_id=dep_id,
        )
        d = asdict(n)
        with _lock:
            items = _load()
            items.insert(0, d)
            del items[NOTIFICATIONS_MAX_STORED:]
            _save(items)
    except Exception:
        pass


def unread() -> list:
    """Return all unread notifications, newest first."""
    with _lock:
        items = _load()
    return [n for n in items if not n.get("read", False)]


def mark_read(ids: list) -> int:
    """Set read=True for given ids. Returns count marked."""
    id_set = set(ids)
    with _lock:
        items = _load()
        count = 0
        for n in items:
            if n.get("id") in id_set and not n.get("read", False):
                n["read"] = True
                count += 1
        _save(items)
    return count


def recent(limit: int = 50) -> list:
    """Return up to limit notifications, newest first, regardless of read state."""
    with _lock:
        items = _load()
    return items[:limit]
