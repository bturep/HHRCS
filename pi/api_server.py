"""
HHRCS API Server — Raspberry Pi
Flask REST API consumed by the HHRCS iOS/macOS app via Tailscale.

Hardware path for camera commands:
    Pi  →─(ethernet)─→  BMPCC 6K Pro REST API (192.168.10.2)

Endpoints match the simulation server exactly so the iOS app needs no changes
when switching from sim (Mac) to real (Pi).
"""

import os
import time
import threading
import random
import logging
from datetime import datetime, timezone
from pathlib import Path
from flask import Flask, jsonify, request, Response
from flask_cors import CORS

from config import config, CAMERA_BASE_URL, HDMI_DEVICE
from state_machine import StateMachine, TriggerType
from sensors import (
    to_dict as sensors_dict,
    get_camera_state,
    read_lux,
    read_house_drive_used_tb,
    start_recording as _sensors_start,
    stop_recording as _sensors_stop,
    set_nd as _sensors_set_nd,
    set_iso as _sensors_set_iso,
)
from detector import Detector
from camera_control import camera
from camera_http import BMPCCCameraClient
from session import (
    log_session, get_sessions, get_agent_log,
    get_field_notes, save_field_note, log_agent_entry,
)
from events import emit, recent, format_as_log_line, set_session_id
import json
import agent
import deployment
import notifier
import notifications
import storage_monitor
try:
    from hdmi_stream import HDMIStreamer as _HDMIStreamer
except ImportError:
    _HDMIStreamer = None
    log.warning("hdmi_stream unavailable (cv2 not installed) — HDMI endpoints disabled")

# ── Logging ────────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(os.path.join(os.path.dirname(__file__), "logs", "hhrcs.log")),
    ],
)
log = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# ── Shared camera HTTP client (singleton for /camera/* endpoints) ──────────────
_cam_client = BMPCCCameraClient()

# ── HDMI capture card streamer ─────────────────────────────────────────────────
if _HDMIStreamer is not None:
    _hdmi = _HDMIStreamer()
    try:
        _hdmi.start()
    except Exception as _e:
        log.warning(f"HDMI streamer failed to start: {_e}")
else:
    _hdmi = None

# Clip name to use for the next record start (set via PUT /camera/clip_name)
_next_clip_name: str = ""

# ── State machine + hardware wiring ───────────────────────────────────────────

sm = StateMachine()
sm.manual_override = False          # explicit: fresh start is never blocked
_uptime_start = time.time()
_current_clip_id: str = ""
_camera_started: bool = False

emit("system.startup", {"subsystem": "api_server"})


def _on_record_start(trigger):
    global _current_clip_id, _camera_started
    _sensors_start()
    if trigger == TriggerType.MANUAL or detector._using_real:
        camera.record_start()
        _camera_started = True
    else:
        _camera_started = False
        log.info(f"Sim mode — skipping camera.record_start (trigger={trigger})")
    _current_clip_id = datetime.now().strftime("hhrcs_%Y%m%d_%H%M%S")
    dep = deployment.get_active_deployment()
    base = (Path(__file__).parent / "deployments" / dep["id"] / "clips" / _current_clip_id
            if dep else None)
    set_session_id(_current_clip_id, base_dir=base)
    if dep:
        deployment.increment_clip_count()
    emit("recording.started", {"clip_id": _current_clip_id, "source": "bmpcc"})
    notifications.emit("recording.started", "HHRCS — Recording", f"Started clip {_current_clip_id}")
    log.info(f"Recording started — trigger={trigger} clip={_current_clip_id}")


def _on_record_stop(elapsed):
    global _current_clip_id, _camera_started
    _sensors_stop()
    if _camera_started:
        camera.record_stop()
        _camera_started = False
    else:
        log.info("Sim mode — skipping camera.record_stop")

    lux = read_lux()
    emit("recording.stopped", {
        "clip_id": _current_clip_id,
        "source": "bmpcc",
        "duration_seconds": round(elapsed, 1),
    })
    notifications.emit("recording.stopped", "HHRCS — Stopped", f"{int(elapsed)}s clip ended")
    log_session(
        trigger_type=sm.trigger_type.value,
        duration_seconds=int(elapsed),
        lux_start=lux,
        iso=config.iso,
        nd=config.nd_filter,
        files=random.randint(1, 3),
    )
    log.info(f"Recording stopped — elapsed={int(elapsed)}s lux={lux:.1f} clip={_current_clip_id}")


sm.on_record_start = _on_record_start
sm.on_record_stop = _on_record_stop


# ── Wildlife detector ─────────────────────────────────────────────────────────

def _on_detection(cls: str):
    was_idle = sm.state.value == "IDLE"
    sm.detection_event(cls)
    if was_idle:
        trigger_events = recent(window_seconds=5, types=["detector.trigger"])
        confidence = trigger_events[-1].get("confidence", 0.0) if trigger_events else 0.0
        notifications.emit("detection.animal", "HHRCS — Animal detected", f"{cls}, {confidence:.0%} confidence")
    log.info(f"Wildlife detected: {cls}")


detector = Detector(
    callback=_on_detection,
    classes=config.detection_classes,
    confidence=config.detection_confidence,
    fps=config.detection_fps,
    resolution=config.detection_resolution,
)
detector.start()
agent.init(detector, sm, camera)
notifier.start()

def _start_passive_agent():
    try:
        summary = agent.build_summary()
        summary["storage"] = storage_monitor.get_storage_stats()
        summary["yolo_running"] = bool(detector._thread and detector._thread.is_alive())
        notifier.evaluate_and_notify(summary)
        agent.run_passive_summary(summary)
    except Exception as e:
        log.warning(f"Passive agent error: {e}")
    threading.Timer(300, _start_passive_agent).start()

threading.Timer(60, _start_passive_agent).start()

# Open scheduled dawn/dusk window based on astral — runs in background
def _schedule_windows():
    try:
        from astral import LocationInfo
        from astral.sun import sun
        import pytz
        from datetime import date

        loc = LocationInfo(
            name="Hunter House",
            region="CA",
            timezone=config.timezone,
            latitude=config.latitude,
            longitude=config.longitude,
        )
        tz = pytz.timezone(config.timezone)

        while True:
            try:
                s = sun(loc.observer, date=date.today(), tzinfo=tz)
                now = datetime.now(tz)

                from datetime import timedelta
                dawn_open  = s["dawn"]  + timedelta(minutes=config.dawn_offset_minutes)
                dawn_close = s["sunrise"] + timedelta(minutes=config.dawn_close_minutes)
                dusk_open  = s["sunset"] + timedelta(minutes=config.dusk_open_minutes)
                dusk_close = s["dusk"]  + timedelta(minutes=config.dusk_close_minutes)

                in_dawn = dawn_open <= now <= dawn_close
                in_dusk = dusk_open <= now <= dusk_close

                if in_dawn or in_dusk:
                    if not sm.window_open:
                        sm.open_window(TriggerType.SCHEDULED)
                        log.info(f"Scheduled window opened ({'dawn' if in_dawn else 'dusk'})")
                else:
                    if sm.window_open and sm.trigger_type == TriggerType.SCHEDULED:
                        sm.close_window()
                        log.info("Scheduled window closed")
            except Exception as e:
                log.error(f"Scheduler error: {e}")

            time.sleep(60)

    except ImportError:
        log.warning("astral/pytz not available — scheduled windows disabled")

threading.Thread(target=_schedule_windows, daemon=True, name="scheduler").start()



def _ts_after(ts_str: str, cutoff: datetime) -> bool:
    """Return True if ts_str (ISO8601) is >= cutoff (timezone-aware datetime)."""
    try:
        dt = datetime.fromisoformat(ts_str)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt >= cutoff
    except Exception:
        return True



def _deployment_status_fields() -> dict:
    dep = deployment.get_active_deployment()
    if not dep:
        return {"deployment_id": None, "deployment_name": None, "detections_since_deployment": None}
    started_at = dep.get("started_at", "")
    try:
        cutoff = datetime.fromisoformat(started_at)
        if cutoff.tzinfo is None:
            cutoff = cutoff.replace(tzinfo=timezone.utc)
        dep_triggers = sum(
            1 for e in recent(window_seconds=604800)
            if e.get("type") == "detector.trigger" and _ts_after(e.get("ts", ""), cutoff)
        )
    except Exception:
        dep_triggers = None
    return {
        "deployment_id":                dep["id"],
        "deployment_name":              dep["name"],
        "detections_since_deployment":  dep_triggers,
    }


def _ssd_free_pct() -> float:
    try:
        import shutil as _shutil
        u = _shutil.disk_usage(config.ssd_mount)
        return round(u.free / u.total * 100, 1) if u.total > 0 else 0.0
    except Exception:
        return 0.0

# ── /status ────────────────────────────────────────────────────────────────────

@app.route("/status")
def status():
    sensor_data = sensors_dict()
    cam = get_camera_state()
    sm_data = sm.to_dict()
    uptime = int(time.time() - _uptime_start)
    cam_state = _cam_client.get_full_state()

    return jsonify({
        "deployment": config.deployment_name,
        "position": config.position_name,
        "uptime_seconds": uptime,
        "timestamp": datetime.now().isoformat(),

        "lux": sensor_data["lux"],
        "ev": sensor_data["ev"],
        "nd_filter": cam["nd_filter"],
        "iso": cam["iso"],

        "recording": sm.is_recording() or cam_state["cam_recording"],
        "recording_state": sm_data["state"],
        "elapsed_seconds": sm_data["elapsed_seconds"],
        "elapsed_formatted": sm_data["elapsed_formatted"],
        "ssd_free_gb": cam["ssd_free_gb"],
        "timecode": cam["timecode"],
        "shutter_angle": cam["shutter_angle"],
        "fps": cam["fps"],

        "trigger_state": sm_data["state"],
        "trigger_type": sm_data["trigger_type"],
        "last_class": sm_data["last_class"],
        "last_detection_time": sm_data["last_detection_time"],
        "countdown_remaining": sm_data["countdown_remaining"],
        "window_open": sm_data["window_open"],
        "manual_override": sm_data["manual_override"],

        "temperature_c": sensor_data["temperature_c"],
        "humidity_pct": sensor_data["humidity_pct"],
        "dew_point_c": sensor_data["dew_point_c"],
        "pressure_hpa": sensor_data["pressure_hpa"],
        "cpu_temp_c": sensor_data["cpu_temp_c"],

        "house_drive_used_tb": read_house_drive_used_tb(),
        "house_drive_total_tb": config.house_drive_total_tb,

        # Camera (ethernet REST API)
        "cam_reachable":             cam_state["cam_reachable"],
        "cam_recording":             cam_state["cam_recording"],
        "cam_codec":                 cam_state["cam_codec"],
        "cam_frame_rate":            cam_state["cam_frame_rate"],
        "cam_resolution":            cam_state["cam_resolution"],
        "cam_iso":                   cam_state["cam_iso"],
        "cam_white_balance":         cam_state["cam_white_balance"],
        "cam_gain":                  cam_state["cam_gain"],
        "cam_active_media_slot":     cam_state["cam_active_media_slot"],
        "cam_remaining_record_time": cam_state["cam_remaining_record_time"],

        "hardware_lux": sensor_data.get("hardware_lux", False),
        "hardware_env": sensor_data.get("hardware_env", False),

        "detector_last_inference_ago_seconds": detector.last_inference_ago_seconds,

        "yolo_running":    bool(detector._thread and detector._thread.is_alive()),
        "yolo_sim_mode":   not detector._using_real,
        "machine_state":   sm_data["state"],
        "ssd_mounted":     os.path.ismount(config.ssd_mount),
        "ssd_free_pct":    _ssd_free_pct(),

        "storage": storage_monitor.get_storage_stats(),

        "hdmi_reachable": _hdmi.is_open() if _hdmi else False,

        # Deployment scope
        **_deployment_status_fields(),
    })

# ── Log endpoints ──────────────────────────────────────────────────────────────

@app.route("/sessions")
def sessions():
    limit = request.args.get("limit", 50, type=int)
    return jsonify(get_sessions(limit))

@app.route("/agent-log")
def agent_log():
    limit = request.args.get("limit", 50, type=int)
    dep = deployment.get_active_deployment()
    if dep:
        log_path = os.path.join(os.path.dirname(__file__), "deployments", dep["id"], "agent_log.json")
    else:
        log_path = os.path.join(os.path.dirname(__file__), "data", "agent_log.json")
    if not os.path.exists(log_path):
        return jsonify([])
    with open(log_path) as f:
        entries = json.load(f)
    entries.reverse()
    return jsonify(entries[:limit])

@app.route("/agent-log/startup", methods=["POST"])
def agent_log_startup():
    try:
        entry = agent.run_passive_summary()
        return jsonify(entry)
    except Exception as e:
        log.error(f"agent_log_startup failed: {e}")
        return jsonify({"error": str(e)}), 500


@app.route("/agent-log/query", methods=["POST"])
def agent_log_query():
    data = request.json or {}
    question = (data.get("question") or data.get("query") or "").strip()
    if not question:
        return jsonify({"error": "question required"}), 400
    result = agent.query_agent(question)
    return jsonify(result)

@app.route("/diagnostics")
def diagnostics():
    return jsonify(agent.build_summary())

@app.route("/notes", methods=["GET"])
def get_notes():
    limit = request.args.get("limit", 50, type=int)
    return jsonify(get_field_notes(limit))

@app.route("/notes", methods=["POST"])
def post_note():
    data = request.json or {}
    author = data.get("author", "Unknown")
    text = data.get("text", "")
    if not text:
        return jsonify({"error": "text required"}), 400
    system_state = {
        "lux": read_lux(),
        "recording": get_camera_state()["recording"],
        "trigger_state": sm.state.value,
        "temperature_c": sensors_dict()["temperature_c"],
    }
    note = save_field_note(author, text, system_state)
    return jsonify(note), 201

# ── Deployment endpoints ───────────────────────────────────────────────────────

@app.route("/deployments", methods=["GET"])
def get_deployments_list():
    return jsonify(deployment.get_deployments())

@app.route("/deployments/active", methods=["GET"])
def get_active_deployment():
    dep = deployment.get_active_deployment()
    if dep is None:
        return jsonify({"active": False})
    return jsonify({"active": True, "deployment": dep})

@app.route("/deployments", methods=["POST"])
def open_new_deployment():
    data = request.json or {}
    name = data.get("name", "").strip()
    if not name:
        return jsonify({"error": "name required"}), 400
    dep = deployment.open_deployment(
        name=name,
        position=data.get("position", ""),
        lat=data.get("lat"),
        lng=data.get("lng"),
        bearing=data.get("bearing"),
        notes=data.get("notes", ""),
        app_version=data.get("app_version", ""),
    )
    notifications.emit("deployment.opened", "HHRCS — Deployment opened", name)
    return jsonify(dep), 201

@app.route("/deployments/close", methods=["POST"])
def close_active_deployment():
    data = request.json or {}
    notes = data.get("notes", "").strip()
    dep = deployment.close_deployment(notes=notes)
    if dep is None:
        return jsonify({"error": "no active deployment"}), 404
    notifications.emit("deployment.closed", "HHRCS — Deployment closed", dep["name"])
    return jsonify(dep)


# ── Notification endpoints ────────────────────────────────────────────────────

@app.route("/notifications/unread", methods=["GET"])
def get_notifications_unread():
    return jsonify({"notifications": notifications.unread()})

@app.route("/notifications/mark-read", methods=["POST"])
def mark_notifications_read():
    data = request.json or {}
    ids = data.get("ids", [])
    count = notifications.mark_read(ids)
    return jsonify({"marked": count})

@app.route("/notifications", methods=["GET"])
def get_notifications_list():
    limit = request.args.get("limit", 50, type=int)
    return jsonify({"notifications": notifications.recent(limit)})

# ── Control endpoints ──────────────────────────────────────────────────────────

@app.route("/control/record/start", methods=["POST"])
def record_start():
    sm.force_start()
    return jsonify({"ok": True, "state": sm.state.value})

@app.route("/control/record/stop", methods=["POST"])
def record_stop():
    sm.force_stop()
    return jsonify({"ok": True, "state": sm.state.value})

@app.route("/record/toggle", methods=["POST"])
def record_toggle():
    """Alias expected by some app versions."""
    if sm.state.value == "IDLE":
        sm.force_start()
    else:
        sm.force_stop()
    return jsonify({"ok": True, "state": sm.state.value})

@app.route("/control/shutter", methods=["POST"])
def set_shutter():
    data = request.json or {}
    angle = data.get("angle", 180)
    camera.set_shutter_angle(angle)
    return jsonify({"ok": True, "shutter_angle": angle})

@app.route("/control/wb", methods=["POST"])
def set_wb():
    data = request.json or {}
    kelvin = data.get("kelvin", 5600)
    tint = data.get("tint", 0)
    camera.set_white_balance(kelvin, tint)
    return jsonify({"ok": True, "kelvin": kelvin, "tint": tint})

_STILLS_DIR = os.path.join(os.path.dirname(__file__), "stills")

@app.route("/control/still", methods=["POST"])
@app.route("/still/trigger", methods=["POST"])
def trigger_still():
    os.makedirs(_STILLS_DIR, exist_ok=True)
    jpeg = detector.capture_jpeg()
    if jpeg:
        path = os.path.join(_STILLS_DIR, "latest.jpg")
        with open(path, "wb") as f:
            f.write(jpeg)
        ts = datetime.now().strftime("%H:%M:%S")
        log_agent_entry("observation", f"Still captured at {ts}.")
        notifications.emit("still.captured", "HHRCS — Still", "Pi cam still saved")
        return jsonify({"ok": True, "timestamp": ts, "bytes": len(jpeg)})
    return jsonify({"ok": False, "error": "no frame available"}), 503

@app.route("/stills/latest", methods=["GET"])
def get_still():
    path = os.path.join(_STILLS_DIR, "latest.jpg")
    if not os.path.exists(path):
        return jsonify({"error": "no still available"}), 404
    with open(path, "rb") as f:
        data = f.read()
    return Response(data, mimetype="image/jpeg")

@app.route("/control/nd", methods=["POST"])
def set_nd():
    data = request.json or {}
    nd = data.get("filter", "ND4")
    _sensors_set_nd(nd)
    camera.set_nd(nd)
    config.nd_filter = nd
    return jsonify({"ok": True, "nd_filter": nd})

@app.route("/control/iso", methods=["POST"])
def set_iso():
    data = request.json or {}
    iso = data.get("iso", 3200)
    _sensors_set_iso(iso)
    camera.set_iso(iso)
    config.iso = iso
    return jsonify({"ok": True, "iso": iso})

@app.route("/control/extend", methods=["POST"])
def extend_session():
    data = request.json or {}
    seconds = data.get("seconds", 300)
    sm.extend(seconds)
    return jsonify({"ok": True, "extended_seconds": seconds, "state": sm.state.value})

@app.route("/control/timeout", methods=["POST"])
def set_timeout():
    data = request.json or {}
    seconds = data.get("seconds", 120)
    config.countdown_seconds = seconds
    return jsonify({"ok": True, "countdown_seconds": seconds})

# ── Camera (BMPCC REST API passthrough) ───────────────────────────────────────

@app.route("/camera/status", methods=["GET"])
def camera_status():
    return jsonify(_cam_client.get_full_state())

@app.route("/camera/record/start", methods=["PUT", "POST"])
def camera_record_start():
    global _next_clip_name
    _next_clip_name = ""
    sm.force_start()        # clears manual_override, transitions state machine, fires _on_record_start → camera.record_start()
    return jsonify({"ok": True})

@app.route("/camera/record/stop", methods=["PUT", "POST"])
def camera_record_stop():
    ok = _cam_client.record_stop()
    sm.force_idle()
    return jsonify({"ok": ok})

@app.route("/camera/iso", methods=["PUT"])
def camera_set_iso():
    data = request.json or {}
    iso = data.get("iso")
    if not isinstance(iso, int):
        return jsonify({"error": "iso (int) required"}), 400
    ok = _cam_client.set_iso(iso)
    return jsonify({"ok": ok})

@app.route("/camera/white_balance", methods=["PUT"])
def camera_set_wb():
    data = request.json or {}
    kelvin = data.get("kelvin")
    if not isinstance(kelvin, int):
        return jsonify({"error": "kelvin (int) required"}), 400
    ok = _cam_client.set_white_balance(kelvin)
    return jsonify({"ok": ok})

@app.route("/camera/format", methods=["PUT"])
def camera_set_format():
    data = request.json or {}
    ok = _cam_client.set_format(**data)
    return jsonify({"ok": ok})

@app.route("/camera/clip_name", methods=["PUT"])
def camera_set_clip_name():
    global _next_clip_name
    data = request.json or {}
    _next_clip_name = str(data.get("clip_name", ""))
    return jsonify({"ok": True, "clip_name": _next_clip_name})

# ── MJPEG stream ───────────────────────────────────────────────────────────────

def _is_complete_jpeg(data: bytes) -> bool:
    return (len(data) >= 4
            and data[:2] == b'\xff\xd8'
            and data[-2:] == b'\xff\xd9')


def _mjpeg_frames():
    while True:
        jpeg = detector.capture_jpeg()
        if jpeg and _is_complete_jpeg(jpeg):
            yield (
                b"--frame\r\n"
                b"Content-Type: image/jpeg\r\n\r\n" + jpeg + b"\r\n"
            )
        else:
            time.sleep(0.033)

@app.route("/stream")
def stream():
    """MJPEG stream from Pi Camera Module 3 for the app's CAMERA tab."""
    return Response(
        _mjpeg_frames(),
        mimetype="multipart/x-mixed-replace; boundary=frame",
    )

# ── HDMI capture endpoints ─────────────────────────────────────────────────────

_HDMI_STILLS_DIR = os.path.join(os.path.dirname(__file__), "stills", "hdmi")

@app.route("/hdmi-stream")
def hdmi_stream():
    """MJPEG stream from the HDMI capture card."""
    if _hdmi is None:
        return jsonify({"error": "HDMI capture not available"}), 503
    return Response(
        _hdmi.generate_mjpeg(),
        mimetype="multipart/x-mixed-replace; boundary=frame",
    )

@app.route("/hdmi/still", methods=["POST"])
def hdmi_still():
    if _hdmi is None:
        return jsonify({"ok": False, "error": "HDMI capture not available"}), 503
    os.makedirs(_HDMI_STILLS_DIR, exist_ok=True)
    jpeg = _hdmi.capture_jpeg()
    if jpeg:
        path = os.path.join(_HDMI_STILLS_DIR, "latest.jpg")
        with open(path, "wb") as f:
            f.write(jpeg)
        ts = datetime.now().strftime("%H:%M:%S")
        log_agent_entry("observation", f"HDMI still captured at {ts}.")
        notifications.emit("still.captured", "HHRCS — Still", "HDMI still saved")
        return jsonify({"ok": True, "timestamp": ts, "bytes": len(jpeg)})
    return jsonify({"ok": False, "error": "no HDMI frame available"}), 503

@app.route("/hdmi/stills/latest", methods=["GET"])
def hdmi_stills_latest():
    path = os.path.join(_HDMI_STILLS_DIR, "latest.jpg")
    if not os.path.exists(path):
        return jsonify({"error": "no HDMI still available"}), 404
    with open(path, "rb") as f:
        data = f.read()
    return Response(data, mimetype="image/jpeg")

@app.route("/camera/monitor/overlay", methods=["POST"])
def camera_toggle_overlay():
    ok = camera.toggle_overlay()
    return jsonify({"ok": ok})

# ── Event bus endpoints ────────────────────────────────────────────────────────

@app.route("/events", methods=["GET"])
def get_events():
    """
    Local event ring buffer.
    ?window=300  — lookback seconds (default 300)
    ?types=a,b   — comma-separated type filter
    """
    window = request.args.get("window", 300, type=int)
    types_param = request.args.get("types", "")
    types = [t.strip() for t in types_param.split(",") if t.strip()] or None

    local = recent(window_seconds=window, types=types)

    dep = deployment.get_active_deployment()
    if dep:
        try:
            cutoff = datetime.fromisoformat(dep["started_at"])
            if cutoff.tzinfo is None:
                cutoff = cutoff.replace(tzinfo=timezone.utc)
            local = [e for e in local if _ts_after(e.get("ts", ""), cutoff)]
        except Exception:
            pass

    return jsonify(local)


@app.route("/log", methods=["GET"])
def get_log():
    """Human-readable event log — one line per event, newest last."""
    window = request.args.get("window", 300, type=int)
    types_param = request.args.get("types", "")
    types = [t.strip() for t in types_param.split(",") if t.strip()] or None

    events = recent(window_seconds=window, types=types)
    lines = [format_as_log_line(e) for e in events]
    return Response("\n".join(lines) + "\n", mimetype="text/plain")


# ── System control ────────────────────────────────────────────────────────────

@app.route("/system/restart-hhrcs", methods=["POST"])
def restart_hhrcs():
    import subprocess
    try:
        subprocess.run(["pkill", "-f", "api_server.py"], check=False)
        return jsonify({"ok": True})
    except Exception as e:
        log.error(f"restart-hhrcs failed: {e}")
        return jsonify({"ok": False, "error": str(e)}), 500

@app.route("/system/restart-detector", methods=["POST"])
def restart_detector_endpoint():
    try:
        threading.Thread(target=detector.restart, daemon=True, name="detector-restart").start()
        return jsonify({"ok": True})
    except Exception as e:
        log.error(f"restart-detector failed: {e}")
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/notifier/test", methods=["POST"])
def notifier_test():
    sent = notifier.send_alert(
        "HHRCS — Test alert",
        "Manual test from /notifier/test endpoint.",
        priority="default",
        tags=["test_tube"],
    )
    return jsonify({"sent": sent})

# ── Health ─────────────────────────────────────────────────────────────────────

@app.route("/health")
def health():
    return jsonify({
        "ok": True,
        "uptime": int(time.time() - _uptime_start),
        "cam_reachable": _cam_client.is_reachable(),
    })

# ── Main ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    port = int(os.environ.get("PORT", config.api_port))
    cam_ok = _cam_client.is_reachable()
    print(f"\n{'─'*56}")
    print(f"  HHRCS — Raspberry Pi")
    print(f"  {config.deployment_name} · {config.position_name}")
    print(f"  http://0.0.0.0:{port}")
    print(f"  Camera: {'reachable at ' + CAMERA_BASE_URL if cam_ok else 'NOT REACHABLE'}")
    print(f"{'─'*56}\n")
    os.makedirs(os.path.join(os.path.dirname(__file__), "logs"), exist_ok=True)
    app.run(host=config.api_host, port=port, debug=False, threaded=True)
