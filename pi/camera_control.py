"""
Camera control via esp32-bridge HTTP daemon (localhost:5002).

Hardware path:  Pi  →─(HTTP localhost:5002)─→  esp32-bridge  →─(USB serial)─→  ESP32  →─(BLE)─→  BMPCC 6K Pro
Firmware:       Magic-Pocket-Control-ESP32 library (marklysze/Magic-Pocket-Control-ESP32)
Bridge:         /home/pi/hhrcs/esp32_bridge.py, systemd unit esp32-bridge.service

Bridge endpoints used:
    POST /esp32/send  {"cmd": "RECORD:START"}
    POST /esp32/send  {"cmd": "RECORD:STOP"}
    POST /esp32/send  {"cmd": "ISO:3200"}
    POST /esp32/send  {"cmd": "ND:ND4"}
    GET  /esp32/state  → {"ble_state": "Connected", ...}
    GET  /esp32/log    → {"lines": [...]}

All public methods are safe to call when the bridge is unreachable —
they log a warning and return immediately.
"""

import logging
import requests

log = logging.getLogger(__name__)

BRIDGE_URL = "http://localhost:5002"
TIMEOUT = 2  # seconds — must not block the main loop


def _send(cmd: str) -> bool:
    """POST a command to the bridge. Returns True on success."""
    try:
        r = requests.post(
            f"{BRIDGE_URL}/esp32/send",
            json={"cmd": cmd},
            timeout=TIMEOUT,
        )
        r.raise_for_status()
        log.info(f"→ bridge: ({cmd})")
        return True
    except Exception as e:
        log.warning(f"[bridge] send failed for ({cmd}): {e}")
        return False


def _get_state() -> dict:
    """GET /esp32/state. Returns empty dict on failure."""
    try:
        r = requests.get(f"{BRIDGE_URL}/esp32/state", timeout=TIMEOUT)
        r.raise_for_status()
        return r.json()
    except Exception as e:
        log.warning(f"[bridge] state fetch failed: {e}")
        return {}


def _get_log_lines() -> list:
    """GET /esp32/log. Returns empty list on failure."""
    try:
        r = requests.get(f"{BRIDGE_URL}/esp32/log", timeout=TIMEOUT)
        r.raise_for_status()
        return r.json().get("lines", [])
    except Exception:
        return []


class CameraControl:
    """
    HTTP client to the esp32-bridge daemon.
    Drop-in replacement for the old serial CameraControl —
    same public API, no direct serial access.
    """

    # ── Recording ──────────────────────────────────────────────────────────────

    def record_start(self):
        _send("RECORD:START")

    def record_stop(self):
        _send("RECORD:STOP")

    # ── Exposure ───────────────────────────────────────────────────────────────

    def set_iso(self, iso: int):
        _send(f"ISO:{iso}")

    def set_shutter_angle(self, angle: int):
        _send(f"SHUTTER:{angle}")

    def set_white_balance(self, kelvin: int, tint: int = 0):
        _send(f"WB:{kelvin}:{tint}")

    def set_auto_white_balance(self):
        _send("AUTOWB:")

    def set_fps(self, fps: int):
        log.info(f"[FPS] {fps} requested — not yet implemented in bridge firmware")

    def set_nd(self, nd_filter: str):
        _send(f"ND:{nd_filter}")

    def trigger_still(self):
        log.info("[STILL] not implemented — BLE-only feature")

    # ── State ──────────────────────────────────────────────────────────────────

    @property
    def connected(self) -> bool:
        """True when bridge is reachable AND BLE is Connected."""
        s = _get_state()
        return s.get("ble_state") == "Connected"

    @property
    def bridge_reachable(self) -> bool:
        """True when the bridge HTTP daemon responds at all."""
        return bool(_get_state())

    @property
    def ble_state(self) -> str:
        return _get_state().get("ble_state", "Unknown")

    @property
    def port_name(self) -> str:
        return "esp32-bridge:5002"

    def get_camera_state(self) -> dict:
        """
        Parse recent log lines from the bridge for camera telemetry.
        Returns a dict with keys: recording, iso, shutter_angle, codec.
        """
        lines = _get_log_lines()
        result = {"recording": False, "iso": None, "shutter_angle": None, "codec": None}
        for line in reversed(lines):
            if line.startswith(">>Recording:") and result["recording"] is False:
                result["recording"] = (line.split(":", 1)[1].strip() == "Yes")
            elif line.startswith(">>ISO:") and result["iso"] is None:
                try:
                    result["iso"] = int(line.split(":", 1)[1].strip())
                except ValueError:
                    pass
            elif line.startswith(">>ShutterAngle:") and result["shutter_angle"] is None:
                try:
                    result["shutter_angle"] = int(line.split(":", 1)[1].strip())
                except ValueError:
                    pass
            elif line.startswith(">>Codec:") and result["codec"] is None:
                result["codec"] = line.split(":", 1)[1].strip()
            if all(v is not None for v in [result["iso"], result["shutter_angle"], result["codec"]]):
                break
        return result


# Module-level singleton — imported by api_server
camera = CameraControl()
