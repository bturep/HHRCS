"""
HHRCS system metrics logger — periodic metrics + service events JSONL.

Logs to data/system_metrics_YYYY-MM-DD.jsonl, one JSON object per line.
Rotates at midnight UTC. Old files are not deleted.

Public API:
    SystemLogger(detector, hdmi, cam_client, uptime_start)
    .start()                       — kick off 60s metrics thread
    .stop()                        — graceful shutdown
    .log_event(category, details)  — write a service event entry immediately
"""

import json
import logging
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

log = logging.getLogger(__name__)

_DATA_DIR = Path(__file__).parent / "data"


def _ts() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


def _log_path() -> Path:
    date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    return _DATA_DIR / f"system_metrics_{date_str}.jsonl"


def _read_cpu_temp() -> float | None:
    try:
        with open("/sys/class/thermal/thermal_zone0/temp") as f:
            return round(int(f.read().strip()) / 1000.0, 1)
    except Exception:
        return None


class SystemLogger:
    def __init__(self, detector=None, hdmi=None, cam_client=None, uptime_start: float = None):
        self._detector    = detector
        self._hdmi        = hdmi
        self._cam_client  = cam_client
        self._uptime_start = uptime_start if uptime_start is not None else time.time()
        self._stop_evt    = threading.Event()
        self._thread      = None
        self._lock        = threading.Lock()

    def start(self):
        _DATA_DIR.mkdir(exist_ok=True)
        self._thread = threading.Thread(
            target=self._metrics_loop, daemon=True, name="system-logger"
        )
        self._thread.start()

    def stop(self):
        self._stop_evt.set()

    def log_event(self, category: str, details: str):
        try:
            entry = {
                "ts":       _ts(),
                "type":     "event",
                "category": category,
                "details":  details,
            }
            self._append(entry)
        except Exception as e:
            log.debug(f"system_logger.log_event failed: {e}")

    # ── Internal ──────────────────────────────────────────────────────────────

    def _metrics_loop(self):
        while not self._stop_evt.wait(60):
            try:
                self._emit_metrics()
            except Exception as e:
                log.warning(f"system_logger metrics error: {e}")

    def _emit_metrics(self):
        try:
            import psutil
        except ImportError:
            log.warning("psutil not installed — run: pip install psutil --break-system-packages")
            return

        cpu_temp = _read_cpu_temp()
        # interval=0.5 gives a real measurement without blocking long
        cpu_pct  = round(psutil.cpu_percent(interval=0.5), 1)
        ram      = psutil.virtual_memory()
        ram_pct       = round(ram.percent, 1)
        ram_mb_used   = ram.used  // (1024 * 1024)
        ram_mb_total  = ram.total // (1024 * 1024)

        # Storage — delegate to storage_monitor so we share its df logic
        ssd_free_gb  = None
        ssd_used_pct = None
        try:
            import storage_monitor
            storage      = storage_monitor.get_storage_stats()
            ssd_free_gb  = storage.get("free_gb")
            ssd_used_pct = storage.get("used_pct")
        except Exception:
            pass

        uptime_s = int(time.time() - self._uptime_start)

        detector_fps   = None
        yolo_running   = False
        cam_reachable  = False
        hdmi_reachable = False

        try:
            if self._detector is not None:
                fps = self._detector.get_fps_actual()
                detector_fps = round(fps, 2) if fps is not None else None
                yolo_running = bool(
                    self._detector._thread and self._detector._thread.is_alive()
                )
        except Exception:
            pass

        try:
            if self._cam_client is not None:
                cam_reachable = bool(self._cam_client.is_reachable())
        except Exception:
            pass

        try:
            if self._hdmi is not None:
                hdmi_reachable = bool(self._hdmi.is_open())
        except Exception:
            pass

        entry = {
            "ts":            _ts(),
            "type":          "metrics",
            "cpu_temp_c":    cpu_temp,
            "cpu_pct":       cpu_pct,
            "ram_pct":       ram_pct,
            "ram_mb_used":   ram_mb_used,
            "ram_mb_total":  ram_mb_total,
            "ssd_free_gb":   ssd_free_gb,
            "ssd_used_pct":  ssd_used_pct,
            "detector_fps":  detector_fps,
            "yolo_running":  yolo_running,
            "cam_reachable": cam_reachable,
            "hdmi_reachable": hdmi_reachable,
            "uptime_s":      uptime_s,
        }
        self._append(entry)

    def _append(self, entry: dict):
        path = _log_path()
        with self._lock:
            with open(path, "a") as f:
                f.write(json.dumps(entry, default=str) + "\n")
