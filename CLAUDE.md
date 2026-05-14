# CLAUDE.md — HHRCS (Hunter House Remote Camera System)

Load this file at the start of any Claude Code session on this project.
Full technical detail lives in `CONTEXT.md` — read that for deep hardware/software context.

---

## Memory protocol — instructions for Claude

This file is the persistent memory for this project. Follow these rules every session:

1. **On load** — read this file, then read `CONTEXT.md` for full technical context.
2. **After each major task** — append a dated entry to the Session Log at the bottom.
3. **Mid-session** — if hardware state, network config, or architecture changes, update `CONTEXT.md` immediately (it is the authoritative technical record). Note the change in the Session Log here.
4. **End of session** — consolidate: update `CONTEXT.md` header timestamp and summary line, write a Session Log entry here, commit and push both files.
5. **Never delete log entries.** Append only.

---

## Project in one sentence

Unattended outdoor wildlife cinema rig at Hunter House (North Meadow, 203 Goward Road, Prospect Lake, Saanich BC) — BMPCC 6K Pro controlled by Raspberry Pi 4 over ethernet, with wildlife detection via Pi Camera + MegaDetectorLite ONNX, managed via SwiftUI iOS app.

- **Local path:** `/Users/brandonpoole/Projects/HHRCS`
- **GitHub:** github.com/bturep/HHRCS
- **Active branch:** `feature/ethernet` (merged BLE removal; main is behind)
- **Deploy:** push to `feature/ethernet` or merge to `main`

---

## Repo structure

```
HHRCS/
├── HHRCS.xcodeproj         iOS app (SwiftUI, iOS 17+, bundle: com.brandonpoole.hhrcs)
├── HHRCS/                  App source
│   ├── Agent/              Tier 1 rule-based + Tier 2 Claude Haiku agent
│   ├── App/                App entry, tab structure
│   ├── Camera/             MJPEG stream, BMPCC control
│   ├── Control/            Recording start/stop
│   ├── Data/               DataViewModel — polls /status every 2s
│   ├── Log/                Event feed from /log and /agent-log
│   ├── Settings/           AppSettings, URL switcher
│   └── UI/                 Shared components, theme
│
├── pi/                     Raspberry Pi 4 backend (Python / Flask)
│   ├── api_server.py       Flask REST API — port 5001
│   ├── agent.py            Two-tier agent (rule-based + Claude Haiku)
│   ├── detector.py         MegaDetectorLite ONNX wildlife detection
│   ├── camera_control.py   BMPCC 6K Pro REST API (192.168.10.2)
│   ├── state_machine.py    ACTIVE → HOLDING → COUNTDOWN recording FSM
│   ├── session.py          Deployment lifecycle
│   ├── sensors.py          I2C sensors (lux, temp — not yet wired)
│   ├── picam_stream.py     Pi Camera Module 3 MJPEG stream
│   ├── hdmi_stream.py      BMPCC HDMI → USB capture MJPEG stream
│   ├── hhrcs.service       systemd service file
│   └── schemas/            Pydantic models
│
└── tools/                  Dev utilities
```

---

## Quick reference — network & access

| Target | Address |
|---|---|
| Pi SSH (LAN) | `ssh pi@raspberrypi.local` · password: hhrcs2026 |
| Pi SSH (Tailscale) | `ssh pi@hhrcs-pi` |
| Pi Tailscale IP | 100.118.27.125 |
| HHRCS API (LAN) | http://raspberrypi.local:5001 |
| HHRCS API (Tailscale) | http://hhrcs-pi:5001 |
| BMPCC REST API | http://192.168.10.2/control/api/v1 |
| Pi Camera stream | http://raspberrypi.local:5001/stream |
| HDMI capture | /dev/video2 · MJPEG 1920×1080@25fps |

**Pi WiFi IPs:** 192.168.1.68 (WiFi) · 192.168.1.82 (Ethernet) — always use hostname, not IP.

---

## Key architecture decisions (current as of May 2026)

- **No ESP32.** BLE bridge removed May 4 2026. Camera control is direct HTTP over USB-C ethernet adapter (192.168.10.0/24 subnet). Tag `pre-ethernet-fork` preserves old architecture.
- **No NVMe SSD.** BMPCC records to its own SD/CFast. Offload is physical (site visit every 2–3 days).
- **ONNX inference:** 3 threads (`intra_op_num_threads=3`), active cooling, thermal ceiling 46.3°C.
- **Recording FSM:** ACTIVE (animal detected) → HOLDING (15 min grace) → COUNTDOWN (2 min, resets on redetect).
- **iOS URL switcher:** seeds `raspberrypi.local:5001` and `100.118.27.125:5001` on first launch; user taps to switch.

See `CONTEXT.md` for full hardware table, networking notes, API reference, and iOS tab structure.

---

## Deploying Pi changes

```bash
scp pi/<file>.py pi@raspberrypi.local:~/hhrcs/
ssh pi@raspberrypi.local "sudo systemctl restart hhrcs"
```

---

## Session log

Append an entry after every major task. Never delete entries.

---

### 2026-05-14 — CLAUDE.md created; repo moved to ~/Projects/HHRCS

- Created this CLAUDE.md as persistent session memory wrapper around existing CONTEXT.md.
- Repo moved from `~/HunterHouseApp` to `~/Projects/HHRCS` — remote (bturep/HHRCS) unchanged.
- ESP32 repo (`~/hhrcs_esp32`) deleted — had no remote, user confirmed.
- Git push/add/commit already pre-authorised in Claude Code settings.local.json.
