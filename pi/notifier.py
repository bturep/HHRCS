"""
HHRCS ntfy.sh Layer 2 notifier — push alerts for actionable system conditions.

In-memory dedup state intentionally resets on service restart.

Public API:
    start()                             — backward-compat no-op
    send_alert(title, body, ...)        — one-shot send (used by /notifier/test)
    evaluate_and_notify(summary: dict)  — condition checks with 6-hour dedup
"""

import logging
import threading
import time

import requests

from config import NTFY_TOPIC, NTFY_BASE_URL, NOTIFIER_DEDUP_HOURS

log = logging.getLogger(__name__)

_DEDUP_SECONDS = NOTIFIER_DEDUP_HOURS * 3600
_lock = threading.Lock()
_last_sent: dict = {}  # condition_key -> monotonic seconds

_PRIORITY_MAP = {"min": 1, "low": 2, "default": 3, "high": 4, "urgent": 5}


# ── Public API ─────────────────────────────────────────────────────────────────

def start():
    """Backward-compat no-op — driven by evaluate_and_notify from passive scheduler."""
    pass


def send_alert(title: str, body: str, priority: str = "default", tags: list = None) -> bool:
    """Send one ntfy.sh alert via JSON API (handles Unicode titles). Returns True on HTTP 2xx."""
    try:
        payload = {
            "topic":    NTFY_TOPIC,
            "title":    title,
            "message":  body,
            "priority": _PRIORITY_MAP.get(priority, 3),
        }
        if tags:
            payload["tags"] = tags
        r = requests.post(
            NTFY_BASE_URL,
            json=payload,
            timeout=10,
        )
        r.raise_for_status()
        log.info(f"ntfy sent: {title!r}")
        return True
    except Exception as e:
        log.warning(f"ntfy send_alert failed: {e}")
        return False


def evaluate_and_notify(summary: dict) -> list:
    """Check summary for alert conditions; fire ntfy.sh if past 6-hour dedup window.
    Returns list of condition keys that fired."""
    now = time.monotonic()
    fired = []
    for key, title, body, priority, tags in _build_checks(summary):
        if _is_due(key, now):
            if send_alert(title, body, priority=priority, tags=tags):
                with _lock:
                    _last_sent[key] = now
                fired.append(key)
    return fired


# ── Internals ─────────────────────────────────────────────────────────────────

def _is_due(key: str, now: float) -> bool:
    with _lock:
        last = _last_sent.get(key)
    return last is None or (now - last) >= _DEDUP_SECONDS


def _build_checks(summary: dict) -> list:
    """Return [(key, title, body, priority, tags)] for all active alert conditions."""
    checks = []

    # Camera REST API unreachable
    if not summary.get("cam_reachable", True):
        checks.append((
            "cam_unreachable",
            "HHRCS — Camera Offline",
            "BMPCC REST API not reachable at 192.168.10.2.",
            "high",
            ["warning", "movie_camera"],
        ))

    # SSD storage — prefer burn-rate days estimate, fall back to used %
    storage        = summary.get("storage") or {}
    days_remaining = storage.get("days_remaining")
    used_pct       = storage.get("used_pct")
    free_gb        = storage.get("free_gb")

    if days_remaining is not None and days_remaining < 3:
        checks.append((
            "ssd_critical",
            "HHRCS — SSD Critical",
            f"~{days_remaining:.1f} days remaining at current burn rate ({free_gb} GB free).",
            "urgent",
            ["rotating_light", "floppy_disk"],
        ))
    elif days_remaining is not None and days_remaining < 7:
        checks.append((
            "ssd_warning",
            "HHRCS — SSD Low",
            f"~{days_remaining:.1f} days remaining at current burn rate ({free_gb} GB free).",
            "high",
            ["warning", "floppy_disk"],
        ))
    elif used_pct is not None and used_pct >= 90:
        checks.append((
            "ssd_high",
            "HHRCS — SSD Nearly Full",
            f"SSD {used_pct:.0f}% full ({free_gb} GB free).",
            "high",
            ["warning", "floppy_disk"],
        ))

    # YOLO detector thread not alive
    if not summary.get("yolo_running", True):
        checks.append((
            "yolo_down",
            "HHRCS — Detector Down",
            "MegaDetectorLite inference thread is not running.",
            "high",
            ["warning", "eye"],
        ))

    # Pi CPU temperature — two tiers: warning >65°C, critical >80°C (test uses 85°C / 70°C)
    cpu_temp = summary.get("cpu_temp_c")
    if cpu_temp is not None and cpu_temp > 80:
        checks.append((
            "cpu_temp_high",
            "HHRCS — High CPU Temp",
            f"Pi CPU is {cpu_temp:.1f}°C. Throttling imminent.",
            "high",
            ["thermometer", "warning"],
        ))
    elif cpu_temp is not None and cpu_temp > 65:
        checks.append((
            "cpu_temp_warning",
            "HHRCS — CPU Warming",
            f"Pi CPU is {cpu_temp:.1f}°C (above 65°C warning threshold).",
            "default",
            ["thermometer"],
        ))

    return checks
