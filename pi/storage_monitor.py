"""
HHRCS Storage Monitor — SSD burn-rate tracking and days-remaining estimation.

Public API:
    get_storage_stats() -> dict  — never raises
"""

import json
import logging
import subprocess
import time
from datetime import date
from pathlib import Path

from config import config

log = logging.getLogger(__name__)

_DATA_DIR      = Path(__file__).parent / "data"
_SNAP_PATH     = _DATA_DIR / "storage_snapshots.json"
_MAX_SNAPSHOTS = 7

_EMPTY = {
    "free_gb": None, "total_gb": None, "used_pct": None,
    "days_remaining": None, "burn_rate_gb_per_day": None, "snapshots": [],
}


# ── Public API ─────────────────────────────────────────────────────────────────

def get_storage_stats() -> dict:
    """Return SSD storage statistics. Never raises."""
    try:
        free_bytes, total_bytes = _read_df()
        if free_bytes is None or total_bytes is None or total_bytes == 0:
            return _EMPTY

        free_gb   = round(free_bytes  / 1e9, 1)
        total_gb  = round(total_bytes / 1e9, 1)
        used_pct  = round((total_bytes - free_bytes) / total_bytes * 100, 1)
        used_bytes = total_bytes - free_bytes

        snapshots = _load_snapshots()
        snapshots = _update_snapshots(snapshots, used_bytes)
        _save_snapshots(snapshots)

        burn_rate, days_remaining = _compute_burn_rate(snapshots, free_bytes)

        return {
            "free_gb":              free_gb,
            "total_gb":             total_gb,
            "used_pct":             used_pct,
            "days_remaining":       days_remaining,
            "burn_rate_gb_per_day": burn_rate,
            "snapshots":            snapshots[:3],
        }
    except Exception as e:
        log.warning(f"storage_monitor: get_storage_stats failed: {e}")
        return dict(_EMPTY)


# ── Internals ─────────────────────────────────────────────────────────────────

def _read_df():
    """Return (free_bytes, total_bytes) from the SSD mount. Falls back through candidates."""
    import glob
    candidates = [config.ssd_mount]
    candidates += sorted(glob.glob("/media/pi/*"))
    candidates.append("/")

    for mount in candidates:
        try:
            r = subprocess.run(
                ["df", "-B1", mount],
                capture_output=True, text=True, timeout=5,
            )
            lines = r.stdout.strip().splitlines()
            if len(lines) < 2:
                continue
            # df -B1 columns: Filesystem 1B-blocks Used Available Use% Mounted
            parts = lines[1].split()
            if len(parts) < 4:
                continue
            total_bytes = int(parts[1])
            avail_bytes = int(parts[3])
            if total_bytes > 0:
                return avail_bytes, total_bytes
        except Exception:
            continue
    return None, None


def _load_snapshots() -> list:
    if not _SNAP_PATH.exists():
        return []
    try:
        content = _SNAP_PATH.read_text().strip()
        if not content:
            return []
        return json.loads(content)
    except json.JSONDecodeError as e:
        log.warning(f"storage_monitor: snapshots file corrupted, resetting: {e}")
        try:
            corrupt = _SNAP_PATH.with_name(f"{_SNAP_PATH.name}.corrupt.{int(time.time())}")
            _SNAP_PATH.rename(corrupt)
        except OSError:
            pass
        return []
    except OSError as e:
        log.warning(f"storage_monitor: load snapshots failed: {e}")
        return []


def _save_snapshots(snapshots: list):
    try:
        _DATA_DIR.mkdir(parents=True, exist_ok=True)
        _SNAP_PATH.write_text(json.dumps(snapshots, indent=2))
    except Exception as e:
        log.warning(f"storage_monitor: save snapshots failed: {e}")


def _update_snapshots(snapshots: list, used_bytes: int) -> list:
    today = date.today().isoformat()
    if snapshots and snapshots[0].get("date") == today:
        snapshots[0]["used_bytes"] = used_bytes
        return snapshots
    new_snap = {"date": today, "used_bytes": used_bytes}
    return ([new_snap] + snapshots)[:_MAX_SNAPSHOTS]


def _compute_burn_rate(snapshots: list, free_bytes: int):
    """Return (burn_rate_gb_per_day, days_remaining) or (None, None) if < 2 snapshots."""
    pts = snapshots[:3]
    if len(pts) < 2:
        return None, None
    try:
        oldest = pts[-1]
        newest = pts[0]
        d0 = date.fromisoformat(oldest["date"])
        d1 = date.fromisoformat(newest["date"])
        days_elapsed = (d1 - d0).days
        if days_elapsed <= 0:
            return None, None
        bytes_delta = newest["used_bytes"] - oldest["used_bytes"]
        if bytes_delta <= 0:
            return None, None
        bytes_per_day  = bytes_delta / days_elapsed
        burn_rate_gb   = round(bytes_per_day / 1e9, 1)
        days_remaining = round(free_bytes / bytes_per_day, 1)
        return burn_rate_gb, days_remaining
    except Exception as e:
        log.warning(f"storage_monitor: burn rate calc failed: {e}")
        return None, None
