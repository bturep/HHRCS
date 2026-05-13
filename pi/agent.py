"""
HHRCS Agent — two-tier field intelligence.
Tier 1: rule-based summarizer (no API, always available).
Tier 2: LLM via claude-haiku-4-5-20251001 (requires ANTHROPIC_API_KEY).
Initialized by api_server.py via agent.init(detector, sm, camera).
"""

import os
import json
import subprocess
import threading
import logging
from datetime import datetime, timezone
from typing import Optional

from events import recent as events_recent, format_as_log_line
import sensors as _sensors

log = logging.getLogger(__name__)

def _fmt(v, suffix=""):
    return f"{v}{suffix}" if v is not None else "--"

# Injected by api_server.py after constructing these objects
_detector = None
_sm       = None
_camera   = None

_DATA_DIR       = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
_HHRCS_DIR      = os.path.dirname(os.path.abspath(__file__))
_AGENT_LOG_PATH = os.path.join(_DATA_DIR, "agent_log.json")
_LOG_LOCK       = threading.Lock()
_MAX_ENTRIES    = 200

_CONTEXT_MD_PATH  = os.path.join(_HHRCS_DIR, "CONTEXT.md")
_context_md_text  = ""
_context_md_mtime = 0.0


def _load_context_md() -> str:
    global _context_md_text, _context_md_mtime
    try:
        mtime = os.path.getmtime(_CONTEXT_MD_PATH)
        if mtime != _context_md_mtime:
            with open(_CONTEXT_MD_PATH, encoding="utf-8") as f:
                _context_md_text = f.read()
            _context_md_mtime = mtime
            log.info(f"CONTEXT.md loaded ({len(_context_md_text)} chars)")
    except Exception as e:
        log.warning(f"Could not read CONTEXT.md: {e}")
    return _context_md_text


_load_context_md()


def init(detector, sm, camera):
    global _detector, _sm, _camera
    _detector = detector
    _sm       = sm
    _camera   = camera


# ── Internal helpers ──────────────────────────────────────────────────────────

def _read_log(log_path=None):
    path = log_path or _AGENT_LOG_PATH
    try:
        with open(path) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return []


def _append_log(entry, log_path=None):
    path = log_path or _AGENT_LOG_PATH
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with _LOG_LOCK:
        entries = _read_log(log_path=path)
        entries.append(entry)
        if len(entries) > _MAX_ENTRIES:
            entries = entries[-_MAX_ENTRIES:]
        with open(path, "w") as f:
            json.dump(entries, f, indent=2)


def _cpu_temp() -> Optional[float]:
    try:
        r = subprocess.run(
            ["vcgencmd", "measure_temp"],
            capture_output=True, text=True, timeout=2,
        )
        return float(r.stdout.strip().replace("temp=", "").replace("'C", ""))
    except Exception:
        return None


def _in_recording_window() -> bool:
    try:
        from astral import LocationInfo
        from astral.sun import sun
        import pytz
        from datetime import date, timedelta
        from config import config

        loc = LocationInfo(
            name="Hunter House", region="CA",
            timezone=config.timezone,
            latitude=config.latitude, longitude=config.longitude,
        )
        tz  = pytz.timezone(config.timezone)
        s   = sun(loc.observer, date=date.today(), tzinfo=tz)
        now = datetime.now(tz)

        dawn_open  = s["dawn"]    + timedelta(minutes=config.dawn_offset_minutes)
        dawn_close = s["sunrise"] + timedelta(minutes=config.dawn_close_minutes)
        dusk_open  = s["sunset"]  + timedelta(minutes=config.dusk_open_minutes)
        dusk_close = s["dusk"]    + timedelta(minutes=config.dusk_close_minutes)

        return (dawn_open <= now <= dawn_close) or (dusk_open <= now <= dusk_close)
    except Exception:
        return False


# ── Tier 1 ────────────────────────────────────────────────────────────────────

def build_summary() -> dict:
    """Rule-based summary — no API call, always available."""
    events_24h = events_recent(window_seconds=86400)
    events_1h  = events_recent(window_seconds=3600)

    triggers_24h = [e for e in events_24h if e.get("type") == "detector.trigger"]
    triggers_1h  = [e for e in events_1h  if e.get("type") == "detector.trigger"]

    last_detection      = None
    last_detection_conf = None
    if triggers_24h:
        last = max(triggers_24h, key=lambda e: e.get("ts", ""))
        last_detection      = last.get("ts")
        last_detection_conf = last.get("payload", {}).get("confidence")

    ble_disconnects_1h = [e for e in events_1h if e.get("type") == "ble.disconnected"]
    ble_stable = len(ble_disconnects_1h) == 0

    state_str  = _sm.state.value       if _sm       else "UNKNOWN"
    sim_mode   = not _detector._using_real if _detector else True
    cam_ok     = _camera.connected          if _camera  else False
    cpu_temp   = _cpu_temp()
    in_window  = _in_recording_window()

    try:
        sensor_data  = _sensors.to_dict()
        camera_state = _sensors.get_camera_state()
        ssd_free_gb  = _sensors.read_ssd_free_gb()
        house_tb     = _sensors.read_house_drive_used_tb()
    except Exception:
        sensor_data  = {}
        camera_state = {}
        ssd_free_gb  = None
        house_tb     = None

    # ── Anomalies ─────────────────────────────────────────────────────────────
    anomalies = []

    for e in ble_disconnects_1h:
        ts       = e.get("ts", "")
        duration = e.get("payload", {}).get("duration_seconds")
        hhmm     = ts[11:16] if len(ts) >= 16 else ts
        label    = f"{int(duration)}s" if duration is not None else "?"
        anomalies.append(f"BLE disconnected at {hhmm} ({label})")

    for e in [e for e in events_1h if e.get("type") == "system.error"]:
        ts       = e.get("ts", "")
        hhmm     = ts[11:16] if len(ts) >= 16 else ts
        err_type = e.get("payload", {}).get("error_type", "unknown")
        anomalies.append(f"system.error: {err_type} at {hhmm}")

    if cpu_temp is not None and cpu_temp > 72:
        anomalies.append(f"CPU temp {cpu_temp:.1f}°C")

    if len(triggers_24h) == 0 and in_window:
        anomalies.append("No detections in 24h during active recording window")

    if _sm:
        elapsed = _sm.to_dict().get("elapsed_seconds", 0)
        if state_str in ("HOLDING", "COUNTDOWN") and elapsed > 1200:
            anomalies.append(
                f"State machine stuck in {state_str} for {int(elapsed // 60)}min"
            )

    # ── Summary line ──────────────────────────────────────────────────────────
    parts = []
    n = len(triggers_1h)
    parts.append(
        "No detections in last hour." if n == 0
        else "1 detection in last hour." if n == 1
        else f"{n} detections in last hour."
    )
    parts.append("BLE stable." if ble_stable else f"BLE dropped {len(ble_disconnects_1h)}x in last hour.")
    if in_window:
        parts.append("In recording window.")
    if anomalies:
        parts.append(f"{len(anomalies)} anomal{'y' if len(anomalies) == 1 else 'ies'} flagged.")

    return {
        "detections_1h":             len(triggers_1h),
        "detections_24h":            len(triggers_24h),
        "last_detection":            last_detection,
        "last_detection_confidence": last_detection_conf,
        "ble_stable":                ble_stable,
        "ble_drops_1h":              len(ble_disconnects_1h),
        "state":                     state_str,
        "sim_mode":                  sim_mode,
        "in_window":                 in_window,
        "cpu_temp_c":                cpu_temp,
        "cam_reachable":             cam_ok,
        "anomalies":                 anomalies,
        "summary_line":              " ".join(parts),
        # sensor / environment
        "lux":                       sensor_data.get("lux"),
        "ev":                        sensor_data.get("ev"),
        "temperature_c":             sensor_data.get("temperature_c"),
        "humidity_pct":              sensor_data.get("humidity_pct"),
        "pressure_hpa":              sensor_data.get("pressure_hpa"),
        "dew_point_c":               sensor_data.get("dew_point_c"),
        "hardware_lux":              sensor_data.get("hardware_lux", False),
        "hardware_env":              sensor_data.get("hardware_env", False),
        # camera / storage
        "iso":                       camera_state.get("iso"),
        "nd_filter":                 camera_state.get("nd_filter"),
        "ssd_free_gb":               ssd_free_gb,
        "house_drive_used_tb":       house_tb,
    }


# ── Tier 2 ────────────────────────────────────────────────────────────────────

def query_agent(question: str) -> dict:
    """
    LLM-enriched response. Falls back to Tier 1 if key absent or API fails.
    Always writes to agent_log.json. Never raises.
    """
    entry_id  = datetime.now().strftime("agent_%Y%m%d_%H%M%S")
    timestamp = datetime.now(timezone.utc).isoformat()

    try:
        summary = build_summary()
    except Exception as e:
        log.error(f"build_summary failed in query_agent: {e}")
        summary = {
            "state": "UNKNOWN", "sim_mode": True,
            "detections_1h": 0, "anomalies": [], "summary_line": "Summary unavailable.",
            "detections_24h": 0, "last_detection": None,
            "last_detection_confidence": None, "ble_stable": True,
            "ble_drops_1h": 0, "in_window": False,
            "cpu_temp_c": None, "cam_reachable": False,
        }

    dep_id        = None
    dep_name      = None
    dep_info      = ""
    agent_log_path = _AGENT_LOG_PATH
    try:
        import deployment as _dep_mod
        _dep = _dep_mod.get_active_deployment()
        if _dep:
            dep_id        = _dep["id"]
            dep_name      = _dep["name"]
            dep_dir       = os.path.join(_HHRCS_DIR, "deployments", dep_id)
            agent_log_path = os.path.join(dep_dir, "agent_log.json")
            os.makedirs(dep_dir, exist_ok=True)
            dep_info = (
                f"\nDEPLOYMENT\n"
                f"id: {_dep['id']}\n"
                f"name: {_dep['name']}\n"
                f"position: {_dep.get('position', '')}\n"
                f"lat: {_dep.get('lat')}, lng: {_dep.get('lng')}\n"
                f"bearing: {_dep.get('bearing')}\n"
                f"clip_count: {_dep.get('clip_count', 0)}\n"
                f"started_at: {_dep.get('started_at')}\n"
                f"notes: {_dep.get('notes', '')}\n"
            )
        else:
            dep_info = "\nDEPLOYMENT\nNo active deployment.\n"
    except Exception:
        pass

    try:
        from config import config as _cfg
        api_key = (os.environ.get("ANTHROPIC_API_KEY", "") or _cfg.agent_api_key).strip()
    except Exception:
        api_key = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    response_text = None
    entry_type    = "query"

    if api_key:
        try:
            import anthropic

            recent_events = events_recent(window_seconds=1800)
            event_lines   = "\n".join(
                format_as_log_line(e) for e in recent_events[-40:]
            ) or "None"

            prior = _read_log(log_path=agent_log_path)[-10:]
            memory_lines = [
                f"{p.get('type','')} · {p.get('timestamp','')[:16]} · "
                f"{(p.get('query') or '')!r} → {(p.get('response') or '')[:200]!r}"
                for p in prior
            ]

            s = summary
            hw_lux_label = "hardware" if s.get("hardware_lux") else "absent"
            hw_env_label = "hardware" if s.get("hardware_env") else "absent"
            context_block = (
                f"SYSTEM STATE\n"
                f"state: {s['state']}\n"
                f"sim_mode: {s['sim_mode']}\n"
                f"in_window: {s['in_window']}\n"
                f"detections_1h: {s['detections_1h']}\n"
                f"detections_24h: {s['detections_24h']}\n"
                f"last_detection: {s['last_detection'] or 'None'}\n"
                f"last_detection_confidence: {s['last_detection_confidence'] or 'None'}\n"
                f"cam_reachable: {s['cam_reachable']}\n"
                f"ble_stable: {s['ble_stable']}\n"
                f"ble_drops_1h: {s['ble_drops_1h']}\n"
                f"cpu_temp_c: {s['cpu_temp_c']}\n"
                f"\nENVIRONMENT ({hw_env_label} sensor)\n"
                f"temperature_c: {_fmt(s.get('temperature_c'), '°C')}\n"
                f"humidity_pct: {_fmt(s.get('humidity_pct'), '%')}\n"
                f"dew_point_c: {_fmt(s.get('dew_point_c'), '°C')}\n"
                f"pressure_hpa: {_fmt(s.get('pressure_hpa'), ' hPa')}\n"
                f"\nLIGHT ({hw_lux_label} sensor)\n"
                f"lux: {_fmt(s.get('lux'))}\n"
                f"ev: {_fmt(s.get('ev'))}\n"
                f"\nCAMERA & STORAGE\n"
                f"iso: {s.get('iso')}\n"
                f"nd_filter: {s.get('nd_filter')}\n"
                f"ssd_free_gb: {s.get('ssd_free_gb')}\n"
                f"house_drive_used_tb: {s.get('house_drive_used_tb')}\n"
                f"\nANOMALIES\n"
                f"{chr(10).join(s['anomalies']) if s['anomalies'] else 'None'}\n"
                f"\nRECENT EVENTS (last 30 min)\n{event_lines}\n"
                f"\nRECENT AGENT EXCHANGES (last 10)\n"
                f"{chr(10).join(memory_lines) or 'None'}\n"
                f"{dep_info}"
                f"\nQuery: {question}"
            )

            context_md = _load_context_md()
            context_prefix = (
                f"PROJECT CONTEXT (CONTEXT.md):\n{context_md}\n\n---\n\n"
                if context_md else ""
            )
            client  = anthropic.Anthropic(api_key=api_key)
            message = client.messages.create(
                model="claude-haiku-4-5-20251001",
                max_tokens=512,
                system=(
                    f"{context_prefix}"
                    "You are the field intelligence for HHRCS, a remote wildlife camera system. "
                    "You have access to real-time sensor readings, detection history, system "
                    "state, and environmental conditions.\n\n"
                    "Report facts plainly. No headers, no bullet points, no bold text, no "
                    "markdown. Do not interpret unless the question asks for interpretation. "
                    "Do not infer what conditions mean for wildlife behaviour, shooting "
                    "decisions, or anything else unless explicitly asked.\n\n"
                    "Be concise and direct. State what the sensors read, what the system is "
                    "doing, what has been detected. One to four sentences is usually correct.\n\n"
                    "Do not editorialize. Do not use figurative language. Do not describe your "
                    "own function or limitations. Answer as if you are already inside the "
                    "situation."
                ),
                messages=[{"role": "user", "content": context_block}],
            )
            response_text = message.content[0].text

        except Exception as e:
            log.error(f"Anthropic API call failed: {e}")
            response_text = None

    if response_text is None:
        response_text = summary.get("summary_line", "No summary available.")

    tier = 2 if (response_text is not None and api_key and response_text != summary.get("summary_line")) else 1

    entry = {
        "id":        entry_id,
        "timestamp": timestamp,
        "type":      entry_type,
        "tier":      tier,
        "query":     question,
        "response":  response_text,
        "context_snapshot": {
            "state":               summary.get("state", "UNKNOWN"),
            "sim_mode":            summary.get("sim_mode", True),
            "recent_trigger_count": summary.get("detections_1h", 0),
            "anomalies":           summary.get("anomalies", []),
            "deployment_id":       dep_id,
            "deployment_name":     dep_name,
        },
    }

    try:
        _append_log(entry, log_path=agent_log_path)
    except Exception as e:
        log.error(f"Failed to write agent log: {e}")

    return entry


# ── Passive summarizer (Tier 1 only) ──────────────────────────────────────────

def run_passive_summary(summary: dict = None) -> dict:
    """Called every 5 min by the passive scheduler in api_server.py.
    Accepts a pre-built summary to avoid a redundant build_summary() call."""
    entry_id  = datetime.now().strftime("agent_%Y%m%d_%H%M%S")
    timestamp = datetime.now(timezone.utc).isoformat()

    if summary is None:
        try:
            summary = build_summary()
        except Exception as e:
            log.error(f"run_passive_summary: build_summary failed: {e}")
            return

    dep_id        = None
    dep_name      = None
    agent_log_path = _AGENT_LOG_PATH
    try:
        import deployment as _dep_mod
        _dep = _dep_mod.get_active_deployment()
        if _dep:
            dep_id        = _dep["id"]
            dep_name      = _dep["name"]
            dep_dir       = os.path.join(_HHRCS_DIR, "deployments", dep_id)
            agent_log_path = os.path.join(dep_dir, "agent_log.json")
            os.makedirs(dep_dir, exist_ok=True)
    except Exception:
        pass

    entry = {
        "id":        entry_id,
        "timestamp": timestamp,
        "type":      "summary",
        "tier":      1,
        "query":     None,
        "response":  summary["summary_line"],
        "context_snapshot": {
            "state":               summary["state"],
            "sim_mode":            summary["sim_mode"],
            "recent_trigger_count": summary["detections_1h"],
            "anomalies":           summary["anomalies"],
            "deployment_id":       dep_id,
            "deployment_name":     dep_name,
        },
    }

    try:
        _append_log(entry, log_path=agent_log_path)
        log.info(f"Passive summary: {summary['summary_line']}")
    except Exception as e:
        log.error(f"run_passive_summary: write failed: {e}")

    return entry
