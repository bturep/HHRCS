# HHRCS — Project Context

> Full context lives at `~/Desktop/HHRCS_CONTEXT.md` on the Mac and `/home/pi/hhrcs/CONTEXT.md` on the Pi.
> This file is a repo-level summary for quick orientation.

---

## What This Is

Unattended outdoor wildlife cinema rig at Prospect Lake, Saanich, BC (48.515°N, −123.408°W).
Primary camera: BMPCC 6K Pro recording BRAW 12:1 at 6K/24fps to NVMe SSD.
Intelligence: Raspberry Pi 4 running MegaDetectorLite ONNX for animal detection, with BMPCC control via ESP32 BLE bridge.

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
  esp32_bridge.py       ESP32 serial bridge :5002
  agent.py              Two-tier agent (Tier 1 rule-based + Tier 2 Claude Haiku)
  deployment.py         Deployment lifecycle management
  events.py             Event bus (ring buffer + JSONL flush)
  notifications.py      Push notification queue
  camera_control.py     BLE camera commands via bridge
  state_machine.py      IDLE → ACTIVE → HOLDING → COUNTDOWN
  sensors.py            I2C lux/env (hardware or sim fallback)
esp32/                  PlatformIO firmware (ELEGOO ESP32, env: hhrcs-bridge)
  src/                  Magic-Pocket-Control-ESP32 + SerialSecurityHandler patch
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

---

## Pi — Key Facts

| Item | Value |
|------|-------|
| LAN | `raspberrypi.local:5001` · `192.168.1.68` |
| Tailscale | `hhrcs-pi:5001` · `100.118.27.125:5001` |
| SSH | `ssh pi@raspberrypi.local` password: `hhrcs2026` |
| ONNX model | `models/md_v1000_spruce.onnx` (28.5 MB, MegaDetectorLite) |
| Inference threads | `intra_op_num_threads=2` (thermal limit, ~202% CPU) |
| ESP32 bridge | `:5002` · owns `/dev/ttyUSB0` exclusively |
| BLE device | BMPCC 6K Pro · `cc:86:ec:e1:38:56` |

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
