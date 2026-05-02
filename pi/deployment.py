"""
HHRCS Deployment — metadata tracker for field deployments.
"""

import json
import os
import threading
from datetime import datetime, timezone

_HHRCS_DIR       = os.path.dirname(os.path.abspath(__file__))
_DATA_DIR        = os.path.join(_HHRCS_DIR, "data")
_DEPLOYMENTS_DIR = os.path.join(_HHRCS_DIR, "deployments")
_DEPLOYMENT_PATH = os.path.join(_DATA_DIR, "deployments.json")
_LOCK            = threading.Lock()


def _read() -> list:
    try:
        with open(_DEPLOYMENT_PATH) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return []


def _save(deployments: list) -> None:
    os.makedirs(_DATA_DIR, exist_ok=True)
    with open(_DEPLOYMENT_PATH, "w") as f:
        json.dump(deployments, f, indent=2)


def _close_active_unlocked(deps: list) -> None:
    """Mark any active deployment closed. Caller must hold _LOCK."""
    now = datetime.now(timezone.utc).isoformat()
    for dep in deps:
        if dep.get("status") == "active":
            dep["status"] = "closed"
            dep["closed_at"] = now


def get_deployments() -> list:
    with _LOCK:
        return _read()


def get_active_deployment() -> dict | None:
    with _LOCK:
        for dep in _read():
            if dep.get("status") == "active":
                return dep
    return None


def open_deployment(name: str, position: str = "", lat=None, lng=None,
                    bearing=None, notes: str = "", app_version: str = "") -> dict:
    with _LOCK:
        deps = _read()
        _close_active_unlocked(deps)   # auto-close any active deployment
        dep_id = datetime.now().strftime("dep_%Y%m%d_%H%M%S")
        new_dep = {
            "id":          dep_id,
            "name":        name,
            "position":    position,
            "lat":         lat,
            "lng":         lng,
            "bearing":     bearing,
            "notes":       notes,
            "app_version": app_version,
            "started_at":  datetime.now(timezone.utc).isoformat(),
            "closed_at":   None,
            "clip_count":  0,
            "status":      "active",
        }
        deps.insert(0, new_dep)
        _save(deps)

    dep_dir = os.path.join(_DEPLOYMENTS_DIR, dep_id)
    os.makedirs(dep_dir, exist_ok=True)
    return new_dep


def close_deployment(notes: str = "") -> dict | None:
    with _LOCK:
        deps = _read()
        for dep in deps:
            if dep.get("status") == "active":
                dep["status"] = "closed"
                dep["closed_at"] = datetime.now(timezone.utc).isoformat()
                if notes:
                    dep["closing_notes"] = notes
                _save(deps)
                return dep
    return None


def increment_clip_count() -> None:
    with _LOCK:
        deps = _read()
        for dep in deps:
            if dep.get("status") == "active":
                dep["clip_count"] = dep.get("clip_count", 0) + 1
                _save(deps)
                return
