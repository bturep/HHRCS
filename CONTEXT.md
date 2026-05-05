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
| Tab accent color | `Theme.accentOrange` (#FF8C00) |
| MJPEG | Stops when FEED tab not visible; stops when app backgrounds |
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
