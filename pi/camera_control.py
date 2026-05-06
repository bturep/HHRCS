"""
Camera control via BMPCC REST API (ethernet, 192.168.10.2).

Hardware path: Pi → ethernet → BMPCC 6K Pro REST API
"""

import logging
from camera_http import BMPCCCameraClient

log = logging.getLogger(__name__)

_client = BMPCCCameraClient()

# Clip name to use for the next record_start call (set via /camera/clip_name)
_next_clip_name: str = ""


class CameraControl:
    """
    Thin wrapper around BMPCCCameraClient that preserves the public
    interface expected by api_server.py, state_machine.py, and agent.py.
    """

    # ── Recording ──────────────────────────────────────────────────────────────

    def record_start(self):
        global _next_clip_name
        clip = _next_clip_name
        _next_clip_name = ""
        ok = _client.record_start(clip_name=clip)
        if not ok:
            log.warning("[cam] record_start returned failure")

    def record_stop(self):
        ok = _client.record_stop()
        if not ok:
            log.warning("[cam] record_stop returned failure")

    # ── Exposure ───────────────────────────────────────────────────────────────

    def set_iso(self, iso: int):
        _client.set_iso(iso)

    def set_white_balance(self, kelvin: int, tint: int = 0):
        _client.set_white_balance(kelvin)

    def set_shutter_angle(self, angle: int):
        log.info(f"[cam] set_shutter_angle({angle}) — not exposed by BMPCC REST API")

    def set_auto_white_balance(self):
        log.info("[cam] set_auto_white_balance — not exposed by BMPCC REST API")

    def set_fps(self, fps: int):
        log.info(f"[cam] set_fps({fps}) — use set_format() instead")

    def set_nd(self, nd_filter: str):
        log.info(f"[cam] set_nd({nd_filter}) — not exposed by BMPCC REST API")

    def trigger_still(self):
        log.info("[cam] trigger_still — not implemented over REST API")

    def toggle_overlay(self) -> bool:
        data = _client._get("/video/outputOverlay")
        if data is None:
            return False
        current = bool(data.get("enabled", data.get("overlayEnabled", False)))
        return _client._put("/video/outputOverlay", {"enabled": not current})

    # ── State ──────────────────────────────────────────────────────────────────

    @property
    def connected(self) -> bool:
        return _client.is_reachable()

    def get_camera_state(self) -> dict:
        return _client.get_full_state()


# Module-level singleton — imported by api_server
camera = CameraControl()
