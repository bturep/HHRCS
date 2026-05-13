# Hunter House Remote Camera System (HHRCS) — Project Context
*Last updated: 2026-05-09 (Part 5: CONTEXT.md full audit — hardware: NVMe SSD removed (BMPCC records to own SD/CFast), Pelican 1400, Rode NTG 3.5mm direct, active cooling installed 46.3°C ceiling; thermal: 3 threads confirmed, 9.53h overnight clean run; iOS: tab/controls/settings structure corrected, stale toggles removed, sim mode section marked removed; agent.py: Fix 1 stale sensor/BLE calls removed; Fix 2 context_snapshot expanded with live cam/storage fields; Fix 3 conversation history as proper messages array)*

## System Overview

Unattended outdoor wildlife cinema rig at Hunter House, Prospect Lake, Saanich, Victoria BC (48.515°N, -123.408°W). Position: North Meadow.

Primary camera: BMPCC 6K Pro — target deployment: BRAW 12:1 at 6K/24fps (~65 MB/s, requires CFast). Currently testing at ProRes Proxy 1920×1080 on SD card. Raspberry Pi 4 is the intelligence layer: controlling the camera via REST API over USB-C ethernet adapter (192.168.10.0/24 private subnet), detecting wildlife via Pi Camera Module 3 + MegaDetectorLite ONNX, managing scheduled dawn/dusk windows via lux sensor + astral. Footage offload is manual — physical site visit every 2–3 days to swap or pull media.

Recording state machine: ACTIVE (animal detected) → HOLDING (15 min grace) → COUNTDOWN (2 min, resets on redetection).

---

## Hardware

| Component | Details |
|-----------|---------|
| Raspberry Pi 4 (4GB) | raspberrypi.local · WiFi: 192.168.1.68 · Ethernet: 192.168.1.82, headless Bookworm Lite 64-bit |
| Tailscale IP | 100.118.27.125 · hostname: `hhrcs-pi` (magic DNS) |
| BMPCC 6K Pro | Firmware 8.6 · USB-C → ethernet adapter → Pi eth0 · static IP 192.168.10.2/24 · REST API enabled (Web Media Manager) · records to SD/CFast |
| ~~ELEGOO ESP32~~ | ~~Removed 2026-05-04~~ — entire BLE bridge stack deleted. Tag `pre-ethernet-fork` preserves prior architecture. |
| Pi Camera Module 3 Wide | 102° FOV, CSI — installed, dual-stream confirmed |
| Guermok USB2 Video | USB2 HDMI capture card · `/dev/video2` · MJPEG 1920×1080@25fps · BMPCC HDMI out → Pi |
| TSL2591 or BH1750 | I2C lux — not yet wired |
| BMP280/BME280 | I2C temp/humidity/pressure — not yet wired |
| Rode NTG (3.5mm) | 3.5mm direct to BMPCC input, deadcat windshield, external boom mount on Pelican |
| Pelican 1400 | Weatherproof enclosure |
| Active cooling | 5V fan attached to Pi GPIO 5V/GND pins — installed and confirmed running. Thermal ceiling: 46.3°C under full inference load. |

**Removed from architecture (May 1, 2026):**
- ~~2–4TB NVMe SSD (USB-C)~~ — removed May 1, 2026. BMPCC records to its own SD (currently) or CFast (for 6K BRAW deployment). No external storage connected to Pi.
- ~~6TB house drive nightly rsync target~~ — abandoned. No nightly transfer; offload is physical.
- ~~USB-C hub for ethernet + SSD simultaneously~~ — investigated (Plugable USB3-HUB3ME identified as best candidate) but skipped. Single USB-C port stays dedicated to ethernet.
- ~~GPIO USB switch~~ — abandoned.
- ~~ssd_free_gb field in /status~~ — removed. Storage monitoring is now via pi_sd_used_pct (Pi microSD), cam_media_space_remaining_gb (BMPCC active slot), external_drives array (USB drives, currently empty).

**Removed from architecture (May 4, 2026 — ethernet migration):**
- ~~ELEGOO ESP32 + BLE bridge~~ — entire stack deleted: `esp32_bridge.py`, `esp32-bridge.service`, `/esp32/` PlatformIO firmware. Camera control is now direct HTTP over ethernet.
- ~~BLE camera control~~ — replaced by BMPCC REST API at `http://192.168.10.2/control/api/v1`.
- ~~`/control/record/start`, `/control/record/stop` (BLE path)~~ — replaced by `PUT /camera/record/start`, `PUT /camera/record/stop`.

---

## Networking

| SSID | Role |
|------|------|
| HarlingPoint | Primary |
| TrialIsland | Secondary |

- Pi SSH: `ssh pi@raspberrypi.local` (preferred — works on both WiFi and Ethernet) · WiFi: 192.168.1.68 · Ethernet: 192.168.1.82 — password: hhrcs2026
- Tailscale: hostname `hhrcs-pi` (magic DNS, resolves on any tailnet device) · IP 100.118.27.125 · Tailscale SSH enabled (`tailscale up --ssh --hostname=hhrcs-pi`)
- HHRCS API: `http://raspberrypi.local:5001` (LAN) · `http://hhrcs-pi:5001` (Tailscale, anywhere) · `http://100.118.27.125:5001` (Tailscale IP, fallback)
- iOS app supports multi-URL switcher in SETTINGS (see iOS app section) — first launch seeds `raspberrypi.local:5001` and `100.118.27.125:5001` **and auto-selects `raspberrypi.local:5001` as the active URL**; user can add and tap-to-switch between any number of saved URLs
- **Note**: IP address changes between WiFi (192.168.1.68) and Ethernet (192.168.1.82) — always use `raspberrypi.local` for LAN or `hhrcs-pi` for Tailscale to avoid connection failures after interface switches
- **Bookworm WiFi**: always use `nmcli`, never wpa_supplicant.conf
  - Add network: `sudo nmcli dev wifi connect "SSID" password "PASS"`

### Thermal Notes
Prior crashes (Apr 19, Apr 21): bare Pi, no cooling, 4 threads at ~390% CPU sustained — not representative of current configuration.

**Current configuration (as of May 8–9, 2026):**
- `intra_op_num_threads = 3` — benchmarked May 8, 2026 (2 threads failed fps floor; 3 threads confirmed correct)
- `inter_op_num_threads = 1` — sequential graph execution
- `graph_optimization_level = ORT_ENABLE_ALL`
- **Active cooling installed**: 5V fan on GPIO 5V/GND pins, running throughout all benchmark sessions
- **Thermal ceiling under full 3-thread inference load: 46.3°C** — 34°C below Pi 4 throttle threshold (80°C)
- 9.53h clean overnight run completed May 9, 2026: zero throttling events, zero connectivity drops, fps mean 1.807, memory flat, storage static

---

## Full System Architecture

```
iOS App (SwiftUI, ~/HunterHouseApp/HHRCS.xcodeproj)
  │  polls GET /status every 2s
  │  streams MJPEG from GET /stream
  │  polls GET /log?window=300 every 3s (SETTINGS/DIAGNOSTIC event feed)
  │  polls GET /agent-log?limit=50 every 3s (FIELD/AGENT chat)
  │  POST /agent-log/startup on AGENT tab appear (Tier 1 summary)
  │  POST /agent-log/query for user questions (Tier 2 LLM)
  │  POST /control/* for ISO, WB, shutter, record, still
  │  POST /deployments for new deployment creation
  │
  ▼  HTTP (LAN 192.168.1.68 or Tailscale 100.118.27.125)
┌─────────────────────────────────────────────────────────┐
│  Raspberry Pi 4 (4GB, Bookworm Lite 64-bit)            │
│                                                         │
│  hhrcs.service  →  api_server.py  :5001                 │
│  ├── Flask REST API                                     │
│  ├── PiCameraStreamer (picam_stream.py)                  │
│  │     owns single Picamera2 instance                   │
│  │     main: 2304×1296 YUV420 · lores: 1280×720 MJPEG  │
│  ├── Detector (detector.py)                             │
│  │     subscribes to picam_stream.py MJPEG frames       │
│  │     ONNX (onnxruntime 1.25.0, CPUExecutionProvider)  │
│  │     model: models/md_v1000_spruce.onnx (28.5 MB)     │
│  │     3 intra threads · ~550ms/frame (1.77 fps)        │
│  ├── StateMachine                                       │
│  │     IDLE → ACTIVE → HOLDING → COUNTDOWN → IDLE       │
│  ├── SensorReader  (I2C sim fallback)                   │
│  ├── Deployment  (deployment.py)                        │
│  │     active deployment tracking + clip routing        │
│  │     deployments/<id>/agent_log.json per deployment   │
│  └── EventBus  (events.py)                              │
│        ring buffer (5000 events) + JSONL flush/10s      │
│        deployments/<id>/clips/<clip_id>/events.jsonl    │
│                                                         │
└─────────────────────────────────────────────────────────┘
                         │
              ethernet 192.168.10.0/24 subnet
              Pi eth0: 192.168.10.1 (static)
                         │
              BMPCC 6K Pro (192.168.10.2)
              REST API: /control/api/v1
              BRAW 12:1 · 6K · 24fps → CFast/SD
```

---

## Camera Control Architecture (Ethernet — as of 2026-05-04)

```
Pi :5001 (hhrcs)  →─ethernet─→  BMPCC 6K Pro REST API (192.168.10.2)
```

### Ethernet Camera Control

- `camera_http.py`: `BMPCCCameraClient` — `requests.Session`, all calls return `None`/`False` on failure
- `camera_control.py`: thin facade over `BMPCCCameraClient`, preserves public API (`record_start/stop`, `set_iso`, etc.)
- Key endpoints used: `/transports/0`, `/transports/0/record`, `/video/iso`, `/video/whiteBalance`, `/video/gain`, `/system/format`, `/media/active`
- `/system/codecFormat` returns "Not implemented" — use `/system/format` instead
- API paths must NOT have trailing slash (`/system/format` works, `/system/format/` returns 404)
- No auth required on this firmware configuration
- `camera.cam_reachable` → True when HTTP responds

### Ethernet Troubleshooting
1. Check adapter LED (solid/blinking green on camera USB-C port)
2. `ping 192.168.10.2` from Pi
3. `curl http://192.168.10.2/control/api/v1/transports/0` from Pi
4. Verify Web Media Manager enabled in Blackmagic Camera Setup (one-time USB setup from Mac)
5. `nmcli con show camlink` — confirm eth0 autoconnects at 192.168.10.1/24

---

## Event Bus

### Module: `events.py`
In-process telemetry layer. No external broker. Non-blocking — `emit()` never raises.

```python
from events import emit, recent, format_as_log_line, set_session_id

emit("state.transition", {"from_state": "IDLE", "to_state": "ACTIVE", "reason": "..."})
emit("ble.connected", {"device_name": "HHRCS-BRIDGE", "address": "cc:86:ec:e1:38:56"})

events = recent(window_seconds=300, types=["detector.trigger"])
```

### Event Types (active)
| Type | Emitter | Key Payload Fields |
|------|---------|-------------------|
| `system.startup` | api_server | subsystem |
| `system.error` | all | subsystem, error_type, message |
| `state.transition` | state_machine | from_state, to_state, reason |
| `detector.trigger` | detector | confidence, category, bbox, frame_timestamp, model_version |
| `recording.started` | api_server | clip_id, source |
| `recording.stopped` | api_server | clip_id, source, duration_seconds |

Note: BLE/ESP32 event types (`ble.connected`, `ble.disconnected`, `command.sent`, `command.failed`) are in the JSON Schema files but no longer emitted — ESP32 bridge removed 2026-05-04.

### Storage
- Ring buffer: 5000 events in memory (thread-safe deque)
- On-disk: `deployments/<dep_id>/clips/<clip_id>/events.jsonl` when active deployment; otherwise `sessions/<clip_id>/events.jsonl`
- Session rotation: `set_session_id(clip_id, base_dir=...)` opens new JSONL path; ring buffer stays continuous
- Boot sessions: `boot_YYYYMMDD_HHMMSS/events.jsonl` (before first clip) — always in `sessions/`

### /events Deployment Scoping
When an active deployment exists, `GET /events` filters the event stream to events with `ts ≥ deployment.started_at`. This ensures the iOS event log only shows activity from the current deployment, not prior history. Filtering uses `_ts_after(ts_str, cutoff)` which parses both timestamps to timezone-aware datetimes. If no active deployment, full ring buffer is returned.

### JSON Schemas
All 10 event types have JSON Schema v7 files in `schemas/events/`:
```
ble.connected.json      ble.disconnected.json   command.failed.json
command.sent.json       detector.trigger.json   recording.started.json
recording.stopped.json  state.transition.json   system.error.json
system.startup.json
```

### API Endpoints
```
GET /events?window=300[&types=detector.trigger,state.transition]
    → JSON array of events, oldest first, within window_seconds
    → filtered to deployment.started_at when active deployment exists

GET /log?window=300
    → Plain text, one line per event: "HH:MM:SS  LABEL     message"
    LABEL values (8-char left-aligned): TRIGGER · STATE · REC · BLE · CMD · SYSTEM · ERROR
    → NOT deployment-scoped (shows raw ring buffer; used for DIAGNOSTIC event feed)
```

---

## Deployment Architecture

A deployment is a continuous period where the camera is in one physical position, from setup to offload/reposition. It is the top-level organizational unit above individual clips.

### Module: `deployment.py`
```python
from deployment import (
    get_deployments,         # → list of all deployments (newest first)
    get_active_deployment,   # → dict | None
    open_deployment,         # creates new deployment, auto-closes any active one
    close_deployment,        # marks active as closed, accepts optional notes
    increment_clip_count,    # called by api_server._on_record_start when active
)
```

**`open_deployment(name, position="", lat=None, lng=None, bearing=None, notes="", app_version="")`**
- Acquires lock, reads deployments.json
- Calls `_close_active_unlocked(deps)` — silently closes any active deployment (no error raised)
- Creates new deployment dict with all fields including `"app_version"` (iOS app version string)
- Saves deployments.json
- Creates `deployments/<dep_id>/` folder on disk (outside lock)
- Returns new deployment dict

**`close_deployment(notes="")`**
- Marks active deployment `status: "closed"`, sets `closed_at` to UTC ISO8601
- If `notes` provided, stores as `"closing_notes"` in the dict
- Returns the closed deployment dict, or None if no active deployment

### Deployment Dict Schema
```json
{
  "id":            "dep_YYYYMMDD_HHMMSS",
  "name":          "HUNTER HOUSE",
  "position":      "North Meadow facing NE",
  "lat":           48.515,
  "lng":           -123.408,
  "bearing":       null,
  "notes":         "",
  "app_version":   "0.4.2",
  "started_at":    "2026-04-27T23:05:07.694235+00:00",
  "closed_at":     null,
  "clip_count":    5,
  "status":        "active",
  "closing_notes": "optional, only present if notes passed to close_deployment()"
}
```

### Folder Structure (on-disk, active)
```
/home/pi/hhrcs/
├── data/
│   └── deployments.json           ← all deployments registry (newest first)
└── deployments/
    └── dep_YYYYMMDD_HHMMSS/
        ├── agent_log.json          ← deployment-scoped agent exchanges
        └── clips/
            └── hhrcs_YYYYMMDD_HHMMSS/
                ├── events.jsonl
                └── sidecars/
                    └── hhrcs_YYYYMMDD_HHMMSS_trigger.json
```

**Clip routing**: In `_on_record_start()`, `api_server.py` checks for an active deployment and passes `base_dir=Path("deployments/<dep_id>/clips/<clip_id>")` to `set_session_id()`. Without an active deployment, clips fall back to `sessions/<clip_id>/` (old structure, still supported).

### Workflow
1. **NEW DEPLOYMENT**: tap in SETTINGS → fill name/position/bearing → Pi creates folder + deployments.json entry; any previous active deployment is auto-closed
2. **CLOSE DEPLOYMENT**: tap CLOSE in SETTINGS → custom sheet with optional notes → Pi marks closed_at, stores closing_notes
3. **Offload**: rsync `deployments/<dep_id>/` to house drive after closing — self-contained, atomic

### API Endpoints
```
GET  /deployments              → list of all deployments (newest first)
GET  /deployments/active       → {"active": bool, "deployment": dict | absent}
POST /deployments              → create new deployment; body: {name, position?, lat?, lng?, bearing?, notes?, app_version?}
                               → 201 on success, auto-closes existing active deployment
POST /deployments/close        → close active deployment; body: {notes?}
                               → 404 if no active deployment
```

---

## Agent Architecture

### Two-Tier Design

| Tier | When | Requires |
|------|------|----------|
| Tier 1 — rule-based | Always available | Nothing — pure Python |
| Tier 2 — LLM | On query; falls back to Tier 1 | `ANTHROPIC_API_KEY` in environment |

**Tier 1 `build_summary()`** — constructs a structured snapshot from live system state:
- Detection counts: `detections_1h`, `detections_24h`, `last_detection`, `last_detection_confidence`
- Camera: `cam_reachable`, `cam_recording` (from BMPCC REST API)
- System: `state`, `sim_mode`, `in_window` (astral dawn/dusk check), `cpu_temp_c`
- Sensor/environment (via `sensors.to_dict()`): `lux`, `ev`, `temperature_c`, `humidity_pct`, `pressure_hpa`, `dew_point_c`, `hardware_lux`, `hardware_env`
- Camera/storage: `iso`, `ssd_free_gb`
- `anomalies` list — auto-detected conditions:
  - CPU temp >72°C
  - No detections in 24h during active recording window
  - State stuck in COUNTDOWN or HOLDING >20min
- `summary_line` — passive template: `"[N] detections. [Recording active/No recording.] Pi stable. BMPCC reachable/unreachable."`

**Tier 2 `query_agent(question)`** — builds context from Tier 1 snapshot, loads `memory.md` alongside `CONTEXT.md`, calls `claude-haiku-4-5-20251001`. Context block sections: SYSTEM STATE · ENVIRONMENT (hardware/simulated label) · LIGHT (hardware/simulated label) · CAMERA & STORAGE · ANOMALIES · RECENT EVENTS (last 30 min) · RECENT AGENT EXCHANGES (last 10) · DEPLOYMENT. On API failure or missing key: falls back to Tier 1, returns `type: "summary"` entry instead of `type: "query"`.

**Note-taking shortcut** — if query begins with "make a note", "remember", "note that", etc.: writes `- [YYYY-MM-DD] text` to the appropriate section (Field/System/Observations) in `memory.md`, returns Tier 1 response without calling the Claude API.

**System prompt** (current): Plain-facts, no interpretation unless asked. Report what sensors read, what the system is doing, what has been detected. No markdown, no headers, no bullet points, no figurative language, no editorializing, no description of own function. One to four sentences. Answer as if already inside the situation.

### Deployment-Scoped Agent Log
Agent log entries are written to `deployments/<dep_id>/agent_log.json` when an active deployment exists, otherwise to `data/agent_log.json` (fallback).

- `_read_log(log_path=None)` — reads from `log_path` or global fallback
- `_append_log(entry, log_path=None)` — writes to `log_path` or global fallback, creates dirs
- In `query_agent()`: computes `agent_log_path` from active deployment, reads prior context from it (last 10 entries), writes new entry to it
- In `run_passive_summary()`: same path logic, writes summary entry, **returns the entry dict**

### Agent Log Entry Schema
```json
{
  "id":        "agent_YYYYMMDD_HHMMSS",
  "timestamp": "ISO8601 UTC",
  "type":      "query | summary",
  "tier":      1,
  "query":     "user question string or null",
  "response":  "response text",
  "context_snapshot": {
    "state":                     "IDLE",
    "cam_reachable":             true,
    "cam_recording":             false,
    "cam_codec":                 "ProRes",
    "cam_codec_variant":         "Proxy",
    "cam_active_media_slot":     "SD",
    "cam_remaining_record_time": 2460,
    "cam_media_volume":          "...",
    "cam_media_clip_count":      5,
    "cam_media_space_remaining_gb": 4.1,
    "cam_shutter_angle":         180.0,
    "cam_iso":                   1600,
    "cam_white_balance":         7500,
    "cpu_temp_c":                40.9,
    "detector_threshold":        0.6,
    "window_open":               true,
    "dawn_dusk_enabled":         false,
    "manual_override":           false,
    "external_drives":           [],
    "pi_sd_used_pct":            35.6,
    "uptime_s":                  3901,
    "recent_trigger_count":      0,
    "anomalies":                 [],
    "deployment_id":             "dep_YYYYMMDD_HHMMSS",
    "deployment_name":           "HUNTER HOUSE"
  }
}
```
`"tier"` field: `2` when Tier 2 LLM responded, `1` when Tier 1 rule-based (including fallback). `sim_mode` removed from context_snapshot — Pi-side detector sim mode is controlled by `.sim_mode` flag file, not tracked in the agent log schema.
`"tier"` field: `2` when Tier 2 LLM responded, `1` when Tier 1 rule-based (including fallback).

### Passive Scheduler
`run_passive_summary()` fires 60s after service startup, then every 300s. Tier 1 only — never calls Claude API. Writes `type: "summary"`, `tier: 1` to the deployment-scoped agent log. Returns the entry dict (used by `/agent-log/startup` endpoint).

### Startup Endpoint
`POST /agent-log/startup` — called by the iOS AGENT tab on appear and after new deployment creation. Calls `agent.run_passive_summary()` and returns the entry immediately. Writes to the deployment-scoped agent log. No Tier 2 (no API key needed, no cost).

### Configuration
`ANTHROPIC_API_KEY` set in `/etc/systemd/system/hhrcs.service` Environment block. Tier 1 works without it. Tier 2 silently falls back if absent.

### /agent-log Deployment Scoping
`GET /agent-log` serves from `deployments/<active_id>/agent_log.json` when an active deployment exists, otherwise from `data/agent_log.json`. This means the iOS AGENT tab shows only the current deployment's exchanges — no prior deployment history bleeds through.

### Camera Reachability Note
`cam_reachable: false` = BMPCC ethernet not connected or Web Media Manager not enabled. Check adapter LED and `ping 192.168.10.2` from Pi.

---

## Detector

### MegaDetectorLite (MDv1000-spruce)
- **Model**: YOLOv5s backbone, camera-trap specific, 3 classes: animal / person / vehicle
- **File**: `models/md_v1000_spruce.onnx` — FP32, 28.3 MB, opset 12, **416×416 input** (re-exported Part 6, 2026-05-07). Backup of 640 model at `models/md_v1000_spruce_640.onnx.bak`.
- **Backend**: onnxruntime 1.25.0 (CPUExecutionProvider)
- **Thread config**: `intra_op_num_threads=3`, `inter_op_num_threads=1`, `ORT_SEQUENTIAL`, `ORT_ENABLE_ALL` — Pi 4 has 4 cores; leaves 1 for system/Flask/capture. Bumped from 2 in Part 5 (2026-05-07). If stability issues arise, drop back to 2.
- **Input**: [1, 3, 416, 416] float32 — letterboxed, normalized (re-exported at 416×416 in Part 6 for ~2x speedup; was 640×640)
- **Output**: [1, 10647, 8] — [cx, cy, w, h, obj_conf, animal_conf, person_conf, vehicle_conf] (was [1,25200,8] at 640)
- **Postprocessing**: pure NumPy — sigmoid applied at export, obj_conf × cls_conf, greedy NMS
- **Frame source**: detector opens its own Picamera2 at `config.pi_cam_resolution` (1152×648 output). Sensor mode forced to 2304×1296 via `raw={"size": config.pi_cam_sensor_mode}` in `create_video_configuration()`. Without this raw= argument, Picamera2 auto-selects the 1536×864 cropped sensor mode for any output below 1536px wide, reducing FOV to ~82°. With raw= forcing 2304×1296, full 102° FOV is preserved at 1152×648 output. `pi_cam_sensor_mode: Tuple[int, int] = (2304, 1296)` in config.py. Single Picamera2 instance shared between _capture_thread_loop and _camera_stream_loop. (⚠ see Known Issues — conflicts with picam_stream.py)
- **Rate**: baseline 0.53fps at 640×640, 2 threads. After Part 5+6: 3 threads + cv2 + 416×416. **Post-deploy fps: 1.77 fps** (2.7× speedup; ~550ms/frame).
- **Rollback to 640**: `mv models/md_v1000_spruce_640.onnx.bak models/md_v1000_spruce.onnx` + `_MODEL_INPUT_SIZE = 640` in detector.py + scp + restart.
- **Coral USB Accelerator**: Considered as hardware acceleration path; chip shortage has inflated pricing to $200+ (normal $60). Not pursuing. Revisit when pricing normalizes.
- **Confidence threshold**: 0.6 (configurable in config.py)
- **Trigger**: "animal" category detections → `emit("detector.trigger", ...)` → state machine callback

### Mac-side tools (`~/HunterHouseApp/tools/`)
- `do_export.py` — torch.hub → ONNX export (avoids yolov5/requirements.txt)
- `export_spruce_onnx.sh` — full shell: downloads .pt, venv, runs export
- `speciesnet_pass.py` — post-session: scans sessions/ for null sidecars, extracts crops via ffmpeg, runs SpeciesNet (CAN/BC region), writes classification back

---

## Simulation Mode — Pi Side Only (iOS sim mode removed)

**iOS sim mode toggle: REMOVED.** The iOS `simulationMode` AppStorage key and its toggle in SETTINGS are no longer present. iOS starts with empty data and populates from Pi `/status` polls only.

**Pi-side sim mode** (detector gating — still active as an operator override):

Two independent sim systems existed: Pi-side (gates ONNX inference and camera commands) and iOS-side (seeds UI data when no Pi URL is configured). iOS side was removed. Pi side remains as an operator safety gate.

### Pi-Side Sim Flags — Real-Mode Gating (all four required)

`detector.py` sets `_using_real = True` only when **all four** conditions are met at startup:

1. `picamera2` is importable (Pi camera library in venv)
2. `onnxruntime` is importable (ONNX inference library in venv)
3. `DETECTOR_ENABLED` env var is **unset** OR its value is not `"0"` (service default: `DETECTOR_ENABLED=1`)
4. Flag file `/home/pi/hhrcs/.sim_mode` does **NOT exist**

| Flag | Location | Mechanism |
|------|----------|-----------|
| `.sim_mode` flag file | `/home/pi/hhrcs/.sim_mode` | Presence → `_flag_enabled = False` → `_using_real = False` |
| `DETECTOR_ENABLED=0` env var | `hhrcs.service` Environment block | Sets `_env_enabled = False` → `_using_real = False` |

The `.sim_mode` flag file is the preferred runtime toggle — create it to disable inference, delete it to re-enable. A service restart is required to pick up either change. Removed `.sim_mode` on 2026-05-07 to enable real inference; first confirmed detection at `2026-05-07T19:00:24 UTC` (animal, conf=0.77).

**iOS sim mode toggle is cosmetic only** — the SETTINGS toggle updates `@AppStorage` on-device but makes no network call to the Pi. It does not create/remove the `.sim_mode` flag file or change `DETECTOR_ENABLED`. To actually toggle Pi sim mode, use SSH. Wiring the toggle to a `POST /detector/sim_mode` endpoint is a future task (open issue).

### Key Invariants

1. **`simulationMode` in iOS does not affect the Pi.** It only gates the fake-detection push notification. The Pi's sim state is controlled entirely by the `.sim_mode` flag file on the Pi.

2. **iOS `tick()` simulation no longer drifts sensor fields.** Lux, temperature, humidity, pressure, and dew point drift removed from `tick()`. These fields are `Double?` and initialize to nil — they populate from Pi `/status` polls or stay nil when Pi is unreachable. CPU temp (`Double`) and SSD sim are unaffected.

3. **`piServerURL.isEmpty` (not `simulationMode`) gates AI log seeding.** Once a Pi URL is configured, `pollAgentLog()` takes over and real entries replace the simulated ones. Fake stills (`CapturedStill.simulatedEntries()`) and fake session log (`SessionLogStore.simulatedEntries()`) were removed in the May 2 fix pass — these now start empty and populate only from Pi data.

4. **`_camera_started` decouples start/stop symmetry.** In sim mode, `_on_record_stop` will never call `camera.record_stop()` unless `_on_record_start` set `_camera_started = True`. This prevents bridge errors on stop when start was skipped.

5. **Sensors return `None` when hardware is absent** (not simulated values). `sensors.py` functions `read_lux()`, `read_ev()`, `read_temperature()`, `read_humidity()`, `read_pressure()`, `read_dew_point()` all return `None` when no I2C hardware is detected. iOS renders `--` in `Theme.tertiary` for null fields. CPU temp (`vcgencmd measure_temp`) is always real.

6. **`_sim_loop` triggers the real state machine.** Fake detections follow the full IDLE → ACTIVE → HOLDING → COUNTDOWN path — they will attempt BLE record commands unless the camera guard stops them.

7. **Manual record always reaches the BMPCC.** `TriggerType.MANUAL` bypasses the sim guard — `_on_record_start` gates on `trigger == MANUAL or detector._using_real`.

### To disable Pi sim mode (enable real inference)
```bash
rm /home/pi/hhrcs/.sim_mode
sudo systemctl restart hhrcs
# confirm:
curl http://192.168.1.68:5001/status | python3 -m json.tool | grep yolo_sim_mode
# should return: "yolo_sim_mode": false
```

### To enable Pi sim mode (disable inference, no camera commands from detector)
```bash
touch /home/pi/hhrcs/.sim_mode
sudo systemctl restart hhrcs
```

---

## Known Issues

| Severity | Issue | File | Notes |
|----------|-------|------|-------|
| `open/medium` | iOS sim mode toggle is cosmetic — does not flip Pi `.sim_mode` flag or `DETECTOR_ENABLED` env var | `SettingsTabView.swift` | Future fix: `POST /detector/sim_mode` endpoint on Pi; or remove iOS toggle. Discovered 2026-05-07. |
| `resolved` | Detector inference speed — 1.77 fps achieved (2.7× speedup from 0.53fps baseline) | `detector.py` | Part 5: threads 2→3, ORT_SEQUENTIAL, cv2 (→~0.7fps). Part 6: 416×416 re-export (→1.77fps, ~550ms/frame). Budget warning threshold updated to 600ms. |
| `fixed` | `detections.jsonl` write failed: `float32 not JSON serializable` | `detector.py` | `confidence` and `bbox` values from onnxruntime are numpy float32 — `json.dumps()` can't serialize them. Fixed 2026-05-07 (Part 4): cast to `float()` before `round()` in `_dispatch()`. |
| `fixed` | `config.detector_confidence_threshold` NameError — bare `config` vs aliased `_config` | `detector.py:213` | Import at line 33 is `from config import config as _config`; line 213 used unaliased `config`. Pi patched via `sed -i` in Part 4 session; Mac copy fixed and committed same session. |

## Deployment Readiness Checklist

### Phase A — System Validation (current)
- [x] Pre-deployment cleanup: address search in SETTINGS (MapKit autocomplete), stale /snapshot 404 eliminated, storage snapshots loader hardened against empty/corrupt JSON (2026-05-08 Part 1)
- [x] Observability for burn-in: CPU temp 65°C warning ntfy tier added; system_logger.py writes system_metrics_YYYY-MM-DD.jsonl every 60s; /status exposes uptime_s + system_log_path; iOS SETTINGS shows UPTIME (2026-05-08 Part 2)
- [x] Active cooling installed and confirmed: 5V fan on GPIO 5V/GND pins, running. Thermal ceiling 46.3°C under full 3-thread inference load — 34°C below throttle threshold
- [x] Thread count benchmarked: intra_op_num_threads=3 confirmed correct (May 8, 2026; 2 threads failed fps floor)
- [x] 24-hour burn-in: completed May 9, 2026 — 9.53h clean window, zero throttling events, zero connectivity drops, fps mean 1.807, memory flat, storage static
- [x] window_open bug fixed: dawn_dusk_enabled=false → window always open (state machine always eligible to record)
- [x] detection_event() gate enforced
- [x] Auto-recording on startup fixed: state machine initializes IDLE
- [x] Notification spam fixed: stills and recordings split into separate toggles
- [x] CONTEXT.md audit completed: May 9, 2026
- [ ] BMPCC trigger chain end-to-end: animal detection → state machine ACTIVE → camera records → HOLDING → COUNTDOWN → IDLE confirmed with real BMPCC
- [ ] Tailscale connectivity: confirmed reachable from cellular (Pi Tailscale IP 100.118.27.125 already active; iOS multi-URL switcher already present)

**Remaining before Hunter House field deployment:**
- [ ] CFast or V90 SD card for 6K BRAW recording (current ProRes Proxy 1920×1080 on SD is for testing only)
- [ ] Physical enclosure build: radiant liner, shade shield, screened vents, desiccant
- [ ] Rode NTG boom mount and 3.5mm cable routing through Pelican 1400
- [ ] First field deployment: Prospect Lake North Meadow

### Phase B — First Field Deployment
- [ ] Overnight in yard or driveway (controlled environment, recoverable if something fails)
- [ ] Footage review: BRAW clips playback, timecodes align with detection log timestamps
- [ ] Battery / power budget measured for target site duration (2–3 days unattended)

### Phase C — Remote Deployment Prep
- [ ] Power budget confirmed (Pi + BMPCC + camera + capture card at idle/active load)
- [ ] Weatherproofing: Pelican 1400 cable routing, desiccant, condensation plan
- [x] Active cooling installed (5V fan on GPIO pins — confirmed running, 46.3°C ceiling)
- [ ] Cellular fallback at remote site (mobile hotspot, LTE hat, or Starlink Mini). Tailscale relies on at least one network path reaching the Pi from the internet — without WiFi or cellular at the deploy site, the system is local-only.
- [ ] Cellular fallback: Tailscale confirmed reachable over mobile hotspot from deployment site
- [ ] Media capacity: CFast card for 6K BRAW 12:1 65 MB/s full deployment window

### Phase D — Future Enhancements
- [ ] iOS sim mode toggle → wired to `POST /detector/sim_mode` Pi endpoint (currently cosmetic)
- [ ] Coral USB Accelerator — revisit when pricing normalizes ($60 normal; currently $200+ shortage)
- [ ] Species classifier: SpeciesNet or fine-tuned ResNet on top of MegaDetector bbox crops
- [ ] Time-of-day scheduling: dawn/dusk windows via `astral` + TSL2591 lux sensor (I2C not yet wired)
- [ ] H264 proxy recording on Pi: background `ffmpeg` from HDMI capture card alongside BRAW
- [ ] Auto-lux: ISO / aperture suggestions based on lux reading pushed to iOS
- [ ] Connect BME280 + TSL2591 I2C sensors to Pi for real environmental + lux readings

---

## Pi File Structure

```
/home/pi/hhrcs/
├── venv/                  Python 3.13 (--system-site-packages)
├── config.py              deployment parameters (dataclass Config)
├── state_machine.py       ACTIVE/HOLDING/COUNTDOWN logic + event emits
├── session.py             session/notes logging
├── sensors.py             real I2C reads + sim fallback
├── detector.py            MegaDetectorLite ONNX + Picamera2 + sim fallback
│                          ⚠ opens its OWN Picamera2 — conflicts with picam_stream.py
├── camera_http.py         BMPCCCameraClient: requests.Session → BMPCC REST API
├── camera_control.py      Thin facade over BMPCCCameraClient (record_start/stop, set_iso, etc.)
├── api_server.py          Flask REST API (port 5001)
├── agent.py               Two-tier agent: Tier 1 rule-based + Tier 2 Claude Haiku
│                          loads memory.md + CONTEXT.md on every Tier 2 call
│                          note-taking shortcut: writes to memory.md sections
│                          writes to deployment-scoped agent_log.json
│                          run_passive_summary() returns entry dict
├── deployment.py          Deployment lifecycle: open/close/increment_clip_count
│                          auto-close on new deployment, app_version field
│                          creates deployments/<id>/ folder on open
├── memory.md              Agent's writable persistent memory (Field/System/Observations notes)
├── events.py              Event bus (ring buffer + JSONL flush)
├── system_logger.py       Writes system_metrics_YYYY-MM-DD.jsonl every 60s
├── notifications.py       Notification queue: emit()/unread()/mark_read()/recent()
│                          persists to data/notifications.json (capped 500, newest-first)
├── notifier.py            ntfy.sh Layer 2 push: send_alert() · evaluate_and_notify(summary)
│                          4 conditions, 6-hour in-memory dedup
├── storage_monitor.py     SSD burn-rate tracking: df -B1, daily snapshots, days_remaining
├── hdmi_stream.py         HDMIStreamer: OpenCV V4L2 MJPEG reader on /dev/video2
│                          start/stop/is_open/capture_jpeg/generate_mjpeg
│                          black JPEG placeholder on no-frame; 25fps yield loop
├── picam_stream.py        PiCameraStreamer (dual stream — owns single Picamera2 instance)
│                          main: 2304×1296 YUV420 · lores: 1280×720 MJPEG
│                          detector subscribes via attach_to_streamer()
├── hhrcs.service          systemd unit (copies in /etc/systemd/system/)
├── models/
│   └── md_v1000_spruce.onnx   MegaDetectorLite model (28.5 MB)
├── schemas/
│   └── events/            10 JSON Schema v7 files (one per event type)
├── data/
│   ├── deployments.json   all deployments registry (newest first)
│   ├── sessions.json      legacy session log (pre-deployment)
│   ├── agent_log.json     fallback agent log (used when no active deployment)
│   ├── field_notes.json   field notes
│   └── storage_snapshots.json   daily SSD used_bytes snapshots (7 max, newest first)
├── deployments/           per-deployment folders (created by open_deployment())
│   └── dep_YYYYMMDD_HHMMSS/
│       ├── agent_log.json     deployment-scoped agent exchanges (tier 1 + 2)
│       └── clips/
│           └── hhrcs_YYYYMMDD_HHMMSS/
│               ├── events.jsonl
│               └── sidecars/
│                   └── <clip_id>_trigger.json
├── sessions/              legacy clip folders (when no active deployment)
│   └── hhrcs_YYYYMMDD_HHMMSS/
│       ├── events.jsonl
│       └── sidecars/
├── stills/
│   ├── latest.jpg         most recent Pi cam JPEG (~20 KB)
│   └── hdmi/
│       └── latest.jpg     most recent HDMI capture JPEG
└── logs/
    └── hhrcs.log
```

---

## iOS/macOS App (HHRCS)

Location: `~/HunterHouseApp/HHRCS.xcodeproj`
Bundle ID: `com.brandonpoole.hhrcs` · Targets: iOS 17 + macOS 14
Version: **0.4.2 (build 1)** — set via `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` in project.pbxproj
Distribution: TestFlight to Brandon, Julian, friends

### Tab Structure
- **FEED** (tab 0, **default on launch**) — `CameraTabView.swift`. Top tab strip (BMPCC / CAM labels left, refresh button right) with hairline below. Feed fills middle space. Bottom control strip with hairline above and below.
  - **BMPCC page**: HDMI still (StillPoller, 5s auto-refresh). Bottom strip: `[record][ISO][WB][SHUTTER][still]` — owner mode only; non-owner sees still button only. ISO/WB/SHUTTER tap opens inline chip strip overlaying feed from bottom. Refresh button in tab strip row.
  - **CAM page**: Pi cam still (StillPoller, 5s auto-refresh). Bottom strip: still button only, centered.
- **FIELD** (tab 1) — `NotesTabView.swift`. Sub-pages (swipeable TabView): STILLS (default) · AGENT · LOG
  - STILLS: Pi cam + HDMI stills gallery. Long-press to delete; `ConfirmationCard` full-screen scrim at gallery level.
  - AGENT: chat view — SUMMARY entries render as pinned plain-text status at top; QUERY entries render as `ChatExchangeView` (user right-aligned outline bubble, agent left-aligned filled bubble with `settings.activeColor.opacity(0.15)` background). Pinned query compose bar at bottom (POST /agent-log/query). On appear: fires `POST /agent-log/startup` (Tier 1 summary). User messages appear optimistically on send; `TypingIndicatorView` (3 pulsing dots) shows while waiting for response.
  - LOG: SUMMARY entries only as plain log lines (timestamp + content); QUERY entries do not appear here.
- **DATA** (tab 2) — `DataTabView.swift`. Pure instrument panel: SYSTEM health dots · ENCLOSURE · WEATHER · ASTRO · STORAGE (only shown when external_drives non-empty) · CAMERA
  - Camera card: CODEC·VARIANT / SHUTTER ANG / ISO / WHITE BAL / GAIN / MEDIA SLOT / REC TIME LEFT / FORMAT / MEDIA VOL / CLIP COUNT / SPACE REM
- **SETTINGS** (tab 3) — `SettingsTabView.swift`. SectionCards top to bottom: DIAGNOSTIC · ENCLOSURE · DEPLOYMENT · REFRESH INTERVAL · DETECTOR THRESHOLD · ACCESS · SYSTEM · AGENT · NOTIFICATIONS · DEPLOYMENT CHECKLIST · DISPLAY
  - Diagnostic dots: PI · BMPCC · CAM · YOLO · HDMI (connectivity) | PI SD · CAM SD · CAM CF (storage)
  - SYSTEM section: DAWN/DUSK WINDOWS toggle only
  - NOTIFICATIONS: master PUSH NOTIFICATIONS + RECORDINGS · STILLS · ANIMAL DETECTIONS · DEPLOYMENTS · SYSTEM ERRORS · AGENT REPORTS
  - DISPLAY: WARM UI toggle (default ON)

### DEPLOYMENT Card (SETTINGS tab)
- **SITE / POSITION / LAT / LONG / URL** — editable fields, FocusState-driven colors (editing=white, set=secondary, empty=tertiary placeholder)
- **Divider** (HRule) above action zone — visual separation from fields
- **NEW DEPLOYMENT** button — `settings.activeColor`, opens `NewDeploymentSheet`
- **CLOSE** button — `settings.activeColor`, trailing; only visible when `piDepActive == true`; opens `CloseDeploymentSheet`
- No PI DEPLOYMENT info block — removed (name/position/clip count display was removed from Settings)
- `pollDeploymentStatus()` — called on appear and after create/close; hits `GET /deployments/active`

### NewDeploymentSheet
Full-screen sheet: site, position, lat, lng, bearing, notes fields. On submit: reads `CFBundleShortVersionString` from Bundle and includes as `"app_version"` in POST body. On 201 success: calls `vm.resetForNewDeployment()` — clears event log + agent chat, increments `deploymentChangeCount` to trigger AGENT tab reset.

### Multi-URL Server Switcher (SETTINGS tab)
Replaces the previous single text field. Implemented May 1, 2026.

- `AppSettings.savedServerURLs: [String]` persisted to UserDefaults
- First launch seeds: `raspberrypi.local:5001` (LAN) and `100.118.27.125:5001` (Tailscale IP)
- Subsequent launches load whatever the user has saved
- Each saved URL renders as a tappable row: active URL has a filled `settings.activeColor` dot; inactive rows have an empty ring in `Theme.tertiary`
- Tap any row → immediately sets it as the active URL and reconnects (no save button needed)
- `+ ADD` expands an inline text field with `SAVE` / `CANCEL`
- `SAVE` deduplicates against existing URLs, selects the new URL as active, collapses the field
- All rows separated by `HRule` to match the rest of the SETTINGS card pattern
- Recommended additions for new deployments: `hhrcs-pi:5001` (Tailscale magic DNS — works anywhere a tailnet device is signed in)

### CloseDeploymentSheet
Custom dark sheet (Theme.cardBackground background, SF Mono throughout). Shows deployment name. Optional notes TextField with `settings.activeColor` border. **CONFIRM CLOSE** in `settings.activeColor`, **CANCEL** in muted grey. No system alert. On confirm: POSTs `{"notes": "..."}` to `/deployments/close`.

### LaunchView (redesigned May 1, 2026)
Black background ZStack. HHRCS acrostic letter block centered on screen:
- **H**/UNTER, **H**/OUSE, **R**/EMOTE, **C**/AMERA, **S**/YSTEM
- Each row: 36pt heavy `Theme.warmAccent.opacity(0.82)` acrostic letter + 10pt monospaced white trailing word at tracking 4.0
- VStack spacing -6 to tighten the block
- Old "HHRCS / deployment name / REMOTE CAMERA SYSTEM / position" left-aligned block removed
- Version string `v0.4.2 (1)` remains pinned to bottom of screen, `Theme.secondary`, 9pt SF Mono, fades with launch animation

### Version Display
- **LaunchView**: `v0.4.2 (1)` pinned to bottom of screen via ZStack overlay, `Theme.secondary` color, 9pt SF Mono. Fades out with the rest of the launch view via `.opacity(opacity)`.
- **Settings**: `versionRow` — last item in the settings ScrollView VStack. Shows `"Version 0.4.2 (build 1)"` centered, 10pt SF Mono, `Theme.secondary`. Non-interactive.
- Both read live from `Bundle.main.infoDictionary` — never hardcoded.

### Deployment Reset (DataViewModel)
`resetForNewDeployment()` — clears `eventLog = []` and `aiLogEntries = []`, then increments `deploymentChangeCount`. The AGENT tab observes `deploymentChangeCount` via `onChange` and resets all startup state, fires a fresh `POST /agent-log/startup`.

### Controls (operator mode only — FEED tab BMPCC page bottom strip)
- **ISO chip strip**: 8 stops — 100 · 200 · 400 · 800 · 1600 · 3200 · 6400 · 12800
- **WB chip strip**: 6 named presets ascending by kelvin — TUNG(3200) · FLUORO(4000) · FLASH(5500) · DAYLGT(5600) · CLOUDY(6500) · SHADE(7500)
- **SHUTTER chip strip**: 6 cinema angles — 45° · 90° · 135° · 180° · 270° · 360°
- Chip strips slide up overlaying bottom of feed; tap feed or same label to dismiss; black background
- Record button: outline when idle, filled red when recording, pulses (breathe animation) when finalizing — no text overlay
- ND removed — physical dial, not electronically controllable

### STILL Page Flow
Auto-capture on appear: 1s settle → POST /still/trigger → 2s wait → GET /stills/latest
Data bar: `● REC timecode · ISO · WB · shutter°` — each tappable in operator mode

### DATA Tab
Pure instrument panel: SYSTEM health dots · ENCLOSURE · WEATHER · ASTRO · STORAGE · CAMERA. Event log is in SETTINGS/DIAGNOSTIC.
Connectivity health dots: PI · BMPCC · CAM · YOLO · HDMI.
Storage health dots: PI SD · CAM SD · CAM CF.
Camera card rows: CODEC+VARIANT / SHUTTER ANG / ISO / WHITE BAL / GAIN / MEDIA SLOT / REC TIME LEFT / FORMAT / MEDIA VOL / CLIP COUNT / SPACE REM.

### SETTINGS Tab — DIAGNOSTIC Card
Collapsible (closed by default). Contains:

**System advisory line** (above health dots): evaluates dependency chain (PI → BMPCC → YOLO) and shows first failure:
- `"PI UNREACHABLE · ALL SYSTEMS OFFLINE"` — danger red, when PI unreachable
- `"BMPCC UNREACHABLE · CAMERA CONTROL OFFLINE"` — danger red, when BMPCC unreachable
- `"DETECTOR IN SIM MODE · TAP YOLO TO RESET"` — warmAccent/text1, when YOLO in sim
- `"ALL SYSTEMS NOMINAL"` — `Theme.tertiary`, when healthy
- 9pt SF Mono, tracking 1.5, centered. Updates on 2s poll cycle.

**Connectivity health dots: PI · BMPCC · CAM · YOLO · HDMI**
**Storage health dots: PI SD · CAM SD · CAM CF**
- **PI dot** — tappable: inline dropdown → `"RESET HHRCS"` button. Calls `POST /system/restart-hhrcs`.
- **YOLO dot** — tappable: inline dropdown → `"RESET DETECTOR"` button. Calls `POST /system/restart-detector`.
- Dropdowns mutually exclusive, animated `easeInOut(duration: 0.2)`.

**Event log**: 5-row visible scroll, filter chips ALL/TRIGGER/STATE/REC from `GET /log?window=300`.

**Red badge** on SETTINGS tab icon when PI unreachable or BMPCC unreachable.

### Agent Compose Bar (NotesTabView.swift — updated May 1, 2026)
- Orange `RoundedRectangle` border removed from compose bar
- Replaced with `HRule` below the input row to match the `HRule` above — clean line-only separator, no box

### BLE Reconnect Recording Bug Fix (DataViewModel.swift — May 1, 2026)
`seenNotRecording` guard re-armed on every BLE reconnect:
- `let wasConnected = healthBleConnected` captured before state update
- `if bleUp && !wasConnected { seenNotRecording = false }` on reconnect
- Prevents stale `recording:true` from Pi lighting the record button immediately when BLE reconnects after a drop

### Simulation Server (Mac)
Location: `~/Desktop/hhrcs-sim/` · Port 5001
Mirrors core Pi API — develop app against this, point at Pi when ready. **Does not implement** /deployments, /events, /agent-log/startup, or deployment-scoped endpoints.

---

## Visual Design Language

### Core Identity
`Theme.background` = black · `Theme.surface` = #0E0E0E · monochrome token system · `#CC3333` recording red · SF Mono throughout · Braun/TE/Intellijel aesthetic — instrument, not consumer app

### Monochrome Token System
- `Theme.text1` = white 96% — primary readouts, active values
- `Theme.text2` = white 62% — secondary readouts
- `Theme.text3` = white 34% — sublabels, muted info
- `Theme.tertiary` = white 30% — section headers, dividers (same as text3, used by name)
- `Theme.surface` = #0E0E0E — card backgrounds
- `Theme.rule` = white 6% opacity — hairlines/dividers
- `Theme.ruleWidth` = 0.5pt

### Active Color System
`settings.activeColor` — computed on `AppSettings.shared`:
- `warmUI = true` → `Theme.warmAccent` (amber) — opt-in via WARM UI toggle in SETTINGS
- `warmUI = false` → `Theme.text1` (white)
Used for: active tab labels, active chip strip chips, DATA/SETTINGS page titles, agent bubble background tint.

### Semantic Colours
| Token | Hex | Use |
|-------|-----|-----|
| `Theme.warmAccent` | amber | settings.activeColor when warmUI on |
| `Theme.recordingRed` | #CC3333 | Record button active, FEED tab icon when recording |
| `ok` (green) | system green | Diagnostic health dots |
| `danger` | #FF3B30 | Destructive actions |

### Typography
- `Theme.label(size:11)` = 11pt monospaced — tab labels, page headers, chip strips
- `Theme.labelTracking` = 1.8 — used with all monospaced labels
- Font sizes: label(11), body(14), display(17) — three-size system, no mixing within a card

### Card Pattern
All settings sections and DATA panels: `Theme.surface` (#0E0E0E) background, `Theme.cardRadius` (8pt) corner radius, 16pt internal padding, section label in tertiary at top left.

### NeutralToggleStyle
Monochrome 38×22 pill toggle. Active = `settings.activeColor`.

---

## REST API Endpoints

```
GET  /status              full system state (polled every 2s)
                          includes: deployment_id, deployment_name,
                          detections_since_deployment (ring-buffer count since started_at)
GET  /health              {"ok":true,"cam_reachable":bool,"uptime":int}
GET  /sessions            legacy session log (stored in data/sessions.json)
GET  /notes               field notes (stored in data/field_notes.json)
POST /notes               {"author": "Brandon", "text": "..."}

GET  /agent-log           deployment-scoped agent log (deployments/<id>/agent_log.json
                          if active deployment, else data/agent_log.json); newest-first, ?limit=N
POST /agent-log/startup   fires run_passive_summary() → Tier 1 entry; writes to deployment log;
                          returns entry dict. Called by iOS on AGENT tab appear + deployment reset.
POST /agent-log/query     {"question": "..."} → Tier 2 Claude Haiku or Tier 1 fallback;
                          writes to deployment log; returns entry dict
GET  /diagnostics         Tier 1 build_summary() live snapshot — no log write, no API key needed

GET  /deployments         list of all deployments (newest first)
GET  /deployments/active  {"active": bool, "deployment": {...} | absent}
POST /deployments         create new deployment; body: {name, position?, lat?, lng?,
                          bearing?, notes?, app_version?}; auto-closes active; 201 on success
POST /deployments/close   close active deployment; body: {notes?}; 404 if none active

GET  /events?window=N[&types=x,y]   merged event stream (hhrcs + bridge), JSON array
                                    filtered to deployment.started_at when active deployment
GET  /log?window=N                  raw event bus text lines (not deployment-scoped)

GET  /stream              MJPEG from Pi Camera Module 3 (~10fps) — available for browser debugging / future use; not consumed by iOS app
GET  /stills/latest       most recent Pi cam still JPEG (image/jpeg) from stills/latest.jpg — polled by iOS CAM page every 5s
POST /still/trigger       capture Pi cam frame → stills/latest.jpg — called by iOS StillPoller before each fetch
GET  /hdmi-stream         MJPEG from HDMI capture card (/dev/video2, 25fps) — browser debugging only; not consumed by iOS app
POST /hdmi/still          capture HDMI frame → stills/hdmi/latest.jpg — called by iOS StillPoller before each fetch
GET  /hdmi/stills/latest  most recent HDMI still JPEG (image/jpeg) — polled by iOS BMPCC page every 5s
GET  /hdmi/histogram      64-bin grayscale histogram; `{"bins":[64 ints],"clipped_low_pct":float,"clipped_high_pct":float,"ts":ISO8601}`; 503 if offline; throttled 1Hz
POST /control/record/start · /control/record/stop · /record/toggle
POST /control/iso         {"iso": 3200}
POST /control/shutter     {"angle": 180}
POST /control/wb          {"kelvin": 5600, "tint": 0}
POST /control/extend      {"seconds": 300}
POST /control/timeout     {"seconds": 120}

GET  /camera/status       passthrough of camera_http.get_full_state() — live BMPCC REST API snapshot
PUT  /camera/iso          {"iso": <int>}
PUT  /camera/white_balance {"kelvin": <int>}
PUT  /camera/format       body matches BMPCC /system/format schema
PUT  /camera/clip_name    sets clip name for next record_start
PUT  /camera/record/start · /camera/record/stop

POST /system/restart-hhrcs      pkill api_server.py → systemd Restart=always relaunches
POST /system/restart-detector   restarts detector thread

GET  /notifications/unread      → {"notifications": [...]} unread only, newest first
POST /notifications/mark-read   body: {"ids": [...]}; returns {"marked": N}
GET  /notifications?limit=N     → {"notifications": [...]} recent N regardless of read state
```

---

## Sidecar JSON

Written to `deployments/<dep_id>/clips/<clip_id>/sidecars/<clip_id>_trigger.json` (with active deployment) or `sessions/<clip_id>/sidecars/` (without) on first animal detection.

```json
{
  "clip_id": "hhrcs_20260424_193943",
  "trigger": {
    "source": "megadetector_lite",
    "model_version": "md_v1000_spruce",
    "confidence": 0.83,
    "category": "animal",
    "bbox": [0.21, 0.44, 0.67, 0.89]
  },
  "detections": [...],
  "classification": null
}
```
`classification` stays null until Mac-side `speciesnet_pass.py` runs post-session.

---

## Recording Parameters

| Parameter | Value |
|-----------|-------|
| Codec | **Testing**: ProRes Proxy · 1920×1080 · 24fps (current SD card). **Target deployment**: BRAW 12:1 · 6K · 24fps · ~65 MB/s (requires CFast) |
| Shutter | 180° (locked, all conditions) |
| ISO | LUX-driven curve, set per-session (see Exposure section below) |
| ND | Manual physical dial; not BLE-controllable; assumed unused at deployment LUX range |
| Aperture | Manual lenses, no electronic control |
| Dawn window | Civil twilight −10 min → 90 min post-sunrise |
| Dusk window | 90 min pre-sunset → civil twilight +10 min |
| Location | 48.515°N, −123.408°W, America/Vancouver |

---

## Exposure: LUX-Driven ISO Curve (planned, not yet built)

### Constraints
- ISO is the only BLE-controllable exposure parameter
- Lenses are manual — no aperture control
- ND filters are manual on the BMPCC and not BLE-controllable; assumed unnecessary at deployment LUX range (dawn/dusk windows)
- Shutter angle locked at 180° for cinematic motion blur
- **Exposure CANNOT shift mid-record** — values commit at session start, hold throughout
- Prefer slight underexposure over overexposure (BRAW shadow latitude is more recoverable than highlight clipping)

### Curve Logic
- Pi reads lux from TSL2591 at session start (and only at session start)
- Time-of-day (relative to solar noon) determines morning vs evening curve
- **Morning curve** biases higher ISO — scene is brightening; start slightly dark, drift to slightly hot by end of session (acceptable, within BRAW latitude)
- **Evening curve** biases lower ISO — scene is darkening; start correctly exposed, drift to slightly dark by end (preferred — preserves shadow info)
- **Predictive offset**: ISO chosen for the *midpoint* of the upcoming session, not current conditions — this is the key idea
- Lookup table lives in `config.py` as `ISO_CURVE_MORNING` / `ISO_CURVE_EVENING` dicts, tuned in field

### Initial Curve (illustrative — to be calibrated in field)
```
LUX at session start    Morning ISO    Evening ISO
< 5                     3200           1600
5–20                    1600           800
20–100                  800            400
100–500                 400            400
500+                    400            400
```

### Session Re-evaluation
- ISO recomputed only between record sessions, never during
- New detection after countdown expiry → re-read LUX → recompute ISO → push via BLE → start new record
- Astral window transitions (dawn→day, day→dusk) also trigger recompute

### False-Colour Overlay (planned)
- Applied to Pi cam stream as software LUT before MJPEG encoding (purple/blue underexposed → green mid → yellow/orange near-clip → red clipped)
- Toggle on FEED/CAM tab near LIVE badge
- ~5% extra Pi CPU cost at 1080p — acceptable but want to verify post-thermal-fix
- Used as exposure guide during initial LUX→ISO curve tuning; informational, not literal (Pi cam dynamic range ≠ BMPCC dynamic range)

---

## Detection → Trigger Sequence (revised May 1, 2026)

### Sequence
1. Pi cam YOLO/MegaDetectorLite detects animal in 102° FOV
2. **Immediately** BLE trigger record start (~150ms latency)
3. Pre-roll BMPCC still: see "Pre-roll still: open question" below
4. Tracking continues while detection holds; HOLDING period extends with each redetection
5. On detection loss → HOLDING (15 min) → COUNTDOWN (2 min) → BLE trigger record stop
6. Closing BMPCC still triggered on record stop (transport returned to InputPreview, confirmed safe)
7. Pi-cam reference still captured at trigger moment, stored in `stills/` and surfaced in iOS STILLS gallery

### Pre-roll Still: Open Question
- The Blackmagic Camera Control Protocol exposes Group 10 / Parameter 3 `Still Capture` as a `void` `Capture` command via BLE — the command exists.
- Whether the BMPCC accepts this command **while actively recording** is undocumented. Forum discussions consistently treat record and still as separate transport states.
- The closing still (post-record-stop) is confirmed safe.
- **Pending field test**: with camera in front of you, fire `still_capture` mid-record and check SSD for DNG output. 30-second test, definitive answer.
- If unsupported: pre-roll still must precede record start, adding ~1s latency to recording. Trade-off accepted; pre-roll still becomes optional config flag.

### Stills Retrieval
- BLE is control-only — no file transfer path from BMPCC over BLE
- BMPCC DNG stills live on the SSD until the next physical site visit
- iOS STILLS gallery shows **Pi-cam** reference stills only — these are the in-app preview
- BMPCC DNGs reviewed post-offload alongside BRAW

### Idle TTL Stills
- Between dawn and dusk recording windows (i.e., midday), Pi triggers BMPCC still every N minutes (default 15, configurable in `config.py`)
- Stills accumulate on BMPCC SSD; Pi-cam reference still captured at same moment, joins iOS STILLS gallery
- Doubles as: framing sanity check, slow time-lapse record of position, camera-alive heartbeat

---

## Storage Strategy: BMPCC Internal Media, Manual Offload

### Current Setup (as of May 9, 2026)
- **No external SSD connected** — the NVMe SSD path was abandoned May 1, 2026
- BMPCC records to its own SD card (current: ProRes Proxy 1920×1080 for testing, SD card in slot)
- **6K BRAW 12:1 deployment** will require CFast card — SD cards max at ProRes/H.265 for most capacities
- Footage retrieved on physical site visits; no nightly transfer, no NAS dependency
- Pi's USB-C ethernet adapter occupies the BMPCC USB-C port — no path for external USB storage on BMPCC

### Media Capacity (BRAW 12:1 / 6K / 24fps ≈ 65 MB/s)
- 512 GB CFast → ~2.2h → too tight for dawn+dusk sessions
- 1 TB CFast → ~4.3h → one full dawn or dusk window
- 2 TB CFast → ~8.5h → full day (dawn+dusk) with margin
- Visit cadence: every 2–3 days requires 2 TB+ CFast for BRAW 6K

### Storage Monitoring (current)
- `pi_sd_used_pct`: Pi microSD used % — in `/status`, shown as PI SD diagnostic dot
- `cam_media_space_remaining_gb`: BMPCC active slot remaining — in `/status` cam fields
- `external_drives`: always `[]` currently — STORAGE card in DATA tab only renders if non-empty

### Why SSD was abandoned
- BMPCC 6K Pro has a single USB-C port used by the ethernet adapter
- Simultaneous ethernet + SSD on one USB-C port requires a hub (Plugable USB3-HUB3ME investigated but unverified for BMPCC 6K Pro)
- Physical site visit is required anyway for repositioning/refocusing — offload joins existing trip
- Removes entire class of USB-switching failure modes
3. SSD smart-status polling (Pi reads `df` + SMART data over USB if available)

---

## Push Notifications

### Two-Layer Architecture

**Layer 1 — APNs via iOS app** (routine events) ✓ **COMPLETE**
- Pi `notifications.py` is the queue: `emit(type, title, body)` → persisted to `data/notifications.json` (capped at 500, newest first)
- iOS `NotificationPoller` (actor) polls `GET /notifications/unread` every 2s while foregrounded; fires `UNUserNotificationRequest` for each; POSTs `POST /notifications/mark-read` to clear queue
- Rate limit: max 3 notifications per 10-second window — prevents spam after offline period; oldest silent-marked-read
- Client-side category filter: Pi sends everything; iOS `AppSettings` toggles gate surfacing per category
- Background refresh: `UIBackgroundModes → fetch` in Info.plist; `AppDelegate.application(_:performFetchWithCompletionHandler:)` calls `NotificationPoller.shared.pollAndSurface()` — opportunistic, best-effort
- Notification types emitted: `recording.started` · `recording.stopped` · `detection.animal` · `still.captured` · `deployment.opened` · `deployment.closed`
- iOS SETTINGS NOTIFICATIONS card: three toggles — RECORDING & STILLS · ANIMAL DETECTIONS · DEPLOYMENTS (all default true)

**Layer 2 — `ntfy.sh` relay** (critical events, app-independent) ✓ **COMPLETE**
- Pi `notifier.py`: `send_alert()` posts via ntfy.sh JSON API (UTF-8 safe, em-dash titles work); `evaluate_and_notify(summary)` checks 4 conditions; 6-hour in-memory dedup (resets on restart intentionally)
- `start()` backward-compat no-op (still imported and called by api_server.py at line 152)
- Conditions checked: `cam_reachable` (camera offline), `storage.days_remaining < 3` (SSD critical), `storage.used_pct ≥ 90` (SSD high), `yolo_running` (detector down), `cpu_temp_c > 80` (overheating)
- Passive scheduler in `api_server.py` builds summary, augments with `storage_monitor.get_storage_stats()` and `yolo_running`, then calls `evaluate_and_notify(summary)` every 5 minutes
- `ntfy.sh` topic: `hhrcs-4a4a678c` (private topic in config.py as `NTFY_TOPIC`) · `NTFY_BASE_URL: https://ntfy.sh` · `NOTIFIER_DEDUP_HOURS: 6`
- iOS: subscribe to topic `hhrcs-4a4a678c` in the ntfy iOS app

### Layer 1 Key Files
| File | Role |
|------|------|
| `/home/pi/hhrcs/notifications.py` | Queue: `emit()` / `unread()` / `mark_read()` / `recent()` |
| `HHRCS/Notifications/NotificationPoller.swift` | iOS actor: polls unread, fires UNNotifications, marks read |
| `HHRCS/Settings/AppSettings.swift` | `notifyRecording` / `notifyDetections` / `notifyDeployments` |
| `HHRCS/Settings/SettingsTabView.swift` | NOTIFICATIONS SectionCard with three ToggleRows |
| `HHRCS/Data/DataViewModel.swift` | `startNotificationPolling()` — 2s task loop |
| `HHRCS/App/HHRCSApp.swift` | `AppDelegate` + `@UIApplicationDelegateAdaptor` for background fetch |

### Layer 2 Implementation Notes (when built)
- `notifier.py` reads anomaly list from `agent.build_summary()` and posts critical ones to ntfy
- Avoid spam: dedupe on event-type + day; only re-fire critical alerts every 6h while condition persists
- Quiet hours: Layer 2 always fires (it's for emergencies)

---

## Build Status

- [x] SD card reflashed — Bookworm Lite 64-bit
- [x] Pi online at raspberrypi.local / 192.168.1.68
- [x] Tailscale authenticated (100.118.27.125)
- [x] I2C enabled (raspi-config)
- [x] Python venv (3.13, --system-site-packages)
- [x] All Python files deployed
- [x] systemd service: hhrcs (:5001) — enabled, running
- [x] BMPCC ethernet: Pi eth0 static 192.168.10.1/24 (con-name "camlink"), BMPCC static 192.168.10.2/24 — REST API confirmed
- ~~esp32-bridge.service~~ — DELETED (removed 2026-05-04)
- [x] Pi Camera Module 3 installed — streaming at ~10fps confirmed
- [x] MegaDetectorLite ONNX deployed — 302 ms load, 2.3 s/frame, sidecar ✓
- [x] ONNX thread fix — intra_op_num_threads=3 (benchmarked May 8, 2026; was 4 causing thermal failures, 2 failed fps floor, 3 confirmed correct)
- [x] Event bus deployed — events.py + 10 JSON schemas, all modules instrumented
- [x] /events and /log endpoints live and verified
- [x] clip_id consistency fixed — set_session_id() called on record start, matched on stop
- [x] session/notes/agent_log storage moved to /home/pi/hhrcs/data/
- [x] /still/trigger fixed — captures live Pi cam frame, writes stills/latest.jpg
- [x] /stills/latest endpoint ✓
- [x] /control/shutter endpoint ✓
- [x] /control/wb endpoint ✓
- [x] deploy.sh service name fixed ✓
- [x] iOS EVENT LOG wired to /log, 3s poll, SF Mono feed, filter chips — in SETTINGS/DIAGNOSTIC
- [x] iOS tab order: FEED(0, default) · FIELD(1) · DATA(2) · SETTINGS(3)
- [x] iOS DATA tab: SYSTEM · ENCLOSURE · WEATHER · ASTRO · STORAGE only
- [x] iOS FIELD → AGENT: deployment-scoped agent log + pinned query bar
- [x] iOS FIELD → LOG: SUMMARY entries only as plain log lines
- [x] agent.py — Tier 1 + Tier 2 (claude-haiku-4-5-20251001); ANTHROPIC_API_KEY in hhrcs.service
- [x] GET /diagnostics — live Tier 1 snapshot ✓
- [x] POST /agent-log/query — field: "question" ✓
- [x] Passive 5-min summary thread — Tier 1 only, returns entry
- [x] agent_log entries include "tier" field (1 or 2)
- [x] POST /agent-log/startup — Tier 1 startup summary endpoint ✓
- [x] iOS AGENT tab fires POST /agent-log/startup on appear (replaces broken empty-question hack)
- [x] iOS startup scroll: anchors to top only when chat empty at launch; existing exchanges open at bottom
- [x] iOS resetForNewDeployment() — clears event log + agent chat, increments deploymentChangeCount
- [x] iOS AGENT tab observes deploymentChangeCount → resets state + fires startup summary
- [x] iOS SETTINGS redesign: SectionCards (DIAGNOSTIC · ENCLOSURE · DEPLOYMENT · ACCESS · SYSTEM · AGENT · NOTIFICATIONS · DISPLAY) ✓
- [x] iOS SETTINGS DIAGNOSTIC card: health dots + collapsible event log ✓
- [x] iOS SETTINGS tab red badge: hasSystemAlert ✓
- [x] iOS MJPEG stream URL fixed, MJPEGPlayer crash fixed, buffered playback ✓
- [x] Pi cam output 1152×648 with sensor mode locked to 2304×1296 (102° FOV preserved) ✓
- [x] AgentLogItem CodingKeys fix — case content = "response" ✓
- [x] agent.py sensor/weather context in Tier 2 ✓
- [x] AGENT/LOG tab chat-bubble restructure ✓
- [x] LaunchView typography restructure ✓
- [x] Theme.cardRadius = 8 single source of truth ✓
- [x] Settings ScrollView BottomRoundedRectangle ✓
- [x] **deployment.py built and deployed** — open/close/increment_clip_count ✓
- [x] **Deployment auto-close on new deployment** (_close_active_unlocked) ✓
- [x] **app_version field in deployment dict** (set from iOS CFBundleShortVersionString) ✓
- [x] **close_deployment(notes="")** — optional closing_notes stored ✓
- [x] **deployments/<id>/ folder created on open** (agent_log.json + clips/) ✓
- [x] **Deployment-scoped /events** — filtered to deployment.started_at ✓
- [x] **Deployment-scoped /agent-log** — reads from deployments/<id>/agent_log.json ✓
- [x] **Deployment-scoped agent log writes** — query_agent() + run_passive_summary() ✓
- [x] **/status: deployment_id, deployment_name, detections_since_deployment** ✓
- [x] **GET/POST /deployments, GET /deployments/active, POST /deployments/close** all live ✓
- [x] **iOS DEPLOYMENT card restructured** — no info block, HRule separator, activeColor CLOSE ✓
- [x] **iOS CloseDeploymentSheet** — dark, SF Mono, notes field, activeColor confirm, no system alert ✓
- [x] **iOS NewDeploymentSheet sends app_version** in POST body ✓
- [x] **iOS resetForNewDeployment() wired to new-deployment callback** ✓
- [x] **App version 0.4.2 build 1** set in project.pbxproj (MARKETING_VERSION / CURRENT_PROJECT_VERSION) ✓
- [x] **LaunchView version string** — v0.4.2 (1), pinned bottom, fades with launch animation ✓
- [x] **Settings version row** — "Version 0.4.2 (build 1)", SF Mono secondary, bottom of scroll ✓
- [x] **Tailscale**: hostname `hhrcs-pi` configured with `tailscale up --ssh --hostname=hhrcs-pi`; magic DNS resolves on tailnet ✓
- [x] **iOS multi-URL switcher** in SETTINGS — savedServerURLs persisted, tap-to-switch, +ADD/SAVE/CANCEL inline UI ✓
- [x] **LaunchView HHRCS acrostic redesign** (black bg, H/UNTER H/OUSE R/EMOTE C/AMERA S/YSTEM letter block) ✓
- [x] **Agent compose bar: orange border removed, HRule separator pattern** ✓
- [x] **Recording state sync fixed** (seenNotRecording guard + manual_override reset on startup) ✓
- [x] **DIAGNOSTIC card: system advisory line, tappable PI/YOLO dots with action dropdowns, 8 health dots (PI·BMPCC·CAM·YOLO·HDMI + PI SD·CAM SD·CAM CF)** ✓
- [x] **Layer 1 push notifications complete** — `notifications.py` queue on Pi; `GET /notifications/unread` · `POST /notifications/mark-read` · `GET /notifications` endpoints; iOS `NotificationPoller` actor polls every 2s; rate-limited to 3/10s window; client-side category filter; NOTIFICATIONS SectionCard in SETTINGS ✓
- [ ] I2C sensors wired (TSL2591/BH1750 + BMP280) — sim fallback active
- [x] Active cooling installed — 5V fan on GPIO pins, running. Thermal ceiling 46.3°C under full inference load
- [ ] UPS/battery hat for clean shutdown on power loss
- [ ] PiCameraStreamer (picam_stream.py) wired into api_server — currently detector uses own Picamera2
- [ ] LUX-driven ISO curve in config.py + session-start commit logic
- [ ] False-colour overlay on Pi cam stream
- [ ] Pre-roll still mid-record field test (definitive 30-sec test pending site visit)
- [ ] Idle TTL stills (15-min cadence between dawn/dusk windows)
- [x] **STORAGE card with days-remaining estimate** — `storage_monitor.py` on Pi (df -B1, daily snapshots, burn rate); `/status` returns `storage` dict; iOS `StorageSnapshot`/`StorageInfo` decodables; `StorageCardView` in DATA tab shows SSD bar + est. remaining + burn rate ✓
- [x] **ntfy.sh push notification relay** — `notifier.py` on Pi; `evaluate_and_notify()` driven by passive scheduler every 5 min; 4 conditions; 6-hour dedup; JSON API (UTF-8 safe); `/notifier/test` endpoint verified ✓
- [x] **HDMI capture stream** — `hdmi_stream.py` (HDMIStreamer, OpenCV V4L2 MJPEG, /dev/video2); `GET /hdmi-stream`, `POST /hdmi/still`, `GET /hdmi/stills/latest` endpoints; `hdmi_reachable` in /status; BMPCC tab shows live HDMI preview; HDMI dot in DIAGNOSTIC card; advisory line; `captureHdmiStill()` on iOS ✓
- [x] **HDMI histogram endpoint** — `GET /hdmi/histogram` (64-bin grayscale, 1Hz throttle on Pi) ✓ — histogram iOS viewer removed; endpoint retained on Pi for future use
- [x] **Fullscreen viewer improvements** — close button moved to `safeAreaInsets.top + 16` (Dynamic Island safe), 44×44 tap target with `contentShape(Rectangle())`; histogram overlay pinned at bottom with `cardBackground.opacity(0.75)` ✓
- [x] **Three small fixes (Part 6)** — (1) Histogram rendering: `NSNumber.doubleValue` for JSON parse, min bar height `max(1,...)`, debug prints; (2) Fullscreen X unreachable: restructured `FullscreenImageView` — image in own `GeometryReader.ignoresSafeArea()`, controls VStack in outer ZStack without `ignoresSafeArea` so safe area is respected naturally, `.padding(.top, 8)` below Dynamic Island; (3) Tab reorder: FEED=0 (default), FIELD=1, DATA=2, SETTINGS=3; `selectedTab=0`, `onAdvance(0)`, recording-red indicator on `tab.tag==0` ✓
- [x] **Landscape bottom padding fix** — `.padding(.bottom, isLandscape ? 0 : 54)` on all three FEED pages; in landscape `OperatorControlRow` is hidden so the 54pt gap is no longer needed ✓
- [x] **Bug fix: HDMI import guard** — `from hdmi_stream import HDMIStreamer` wrapped in `try/except ImportError`; `_hdmi = None` fallback; all HDMI endpoints guard against `_hdmi is None`; service starts cleanly without opencv ✓
- [x] **Bug fix: `recording` flag stuck** — `/status` `"recording"` changed from `sensors._recording` to `sm.is_recording() or cam_state["cam_recording"]`; `is_recording()` added to StateMachine ✓
- [x] **Bug fix: `manual_override` + state machine desync** — `camera_record_start` now calls `sm.force_start()`; `sm.manual_override = False` on startup ✓
- [ ] opencv-python-headless installed in Pi venv (`pip install opencv-python-headless` in venv)
- [ ] Astral scheduler triggering record start/stop on civil twilight windows
- [ ] End-to-end field test: detection → BMPCC recording trigger via ethernet (state machine ACTIVE confirmed; camera trigger path pending real detection event at deployment site)
- [ ] Phase 5: Pi Camera H264 recording to SSD (attach H264Encoder to PiCameraStreamer main stream)
- [ ] Deployment summary.json on close (post-deployment stats: total clips, species, duration, errors)
- [ ] speciesnet_pass.py integration — post-session species classification from sidecar crops
- [ ] TestFlight distribution

### Abandoned (May 1, 2026)
- ~~USB switch + SSD wired~~ — storage strategy changed to SSD-only manual offload
- ~~Nightly rsync to house drive~~ — same reason
- ~~Flush SD-to-USB-A adapter~~ — SD-card-extraction hack abandoned (SD is single-host, can't be safely shared with recording camera)
- ~~USB-C hub for ethernet + SSD simultaneously~~ — investigated (Plugable USB3-HUB3ME) but skipped; stays SSD-only

---

## Useful Commands

```bash
# Service management
sudo systemctl status hhrcs
sudo systemctl restart hhrcs
sudo journalctl -u hhrcs -f
tail -f /home/pi/hhrcs/logs/hhrcs.log

# Health checks
curl http://192.168.1.68:5001/health
curl http://192.168.1.68:5001/status | python3 -m json.tool

# Camera control (ethernet)
ping 192.168.10.2               # confirm ethernet link to BMPCC
curl http://192.168.10.2/control/api/v1/transports/0 | python3 -m json.tool
curl http://192.168.1.68:5001/camera/status | python3 -m json.tool

# Deployment management
curl http://192.168.1.68:5001/deployments/active | python3 -m json.tool
curl -X POST http://192.168.1.68:5001/deployments \
  -H 'Content-Type: application/json' \
  -d '{"name":"HUNTER HOUSE","position":"North Meadow facing NE","lat":48.515,"lng":-123.408}'
curl -X POST http://192.168.1.68:5001/deployments/close \
  -H 'Content-Type: application/json' -d '{"notes":"End of session"}'

# Agent
curl http://192.168.1.68:5001/diagnostics | python3 -m json.tool
curl -X POST http://192.168.1.68:5001/agent-log/startup
curl http://192.168.1.68:5001/agent-log | python3 -m json.tool | head -40
curl -X POST http://192.168.1.68:5001/agent-log/query \
  -H 'Content-Type: application/json' -d '{"question":"How many detections today?"}'

# Event bus
curl "http://192.168.1.68:5001/events?window=300"
curl "http://192.168.1.68:5001/events?window=300&types=detector.trigger,state.transition"
curl "http://192.168.1.68:5001/log?window=300"

# Hardware
vcgencmd measure_temp           # CPU temp
vcgencmd get_throttled          # 0x0 = healthy
i2cdetect -y 1                  # scan I2C bus
nmcli con show camlink          # verify eth0 → 192.168.10.1/24

# Tailscale (remote access from anywhere)
ssh pi@hhrcs-pi               # via magic DNS — preferred
ssh pi@100.118.27.125         # via Tailscale IP — fallback
curl http://hhrcs-pi:5001/status
curl http://100.118.27.125:5001/status
tailscale status
tailscale ip -4
sudo tailscale up --ssh --hostname=hhrcs-pi   # if reauth needed
```

---

## Known Architecture Issues

| Issue | Severity | Notes |
|-------|----------|-------|
| `detection_fps=5` config has no effect | Low | Inference takes ~550ms; the 0.2s interval cap is always zero. Effective rate is ~1.77 fps. Not harmful, but config is misleading. |
| Real-mode stream not yet field-tested | Low | Detector subscribes to picam_stream.py MJPEG frames. Full end-to-end stream test (real mode, no .sim_mode flag) pending. |
| Event ring buffer limit for long deployments | Low | Ring buffer holds 5000 events. Long deployments with high event volume may not have full history in-memory. JSONL files are the authoritative record. |
| No deployment summary.json on close | Low | close_deployment() marks status and stores notes, but does not write a summary.json with total clips, species, duration, errors. Planned but not built. |
| ~10s delay on record-stop response | Info | After `PUT /camera/record/stop`, the BMPCC REST API returns success immediately but the camera takes ~10 seconds to finalize and close the clip. This is BMPCC firmware behavior — not a software bug. |

---

## Immediate Next Steps

Ordered by recommended sequence given current constraints (cooling installed, no hardware visit to deployment site yet):

1. **Astral scheduler** — civil twilight windows triggering record start/stop. Pure software, no thermal load.
2. **UPS/battery hat** — Waveshare UPS HAT C; pair with `power_monitor.py` emitting `system.shutdown` event before cutting power.
4. **Wire I2C sensors** — TSL2591 lux + BMP280 temp/humidity; disable sim fallback in `sensors.py`. Required to land the LUX-driven ISO curve.
5. **LUX-driven ISO curve** — `config.py` lookup tables (`ISO_CURVE_MORNING` / `ISO_CURVE_EVENING`); session-start ISO commit; predictive midpoint logic; recompute between sessions only.
6. **False-colour overlay on Pi cam stream** — software LUT, FEED/CAM tab toggle. Setup tool for tuning ISO curve.
7. **Field test still-while-recording** — fire `still_capture` REST command mid-record via BMPCC ethernet API; check SSD for DNG output. Definitive answer in 30 seconds.
8. **Idle TTL stills** — every 15 min between dawn/dusk windows; BMPCC still + Pi-cam reference.
9. **Wire PiCameraStreamer (`picam_stream.py`) into api_server.py** — prerequisite for Phase 5; resolve Picamera2 ownership conflict with Detector.
10. **Phase 5: Pi Camera H264 recording to SSD** — attach H264Encoder to PiCameraStreamer main stream as fallback record path.
11. **deployment summary.json on close** — write post-deployment stats (total clips, species, duration, errors) when `close_deployment()` is called.
12. **TestFlight distribution** — Brandon, Julian, friends.

### Completed since last update
- ~~Layer 1 push notifications~~ — `notifications.py` + 3 endpoints on Pi; `NotificationPoller` actor + NOTIFICATIONS settings card on iOS. Done.
- ~~ntfy.sh Layer 2 notifier~~ — `notifier.py` on Pi; `evaluate_and_notify()` driven by passive scheduler; 4 conditions; 6-hour dedup; `/notifier/test` verified. Done.
- ~~STORAGE card upgrade~~ — `storage_monitor.py` on Pi; `StorageCardView` in iOS DATA tab; days-remaining + burn rate from daily snapshots. Done.

### Removed from roadmap
- ~~GPIO USB switch wiring~~ — abandoned (storage strategy changed to manual offload)
- ~~Nightly rsync to house drive~~ — abandoned (storage strategy changed)
- ~~BLE/ESP32 bridge~~ — fully replaced by ethernet (2026-05-04); `pre-ethernet-fork` tag preserves prior architecture

---

## Session Summaries

### May 9, 2026 (Part 5 — CONTEXT.md full audit + agent.py fixes)

**CONTEXT.md corrections**: Hardware table — NVMe SSD row removed (abandoned May 1, BMPCC records to own SD/CFast), Pelican 1510→1400, Rode NTG updated (3.5mm direct, deadcat, boom mount), active cooling row added. Thermal notes replaced: 3 threads benchmarked, 46.3°C ceiling, 9.53h overnight clean confirmed. iOS tab/controls/settings structure corrected (stale FIN overlay, DETECT screen, Notes tab, sim mode toggle, HistogramPoller, orange accent refs all removed). Storage Strategy section updated (SSD abandoned, Pi microSD + BMPCC internal media). Deployment checklist: burn-in, cooling, threads, window_open fix all marked complete. Remaining: CFast for BRAW, enclosure build, boom mount wiring, field deployment. Agent Architecture: context_snapshot schema expanded with live camera/storage fields, sim_mode removed from schema. Simulation Mode: iOS side marked removed.

**agent.py Fix 1**: Removed stale `_sensors.get_camera_state()`, `_sensors.read_ssd_free_gb()`, `_sensors.read_house_drive_used_tb()` calls from `build_summary()` — these were legacy BLE/SSD-era sensor functions. Camera state now fetched directly from `_camera.get_full_state()`. No BLE string literals remain in any code path.

**agent.py Fix 2**: `context_block` expanded with live camera fields from `_camera.get_full_state()`: cam_reachable, cam_recording, cam_codec, cam_codec_variant, cam_active_media_slot, cam_remaining_record_time, cam_media_space_remaining_gb, cam_media_volume, cam_media_clip_count, cam_shutter_angle, cam_iso, cam_white_balance; plus system fields: cpu_temp_c, detector_threshold, window_open, dawn_dusk_enabled, manual_override, external_drives, pi_sd_used_pct, uptime_s. `context_snapshot` in log entries updated to include all live fields. `sim_mode` removed from context_snapshot.

**agent.py Fix 3**: Conversation history now passed as proper alternating user/assistant messages array to Anthropic API (last 10 exchanges), not as text dump in context_block.

### May 9, 2026 (Part 4 — iOS feed layout; agent memory; CONTEXT.md audit)

**iOS — CameraTabView.swift**: ISO/WB/Shutter/refresh moved from above feed to bottom block alongside record+still. Bottom block order: `[record][ISO][WB][refresh][SHUTTER][still]`. Chip strips changed from scrollable left-aligned to full-width equal-spacing HStack. WB chips: named presets (TUNG/FLUORO/FLASH/DAYLT/CLOUDY/SHADE). Shutter chips: 45/90/135/180/270/360 (172.8° removed). FINALIZING text overlaid above icon via `.overlay(alignment:.top)` — layout never shifts. Hairline below tab indicator gets `.padding(.horizontal, Theme.pagePadding)`.

**iOS — All pages**: All page headers (BMPCC/CAM, FIELD, DATA, SETTINGS titles) use `settings.activeColor` for active. FIELD tab strip: `Theme.label(size:11)` + activeColor active / tertiary inactive, no underline rectangle.

**iOS — NotesTabView.swift**: Agent chat optimistic rendering — user message appears immediately on send; `TypingIndicatorView` (3 pulsing dots) while waiting. Agent bubble background: `settings.activeColor.opacity(0.15)`. Enclosure nil values display "—" in `Theme.text1`.

**Pi — agent.py**: `memory.md` created at `/home/pi/hhrcs/memory.md`. Loaded alongside `CONTEXT.md` on every Tier 2 call. Note-taking: "make a note"/"remember" → writes to memory.md sections (Field/System/Observations), returns Tier 1 without calling LLM. BLE removed from passive summary. New template: "[N] detections. [Recording active/No recording.] Pi stable. BMPCC reachable/unreachable."

**CONTEXT.md**: Full audit — BLE Architecture and BLE Troubleshooting sections replaced by Ethernet Camera Control; System Architecture diagram updated; Tab Structure corrected (FEED=0, FIELD=1); Visual Design Language updated to monochrome token system; Agent Architecture updated (memory.md, new summary template, note-taking); Pi File Structure updated (removed esp32 files, added memory.md + system_logger.py); REST API updated (removed esp32 endpoints, added /camera/* endpoints); Event Types table pruned (BLE types noted as inactive); all `accentOrange` references updated to `settings.activeColor`; DIAGNOSTIC card corrected (8 health dots, no BRIDGE/BLE entries).

---

### May 8, 2026 (Part 3 — No-sensor None returns; timecode relocation)

**sensors.py**: `read_lux()`, `read_ev()`, `read_temperature()`, `read_humidity()`, `read_pressure()`, `read_dew_point()` now return `None` (typed `float | None`) when hardware is absent. Entire diurnal simulation curve removed from `read_lux()`. Operator confirmed simulated values were misleading when displayed in the app. Log messages changed from `warning("simulating ...")` to `info("no ... sensor present — readings will be None")`. `_recording`, `_nd_filter`, `_iso`, `_ssd_free_gb`, `_house_drive_used_gb` retained (used in CPU temp and SSD sim fallbacks). `random`/`math` imports retained.

**api_server.py**: `lux:.1f` format in `_on_record_stop` log line guarded against `None` via `lux_str` helper.

**agent.py**: `_fmt(v, suffix="")` helper added at module level. `hw_lux_label`/`hw_env_label` now say "absent" instead of "simulated" when hardware is missing. Tier 2 LLM context block uses `_fmt()` for all env/lux values — renders "--°C" etc. instead of "None".

**DataViewModel.swift**: `enclosureTempC`, `enclosureHumidity`, `pressure`, `lux`, `ev` changed to `Double?` (nil initial); `dewPoint` computed var returns `Double?` (nil if temp or humidity nil); `camTimecode: String?` published var added; `HealthPoll` struct gains `temperatureC`, `humidityPct`, `dewPointC`, `pressureHpa`, `luxValue`, `evValue`, `cpuTempC`, `timecode` fields with CodingKeys; `pollHealth()` sets these from the decoded `/status` payload; sensor drift entirely removed from `tick()`.

**DataTabView.swift**: ENCLOSURE card updated to display `--` for nil sensor fields using `.map { format } ?? "--"` pattern; `valueColor: Theme.tertiary` when nil; TIMECODE MetricCell removed; third slot in row 2 is now `Spacer()`.

**CameraTabView.swift**: `stillDataBar` (BMPCC page top overlay) gains `TC HH:MM:SS:FF` label after the shutter angle — SF Mono 9pt, `Theme.tertiary`. Reads from `vm.camTimecode`; renders `TC --:--:--:--` when nil. CPU temp continues to read as real from `vcgencmd`; renders in `.white` without null treatment.

**Operator notes — sensors**: No environmental sensors currently connected. To populate temperature/humidity/pressure/dew point: connect BME280 or BMP280 to Pi I2C pins. Sensor auto-detected on next service start; readings appear automatically. For lux/EV: connect TSL2591 or BH1750 on I2C. CPU temp (`vcgencmd measure_temp`) requires no sensor — always real.

---

### May 2, 2026 (Part 2 — iOS Post-Sideload Fix Pass, v0.4.2)

8 items fixed after first sideload install. All changes in `~/HunterHouseApp/HHRCS/`:

1. **`AppSettings.swift` — piServerURL default**: Reordered init so `savedServerURLs` is computed first (from `defaultURLs`), then `piServerURL` defaults to `defaultURLs[0]` (`http://raspberrypi.local:5001`) instead of `""`. First launch now has an active URL pre-selected.

2. **`AppSettings.swift` — Anthropic API key placeholder**: Added `// TODO: INSERT ANTHROPIC_API_KEY HERE` comment and `anthropicAPIKeyDefault` static constant above init. `anthropicAPIKey` seeds from this constant on first launch.

3. **`ContentView.swift` — tab icon color**: `tabForeground()` was returning `Theme.accent` (#C4714A terracotta) for selected tab. Fixed to `Theme.accentOrange` (#FF8C00). All tab icons now correctly use orange when active.

4. **Fake data disabled**:
   - `DataViewModel.init`: removed `stills = CapturedStill.simulatedEntries()` — stills now start empty.
   - `SessionLogStore.init` (`SessionLogView.swift`): changed `entries = Self.simulatedEntries()` to `init() { }` — session log starts empty.
   - AI log seeding (`piServerURL.isEmpty` gate) kept as-is — still seeds simulated agent entries when no Pi URL configured.

5. **Performance — background polling pause** (`DataViewModel.swift` + `HHRCSApp.swift`):
   - Added `suspend()` (cancels `healthTask`, `logTask`, `notificationTask`) and `resume()` (restarts all three) to `DataViewModel`.
   - `HHRCSApp` now has `@Environment(\.scenePhase)` and `.onChange(of: scenePhase)` — calls `dataVM.suspend()` on `.inactive`/`.background`, `dataVM.resume()` on `.active`.
   - `simTask` and `trigTask` (sensor drift, trigger sim) not suspended — no networking, no impact.

6. **Performance — MJPEG stops when FEED tab not active** (`ContentView.swift` + `CameraTabView.swift`):
   - `ContentView` passes `isActive: selectedTab == 1` to `CameraTabView`.
   - `CameraTabView` adds `var isActive: Bool = true` and `.onChange(of: isActive)` — calls `mjpegPlayer.stop()` on deactivate; calls `mjpegPlayer.start()` on reactivate if `currentPage == .live || .detection`.

7. **Performance — LazyVStack in diagnostic event log** (`SettingsTabView.swift`):
   - `logPanelView` inner `VStack` changed to `LazyVStack`. Prevents rendering all 200 log rows up-front.

8. **Standalone RESTART buttons removed from SYSTEM card** (`SettingsTabView.swift`):
   - Removed both `HStack { ... RESTART HHRCS ... }` and `HStack { ... RESTART DETECTOR ... }` blocks from `systemCard`. The `restartHhrcs()` and `restartDetector()` functions are retained for use from diagnostic dot detail panels (PI dot → RESET HHRCS, YOLO dot → RESET DETECTOR).

9. **Diagnostic panel state separation** (`SettingsTabView.swift`):
   - Replaced single `diagnosticPanel: DiagnosticPanelMode` with two independent states: `showLog: Bool` and `activeDot: DiagnosticDot?`.
   - Chevron button now only toggles `showLog` (and clears `activeDot` when opening log).
   - Dot buttons toggle `activeDot` (and clear `showLog`).
   - Panel displays dot detail when `activeDot != nil`, event log when `showLog`, nothing otherwise.
   - Both states animate independently — opening a dot no longer interferes with the log chevron state.

**GitHub repo**: `~/HunterHouseApp/` → `git@github.com:bturep/HHRCS.git`. GitHub Actions workflow builds unsigned `.ipa` on push to `main`; install via Sideloadly (free Apple ID, 7-day expiry).

---

### May 2, 2026 — ESP32 Firmware Crash Fix + BLE Re-Pair
- **Context**: BMPCC 6K Pro bond cleared and ESP32 freshly flashed. Full re-pairing required.
- **Root cause 1 — `abort()` crash**: `BMDCameraConnection::disconnect()` called `bleClient->isConnected()` without null check. When `createClient()` failed or was called before `bleClient` was set, the dereference caused an abort. Also: old `bleClient` was never deleted before creating a new one, exhausting BLE GATT client slots after repeated failures. **Fixed**: null check + `delete bleClient; bleClient = nullptr` in `disconnect()`.
- **Root cause 2 — connection rejection**: ESP32 called `bleClient->connect()` immediately after `ScanningFound` with zero delay. Camera BLE stack needed time after advertisement before accepting a connection. **Fixed**: 1.5s delay in `ScanningFound` case in `main.cpp`.
- **Root cause 3 — stale bonds**: No `clearBondedDevices()` call at startup. **Fixed**: called in `BMDCameraConnection::initialise()`.
- **Flashing issue**: `pi` user cannot sudo, so `sudo systemctl stop esp32-bridge` fails. `esp32-bridge.service` has `Restart=always` / `RestartSec=3` — systemd revived the bridge every 3s and stole the serial port mid-flash. **Fixed**: added `/esp32/flash` POST endpoint to `esp32_bridge.py` that closes the port and sets `_flash_in_progress = True` before running esptool, preventing the serial reader thread from reopening the port during the ~60s flash window.
- **Pairing sequence that works**: Toggle camera BT off, reset ESP32, toggle camera BT on (stay on BT Control menu), poll for ScanningFound then NeedPassKey, send passkey within 60s.
- **Result**: BLE bonded (`ble_state: Connected`, `esp32_bridge_reachable: true`). Bond is persistent — auto-reconnects on reboot.
- **Firmware binary**: rebuilt from `~/hhrcs_esp32/` (PlatformIO), deployed via `/esp32/flash` endpoint.

### May 1, 2026 (Part 3 — Layer 1 push notifications complete)
- **`notifications.py` built and deployed on Pi**: `Notification` dataclass; `emit(type, title, body)` non-blocking — reads active deployment for `deployment_id`, inserts newest-first into `data/notifications.json`, caps at `NOTIFICATIONS_MAX_STORED` (500). `unread()` / `mark_read(ids)` / `recent(limit)` functions. Thread-safe via module lock.
- **`config.py`**: added `NOTIFICATIONS_MAX_STORED = 500` module-level constant.
- **`api_server.py`**: imported `notifications`; 5 emit calls added — `recording.started` in `_on_record_start`, `recording.stopped` in `_on_record_stop`, `detection.animal` in `_on_detection` (only when transitioning from IDLE, confidence fetched from ring buffer), `still.captured` in `trigger_still`, `deployment.opened` / `deployment.closed` in their respective endpoints. Three new endpoints: `GET /notifications/unread`, `POST /notifications/mark-read`, `GET /notifications?limit=N`.
- **Pi end-to-end verified**: `POST /still/trigger` → `GET /notifications/unread` returned `still.captured` notification → `POST /notifications/mark-read` returned `{"marked": 1}` → second `GET /notifications/unread` had one fewer entry.
- **`NotificationPoller.swift`** (new, `Notifications/`): Swift `actor` singleton. Polls `GET /notifications/unread`; filters by category using `AppSettings` toggles; rate-limits surfacing to 3 per 10-second window (prevents spam after offline period); fires `UNUserNotificationRequest` for each surfaced notification; POSTs `POST /notifications/mark-read` to clear **all** unread (including filtered/over-limit ones).
- **`AppSettings.swift`**: added `notifyRecording`, `notifyDetections`, `notifyDeployments` (all `Bool`, default `true`), with `UserDefaults` persistence.
- **`DataViewModel.swift`**: added `notificationTask` + `startNotificationPolling()` — 2s loop calling `NotificationPoller.shared.pollAndSurface()`, parallel to and independent of health polling.
- **`SettingsTabView.swift`**: added `notificationsCard` between `agentCard` and `versionRow` — `SectionCard` with three `ToggleRow`s: RECORDING & STILLS · ANIMAL DETECTIONS · DEPLOYMENTS.
- **`HHRCSApp.swift`**: added `AppDelegate` class with `application(_:performFetchWithCompletionHandler:)` calling `NotificationPoller.shared.pollAndSurface()`; `@UIApplicationDelegateAdaptor(AppDelegate.self)` wired in.
- **`Info.plist`**: added `UIBackgroundModes → [fetch]` for opportunistic background refresh.
- **`project.pbxproj`**: `NotificationPoller.swift` added to both iOS and macOS targets (file reference + build file entries + Notifications group).

### May 1, 2026 (Part 2 — iOS: LaunchView acrostic, DIAGNOSTIC card, BLE reconnect fix, compose bar)
- **LaunchView.swift completely redesigned**: black background ZStack, HHRCS acrostic letter block (H/UNTER, H/OUSE, R/EMOTE, C/AMERA, S/YSTEM) with 36pt heavy orange letters (`accentOrange.opacity(0.82)`) and 10pt monospaced white trailing words at tracking 4.0, VStack spacing -6, centered on screen. Old "HHRCS / deployment name / REMOTE CAMERA SYSTEM / position" block removed.
- **Agent compose bar (NotesTabView.swift)**: removed orange `RoundedRectangle` border; replaced with `HRule` below input row to match `HRule` above — clean line-only separator, no box.
- **DataViewModel.swift BLE reconnect recording bug fixed**: `seenNotRecording` guard re-armed on every BLE reconnect (`let wasConnected = healthBleConnected` captured before update; `if bleUp && !wasConnected { seenNotRecording = false }`) — prevents stale `recording:true` from Pi lighting the record button immediately on BLE connect.
- **DIAGNOSTIC card (SettingsTabView.swift) major update**:
  - System advisory line above health dots: evaluates dependency chain (PI → BRIDGE → BLE → YOLO) and shows first failure. `"PI UNREACHABLE · ALL SYSTEMS OFFLINE"` (recordingRed), `"BRIDGE OFFLINE · BLE AND CAMERA UNAVAILABLE"` (recordingRed), `"BLE DISCONNECTED · TAP BLE TO RECOVER"` (accentOrange), `"DETECTOR IN SIM MODE · TAP YOLO TO RESET"` (accentOrange), `"ALL SYSTEMS NOMINAL"` (tertiary). 9pt SF Mono, tracking 1.5, centered. Updates on 2s poll cycle.
  - DETECT dot removed from health dots row. `detectStatus` and `detectDetailState` computed properties removed.
  - PI dot now tappable: tap toggles inline dropdown with warning `"RESTARTS ALL SERVICES · 3s DOWNTIME"` (tertiary, 9pt) and `"RESET HHRCS"` button (same style as RECOVER ESP32: 11pt medium monospaced, accentOrange). Calls `POST /system/restart-hhrcs`.
  - YOLO dot now tappable: tap toggles inline dropdown with `"RESET DETECTOR"` button. Calls `POST /system/restart-detector`.
  - BRIDGE dot now tappable: tap toggles inline dropdown with `"RESTART BRIDGE"` button. Calls `POST /system/restart-bridge`. Note: restarts `esp32_bridge` process, not the ESP32 chip itself — BLE bond preserved.
  - All three dropdowns are mutually exclusive (opening one closes others). Animated with `easeInOut(duration: 0.2)`.
  - `restartBridge()` function added to SettingsTabView (mirrors `restartHhrcs`/`restartDetector` pattern).

### May 1, 2026 (Part 1 — Architecture pivot + Tailscale + iOS multi-URL switcher)
- **Tailscale deployed on Pi**: `tailscale up --ssh --hostname=hhrcs-pi` — magic DNS resolves on any tailnet device. Pi reachable from anywhere via `ssh pi@hhrcs-pi` and `http://hhrcs-pi:5001`.
- **iOS multi-URL switcher** in SETTINGS: `AppSettings.savedServerURLs: [String]` persisted to UserDefaults. Tap-to-switch UI with active orange dot, `+ ADD` inline expand, SAVE/CANCEL, deduplication. First launch seeds `raspberrypi.local:5001` and `100.118.27.125:5001`.
- **USB switch hardware path investigated and ABANDONED**: GPIO-controllable USB 3 host-switch ICs (HD3SS3220) are not consumer products; consumer "USB switches" are manual button-press only. Acroname USBHub3+ (~$300) is the only off-the-shelf option and it's overkill.
- **USB-C hub option investigated and SKIPPED**: BMPCC firmware 8.6 supports REST API/web media manager/FTP/SMB over USB-C ethernet adapter, but BMPCC's single USB-C port is occupied by the SSD. Plugable USB3-HUB3ME identified as best-candidate hub (RTL8153 ethernet + VIA VL817 hub controller, $45 CAD at PC-Canada) but no documented BMPCC 6K Pro success — not worth the experiment given simpler path available.
- **SD-card extraction hack investigated and ABANDONED**: SD bus is single-host, can't be safely shared with recording camera. No clean hardware exists for this.
- **STORAGE STRATEGY DECISION — SSD-only with manual offload**: SSD stays in BMPCC permanently. Footage retrieved on physical site visits (every 2–3 days, depending on SSD capacity). Removes nightly transfer dependency, USB switch, NAS, host-switching hardware, all related failure modes. Trade-off: previous-night footage not on NAS by morning; instead, footage collected on next visit (which is needed anyway for repositioning/refocusing).
- **DETECTION → TRIGGER SEQUENCE revised**: Pi cam detects → record start (immediate) → mid-record still capture (pending field test of BMPCC behaviour during recording) → tracking holds → record stop → closing still (confirmed safe). Pi-cam reference still always captured at trigger moment for in-app preview. BMPCC DNG stills live on SSD until offload.
- **EXPOSURE STRATEGY decided**: LUX-driven ISO-only curve. ISO is only BLE-controllable parameter. Manual lenses and physical-only ND. Shutter locked at 180°. Exposure cannot shift mid-record — values commit at session start, hold throughout, recompute between sessions. Morning curve biases higher ISO (scene brightening, prefer slightly under at start). Evening curve biases lower ISO (scene darkening, prefer correct at start, drift dark). Predictive offset: ISO chosen for session midpoint, not current moment. Curve table TBD in `config.py`, calibrated in field.
- **False-colour overlay** spec'd: software LUT on Pi cam stream, FEED/CAM tab toggle. Setup tool for tuning ISO curve.
- **Idle TTL stills** spec'd: every 15 min between dawn/dusk windows; doubles as framing sanity check, slow time-lapse, camera-alive heartbeat.
- **Push notifications architecture spec'd**: Layer 1 — APNs via app for routine events; Layer 2 — `ntfy.sh` relay for critical events (SSD <2 days, Pi unreachable, BLE disconnect, enclosure overheating). ntfy chosen for being free, no-account, no-data-retention.
- **Pre-roll still mid-record**: documented as open question — Blackmagic protocol exposes `still_capture` command but mid-record behaviour undocumented. 30-second field test will resolve it. If unsupported, pre-roll still precedes record start (adds ~1s latency to recording).

### April 27, 2026 (Part 2 — Version Display + app_version in Deployment Metadata)
- **project.pbxproj**: MARKETING_VERSION = 0.4.2, CURRENT_PROJECT_VERSION = 1 (all 4 build configurations)
- **LaunchView.swift**: appVersionString computed from Bundle.main.infoDictionary; "v0.4.2 (1)" pinned to bottom via ZStack overlay, Theme.secondary, 9pt SF Mono; fades with opacity animation
- **SettingsTabView.swift**: versionRow — "Version 0.4.2 (build 1)", 10pt SF Mono secondary, centered, bottom of scroll VStack; reads from Bundle, never hardcoded
- **deployment.py**: open_deployment() accepts app_version: str = "" parameter; stored in deployment dict as "app_version"
- **api_server.py**: POST /deployments passes app_version from request body to open_deployment()
- **NewDeploymentSheet.submit()**: reads CFBundleShortVersionString from Bundle.main.infoDictionary before POST, includes as "app_version" in JSON payload

### April 27, 2026 (Part 1 — Deployment Integration)
- **deployment.py confirmed exists on Pi** (context doc was outdated — it was already built)
- **Deployment scoping for /events**: filtered to deployment.started_at via _ts_after() helper; if no active deployment, full ring buffer returned
- **Deployment scoping for /agent-log**: serves from deployments/<id>/agent_log.json; fallback to data/agent_log.json
- **agent.py deployment routing**: _read_log(log_path) + _append_log(entry, log_path) accept optional path; query_agent() and run_passive_summary() compute dep-specific path from active deployment
- **"tier" field added to all agent log entries**: 2 = Tier 2 LLM, 1 = Tier 1 rule-based / fallback
- **run_passive_summary() returns entry dict** (required by /agent-log/startup)
- **POST /agent-log/startup endpoint**: calls run_passive_summary(), returns entry. No Tier 2, no API key needed.
- **/status: deployment_id, deployment_name, detections_since_deployment** new fields (via _deployment_status_fields())
- **/deployments/close** now accepts {"notes": "..."} body, stored as "closing_notes"
- **deployment.py: open_deployment() uses _close_active_unlocked() helper** — makes auto-close behavior explicit; creates deployments/<dep_id>/ folder on disk
- **deployment.py: close_deployment(notes="")** — optional notes parameter
- **iOS: DataViewModel.resetForNewDeployment()** — clears eventLog + aiLogEntries, increments deploymentChangeCount
- **iOS: NotesTabView** — startupChatWasEmpty flag: anchor-to-top only when chat empty at launch; existing exchanges stay at bottom. onChange(of: deploymentChangeCount) resets all startup state + fires startup query
- **iOS: fireStartupQuery()** changed to POST /agent-log/startup (was broken empty-question to /agent-log/query)
- **iOS: SettingsTabView DEPLOYMENT card** — piDeploymentSection restructured: info block removed, HRule separator, CLOSE button in accentOrange
- **iOS: CloseDeploymentSheet** — custom dark sheet replacing system alert: deployment name, optional notes TextField (accentOrange border), CONFIRM CLOSE / CANCEL
- **iOS: closeDeployment(notes:)** sends JSON body with notes
- **iOS: NewDeploymentSheet.onCreated callback** calls vm.resetForNewDeployment()

### April 26, 2026 (Part 3 — Resolution Downscale + Sensor Mode Lock)
- pi_cam_resolution: 2304×1296 → 1152×648 (JPEG ~300KB → ~35KB, ~10× reduction)
- pi_cam_sensor_mode: (2304, 1296) added to config.py
- raw={"size": pi_cam_sensor_mode} in both Picamera2 init sites
- Full 102° FOV preserved at half resolution
- Confirmed in journal: streams (0) 1152x648-RGB888 (1) 2304x1296-SBGGR10_CSI2P/RAW

### April 26, 2026 (Part 2 — iOS UI Pass — Visual Consistency + LaunchView)
- Theme.recordingRed added (#CC3333)
- RecDotOverlay removed from CameraTabView
- FEED tab icon turns red during recording
- togglePiCamRecord() made sync
- DATA tab typography: SF Mono throughout
- DIAGNOSTIC card made collapsible (default closed)
- LaunchView.swift created: connection attempt, CONNECTED/UNREACHABLE flow, cached status fallback

### April 26, 2026 (Part 1 — Agent Polish + AGENT/LOG Restructure + UI Refinement)
- AgentLogItem CodingKeys fix: content = "response", query: String? added
- agent.py sensor/weather context: imports sensors, includes lux/EV/temp/humidity/pressure/dew_point/iso/ssd_free/house_drive in Tier 2 context block
- Agent system prompt: plain-facts style, no markdown, no editorializing, 1–4 sentences
- AGENT/LOG tab restructure: SUMMARY entries → SummaryCardView (full-width); QUERY entries → ChatExchangeView (user right-bubble, agent left-bubble); LOG tab shows SUMMARY only
- FIELD tab default sub-tab: AGENT; order: AGENT → STILLS → LOG
- AGENT tab startup scroll: anchors to first message of session; hasSentQuery guards bottom-scroll
- Theme.cardRadius = 8 single source
- Settings ScrollView BottomRoundedRectangle custom shape
- LaunchView typography restructure: left-aligned block, accentOrange position text

### April 25, 2026 (Part 5 — Agent Build)
- agent.py built and deployed: Tier 1 rule-based + Tier 2 claude-haiku-4-5-20251001
- Passive scheduler: 60s first fire, then every 300s (Tier 1 only)
- GET /diagnostics + POST /agent-log/query endpoints live
- ANTHROPIC_API_KEY wired into hhrcs.service
- anthropic SDK 0.97.0 installed in Pi venv
- build_summary() verified standalone

### April 25, 2026 (Part 4 — MJPEG stream root cause, color fix, aspect ratio, stability, playback)
- Root cause: _sim_loop never opened camera → _latest_jpeg stayed None → stream yielded nothing
- Pi fix: `_camera_stream_loop()` added to Detector — opens Picamera2 at ~10fps in sim mode
- BGR→RGB color fix: `frame[:, :, ::-1]` channel flip before JPEG encoding
- Aspect ratio corrected: 16:9 output (1152×648), IMX708 full sensor mode
- MJPEGPlayer crash fixed: DispatchQueue serializes all buffer access
- MJPEG buffered playback: 8-frame queue, 200ms timer (~5fps), bounded growth
- Real-mode stream decoupled from inference: dedicated _capture_thread_loop at ~10fps

### April 25, 2026 (Part 3 — Settings DIAGNOSTIC card, tab badge, MJPEG stream fix)
- DIAGNOSTIC card at top of SETTINGS: health dots + collapsible event log
- Red badge on SETTINGS tab gearshape icon (hasSystemAlert)
- MJPEG stream URL construction fixed (URLComponents, no double-slash)
- CHANGE PIN removed from ACCESS card

### April 25, 2026 (Part 2 — iOS UI Restructure)
- FIELD tab default; FIELD · FEED · DATA · SETTINGS tab order
- DATA tab cleaned: EVENT LOG removed; moved to SETTINGS/DIAGNOSTIC
- AI SUMMARY CARD in FIELD → LOG (replaced by AGENT tab chat in later session)
- FIELD sub-tabs: LOG · AGENT · STILLS (NOTES removed)
- LOG entry row simplified: `HH:MM:SS  SPECIES (0.83)  3m 7s`
- AGENT tab: pi agent log + pinned query bar; POST /agent-log/query live
- Dead code removed: FieldAgentView, NotesStore, Note deleted
- RECOVER ESP32 (4-step sequence) replaces RESET button
- POST /system/restart-bridge added
- Settings redesign: 5 SectionCards

### April 25, 2026
- **Thermal diagnostic**: Pi ran overnight in sealed Pelican, single boot, WiFi dropped from heat
- **Sim mode**: `.sim_mode` flag file implemented; DETECTOR_ENABLED env var wired
- **`esp32_bridge_reachable` + `esp32_ble_state` surfaced in `/status`**
- **Sim mode camera guard**: _on_record_start/stop skip camera commands when _using_real=False
- **End-to-end recording test passed**: clip hhrcs_20260425_104237, recording.started + recording.stopped confirmed in JSONL, 10.1s duration ✓
- **BLE drop guard** in _on_record_stop

### April 24, 2026 (Part 3 — API Bug Fixes, iOS Event Log, Seed Data Removal)
- `/still/trigger`, `/stills/latest`, `/control/shutter`, `/control/wb` fixed or restored
- `session.py` moved from /tmp to /home/pi/hhrcs/data/ (survives reboot)
- `clip_id` consistency fixed (set_session_id wired in _on_record_start)
- `deploy.sh` service name fixed (was hhrcs-bridge → esp32-bridge)
- Fake seed data removed from api_server.py
- iOS DATA tab EVENT LOG: SF Mono feed, filter chips ALL/TRIGGER/STATE/REC/BLE

### April 24, 2026 (Part 2 — Thermal Fix + Event Bus)
- **Pi failure investigation**: two crashes in 3 days — root cause: `intra_op_num_threads=4` pinning all 4 cores at ~390% CPU → heat → unclean shutdown → NetworkManager corruption → WiFi fail on boot
- **Fix**: `intra_op_num_threads=2`, `inter_op_num_threads=1` in detector.py — CPU now ~202%, temp 57.9°C, no throttling
- WiFi profile lost after crash — re-added via nmcli; IP confirmed 192.168.1.68 / raspberrypi.local
- **Event bus deployed**: `events.py` (in-process ring buffer + JSONL), 10 event types, all 4 modules instrumented
- **10 JSON Schemas** in `schemas/events/`
- **`/events` and `/log` endpoints** live and verified
- Startup events confirmed on first boot

### April 24, 2026 (Part 1 — Detector Rewrite)
- Abandoned YOLOv8/ultralytics (CPU torch wheel broken on Pi 4)
- Adopted MegaDetectorLite — MDv1000-spruce ONNX (28.5 MB), onnxruntime 1.25.0
- Pure-NumPy postprocessing: letterbox → NMS; frame delivery via PiCameraStreamer subscriber
- Sidecar JSON architecture: `sessions/<id>/sidecars/<id>_trigger.json`, classification=null
- Mac tools: `do_export.py`, `export_spruce_onnx.sh`, `speciesnet_pass.py`
- Verified on Pi: 302ms load, 2.3s/frame avg, sidecar written ✓

### May 6, 2026 (Part 2 — MJPEG Tiling Fix + HUD Toggle Removed)

**MJPEG tiling root cause:** First attempt used `CAP_PROP_FORMAT=-1` to request raw MJPEG bytes from V4L2 + `_is_complete_jpeg()` SOI/EOI check. Caused tiling — V4L2 splits MJPEG data across multiple reads, so frame fragments happen to start with `\xff\xd8` and end with `\xff\xd9`, passing the check despite being partial data.

**Fix applied — `hdmi_stream.py`:**
- Reverted to `cap.read()` → `cv2.imencode(".jpg", frame, quality=85)` pipeline
- `cap.read()` lets OpenCV fully decode the MJPEG frame to numpy; `imencode` re-encodes to a guaranteed-complete JPEG
- Removed `CAP_PROP_FORMAT=-1`, `_is_complete_jpeg()`, `grab()`/`retrieve()` fallback path

**Fix applied — `api_server.py`:**
- Removed `_is_complete_jpeg()` from `_mjpeg_frames()` — detector's `_camera_stream_loop` already uses `PIL.Image.save(format="JPEG")` which always produces complete JPEGs; the check was redundant
- Reverted sleep on miss from 33ms back to 200ms

**HUD toggle removed (BMPCC firmware 8.6 returns 404 on `/video/outputOverlay`):**
- `POST /camera/monitor/overlay` endpoint removed from `api_server.py`
- `toggle_overlay()` removed from `camera_control.py`
- `toggleBmpccOverlay()` removed from `DataViewModel.swift`
- `overlayEnabled` state and HUD button removed from `CameraTabView.swift`

**MJPEG player rewritten with `URLSessionDataDelegate` boundary-aware buffering — fixes partial frame / tiling artifact on both streams. Root cause was iOS progressive JPEG rendering, not Pi frame encoding.**
- Previous `extractFrames()` scanned for SOI (`0xFF 0xD8`) / EOI (`0xFF 0xD9`) byte markers. JPEG bitstreams can contain `0xFF 0xD9` sequences internally (e.g. within entropy-coded data), causing the scan to extract a truncated frame that iOS renders with grey/tiling below the valid portion.
- Replaced with multipart boundary detection: `extractFrames()` now searches for `--frame\r\n` (the boundary Flask's `generate_mjpeg()` sends on both streams), skips MIME headers by finding `\r\n\r\n`, then looks for the next `--frame\r\n` to delimit the complete JPEG payload. Pi appends `\r\n` after each JPEG; stripped before passing to `PlatformImage(data:)`.
- Buffer is advanced to the start of the next boundary after each extraction, so multi-packet frames accumulate correctly.
- Applies to both `/stream` (Pi cam) and `/hdmi-stream` (BMPCC HDMI) since both use the same `MJPEGPlayer` class.
- No Pi-side changes — `hdmi_stream.py`, `api_server.py`, `camera_control.py` are correct as-is.

### May 6, 2026 (Part 3 — FEED Architecture Rewrite: MJPEG → 5s Still Polling)

**Use-case clarification:** Framing is done on-site directly on the BMPCC. The app's purpose is to confirm exposure/ISO settings, confirm detection, and confirm system health. Real-time video is unnecessary and was saturating the network and bogging down the app (10s tab delays, blank feeds, high CPU).

**iOS changes (no Pi files touched):**
- `MJPEGPlayer.swift` and `MJPEGStreamView.swift` **deleted** entirely
- `StillPoller.swift` (new): `ObservableObject` with `triggerURL` + `fetchURL`. `start()` fires an immediate poll then schedules a `Timer` every 5s. Each poll: `POST triggerURL` (capture) → `GET fetchURL` (fetch JPEG) → decode to `PlatformImage` → publish `latestImage` + `lastUpdated`. `stop()` invalidates timer and clears image to free memory. `refreshNow()` triggers an immediate poll. `running` guard prevents double-start on shared pollers.
- `DetectionOverlayView.swift` rewritten: takes `StillPoller` instead of `MJPEGPlayer`; uses `poller.latestImage` as background image for bounding-box overlay
- `CameraTabView.swift` rewritten: two `@StateObject StillPoller` instances (`hdmiPoller` for BMPCC page, `camPoller` for CAM + DETECT pages). Only one poller runs at a time — `onChange(of: currentPage)` calls `rebalancePollers()`. `StillImagePage` private struct shows the still image, a `TimelineView`-driven elapsed seconds label (dims when >15s stale), and a subtle `arrow.clockwise` refresh button top-right. `onAppear`/`onDisappear` on the outer view manage start/stop; `isActive` prop still controls tab-level lifecycle.

**Endpoint mapping:**
- BMPCC page: `POST /hdmi/still` → `GET /hdmi/stills/latest`
- CAM + DETECT pages: `POST /still/trigger` → `GET /stills/latest`
- `GET /stream` and `GET /hdmi-stream` still served by Pi — available for browser debugging / future use, not consumed by iOS

**xcodegen regenerated** after file additions/deletions.

### May 6, 2026 (Part 4 — UI/UX Cleanup Batch)

**Change 1 — CAM page record button disabled**
Pi-side H264 recording (Phase 5) is not yet built. CAM page record button now shows at 0.4 opacity with "PROXY RECORDING — PLANNED" caption (7pt SF Mono, `Theme.tertiary`), `allowsHitTesting(false)`. BMPCC page record button unchanged. Added `recordDisabled: Bool = false` parameter to `OperatorControlRow`.

**Change 2 — LaunchView all blue letters**
H·UNTER and H·OUSE rows previously hardcoded `Color(hex: "FF8C00")` orange as an exception. Removed `letterColor` overrides on those two rows — they now fall back to `Theme.accentColor` (#349beb) like R·C·S. All five acrostic letters are now blue.

**Change 3 — Launch screen 3-second cosmetic fade**
`runPreflight()` simplified to: set `.p1`, start ellipsis, sleep 2.5s, call `onAdvance(1)`. No connectivity checks, no phase 2/3 polling. Phases `p2` and `p3` removed from enum. `pingStatus()` and `buildOfflineSummary()` deleted. ContentView fade animation changed from 0.3s to 0.5s (`easeIn`). Total: 2.5s display + 0.5s fade = 3s. Connectivity shown in DATA tab health dots once app is open.

**Change 4 — Default tab on launch = FEED** *(tab index updated in May 6 Part 6 — now tab 0)*
`ContentView.selectedTab` initialized to `0` (FEED). `onAdvance(0)` in `runPreflight()` and "CONTINUE OFFLINE" button navigate to FEED. BMPCC is the default sub-page within FEED.

**Change 5 — FIELD sub-tab reorder: STILLS → AGENT → LOG**
`FieldSegment` enum reordered: `stills` first, then `agent`, then `log`. Default segment changed to `.stills`. Tab bar renders in declaration order via `CaseIterable`.

**Change 6 — BMPCC HUD manual workaround documented (no code)**
REST `/video/outputOverlay` returns 404 on firmware 8.6 — HUD toggle not available via API. Workaround: Menu → Monitor → HDMI → Status Text → Off on-camera before deployment. Added to BMPCC quirks section.

### May 5, 2026 (Part 3 — ntfy.sh Layer 2 Notifier + STORAGE Card)

**Pi — new files:**
- **`notifier.py`** (new): ntfy.sh Layer 2 push module. `send_alert(title, body, priority, tags)` uses ntfy.sh JSON API (`POST https://ntfy.sh` with `{"topic":..., "title":..., "message":..., "priority": int, "tags": [...]}`) — avoids latin-1 header encoding issue with Unicode titles. `evaluate_and_notify(summary: dict)` checks 4 conditions and fires if past 6-hour in-memory dedup window. `start()` is a backward-compat no-op. Condition keys: `cam_unreachable`, `ssd_critical` (days_remaining < 3), `ssd_high` (used_pct ≥ 90), `yolo_down`, `cpu_temp_high` (>80°C). Priority map: min=1 … urgent=5.
- **`storage_monitor.py`** (new): SSD burn-rate tracker. `get_storage_stats()` calls `df -B1` on `config.ssd_mount`, then `/media/pi/*`, then `/` as fallback. Persists daily `used_bytes` snapshots to `data/storage_snapshots.json` (7 max, newest first). `_compute_burn_rate()` uses oldest-to-newest delta over up to 3 snapshots; returns `None` until ≥2 snapshots exist. Returns `{"free_gb", "total_gb", "used_pct", "days_remaining", "burn_rate_gb_per_day", "snapshots"}`.

**Pi — `api_server.py` edits:**
- `import storage_monitor` added at top (alongside existing `import notifier`)
- `/status` response: `"storage": storage_monitor.get_storage_stats()` added
- `_start_passive_agent()`: now builds `summary = agent.build_summary()`, augments with `summary["storage"] = storage_monitor.get_storage_stats()` and `summary["yolo_running"] = bool(detector._thread and detector._thread.is_alive())`, calls `notifier.evaluate_and_notify(summary)`, then calls `agent.run_passive_summary()` as before

**Bug fixed — ntfy.sh unicode headers:** First attempt used header-based API (`requests.post(url, data=..., headers={"Title": title})`). Em-dash `—` in "HHRCS — Test alert" caused `'latin-1' codec can't encode character '—' in position 6`. Fixed by switching to ntfy.sh JSON API: `requests.post(base_url, json=payload)` where payload includes `topic`, `title`, `message`, `priority` (int), `tags` (array). Verified via `/notifier/test` → `{"sent": true}`.

**iOS — DataViewModel.swift:**
- `StorageSnapshot: Decodable, Identifiable` struct added (top-level): `date: String`, `usedBytes: Int` (CodingKey `used_bytes`)
- 6 new `@Published` vars under `// MARK: – SSD`: `storageFreeGb`, `storageTotalGb`, `storageUsedPct`, `storageDaysRemaining`, `storageBurnRateGbPerDay: Double?` and `storageSnapshots: [StorageSnapshot]`
- `HealthPoll.StorageInfo: Decodable` nested struct added (fields: `freeGb`, `totalGb`, `usedPct`, `daysRemaining`, `burnRateGbPerDay`, `snapshots`)
- `HealthPoll.storage: StorageInfo?` field added; `case storage` in CodingKeys
- `pollHealth()`: parses `poll.storage` and sets all 6 published vars

**iOS — DataTabView.swift:**
- `storageSection` private var expanded inline: house drive `BarCell` always shown; SSD `BarCell` + `MetricCell` row (EST. REMAINING, BURN RATE) conditionally shown when `storageFreeGb`, `storageTotalGb`, `storageUsedPct` are non-nil; `HRule()` separator between sections; `storageDaysRemaining` and `storageBurnRateGbPerDay` only shown when both non-nil (requires ≥2 days of snapshots). No separate `StorageCardView` struct — matches the inline var pattern of every other section in the file.

**Post-session fixes (same day):**
- `agent.py`: `run_passive_summary(summary: dict = None)` — accepts pre-built summary; only calls `build_summary()` internally if `summary is None`
- `api_server.py`: passive scheduler passes the already-augmented `summary` into `run_passive_summary(summary)` — single `build_summary()` call per 5-min tick
- `DataTabView.swift`: `StorageCardView` struct removed; its body inlined directly into `storageSection` private var — matches the pattern of every other section in the file
- `HHRCSApp.swift`: status bar hidden app-wide via `.statusBarHidden(true)` on root view in `WindowGroup`

### May 5, 2026 (Part 2 — Color System Overhaul)
- All orange and terra-cotta accent colors replaced with blue `#349beb`
- `Theme.accent` (#C4714A terra-cotta) → `Color(hex: "349beb")`
- `Theme.accentOrange` (#FF8C00 bright orange) → `Color(hex: "349beb")`
- `accentOrange` renamed to `accentColor` across 57 references in 7 files: Theme.swift, LaunchView.swift, ContentView.swift, CameraTabView.swift, SettingsTabView.swift, DiagnosticRecovery.swift, NotesTabView.swift
- Launch screen exception: H (UNTER) and H (OUSE) retain original `#FF8C00` orange; R (EMOTE), C (AMERA), S (YSTEM) use new blue
- `letterRow()` in LaunchView gains optional `letterColor: Color` parameter (default = `Theme.accentColor`)
- No hardcoded hex orange values remain anywhere except the two HH rows in LaunchView

### May 8, 2026 (Part 2 — CPU temp warning tier, system metrics logger, iOS uptime)
- **Pi — CPU temp warning tier**: `notifier.py` adds `cpu_temp_warning` condition at >65°C (priority `default`, tag `thermometer`); existing `cpu_temp_high` (>80°C) bumped to priority `high` and body updated ("Throttling imminent."). `evaluate_and_notify()` now returns `list[str]` of fired condition keys instead of None. `test_ntfy.sh` gains `temp_warning` condition (cpu_temp_c=70, between thresholds) and adds it to `all` run.
- **Pi — system_logger.py (new)**: `SystemLogger` class. 60s metrics thread writes one JSON object per line to `data/system_metrics_YYYY-MM-DD.jsonl`, rotating at midnight UTC. Metrics: cpu_temp_c, cpu_pct, ram_pct, ram_mb_used/total, ssd_free_gb, ssd_used_pct, detector_fps, yolo_running, cam_reachable, hdmi_reachable, uptime_s. Uses psutil 7.2.2 (already in venv) + existing storage_monitor/detector/cam_client refs — no new polling. `log_event(category, details)` writes immediate event entries for: service_start, recording start/stop, ntfy_sent, passive agent errors.
- **Pi — api_server.py**: Imports and instantiates `SystemLogger` (after detector ready, passing detector/hdmi/cam_client refs + _uptime_start). Logs service_start event at startup. Hooks `_on_record_start` and `_on_record_stop` with recording events. Calls `log_event("ntfy_sent", keys)` when `evaluate_and_notify()` returns non-empty list. Adds `uptime_s` and `system_log_path` to `/status` response.
- **iOS — DataViewModel.swift**: Added `uptimeSeconds: Int?` published var, decoded from `uptime_s` field in HealthPoll CodingKeys.
- **iOS — SettingsTabView.swift**: New ENCLOSURE card inserted between DIAGNOSTIC and LOG cards. Shows UPTIME row (formatted as Xh Ym from `vm.uptimeSeconds`) and LOG row (today's metrics file path, purely informational). Temp tiers: <65°C normal · 65–80°C warning ntfy · >80°C critical ntfy.
- **Monitoring commands**: ssh pi@raspberrypi.local "tail -50 /home/pi/hhrcs/data/system_metrics_$(date -u +%Y-%m-%d).jsonl | python3 -m json.tool" — retrospective review. /status uptime_s and system_log_path present for live visibility.

### May 8, 2026 (Part 1 — Address geocoding, /snapshot fix, storage snapshots hardening)
- **iOS — address search in SETTINGS**: `LocationSearchViewModel` (new file, `HHRCS/Settings/LocationSearchViewModel.swift`) — `NSObject + ObservableObject + MKLocalSearchCompleterDelegate`; 0.3s debounce; `resultTypes = [.address, .pointOfInterest]`; up to 5 completions; no location-services permission required (text-to-coordinate lookup). `selectLocation(_:)` fires `MKLocalSearch` on the chosen completion, extracts lat/lon and formats address string. New LOCATION field in SETTINGS DEPLOYMENT card (above lat/long): live dropdown of results; tap to populate lat/long + store address. Selected address shown below lat/long in `Theme.secondary`, truncated to one line. Manual lat/long edit (while focused) clears stale address. Clearing LOCATION field with a stored address shows `ClearLocationSheet` confirmation (zeroes lat/lon on confirm). `AppSettings.deploymentAddress` (`hhrcs.deploymentAddress`) persists across app reloads. `import MapKit` added to `SettingsTabView.swift`.
- **iOS — /snapshot 404 fix**: `captureStill()` fallback array changed from `["/stills/latest", "/snapshot"]` to `["/stills/latest"]` — `/snapshot` was leftover from the pre-refactor MJPEG streaming era and 404'd on every manual still. `captureAndStoreSnapshot()` rewritten to use `POST /still/trigger` + 2s sleep + `GET /stills/latest` via `piServerURL` (was using dead `streamBaseURL + "/snapshot"`).
- **Pi — storage snapshots hardening**: `_load_snapshots()` in `storage_monitor.py` now: (a) returns `[]` silently if file absent; (b) returns `[]` silently if file is empty (no warning); (c) on `JSONDecodeError`, logs once and renames file to `.corrupt.<timestamp>` for forensics before returning `[]`. Added `import time`. Storage snapshots file on Pi confirmed valid at time of fix (67 bytes, well-formed JSON with one snapshot entry for 2026-05-08).
- **Phase A checklist**: Pre-deployment cleanup item checked.

### May 7, 2026 (Part 1 — Tri-State Recording, Still Interval, Deployment Checklist)
- **RecordingState tri-state enum**: `idle | recording | finalizing` replaces `Bool isRecording`. iOS optimistically transitions to `.finalizing` on stop; resolves to `.idle` when Pi polling confirms `cam_recording=false` AND `machine_state=IDLE`. 20s safety timer (`Task<Void, Never>`) prevents stuck `.finalizing` state. `DataTabView` RECORDING metric shows tri-state label and color (white/dotRed/accentColor). `CameraTabView` breathing animation (opacity 0.4↔1.0, 1.2s easeInOut repeatForever) on FINALIZING state.
- **StillPoller configurable interval**: `UserDefaults` key `"stillRefreshInterval"` (seconds; -1 = manual only). `currentInterval` treats 0 (unset) as default 5s. `NotificationCenter` (`stillRefreshIntervalChanged`) wires `SettingsTabView` picker to running `StillPoller`. `StillPoller.isManual` drives MANUAL top-left label on STILL image page.
- **Settings — REFRESH INTERVAL card**: Chevron-expandable picker; options 2s / 5s / 10s / 30s / 1m / 5m / Manual. Checkmark on selected. Posts `stillRefreshIntervalChanged` on selection. `@AppStorage("stillRefreshInterval")` for reactive update.
- **Settings — DEPLOYMENT CHECKLIST card**: Three sections — BMPCC MENU (7 items), PHYSICAL (8 items), SYSTEM HEALTH (8 items). UserDefaults keys `deploy_check_<section>_<id>`. Health items 1–5 have `autoCheck` closures reading live `DataViewModel` props (`healthPiReachable`, `camReachable`, `hdmiReachable`, `healthYoloRunning`, `storageDaysRemaining > 2`). Auto-OK items show amber outline halo (unfilled); checked items show amber-filled checkbox. RESET CHECKLIST → confirmation sheet.
- **pi/scripts/test_ntfy.sh**: Exercises all ntfy alert paths (`ssd_critical`, `ssd_warning`, `temp_high`, `cam_unreachable`, `ble_down`). Uses `python3 - "$@"` heredoc to pass bash positional args as `sys.argv`. Storage fields use nested dict (`base['storage'] = {...}`) matching notifier's `summary.get("storage")`. `ble_down` maps to `yolo_running=False` (BLE removed; same alert path). Verified on Pi: `test_ntfy.sh all` → all 5 conditions fired cleanly. `/status` `yolo_sim_mode` field confirmed present and correct.
- **Operator note**: Deployment checklist now lives in-app (SETTINGS → DEPLOYMENT CHECKLIST). Physical operator card no longer needs to carry the full checklist — it's always available on-device.
- **git**: Committed `012d7ee` on `feature/ethernet`.

### May 7, 2026 (Part 2 — ntfy notifier and test script aligned)
- **`notifier.py`**: Added `ssd_warning` tier (3–7 days remaining, priority `high`) between `ssd_critical` (<3 days, `urgent`) and `ssd_high` (≥90% used, `high`). `elif` chain ensures only one SSD condition fires per evaluation. BLE check deliberately omitted: `ble_state` was removed from the summary dict in the 2026-05-05 session (ethernet migration).
- **`test_ntfy.sh`** rewritten: fake summary now uses nested `storage` dict (`base['storage']['days_remaining']` etc.) matching `_build_checks()` access pattern. Previous version's `ssd_warning` condition fired `ssd_high` (used `used_pct=92` instead of `days_remaining=5.0`). `ble_down` alias removed. Conditions expanded from 5 to 6: `ssd_critical`, `ssd_warning`, `ssd_high`, `temp_high`, `cam_unreachable`, `yolo_down`. `yolo_down` now its own explicit condition (was only reachable via the `ble_down` alias). All 6 conditions verified to fire and land on iOS ntfy app.
- **Alert conditions reference**:

  | Condition | Trigger | Priority |
  |---|---|---|
  | `ssd_critical` | <3 days remaining | urgent |
  | `ssd_warning` | <7 days remaining | high |
  | `ssd_high` | ≥90% used (no burn-rate data) | high |
  | `cpu_temp_high` | >80°C | default |
  | `cam_unreachable` | BMPCC REST 192.168.10.2 unreachable | high |
  | `yolo_down` | detector thread not alive | high |

### May 7, 2026 (Part 3 — YOLOv8 real-mode bring-up: ring buffer, threshold UI, VERIFY mode, LOG detections)
- **`detector.py`**: 2fps cadence (`sleep_time = 0.5 - elapsed`; warns if inference >500ms). Module-level `_recent_detections: deque` ring buffer with 24h epoch-based pruning. `_dispatch()` builds canonical record `{ts, class, confidence, bbox, frame_w, frame_h}` and appends to ring buffer with `_ts` key; daily JSONL rotation to `data/detections_YYYY-MM-DD.jsonl`. Hot-reload of `config.detector_confidence_threshold` each inference frame. FPS tracking via `_inference_ts` deque. Public methods: `get_recent_detections(hours=24)` and `get_fps_actual()`.
- **`api_server.py`**: Startup loads threshold from `data/detector_threshold.json`. `/status` gains `detector_threshold` and `detector_fps_actual`. New endpoints: `GET /detections/recent?hours=24` → `{detections:[...]}`, `GET /detections/latest` → single record or 404, `POST /detector/threshold` → persists `{threshold: float}` to JSON file.
- **`DataViewModel.swift`**: `DetectionHistoryItem` struct (Identifiable+Decodable; `class` key aliased to `detectionClass`; `cgRect` computed from normalized bbox; `timestamp` parsed from ISO-8601 `ts`). `@Published` vars: `detectorThreshold`, `detectorFpsActual`, `detectionHistory`. HealthPoll extended with new fields. Methods: `setDetectorThreshold()`, `startDetectionHistoryPolling()` (5s loop), `stopDetectionHistoryPolling()`, `fetchDetectionHistory()`.
- **`SettingsTabView.swift`**: DETECTOR THRESHOLD chevron card — header shows current value; expanded: `Slider(0.0...1.0, step: 0.05)` with reference marks (0.40 PERMISSIVE / 0.60 DEFAULT / 0.80 STRICT); `.onEditingChanged` fires `setDetectorThreshold()`.
- **`CameraTabView.swift`**: `detectVerifyMode: Bool` via `@AppStorage`. VERIFY toggle button in `detectionControlBar`. `verifyLatestDetection` (first detection ≤60s old) and `verifyFiveMinCount` (count within 5min). `startVerifyPolling()`/`stopVerifyPolling()`/`fetchVerifyDetections()` (2s Task loop hitting `/detections/recent`). `DetectionOverlayView` now receives `verifyDetection:` and `verifyFiveMinCount:`.
- **`DetectionOverlayView.swift`**: Accepts `verifyDetection: DetectionHistoryItem?` and `verifyFiveMinCount: Int`. When non-nil, draws 2pt bounding box in class-keyed color (animal=`Theme.accentColor`, person=`Theme.recordingRed`, vehicle=`Theme.secondary`) with 8pt SF Mono label "class  0.87" above top-left corner on `Theme.background` backing. `verifyFiveMinCount > 0` shows "DETECTIONS: N / 5min" counter top-right in 11pt SF Mono `Theme.tertiary`.
- **`SessionLogView.swift`**: `LogItem` enum gains `.detection(DetectionHistoryItem)` case. `SessionLogView` gains `detectionEntries: [DetectionHistoryItem] = []` param included in grouped computation (sorted by timestamp). `DetectionLogRow` private struct: time | uppercased class (class-keyed color) | confidence. Empty state shows clock icon + "NO ENTRIES" when no entries exist.
- **`NotesTabView.swift`**: `logContent` passes `detectionEntries: dataVM.detectionHistory`. `.onAppear`/`.onDisappear` on `logContent` and `.onChange(of: segment)` manage `startDetectionHistoryPolling()`/`stopDetectionHistoryPolling()` lifecycle.
- **Operator note**: MegaDetectorLite classes are `animal`, `person`, `vehicle` — no species-level classification at detection time.

### May 7, 2026 (Part 4 — Detector real-mode post-deployment fixes)
- **First confirmed real detection**: `animal conf=0.77` at `2026-05-07T19:00:24 UTC`. Real-mode inference is functional end-to-end through to the state machine.
- **`.sim_mode` removal**: Removed `/home/pi/hhrcs/.sim_mode` today to enable real inference. Real mode requires all four conditions: `picamera2` importable + `onnxruntime` importable + `DETECTOR_ENABLED` not `"0"` + `.sim_mode` file absent.
- **Bug fix — `_config` typo (`detector.py:213`)**: Claude Code wrote `config.detector_confidence_threshold` (bare name) instead of `_config.detector_confidence_threshold` (matching line 33 import alias `from config import config as _config`). Pi was patched via `sed -i` during the session; Mac copy fixed and committed here. **Deployment discipline lesson**: any Pi-side fix that bypasses the Mac copy (sed-i, nano, etc.) MUST be backported and committed in the same session or the next scp reintroduces the bug.
- **Bug fix — float32 JSON serialization (`detector.py`)**: Every detection emitted `WARNING: detections.jsonl write failed: Object of type float32 is not JSON serializable`. Root cause: onnxruntime outputs numpy float32 for `confidence` and `bbox` values. `round(float32_val, 4)` returns a numpy scalar, not a Python float. Fix: `round(float(confidence), 4)` and `[round(float(v), 4) for v in bbox]` in `_dispatch()`. Applied to both the JSONL record and the event-bus dict.
- **Known open issue — inference speed**: `detector_fps_actual ≈ 0.53` (~1600ms/frame). Target was 2fps (500ms/frame). CPU temp 37.9°C so thermal throttling is not the cause. Model input is 640×640 padded from 1280×720; onnxruntime at `intra_op_num_threads=2`. Possible causes: resolution, thread config, model specifics. Investigate in a future session.
- **Known open issue — iOS sim mode toggle is cosmetic**: SETTINGS toggle updates `@AppStorage` but makes no API call to the Pi. Does not affect the running detector. SSH + `.sim_mode` flag file is the correct mechanism.

### May 7, 2026 (Part 5 — Detector real-mode performance fixes)
- **Pre-flight**: `diff <(ssh pi@...) detector.py` returned empty — Mac and Pi already identical from Part 4. No backport needed.
- **ONNX thread config**: `intra_op_num_threads` bumped 2→3; `ORT_SEQUENTIAL` execution mode added. Pi 4 has 4 cores — leaves 1 for system/Flask/capture. Model load log now prints `ONNX intra=3, inter=1`. Note: 4 threads was a known crash cause (prior history); 3 is a deliberate safe ceiling.
- **`_letterbox()` hot-path**: Replaced `__import__("PIL").Image.fromarray(...).resize(...)` (dynamic import on every inference call, ~10–15ms overhead per frame) with `cv2.resize(..., interpolation=cv2.INTER_LINEAR)`. Module-level `import cv2 as _cv2` with `try/except ImportError` fallback retains PIL path if cv2 unavailable. `cv2` 4.13.0 confirmed in Pi venv.
- **Baseline fps before fix**: `detector_fps_actual ≈ 0.53` (~1600ms/frame).
- **Post-deploy fps**: ~0.7 fps (improvement from Part 5 mitigations; further boosted to 1.77fps after Part 6 416×416 re-export)
- **JSONL persistence**: Confirmed already fixed in Part 4; no regression.
- **Model note**: `md_v1000_spruce.onnx` — MegaDetector v1000 Spruce tier (28MB, YOLOv8-derivative). 3 classes: animal / person / vehicle. No species ID. ~12.7× faster than Redwood tier. Appropriate for Pi 4 CPU inference.

### May 7, 2026 (Part 6 — Re-export MegaDetector Spruce at 416×416)
- **Goal**: Improve inference fps by reducing model input from 640×640 to 416×416 (~2x speedup expected at modest accuracy cost for distant small targets).
- **Constraint**: Existing ONNX has static shape [1,3,640,640] — cannot resize on the fly. Must re-export from the original .pt checkpoint.
- **Export environment**: Python 3.12 venv (3.14 has no onnxruntime wheel), torch 2.2.2, numpy pinned to <2 (torch 2.2 not compatible with numpy 2.x). `ultralytics` package used, but model is YOLOv5-backbone so needed `autoshape=False` and `torch.hub.load("ultralytics/yolov5", "custom", ...)`.
- **Export command**: `torch.onnx.export(model, dummy_416, ..., opset_version=12, input_names=["images"], output_names=["output0"], dynamic_axes=None)`. Output verified: shape [1, 3, 416, 416], NMS not baked in, 28.3 MB, SHA256 `7cf200f3...`.
- **Mac sanity test**: onnxruntime inference on random input → `Output 0 shape: (1, 10647, 8)` — correct anchor count for 416 (13×13×3 + 26×26×3 + 52×52×3 = 10647).
- **Pi**: Backup of 640 model at `models/md_v1000_spruce_640.onnx.bak`. New 416 model deployed as `models/md_v1000_spruce.onnx`. Pi model shape verified: `[1, 3, 416, 416]`.
- **detector.py**: `_MODEL_INPUT_SIZE` 640→416; `_letterbox` default 640→416. Single-line change — call site already passes the constant.
- **Baseline fps (640 model)**: 0.53. **Post-deploy fps at 416**: **1.77 fps** (2.7× speedup from 0.7fps post-Part-5 baseline; ~550ms/frame). Budget warning threshold updated 500ms→600ms to suppress noise at borderline-OK frames.
- **Rollback**: `mv models/md_v1000_spruce_640.onnx.bak models/md_v1000_spruce.onnx` + `_MODEL_INPUT_SIZE = 640` in detector.py + scp + restart.
- **Coral USB Accelerator**: Considered as hardware acceleration path. Worldwide chip shortage has inflated pricing to $200+ (normal $60). Not pursuing. Revisit when pricing normalizes.
- **End-of-day status (2026-05-07)**: 1.77 fps at 416×416 stable. Pi temp ~42°C. ntfy verified. iOS polished (Parts 3–6, ~6 hours). Budget warning threshold 500ms→600ms. Next: Phase A — burn-in test, BMPCC trigger chain, iOS smoke test.

### May 5, 2026 (Part 1 — Agent bridge_reachable Fix)
- **Bug**: `agent.py` `build_summary()` crashed every ~60s with `'CameraControl' object has no attribute 'bridge_reachable'` — cascaded to notifier as well
- **Root cause**: migration deleted `bridge_reachable` and `ble_state` from `CameraControl` but agent.py still read them as attributes
- `_camera.bridge_reachable` → `_camera.connected` (the property that calls `_client.is_reachable()`)
- `_camera.ble_state` → removed (BLE is gone; no equivalent)
- Summary dict key `"bridge_reachable"` → `"cam_reachable"` throughout `build_summary()`, fallback dict, LLM context block
- `"ble_state"` key removed from summary dict, context block, and both `context_snapshot` dicts in `query_agent()` and `run_passive_summary()`
- Verified live: passive summary fired clean at 17:47:31 with no errors

### May 4, 2026 (Part 2 — Bug Fixes, feature/ethernet)
- **Fix 1 — Manual stop authoritative**: `state_machine.py` gains `manual_override: bool` flag and `force_idle()` method. `detection_event()` and `open_window()` no-op while flag is set. Flag cleared on next manual start (`force_start()`). `api_server.py` calls `sm.force_idle()` on `PUT /camera/record/stop` and clears flag on `PUT /camera/record/start`. `"manual_override"` surfaced in `/status` response and `to_dict()`.
- **Fix 1 — iOS**: YOLO confirmation popup removed from `CameraTabView` `OperatorControlRow`. Stop button calls `onRecord()` directly with no gate. `yoloLocked` parameter removed from `OperatorControlRow` (still exists in `DataViewModel` for the AUTO badge in the data bar).
- **Fix 2 — HDMI placeholder**: BMPCC page capture button replaced with disabled "HDMI PREVIEW" text at 0.4 opacity (HDMI dongle ordered; hardware stills not yet available). `OperatorControlRow` gains `captureIsPlaceholder: Bool` parameter. CAM page retains working capture button.
- **Fix 3 — Media slot display names**: Raw BMPCC slot identifiers mapped in `camera_http.py` before surfacing: `sd0`→`SD`, `cf0`→`CFast`, `usb0`→`USB`. Uses module-level `_SLOT_MAP` dict.

### May 4, 2026 (Part 1 — BLE → Ethernet Migration)
- **Architecture**: Replaced ESP32/BLE bridge with direct BMPCC REST API over USB-C ethernet adapter. Pi eth0 static: 192.168.10.1/24 (NetworkManager con-name "camlink"). BMPCC static: 192.168.10.2/24. REST API base: `http://192.168.10.2/control/api/v1`. No auth required. No trailing slashes on paths.
- **Deleted**: `esp32_bridge.py`, `esp32-bridge.service`, entire `/esp32/` PlatformIO firmware directory from repo.
- **New Pi files**: `camera_http.py` (BMPCCCameraClient wrapping requests.Session), `camera_control.py` (thin facade, preserves public API). `config.py` gains `CAMERA_BASE_URL` and `CAMERA_REQUEST_TIMEOUT`.
- **API**: New endpoints: `GET /camera/status`, `PUT /camera/record/start`, `PUT /camera/record/stop`, `PUT /camera/iso`, `PUT /camera/white_balance`, `PUT /camera/format`, `PUT /camera/clip_name`. `/status` now returns `cam_*` fields; all `esp32_*` fields removed.
- **Cam fields in `/status`**: `cam_reachable`, `cam_recording`, `cam_codec`, `cam_frame_rate`, `cam_resolution`, `cam_iso`, `cam_white_balance`, `cam_gain`, `cam_active_media_slot`, `cam_remaining_record_time`.
- **iOS DataViewModel**: `healthBridgeReachable`, `healthBleConnected`, `healthEsp32BleState`, `seenNotRecording` removed. `cam*` `@Published` vars added. `isRecording` = `camRecording` (no BLE cold-start guard). `hasSystemAlert` = `!healthPiReachable || !camReachable`. `toggleBmpccRecord()` calls `PUT /camera/record/start` or `PUT /camera/record/stop`.
- **iOS Diagnostic dots**: PI · BRIDGE · BLE · YOLO · SSD → **PI · CAM · YOLO · CARD · SSD**. `DiagnosticDot` enum updated. New `CamDetailView` (with 3-step recovery flow) and `CardDetailView`. Removed `BridgeDetailView`, `BleDetailView`.
- **iOS DATA tab**: CAMERA section added at top — 3 rows: codec/frame rate/resolution, ISO/WB/gain, recording/media slot/rec time.
- **iOS LaunchView**: Phase 2 polls `/camera/status` for `cam_reachable` (4s max, 500ms intervals). `buildOfflineSummary` uses `cam_reachable`.
- **GitHub Actions**: `feature/**` branch trigger added alongside `main`. `workflow_dispatch` confirmed.
- **Tag**: `pre-ethernet-fork` preserves BLE-based architecture as permanent rollback point.
- **Note**: `hhrcs.service` — `ANTHROPIC_API_KEY` set on device only; repo copy uses placeholder `SET_ON_DEVICE_NOT_IN_REPO`.
- **BMPCC quirks confirmed**: `/system/codecFormat` returns "Not implemented" — use `/system/format`. Reference/live JPEG not exposed by firmware — Pi cam stays as stills source. No trailing slash on any path.
- **BMPCC HUD — manual workaround**: REST API `/video/outputOverlay` returns 404 on firmware 8.6 (overlay toggle not implemented). HUD **can** be hidden manually on-camera: Menu → Monitor → HDMI → Status Text → Off. Set this before each deployment for clean HDMI capture. No software fix needed — operator procedure.

### April 23, 2026
- Still capture fixed — `/still/trigger` now calls `streamer.capture_jpeg()`, writes real frame
- `GET /stills/latest` and `GET /snapshot` endpoints added
- All camera control endpoints audited (ISO, WB, shutter, ND, FPS)
- ESP32 firmware: ND handler rewritten (CCU Command struct); WB AUTO bug fixed; ND removed (physical dial)
- iOS: FEED reordered (STILL default), STILL page redesign with auto-capture + data bar, CAM page minimal monitor, Config sheet removed, ND removed everywhere
- iOS: LIVE badge popover — connection status, ESP32 BLE state, RESET ESP32 button
- iOS: ISO slider (9 stops), WB slider + presets, FPS removed
- Recording state: `vm.isRecording` driven by `recording_active` from `/status` poll

---

## Mac Source Files — Keep In Sync With Pi

These files exist both on Mac (for editing/reference) and deployed to Pi. If you edit them locally, redeploy to Pi via scp.

> **Pi deployment rule — NO EXCEPTIONS**: Every session that modifies Pi-side Python files MUST end with scp deployment + `sudo systemctl restart hhrcs` + `curl` verification of any new endpoint. Writing code locally on the Mac and forgetting to deploy means the Pi runs stale code and any iOS feature depending on the new endpoint silently returns 404/503. This happened with the histogram endpoint (written locally, never deployed until the following session). The verification step is mandatory — "it should work" is not enough.

> **Mac copy sync discipline**: If a bug is patched directly on the Pi (e.g. via `sed -i` or nano in an SSH session) without updating the Mac copy, the next `scp` deploy will silently reintroduce the bug. Rule: any Pi-side fix MUST be backported to the Mac copy and committed to git in the same session before scp'ing. Specific instance: `detector.py:213` was patched on Pi via `sed -i` during Part 4 (2026-05-07); Mac copy was fixed and committed in the same session. If you ever find the Pi and Mac copies differ on a specific line, treat the Pi as ground truth for that patch — reconcile, commit, then scp.

```bash
# Mandatory end-of-session Pi deploy checklist:
scp ~/HunterHouseApp/pi/<changed>.py pi@raspberrypi.local:/home/pi/hhrcs/<changed>.py
ssh pi@raspberrypi.local "sudo systemctl restart hhrcs && sleep 2 && sudo systemctl is-active hhrcs"
curl -s http://raspberrypi.local:5001/<new-endpoint> | python3 -m json.tool
```

> **CONTEXT.md rule**: There are two copies — `~/Desktop/HHRCS_CONTEXT.md` (Mac) and `/home/pi/hhrcs/CONTEXT.md` (Pi). **Always update both at the end of every session.** The desktop copy is the authoritative base; push it to the Pi with: `scp ~/Desktop/HHRCS_CONTEXT.md pi@hhrcs-pi:/home/pi/hhrcs/CONTEXT.md`

| File | Pi Path | Critical notes |
|------|---------|----------------|
| `detector.py` | `/home/pi/hhrcs/detector.py` | `intra_op_num_threads=3` (as of Part 5, 2026-05-07). **Never set to 4** — prior crash history: 4 threads → 390% CPU → thermal shutdown → filesystem corruption. |
| `deployment.py` | `/home/pi/hhrcs/deployment.py` | Source of truth for deployment lifecycle. Auto-close in open_deployment(). |
| `api_server.py` | `/home/pi/hhrcs/api_server.py` | All route changes must be deployed to Pi and service restarted. |
| `agent.py` | `/home/pi/hhrcs/agent.py` | Deployment path routing in _append_log + _read_log. Uses `cam_reachable` (not `bridge_reachable`). |
| `camera_http.py` | `/home/pi/hhrcs/camera_http.py` | BMPCCCameraClient. All methods return None/False on failure — never raise. |
| `camera_control.py` | `/home/pi/hhrcs/camera_control.py` | Thin facade over BMPCCCameraClient. `camera.connected` property calls `is_reachable()`. |
| `state_machine.py` | `/home/pi/hhrcs/state_machine.py` | `manual_override` flag blocks detection_event/open_window. Cleared by force_start(). |
