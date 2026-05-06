# HHRCS — Project Context

> Full context lives at `~/Desktop/HHRCS_CONTEXT.md` on the Mac and `/home/pi/hhrcs/CONTEXT.md` on the Pi.
> This file is a repo-level summary for quick orientation.
>
> **Architecture:** BLE → Ethernet migration completed 2026-05-04. ESP32/BLE removed. BMPCC controlled via REST API over USB-C ethernet adapter.

---

## What This Is

Unattended outdoor wildlife cinema rig at Prospect Lake, Saanich, BC (48.515°N, −123.408°W).
Primary camera: BMPCC 6K Pro recording BRAW 12:1 at 6K/24fps to NVMe SSD.
Intelligence: Raspberry Pi 4 running MegaDetectorLite ONNX for animal detection, with BMPCC control via ethernet REST API.

---

## Repo Structure

```
HHRCS/                  iOS SwiftUI app (Xcode target: HHRCS_iOS / HHRCS_macOS)
  App/                  HHRCSApp.swift · ContentView.swift
  Camera/               CameraTabView.swift · MJPEGPlayer.swift
  Data/                 DataViewModel.swift
  Log/                  SessionLogView.swift
  Notes/                NotesTabView.swift
  Settings/             AppSettings.swift · SettingsTabView.swift · DiagnosticRecovery.swift
  Theme/                Theme.swift
  Notifications/        NotificationPoller.swift
pi/                     Raspberry Pi Python backend
  api_server.py         Flask REST API :5001
  detector.py           MegaDetectorLite ONNX inference
  camera_http.py        BMPCC REST API client (ethernet, 192.168.10.2)
  camera_control.py     Camera command facade (calls camera_http)
  agent.py              Two-tier agent (Tier 1 rule-based + Tier 2 Claude Haiku)
  deployment.py         Deployment lifecycle management
  events.py             Event bus (ring buffer + JSONL flush)
  notifications.py      Push notification queue
  state_machine.py      IDLE → ACTIVE → HOLDING → COUNTDOWN
  sensors.py            I2C lux/env (hardware or sim fallback)
  hhrcs.service         systemd unit for main API
tools/                  Mac-side tools (speciesnet export, ONNX conversion)
project.yml             XcodeGen project spec
ExportOptions.plist     For future ad-hoc signed builds (requires paid Apple account)
.github/workflows/      GitHub Actions: build unsigned IPA on push to main
```

---

## iOS App — Key Decisions

| Topic | Decision |
|-------|----------|
| Bundle ID | `com.brandonpoole.hhrcs` |
| Version | 0.4.2 |
| Target | iOS 17 / macOS 14 |
| Tab order | FIELD · FEED · DATA · SETTINGS |
| Active URL default | `http://raspberrypi.local:5001` (first launch) |
| Default tab | FEED (tab 1) — `selectedTab = 1` in ContentView |
| Tab accent color | `Theme.accentOrange` (#FF8C00) |
| FEED images | 5s still polling (StillPoller); no MJPEG streaming. One poller runs at a time. |
| Fake data | Disabled — stills and session log start empty |
| Signing | Unsigned IPA → Sideloadly (free Apple ID, 7-day expiry) |
| Diagnostic dots | PI · CAM · YOLO · CARD · SSD |

---

## Pi — Key Facts

| Item | Value |
|------|-------|
| LAN | `raspberrypi.local:5001` · `192.168.1.68` |
| Tailscale | `hhrcs-pi:5001` · `100.118.27.125:5001` |
| SSH | `ssh pi@raspberrypi.local` password: `hhrcs2026` |
| ONNX model | `models/md_v1000_spruce.onnx` (28.5 MB, MegaDetectorLite) |
| Inference threads | `intra_op_num_threads=2` (thermal limit, ~202% CPU) |
| Pi eth0 | `192.168.10.1/24` (static, NetworkManager con-name "camlink") |
| BMPCC eth | `192.168.10.2/24` (via USB-C ethernet adapter on camera) |
| REST API base | `http://192.168.10.2/control/api/v1` |

---

## Ethernet REST API

The Pi controls the BMPCC 6K Pro directly via HTTP. The camera's USB-C port connects to the Pi via a USB-C-to-ethernet adapter, putting both on a private 192.168.10.0/24 subnet.

**Important:** API paths must NOT have a trailing slash. `/system/format` works; `/system/format/` returns 404.

Enable Web Media Manager on the BMPCC once via Blackmagic Camera Setup (USB to Mac/PC) — this enables the REST API and lets the camera accept a static IP.

Key endpoints (all base: `http://192.168.10.2/control/api/v1`):
- `GET  /transports/0/record` — `{"recording": bool}`
- `PUT  /transports/0/record` — `{"recording": bool, "clipName": "..."}`
- `GET  /video/iso`            `PUT /video/iso`
- `GET  /video/whiteBalance`   `PUT /video/whiteBalance`
- `GET  /video/gain`
- `GET  /system/format`        `PUT /system/format`
- `GET  /media/active`
- `GET /video/outputOverlay`   `PUT /video/outputOverlay` — **returns 404 on firmware 8.6; overlay API not implemented**; HUD toggle removed from app

---

## Ethernet Link Troubleshooting

1. Check the adapter LED on the camera's USB-C port (should be solid/blinking green)
2. On Pi: `ping 192.168.10.2`
3. On Pi: `curl http://192.168.10.2/control/api/v1/transports/0`
4. Verify Web Media Manager is enabled in Blackmagic Camera Setup
5. Check NetworkManager: `nmcli con show camlink`

---

## Diagnostic Dots (iOS Settings tab)

| Dot | Green | Red | Detail panel |
|-----|-------|-----|--------------|
| PI | Pi reachable | Pi unreachable | Last poll time |
| CAM | Camera REST API reachable | Unreachable | Format, ISO, WB, recovery flow |
| YOLO | Detector running | Not running | Inference mode, reset flow |
| CARD | Active media slot present | No media | Slot name, remaining time |
| SSD | ≥10% free | <5% free | Free %, GB remaining |

---

## Build

```bash
# Generate Xcode project (required after project.yml changes)
xcodegen generate

# Build unsigned IPA locally (or let GitHub Actions do it)
xcodebuild archive -project HHRCS.xcodeproj -scheme HHRCS_iOS \
  -configuration Release -destination "generic/platform=iOS" \
  -archivePath /tmp/HHRCS.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" CODE_SIGN_STYLE=Manual
```

GitHub Actions builds on every push to `main` and uploads the IPA as an artifact.
Install via Sideloadly with a free Apple ID (7-day re-sign cycle).

---

## Anthropic API Key

The Pi's `agent.py` (Tier 2 Claude Haiku) requires `ANTHROPIC_API_KEY` in the Pi's environment.
It is set in `hhrcs.service` on the Pi — not stored in this repo.

The iOS `AppSettings.swift` has a placeholder:
```swift
// TODO: INSERT ANTHROPIC_API_KEY HERE
private static let anthropicAPIKeyDefault = ""
```
This is for a future feature (direct iOS → Anthropic queries). Currently unused on iOS.

---

## Session Notes

**2026-05-04 — Ethernet migration**
Replaced ESP32/BLE bridge with direct BMPCC REST API over USB-C ethernet adapter. Removed `esp32_bridge.py`, `esp32-bridge.service`, and the entire `/esp32/` PlatformIO firmware from the repo. Pi static IP: 192.168.10.1. Camera static IP: 192.168.10.2. New `camera_http.py` wraps the REST API. iOS diagnostic dots updated from PI·BRIDGE·BLE·YOLO·SSD to PI·CAM·YOLO·CARD·SSD. `pre-ethernet-fork` tag preserves the BLE-based rig as a permanent rollback point.

**2026-05-04 — Bug fixes (feature/ethernet)**
Three targeted fixes: (1) Manual stop is now authoritative — `state_machine.py` gains `manual_override` flag and `force_idle()` method; `detection_event()` and `open_window()` no-op while flag is set; cleared on next manual start. `api_server.py` calls `sm.force_idle()` on `/camera/record/stop` and clears flag on `/camera/record/start`. YOLO confirmation popup removed from `CameraTabView` — stop button always acts immediately. (2) BMPCC stills button replaced with disabled "HDMI PREVIEW" placeholder (HDMI dongle ordered; Pi stills via `/still/trigger` still available on CAM page). (3) Raw media slot names from BMPCC REST API mapped before display: `sd0`→`SD`, `cf0`→`CFast`, `usb0`→`USB` in `camera_http.py`.

**2026-05-05 — Agent bridge_reachable fix**
`agent.py` crashed every ~60s: `'CameraControl' object has no attribute 'bridge_reachable'` (notifier cascaded too). Fixed: `_camera.bridge_reachable` → `_camera.connected`; `_camera.ble_state` removed (BLE gone). Summary dict key `bridge_reachable` → `cam_reachable`; `ble_state` key removed from summary dict, LLM context block, and both `context_snapshot` dicts.

**2026-05-05 — Color system overhaul**
All orange/terra-cotta accent colors replaced with `#349beb` blue. `Theme.accent` (#C4714A) and `Theme.accentOrange` (#FF8C00) both set to `Color(hex: "349beb")`. `accentOrange` renamed to `accentColor` across 57 references in 7 files. Launch screen exception: H·H rows hardcode original `#FF8C00` orange; R·C·S rows use `Theme.accentColor` (blue). `letterRow()` gains optional `letterColor` parameter.

**2026-05-06 — HDMI deployed to Pi; bug fixes confirmed live**
All four files deployed via scp: `hdmi_stream.py`, `api_server.py`, `config.py`, `state_machine.py`. `opencv-python-headless` installed in Pi venv. Service restarted; `/status` confirmed: `"hdmi_reachable": true`, `"recording": false`, `"manual_override": false`. `/hdmi-stream` returns HTTP 200 `multipart/x-mixed-replace`. Known architecture note: ~10s delay after record-stop is BMPCC firmware behavior (clip finalization) — not a software bug.

**2026-05-06 — Bug fixes: hdmi_reachable, recording flag, manual_override**
Three targeted fixes: (1) HDMI import wrapped in `try/except ImportError` so service starts cleanly even without `opencv-python-headless`; `_hdmi = None` fallback; all HDMI endpoints guard against `_hdmi is None`; `hdmi_reachable` uses `_hdmi.is_open() if _hdmi else False`. (2) `"recording"` in `/status` was derived from `sensors._recording` (a separate flag that `force_idle()` never clears) — changed to `sm.is_recording() or cam_state["cam_recording"]`; `is_recording()` method added to StateMachine returning `state != IDLE`. (3) `camera_record_start` endpoint now calls `sm.force_start()` instead of just setting `sm.manual_override = False` + calling `_cam_client.record_start()` directly — ensures state machine transitions to ACTIVE and fires `_on_record_start`; `sm.manual_override = False` set explicitly after `sm = StateMachine()` instantiation on startup.

**2026-05-06 — HDMI capture stream + BMPCC page live preview**
`hdmi_stream.py` added: HDMIStreamer class opens `/dev/video2` via OpenCV V4L2 CAP_V4L2, MJPEG FOURCC, 1920×1080@25fps. Three new Pi endpoints: `GET /hdmi-stream` (MJPEG), `POST /hdmi/still`, `GET /hdmi/stills/latest`. `hdmi_reachable` added to `/status`. BMPCC camera tab now shows live HDMI preview (replacing StillFrameView placeholder) via a second MJPEGPlayer instance. Capture button wired to `captureHdmiStill()`. HDMI diagnostic dot added to SETTINGS DIAGNOSTIC card (sixth dot). Advisory line added: PI unreachable → red; HDMI offline + PI reachable → accentColor. `HdmiDetailView` added to DiagnosticRecovery.swift. Install on Pi: `pip install opencv-python-headless` in venv.

**2026-05-06 — MJPEG frame integrity attempt + BMPCC HUD toggle (partially reverted)**
First attempt: `_is_complete_jpeg()` SOI/EOI check + `CAP_PROP_FORMAT=-1` raw V4L2 bytes in `hdmi_stream.py`. Caused tiling — V4L2 splits MJPEG data across reads so fragments pass the header/footer check. Reverted to `cap.read()` → `cv2.imencode()` decode/re-encode pipeline (always produces complete JPEGs). Same check removed from `_mjpeg_frames()` in `api_server.py` (detector uses PIL encode — already valid). BMPCC HUD toggle added and then removed: `POST /camera/monitor/overlay`, `toggle_overlay()` in `camera_control.py`, `toggleBmpccOverlay()` in `DataViewModel.swift`, HUD button in `CameraTabView.swift` — all removed. BMPCC firmware 8.6 returns 404 on `/video/outputOverlay`; overlay API not implemented.

**2026-05-06 — UI/UX cleanup batch**
(1) CAM page record button disabled — `recordDisabled: true` in `OperatorControlRow`, shown at 0.4 opacity with "PROXY RECORDING — PLANNED" caption; Pi H264 recording (Phase 5) not yet built. (2) LaunchView acrostic — H/UNTER and H/OUSE now use `Theme.accentColor` (blue) like R/C/S; orange hardcode removed. (3) Launch simplified — 2.5s cosmetic sleep then `onAdvance(1)`; phases p2/p3 and connectivity checks removed; ContentView fade 0.3→0.5s. (4) Default tab changed to FEED (`selectedTab = 1`). (5) FIELD sub-tab reorder: STILLS (default) → AGENT → LOG. (6) BMPCC HUD manual workaround documented: Menu → Monitor → HDMI → Status Text → Off before deployment; no REST fix available on firmware 8.6.

**2026-05-06 — FEED architecture rewrite: MJPEG → 5s still polling**
`MJPEGPlayer.swift` and `MJPEGStreamView.swift` deleted. New `StillPoller.swift`: `ObservableObject`, `POST triggerURL` then `GET fetchURL` every 5s, publishes `latestImage: PlatformImage?` and `lastUpdated: Date?`. `CameraTabView` rewritten: two `StillPoller` instances (`hdmiPoller` for BMPCC, `camPoller` for CAM + DETECT), only one runs at a time. `StillImagePage` shows still + elapsed-seconds label (dims >15s) + refresh button. `DetectionOverlayView` updated to take `StillPoller`. Pi endpoints: BMPCC → `POST /hdmi/still` + `GET /hdmi/stills/latest`; CAM/DETECT → `POST /still/trigger` + `GET /stills/latest`. `GET /stream` and `GET /hdmi-stream` still served but not consumed by iOS.

**2026-05-06 — iOS MJPEG player boundary-aware buffering (tiling fix)**
`MJPEGPlayer.extractFrames()` rewritten to use `--frame\r\n` multipart boundary detection instead of SOI/EOI byte scanning. Prior approach could find a false `0xFF 0xD9` (EOI) inside the JPEG bitstream, extracting a truncated frame that iOS renders with grey tiling below the valid content. New approach: find `--frame\r\n`, skip headers via `\r\n\r\n`, extract bytes up to the next `--frame\r\n` (stripping the trailing `\r\n` the Pi appends), then pass the complete JPEG to `PlatformImage(data:)`. Fixes both `/stream` and `/hdmi-stream`. No Pi changes.

**2026-05-05 — ntfy.sh Layer 2 notifier + STORAGE card**
New `notifier.py` on Pi: `send_alert()` via ntfy.sh JSON API (UTF-8 safe); `evaluate_and_notify(summary)` checks cam_unreachable / ssd_critical / ssd_high / yolo_down / cpu_temp_high with 6-hour in-memory dedup. Passive scheduler in `api_server.py` builds summary once, augments with storage + yolo_running, calls `evaluate_and_notify()` then `run_passive_summary(summary)` — single `build_summary()` call per tick. New `storage_monitor.py`: `df -B1` burn-rate tracker with daily snapshots; returns `days_remaining` after ≥2 days of data. `/status` now includes `storage` dict. iOS: `StorageSnapshot` + `StorageInfo` decodables; 6 new `@Published` vars in `DataViewModel`; `storageSection` var in `DataTabView` expanded inline (house drive bar + SSD bar + est. days remaining + burn rate). `run_passive_summary()` accepts optional pre-built `summary` dict to avoid redundant `build_summary()` call. Status bar hidden app-wide via `.statusBarHidden(true)` on root view in `HHRCSApp.swift`.
