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

Pi HDMI endpoints (base: `http://raspberrypi.local:5001`):
- `GET  /hdmi/histogram` — per-channel 64-bin histogram; returns `{"luma":{...}, "r":{...}, "g":{...}, "b":{...}, "ts":ISO8601}`. Each channel has `bins:[64 ints]`, `clipped_low_pct`, `clipped_high_pct`. Throttled to 1Hz on Pi.
- `GET  /hdmi/falsecolor` — BMPCC-style false color JPEG (1920×1080, Q80) of latest HDMI frame. Throttled to 1Hz. 503 if HDMI offline.

**BMPCC false color — smooth gradient interpolation between IRE anchors:**
| Anchor | IRE | Color | Meaning |
|--------|-----|-------|---------|
| BDL    | 0   | Deep purple | Crushed black |
| NBDL   | 4   | Bright blue | Near-black warning |
| 18%MG  | 40  | Green       | 18% middle grey reference |
| MG+1   | 55  | Pink        | Skin tone / one stop above MG |
| 80%WC  | 80  | Yellow      | Highlight warning |
| 95%WC  | 95  | Red         | Clipped white |

Continuous gradient; no grey zones. Every pixel gets a color interpolated between the nearest two anchors. Image definition is preserved through gradient texture.

**HDMI letterbox auto-detection:** `_detect_active_image_area()` scans row/column luminance means from each edge; any row/column below threshold 8/255 is treated as a black bar. Active area is cached and rechecked every ~25 frames (~1s), so codec/aspect ratio changes (e.g. switching between 4K DCI 17:9 and 16:9) are picked up without restart. Both `compute_histogram()` and `compute_false_color()` operate only on the detected active area — letterbox bars stay black in false color output and are excluded from histogram pixel counts. A 50% sanity-check falls back to the full frame when the scene is very dark (no bars detectable).

**BMPCC operator setup (before deployment):**
- Menu → Monitor → HDMI → Status Text → **Off** (removes firmware overlay from HDMI output)
- Menu → Monitor → HDMI → Display 3D LUT → **Off** (ensures histogram reads true log data)
- Menu → Monitor → HDMI → Zebra → **Off** (optional, avoids blown whites masking histogram)

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
New `notifier.py` on Pi: `send_alert()` via ntfy.sh JSON API (UTF-8 safe); `evaluate_and_notify(summary)` checks cam_unreachable / ssd_critical / ssd_high / yolo_down / cpu_temp_high with 6-hour in-memory dedup. Passive scheduler in `api_server.py` builds summary once, augments with storage + yolo_running, calls `evaluate_and_notify()` then `run_passive_summary(summary)` — single `build_summary()` call per tick. New `storage_monitor.py`: `df -B1` burn-rate tracker with daily snapshots; returns `days_remaining` after ≥2 days of data. `/status` now includes `storage` dict. iOS: `StorageSnapshot` + `StorageInfo` decodables; 6 new `@Published` vars in `DataViewModel`; `storageSection` var in `DataTabView` expanded inline (house drive bar + SSD bar + est. days remaining + burn rate). `run_passive_summary()` accepts optional pre-built `summary` dict to avoid redundant `build_summary()` call. Status bar hidden app-wide via `.statusBarHidden(true)` on root view in `HHRCSApp.swift`.
