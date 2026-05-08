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
| Tab order | FEED · FIELD · DATA · SETTINGS |
| Active URL default | `http://raspberrypi.local:5001` (first launch) |
| Default tab | FEED (tab 0) — `selectedTab = 0` in ContentView |
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
| ONNX model | `models/md_v1000_spruce.onnx` (28.3 MB, MegaDetectorLite, **416×416 input** as of Part 6) |
| Inference threads | `intra_op_num_threads=3`, `ORT_SEQUENTIAL` (Pi 4 has 4 cores; leaves 1 for system/Flask/capture) |
| Pi eth0 | `192.168.10.1/24` (static, NetworkManager con-name "camlink") |
| BMPCC eth | `192.168.10.2/24` (via USB-C ethernet adapter on camera) |
| REST API base | `http://192.168.10.2/control/api/v1` |

---

## Detector Real-Mode Gating

`detector.py` sets `_using_real = True` only when **all four** conditions are met at startup:

1. `picamera2` is importable (Pi camera library present)
2. `onnxruntime` is importable (ONNX inference library present)
3. `DETECTOR_ENABLED` env var is **unset** OR its value is not `"0"`
4. The flag file `/home/pi/hhrcs/.sim_mode` does **NOT exist**

If any condition fails, the detector falls back to simulation mode (`_using_real = False`), which emits fake detections on a timer without running inference.

**To switch between modes:**
```bash
# Force simulation mode
touch /home/pi/hhrcs/.sim_mode

# Force real inference mode
rm -f /home/pi/hhrcs/.sim_mode

# Check current mode via API
curl -s http://raspberrypi.local:5001/status | python3 -m json.tool | grep yolo_sim_mode
```

**Model rollback (416 → 640):** If accuracy regresses, the 640 model is preserved:
```bash
ssh pi@raspberrypi.local "mv /home/pi/hhrcs/models/md_v1000_spruce_640.onnx.bak /home/pi/hhrcs/models/md_v1000_spruce.onnx"
# also update _MODEL_INPUT_SIZE = 640 in detector.py, scp, restart
```

**iOS sim mode toggle is cosmetic only** — the SETTINGS toggle updates `@AppStorage` on-device but does not call any Pi endpoint. It has no effect on the running detector. To actually toggle sim mode, use `ssh` to create/remove the `.sim_mode` flag file. Wiring the toggle to a `POST /detector/sim_mode` endpoint is a future task.

---

## Known Issues

| Severity | Issue | File | Notes |
|----------|-------|------|-------|
| `medium` | iOS sim mode toggle is cosmetic — does not flip Pi `.sim_mode` flag or `DETECTOR_ENABLED` env var | `SettingsTabView.swift` | Future fix: `POST /detector/sim_mode` endpoint; or remove toggle. Discovered 2026-05-07. |
| `resolved` | Detector inference speed — 1.77 fps achieved (2.7× speedup from 0.53fps baseline) | `detector.py` | Part 5: threads 2→3, ORT_SEQUENTIAL, cv2 letterbox (→~0.7fps). Part 6: 416×416 re-export (→1.77fps, ~550ms/frame). Budget warning threshold updated to 600ms. |
| `fixed`  | `detections.jsonl` write failed: `float32 not JSON serializable` | `detector.py` | `confidence` and `bbox` values were numpy float32. Fixed in Part 4 (2026-05-07): cast to `float()` before `round()`. |
| `fixed`  | `config.detector_confidence_threshold` NameError — should be `_config.` | `detector.py:213` | Pi was patched via `sed -i`; Mac copy fixed and committed in Part 4 (2026-05-07). |

---

## Deployment Readiness Checklist

### Phase A — System Validation (current)
- [ ] 24-hour burn-in test: Pi + real detector running unattended indoors, no thermal shutdown
- [ ] BMPCC trigger chain: animal detection → state machine ACTIVE → camera records → HOLDING → COUNTDOWN → IDLE confirmed end-to-end
- [ ] iOS smoke test: FEED stills update, detection log populates, ntfy alert lands, VERIFY mode shows correct bbox
- [ ] Tailscale connectivity: subscribe to free Personal plan, install Tailscale on Pi, install Tailscale on iPhone. Verify the iOS app can reach the Pi via Tailscale IP (not just local WiFi mDNS). Update DataViewModel to support both endpoints with automatic fallback. Document Pi's Tailscale IP in CONTEXT.md operator notes.
- [ ] Tailscale stress test: leave iPhone on cellular (off home WiFi) for 1+ hour, confirm /status polls succeed, stills load, ntfy pushes still arrive. Verify behavior across Pi reboot and WiFi flap at Pi side.

### Phase B — First Field Deployment
- [ ] Overnight in yard or driveway (controlled environment, recoverable if something fails)
- [ ] Footage review: BRAW clips playback, timecodes align with detection log timestamps
- [ ] Battery / power budget measured for target site duration (2–3 days unattended)

### Phase C — Remote Deployment Prep
- [ ] Power budget confirmed (Pi + BMPCC + camera + capture card at idle/active load)
- [ ] Weatherproofing: Pelican 1510 cable routing, desiccant, condensation plan
- [ ] Cellular fallback at remote site (mobile hotspot, LTE hat, or Starlink Mini). Tailscale relies on at least one network path reaching the Pi from the internet — without WiFi or cellular at the deploy site, the system is local-only.
- [ ] Active cooling installed (heatsink-fan case — required for sealed enclosure; bare Pi 4 will overheat)
- [ ] Cellular fallback: Tailscale confirmed reachable over mobile hotspot from deployment site
- [ ] Media capacity: CFast/SSD sized for full deployment window at BRAW 12:1 65 MB/s

### Phase D — Future Enhancements
- [ ] iOS sim mode toggle → wired to `POST /detector/sim_mode` Pi endpoint (currently cosmetic)
- [ ] Coral USB Accelerator — revisit when pricing normalizes ($60 normal; currently $200+ shortage)
- [ ] Species classifier: SpeciesNet or fine-tuned ResNet on top of MegaDetector bbox crops
- [ ] Time-of-day scheduling: dawn/dusk windows via `astral` + TSL2591 lux sensor (I2C not yet wired)
- [ ] H264 proxy recording on Pi: background `ffmpeg` from HDMI capture card alongside BRAW
- [ ] Auto-lux: ISO / aperture suggestions based on lux reading pushed to iOS

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

Pi HDMI endpoints (base: `http://raspberrypi.local:5001`):
- `GET  /hdmi-stream` — MJPEG live stream
- `POST /hdmi/still` — trigger HDMI still capture
- `GET  /hdmi/stills/latest` — fetch latest HDMI still JPEG

**BMPCC operator setup (before deployment):**
- Menu → Monitor → HDMI → Status Text → **On** (enables onboard histogram + recording state in the HDMI feed — the app displays this as part of the still image)
- Menu → Monitor → HDMI → Display 3D LUT → on or off per preference (no longer affects app behavior)
- Menu → Setup → Bluetooth Control → **Off** (BLE removed in ethernet migration)

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

## Pi Deployment — Mandatory Protocol

**Every session that modifies Pi-side Python MUST end with:**
```bash
scp pi/<file>.py pi@raspberrypi.local:/home/pi/hhrcs/<file>.py
ssh pi@raspberrypi.local "sudo systemctl restart hhrcs"
curl -s http://raspberrypi.local:5001/<new-endpoint> | python3 -m json.tool
```
No exceptions. If the session ends without these steps, the Pi is running stale code and any iOS feature depending on the new endpoint will silently fail (404/503).

**Mac copy sync discipline:** If a bug is patched directly on the Pi (e.g. via `sed -i`) without updating the Mac copy, the next `scp` deploy will silently reintroduce the bug. Rule: any Pi-side fix MUST be backported to the Mac copy and committed to git in the same session. Example: `detector.py` line 213 (`config.` → `_config.`) was patched on the Pi via sed; the Mac copy was fixed and committed in Part 4 (2026-05-07). If you ever find a discrepancy between a Pi file and the Mac copy, treat the Pi as ground truth only for that specific patch — always reconcile and commit.

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

**2026-05-06 — Three small fixes: histogram rendering, fullscreen X button, tab reorder**
(1) Histogram not displaying: `HistogramPoller.poll()` now uses `(json["clipped_low_pct"] as? NSNumber)?.doubleValue` instead of `as? Double` — `JSONSerialization` returns `NSNumber`, and `as? Double` can fail for integer-valued floats like `0.0`. Added `print` debug statements to confirm poll responses. Min bar height set to `max(1, ...)` so baseline is always visible even at 0-count bins. (2) Fullscreen X button unreachable: Root cause was `GeometryReader { }.ignoresSafeArea()` which makes `geo.safeAreaInsets.top = 0`, so `.padding(.top, geo.safeAreaInsets.top + 16)` resolved to only 16pt — inside Dynamic Island. Fix: restructured `FullscreenImageView` — removed outer `GeometryReader.ignoresSafeArea()` wrapper; image now has its own inner `GeometryReader.ignoresSafeArea()` (full screen for clamping); controls `VStack` sits in the outer `ZStack` which does NOT opt out of safe area, so it starts naturally below Dynamic Island; close button only needs `.padding(.top, 8)`. Applies to both BMPCC fullscreen and FIELD/STILLS fullscreen (shared `FullscreenImageView`). (3) Tab reorder: FEED is now tab 0 (was 1), FIELD is tab 1 (was 0). Updated `appTabs` array, `selectedTab = 0`, `tabContent` view order, recording-red indicator check (`tab.tag == 0`), `LaunchView.onAdvance(0)` for both auto-advance and CONTINUE OFFLINE.

**2026-05-06 — Histogram endpoint + iOS exposure monitoring** *(histogram code deployed to Pi 2026-05-06; was written locally last session but never scp'd)*
New Pi endpoint `GET /hdmi/histogram`: returns `{"bins":[64 ints], "clipped_low_pct":float, "clipped_high_pct":float, "ts":ISO8601}` from latest HDMI frame; throttled to 1Hz in `_read_loop`; 503 if HDMI offline. New iOS `HistogramView.swift`: `HistogramPoller` (ObservableObject, polls every 5s) + `HistogramView` (Canvas-based 64-bar rendering; bins 0/63 turn `recordingRed` when clipping >2%; clipping label shown when either value ≥0.5%). `CameraTabView` wires `histogramPoller` to BMPCC page only — starts/stops with `hdmiPoller`; `StillImagePage` gains `bins`/`clippedLow`/`clippedHigh` params, shows histogram strip below image (`.cardBackground` background). Tap-to-fullscreen added to `StillImagePage`: tapping the image opens `FullscreenImageView` with histogram overlay. `FullscreenImageView` updated: close button repositioned to `safeAreaInsets.top + 16` (Dynamic Island safe), 44×44 tap target with `contentShape(Rectangle())`; histogram pinned at bottom with `cardBackground.opacity(0.75)`. Landscape padding fix: `.padding(.bottom, isLandscape ? 0 : 54)` on all three FEED tab pages. **BMPCC operator setup (before deployment):** Menu → Monitor → HDMI → Status Text → Off; Display 3D LUT → Off (ensures histogram reads true log data).

**2026-05-06 — Histogram and false color subsystems removed (Part 9)**
Histogram and false color removed entirely. Both features derived exposure data from the 8-bit Rec.709-compressed HDMI feed, which redistributes the BMPCC's 12-bit log signal non-linearly — numeric IRE values diverge from the camera's onboard reference by ~20 IRE in highlights, making the derived data unreliable for calibrated exposure decisions. Operator instead enables BMPCC's Status Text HUD on-camera before deployment, which provides a ground-truth histogram and recording state directly in the HDMI feed image. Pi: `compute_histogram()`, `latest_histogram()`, `compute_false_color()`, `latest_false_color()`, `_get_crop()`, `_detect_active_image_area()`, `_build_false_color_lut()`, `_FALSE_COLOR_LUT`, and all associated instance attributes removed from `hdmi_stream.py`; `numpy` and `datetime` imports removed. `GET /hdmi/histogram` and `GET /hdmi/falsecolor` endpoints removed from `api_server.py`. iOS: `HistogramView.swift` deleted; `HistogramPoller`, `ChannelHistogram`, `HistogramChannel`, `FalseColorPoller`, `DisplayMode`, `FalseColorScalebar` removed from `CameraTabView.swift`; `StillImagePage` simplified to show only the still image with elapsed-time + refresh overlay; `FullscreenImageView` histogram overlay removed from `StillFrameView.swift`. BMPCC operator setup note updated: Status Text → On (was Off). Deployment verification: `/hdmi/histogram` HTTP 404, `/hdmi/falsecolor` HTTP 404, `/hdmi-stream` HTTP 200, `hdmi_reachable: True`.

**2026-05-06 — False color band IRE thresholds empirically shifted for 8-bit HDMI log**
False color band IRE thresholds shifted to compensate for 8-bit HDMI log → Rec.709 redistribution. Side-by-side comparison with BMPCC onboard false color showed a systemic IRE shift: surfaces BMPCC reads as 38 IRE (green, 18%MG) read as ~60 IRE in our 8-bit feed. `_build_false_color_lut()` updated with empirically-calibrated thresholds: Purple 0–5.5, Blue 5.5–10, Green 58–62, Pink 73–77, Yellow 88–93, Red 95+ (all IRE). Labels in `FalseColorScalebar` remain at BMPCC conceptual reference positions (BDL 0%, NBDL 4%, 18%MG 40%, MG+1 55%, 80%WC 80%, 95%WC 95%) because they describe exposure intent, not pixel values — label positions and gradient band positions are intentionally misaligned. Scalebar gradient stops updated with 20 stops to match new shifted thresholds; grey zone hex values from user spec. Deployment: HTTP 200, 314588 bytes, JPEG 1920×1080. **Operator note:** false color is visually calibrated to match BMPCC's onboard false color for the same scene, but the underlying numeric IRE values differ from BMPCC's because we read 8-bit Rec.709 HDMI, not 12-bit sensor log. Use false color as a relative exposure guide between deployments rather than a calibrated proof.

**2026-05-06 — False color rebuilt as ARRI-style narrow bands per BMPCC reference scale**
False color rebuilt as ARRI/BMPCC band-based scheme (corroborated by user-supplied BMPCC documentation image). Previous gradient approach was wrong — BMPCC scheme is band-based with grayscale between reference IRE points. `_build_false_color_lut()` replaced: most pixels map to luminance-preserving grayscale (`(v, v, v)` — full brightness, no dimming); 6 narrow color bands fire only at reference exposure zones: Purple 0–2.5 IRE (black detail loss), Blue 2.5–4 (near-black), Green 38–42 (18% middle grey), Pink 52–56 (skin tone, 1 stop over MG), Yellow 97–99 (near-white clipping warning), Red 99–100 (clipping). Red/Yellow thresholds raised to 97/99 IRE (from 80/95) to account for 8-bit HDMI signal compression vs 12-bit sensor log — highlights in our feed read slightly hot vs the camera's onboard reading. iOS `FalseColorScalebar.gradientStops` updated to 18 stops with paired duplicate-location stops for hard band transitions; grey zones use luminance-matched `Color(white:)` values; Canvas legend labels repositioned to band centers. Deployment: HTTP 200, 458931 bytes, JPEG 1920×1080. **Operator note:** false color in this app approximates exposure but is computed from compressed 8-bit HDMI feed, not raw sensor log — use as a guide, not a calibrated proof.

**2026-05-06 — False color LUT rebuilt as smooth gradient interpolation (BMPCC accurate)**
False color rebuilt as smooth gradient interpolation between BMPCC reference anchors. Previous narrow-band approach was incorrect — BMPCC uses continuous gradients with labeled reference points as landmarks, not isolated band colors. Image definition is preserved through gradient texture, not grey neutral zones. `_build_false_color_lut()` replaced with linear interpolation between 7 anchor points `(IRE, B, G, R)`: BDL (0) deep purple → NBDL (4) blue → 18%MG (40) green → MG+1 (55) pink → 80%WC (80) yellow → 95%WC/clip (95–100) red. Every pixel in 0–255 maps to an interpolated BGR color; no grey zones; no fallback paths reached under normal input. iOS `FalseColorScalebar.gradientStops` updated to 7 smooth stops (no duplicate-location pairs, no step transitions). Deployment: HTTP 200, 98027 bytes, JPEG 1920×1080.

**2026-05-06 — HDMI letterbox auto-detection for false color and histogram**
`_detect_active_image_area(frame)` added to `hdmi_stream.py`: scans row/column luminance means (threshold 8/255) from each edge to find the active image boundary, excluding HDMI letterbox bars (e.g. 4K DCI 17:9 framed into 16:9 HDMI produces ~34px black bars top and bottom). Result cached on `HDMIStreamer` and rechecked every 25 frames (~1s). `_get_crop(frame)` method encapsulates the cache logic. Both `compute_histogram()` and `compute_false_color()` updated to crop to the active area before processing. In false color, letterbox bars stay black (output frame is zero-initialized; only the active crop is colorized). In histogram, `total` pixel count uses the cropped shape so `clipped_low_pct` reflects real shadow content, not bar pixels. Verification: `luma clipped_low_pct: 0.0` (down from inflated value caused by counting letterbox black pixels as crushed shadows). False color: HTTP 200, 170183 bytes, JPEG 1920×1080.

**2026-05-06 — False color LUT corrected to BMPCC narrow-band scheme**
`hdmi_stream.py` `_build_false_color_lut()` replaced. Old LUT painted every pixel a band color (9 solid bands), which flattened image definition and didn't match BMPCC behavior. New LUT: most pixels map to desaturated grey (`v × 0.7`); only 6 narrow reference bands receive color — BDL (0–2 IRE, black), NBDL (2–4, bright blue), 18%MG (38–42, green), MG+1 (52–58, pink), 80%WC (78–82, yellow), 95%WC (95–100, red). Grey areas preserve image texture so image definition is readable. JPEG output size increased from ~92 KB to ~175 KB as expected (grey texture requires more JPEG bits than solid color). iOS `FalseColorScalebar` gradient stops updated to match: paired duplicate-location stops create sharp step transitions at band edges; grey zones use per-IRE grey values matching LUT. Legend row added below IRE labels using Canvas text draw: BDL · NBDL · 18%MG · MG+1 · 80%WC · 95%WC positioned at their approximate IRE fractions. Deployment curl: HTTP 200, 174636 bytes, JPEG 1920×1080.

**2026-05-06 — False color, RGB histogram modes, gesture cleanup**
Pi changes: (1) `hdmi_stream.py` — BMPCC-style false color LUT (`_build_false_color_lut()`, `_FALSE_COLOR_LUT`); `compute_false_color(frame)` converts BGR→gray, applies 256-entry LUT via numpy indexing, re-encodes as JPEG Q80; `compute_histogram()` extended to return per-channel data `{luma, r, g, b, ts}` — each channel has `bins:[64 ints]`, `clipped_low_pct`, `clipped_high_pct`; both computed at 1Hz in same throttle block. (2) `api_server.py` — `GET /hdmi/falsecolor` endpoint returns JPEG bytes or 503. BMPCC IRE→color scheme: 0–2.5 purple, 2.5–10 blue, 10–35 dark grey, 35–55 green (18% grey), 55–65 light grey, 65–78 pink (skin), 78–88 yellow, 88–97 orange, 97–100 red. iOS changes: (3) `HistogramView.swift` — `HistogramStyle` replaced by `HistogramChannel` enum (luma/rgbOverlap/rgbStacked); `ChannelHistogram` struct; `HistogramPoller` updated to parse new JSON; tap cycles channel mode via `@AppStorage("histogramChannel")`; only filled curve rendering; rgbOverlap draws B/G/R at 0.5 opacity; rgbStacked draws three horizontal bands with 0.5pt separators; clipping ticks use `anyClippedLow/High` (max across all channels). (4) `CameraTabView.swift` — `FalseColorPoller` class (GET every 5s); `DisplayMode` enum (still/falseColor); `FalseColorScalebar` view (4pt gradient bar + IRE labels 0 25 50 75 100); `StillImagePage` updated: long-press cycles still↔falseColor via `@AppStorage("bmpccDisplayMode")`; in falseColor mode shows FC image + scalebar instead of regular still + histogram; `.contentShape(Rectangle())` + `.contextMenu {}` suppress iOS image preview; tap→fullscreen only in still mode; `HistogramView` now takes luma/r/g/b `ChannelHistogram`. `FullscreenImageView` updated to take luma/r/g/b. Deployment: histogram HTTP 200 `keys:['b','g','luma','r','ts']` has_rgb:True; falsecolor HTTP 200, 91625 bytes, JPEG 1920×1080.

**2026-05-06 — Histogram styles + visibility toggle + unified black background**
iOS-only; no Pi changes. (1) Theme colors: `background` changed to `Color.black` (#000000); `cardBackground` changed to `Color(white: 0.07)` (#121212); `LaunchView` updated to reference `Theme.background` instead of hardcoded `Color.black`. (2) `HistogramView.swift` rewritten: new `HistogramStyle` enum (`.bars`, `.curve`, `.outline`); single-tap histogram cycles styles via `@AppStorage("histogramStyle")`; `.bars` renders 64 vertical rects (gap 0.5pt); `.curve` renders mid-point quadratic bezier as filled area (60% opacity, `smoothPath(closed:true)`); `.outline` renders same path as 1pt stroke; all modes mark bins 0/63 red when clipping >2%. (3) Long-press (≥0.4s) on BMPCC still image toggles histogram visibility via `@AppStorage("histogramVisible")`; `UIImpactFeedbackGenerator(.light)` haptic on iOS; guard prevents action when bins empty (CAM page); passing `histogramVisible ? bins : []` to `FullscreenImageView` cleanly hides histogram in fullscreen. (4) Refresh indicator (elapsed label + refresh button) always shown at flat `Theme.tertiary.opacity(0.4)` — removed conditional dim logic. (5) Histogram strip background changed from `Theme.cardBackground` to `Theme.background` in both `StillImagePage` and `FullscreenImageView` (`cardBackground.opacity(0.75)` → `Theme.background.opacity(0.82)`).

**2026-05-05 — ntfy.sh Layer 2 notifier + STORAGE card**
New `notifier.py` on Pi: `send_alert()` via ntfy.sh JSON API (UTF-8 safe); `evaluate_and_notify(summary)` checks cam_unreachable / ssd_critical / ssd_high / yolo_down / cpu_temp_high with 6-hour in-memory dedup. ntfy topic: `hhrcs-4a4a678c` (stored in `config.py` as `NTFY_TOPIC`; subscribe to this topic in the iOS ntfy app). Passive scheduler in `api_server.py` builds summary once, augments with storage + yolo_running, calls `evaluate_and_notify()` then `run_passive_summary(summary)` — single `build_summary()` call per tick. New `storage_monitor.py`: `df -B1` burn-rate tracker with daily snapshots; returns `days_remaining` after ≥2 days of data. `/status` now includes `storage` dict. iOS: `StorageSnapshot` + `StorageInfo` decodables; 6 new `@Published` vars in `DataViewModel`; `storageSection` var in `DataTabView` expanded inline (house drive bar + SSD bar + est. days remaining + burn rate). `run_passive_summary()` accepts optional pre-built `summary` dict to avoid redundant `build_summary()` call. Status bar hidden app-wide via `.statusBarHidden(true)` on root view in `HHRCSApp.swift`.

**2026-05-07 — ntfy notifier and test script aligned (Part 2)**
`notifier.py`: added `ssd_warning` tier (3–7 days remaining, priority `high`) between `ssd_critical` (<3 days, `urgent`) and `ssd_high` (≥90% used, `high`) — `elif` chain so only one fires per evaluation. BLE check skipped: BLE was fully removed in ethernet migration (2026-05-05 session confirmed `ble_state` removed from summary dict). `test_ntfy.sh` rewritten: fake summary now uses nested `storage` dict matching actual `agent.build_summary()` shape (previous version wrote flat keys that `_build_checks()` could not find). `ssd_warning` condition now fires with `days_remaining=5.0` (not `used_pct=92` as before). Conditions expanded from 5 to 6: `ssd_critical`, `ssd_warning`, `ssd_high`, `temp_high`, `cam_unreachable`, `yolo_down`. `ble_down` alias removed. All 6 conditions confirmed to fire and land on iOS ntfy app.

Alert conditions reference:

| Condition | Trigger | Priority |
|---|---|---|
| `ssd_critical` | <3 days remaining | urgent |
| `ssd_warning` | <7 days remaining | high |
| `ssd_high` | ≥90% used (no burn-rate data) | high |
| `cpu_temp_high` | >80°C | default |
| `cam_unreachable` | BMPCC REST 192.168.10.2 unreachable | high |
| `yolo_down` | detector thread not alive | high |

**2026-05-07 — YOLOv8 real-mode bring-up: ring buffer, threshold UI, VERIFY mode, LOG detections (Part 3)**
Pi changes: (1) `detector.py` — 2fps cadence (`sleep_time = 0.5 - elapsed`; warns if inference >500ms); module-level `_recent_detections: deque` ring buffer with 24h epoch-based pruning; `_dispatch()` now builds canonical record `{ts, class, confidence, bbox, frame_w, frame_h}` and appends to ring buffer with `_ts` key; daily JSONL rotation to `data/detections_YYYY-MM-DD.jsonl`; hot-reload of `config.detector_confidence_threshold` each inference frame; FPS tracking via `_inference_ts` deque; public methods `get_recent_detections(hours=24)` and `get_fps_actual()`. (2) `api_server.py` — startup loads threshold from `data/detector_threshold.json`; `/status` gains `detector_threshold` and `detector_fps_actual`; new endpoints: `GET /detections/recent?hours=24` returns `{detections:[...]}`, `GET /detections/latest` returns single record or 404, `POST /detector/threshold` accepts `{threshold: float}` and persists to JSON file. iOS changes: (3) `DataViewModel.swift` — `DetectionHistoryItem` struct (Identifiable+Decodable, `class` key aliased to `detectionClass`; `cgRect` computed from normalized bbox; `timestamp` parsed from ISO-8601 `ts`); `@Published var detectorThreshold`, `detectorFpsActual`, `detectionHistory`; HealthPoll extended with new fields; `setDetectorThreshold()`, `startDetectionHistoryPolling()` (5s loop), `stopDetectionHistoryPolling()`, `fetchDetectionHistory()` methods. (4) `SettingsTabView.swift` — DETECTOR THRESHOLD chevron card: header shows current value `0.60`; expanded: `Slider(0.0...1.0, step: 0.05)` with label + reference marks (`0.40 PERMISSIVE` / `0.60 DEFAULT` / `0.80 STRICT`); `.onEditingChanged` fires `vm.setDetectorThreshold()`. (5) `CameraTabView.swift` — `detectVerifyMode: Bool` via `@AppStorage`; VERIFY toggle button in `detectionControlBar`; `verifyLatestDetection` (first detection ≤60s old), `verifyFiveMinCount` (count within 5min); `startVerifyPolling()`/`stopVerifyPolling()`/`fetchVerifyDetections()` (2s Task loop hitting `/detections/recent`); `DetectionOverlayView` now receives `verifyDetection:` and `verifyFiveMinCount:`. (6) `DetectionOverlayView.swift` — accepts `verifyDetection: DetectionHistoryItem?` and `verifyFiveMinCount: Int`; when non-nil, draws 2pt bounding box in class-keyed color (animal=`Theme.accentColor`, person=`Theme.recordingRed`, vehicle=`Theme.secondary`) with 8pt SF Mono label "class  0.87" above top-left corner on `Theme.background` backing; `verifyFiveMinCount > 0` shows "DETECTIONS: N / 5min" counter top-right in 11pt SF Mono `Theme.tertiary`. (7) `SessionLogView.swift` — `LogItem` enum gains `.detection(DetectionHistoryItem)` case; `SessionLogView` gains `detectionEntries: [DetectionHistoryItem] = []` param; `DetectionLogRow` private struct: time | uppercased class (class-keyed color) | confidence; empty state shows clock icon + "NO ENTRIES" when grouped is empty. (8) `NotesTabView.swift` — `logContent` passes `detectionEntries: dataVM.detectionHistory`; `.onAppear`/`.onDisappear` on `logContent` call `startDetectionHistoryPolling()`/`stopDetectionHistoryPolling()`; `.onChange(of: segment)` also manages polling lifecycle. Operator note: MegaDetectorLite classes are `animal`, `person`, `vehicle` — no species-level classification.

**2026-05-07 — Re-export MegaDetector Spruce at 416×416 for faster Pi inference (Part 6)**
Pi-only; iOS untouched. Pre-flight: Mac and Pi `detector.py` confirmed identical (diff empty). Export: `md_v1000.0.0-spruce.pt` (14.3 MB YOLOv5-backbone) re-exported via `torch.hub.load("ultralytics/yolov5", "custom", autoshape=False)` + `torch.onnx.export(opset=12, imgsz=416)`. Output: `md_v1000_spruce_416.onnx` (28.3 MB, input `[1,3,416,416]`, output `[1,10647,8]`, NMS not baked in). Export venv: Python 3.12 + torch 2.2.2 + numpy<2 pin. Mac `onnxruntime` sanity test: `[PASS] Inference OK`. Pi model shape confirmed: `[1, 3, 416, 416]`. Backup of 640 model preserved at `models/md_v1000_spruce_640.onnx.bak`. `_MODEL_INPUT_SIZE` in `detector.py` changed 640→416; `_letterbox` default 640→416. Baseline fps: 0.53 (640 model). Post-deploy fps at 416: **1.77 fps** (2.7× speedup from 0.7fps post-Part-5 baseline; ~550ms/frame). Budget warning threshold updated 500ms→600ms to suppress noise at borderline-OK frames. Coral USB Accelerator considered as hardware acceleration path but pricing inflated ($200+ vs normal $60 due to chip shortage). Documented, not pursuing. Revisit when pricing normalizes. End-of-day status: 1.77fps stable, Pi temp ~42°C, ntfy verified, iOS polished across Parts 3–6 (6 hours). Next: Phase A system validation (burn-in test, BMPCC trigger chain, iOS smoke test).

**2026-05-07 — Detector real-mode performance fixes (Part 5)**
Pi-only; iOS untouched. Pre-flight confirmed Mac and Pi `detector.py` copies already identical (diff empty). Three changes: (1) ONNX session options: `intra_op_num_threads` bumped 2→3 (`ORT_SEQUENTIAL` also added); Pi 4 has 4 cores — leaves 1 for system/Flask/capture. Session creation now logs `ONNX intra=3, inter=1`. (2) `_letterbox()` hot-path: replaced `__import__("PIL").Image.fromarray(...).resize(...)` (dynamic import every call) with `cv2.resize()` via module-level `import cv2 as _cv2` with `ImportError` fallback. `cv2` 4.13.0 confirmed in Pi venv. (3) Baseline fps before fix: `detector_fps_actual ≈ 0.53`. Post-deploy fps: ~0.7 fps (improvement from Part 5 mitigations; further boosted to 1.77fps after Part 6 416×416 re-export). Model: `md_v1000_spruce.onnx` — MegaDetectorLite, 28MB, YOLOv5-backbone, 3 classes: animal/person/vehicle, no species ID.

**2026-05-07 — Detector real-mode bring-up: post-deployment fixes and status (Part 4)**
Real inference confirmed functional end-to-end. First detection: `animal conf=0.77` at `2026-05-07T19:00:24 UTC`. Gating: real mode requires picamera2 importable + onnxruntime importable + `DETECTOR_ENABLED` not `"0"` + `/home/pi/hhrcs/.sim_mode` file absent. Removed `.sim_mode` today to enable real inference. Two bugs found and fixed: (1) `detector.py:213` — `config.detector_confidence_threshold` should be `_config.detector_confidence_threshold` (Pi was patched via `sed -i`; Mac copy fixed and committed here). (2) `detections.jsonl` write failed with `float32 not JSON serializable` — numpy float32 bbox/confidence values not castable by `json.dumps()`; fixed by wrapping with `float()` before `round()`. Known open issues: inference is ~1600ms/frame (target 500ms, 0.53 actual fps vs 2.0 target) — thermal ruled out (CPU 37.9°C); root cause unknown, likely input resolution or onnxruntime config. iOS sim mode toggle is cosmetic only — does not affect the Pi; fix deferred.

**2026-05-07 — UI cleanup batch: settings/field/stills/feed (Part 10)**
iOS-only; no Pi changes. (1) SETTINGS — LOG extracted from DIAGNOSTIC card into a standalone tappable card (`logCard`) inserted directly below DIAGNOSTIC in the settings scroll view. Header row: `LOG` title left + chevron right; tapping anywhere toggles expanded/collapsed; default collapsed; `easeInOut(0.2s)` animation. DIAGNOSTIC card now only contains dot rows and active-dot detail panel; LOG chevron button removed from DIAGNOSTIC. (2) FIELD — Swipe between STILLS / AGENT / LOG sub-pages: `switch segment {}` replaced by `TabView(selection: $segment)` with `.tabViewStyle(.page(indexDisplayMode: .never))`; existing `segment` state var drives both tab bar tap selection and swipe. (3) STILLS source label — `CapturedStill.sourceLabel` computed property added (`triggerType == "hdmi" ? "BMPCC" : "CAM"`); 9pt SF Mono `Theme.tertiary` label shown centered below each thumbnail in `StillCell` (4pt spacing); BMPCC badge (was keyed off `bmpccFilename`) removed; `FullscreenImageView` gains optional `sourceLabel: String?` shown top-left at 16pt padding. (4) STILLS empty state — "tap the camera button..." helper text removed; empty state is icon + "NO STILLS CAPTURED" only. (5) STILLS long-press delete — `LongPressGesture(minimumDuration: 0.4)` replaces `.onLongPressGesture`; `UIImpactFeedbackGenerator(style: .medium)` haptic on iOS; system `.alert()` replaced by themed `DeleteConfirmSheet` (`.sheet(isPresented:)`): `Theme.background` full-screen, `Theme.cardBackground` card with 32pt margins, centered slightly above center; "DELETE STILL?" header + "This cannot be undone." body; CANCEL (`Theme.secondary`) / DELETE (`Theme.recordingRed`) horizontal buttons; same sheet accessible from fullscreen via `FullscreenImageView`'s optional `onDelete` closure. (6) FEED — `Text("POLLING")` changed to `Text("CONNECTING")` in `CameraTabView.swift` (the empty-state label when no still is available yet).
