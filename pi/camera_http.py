"""
BMPCC REST API client (ethernet, 192.168.10.2).
All methods return None/False on failure — never raise.
"""

import logging
from typing import Optional
import requests
from requests.adapters import HTTPAdapter

from config import CAMERA_BASE_URL, CAMERA_REQUEST_TIMEOUT

log = logging.getLogger(__name__)

_SLOT_MAP = {"sd0": "SD", "cf0": "CFast", "usb0": "USB"}


class BMPCCCameraClient:

    def __init__(self, base_url: str = CAMERA_BASE_URL, timeout: int = CAMERA_REQUEST_TIMEOUT):
        self._base = base_url.rstrip("/")
        self._timeout = timeout
        self._session = requests.Session()
        adapter = HTTPAdapter(max_retries=0)
        self._session.mount("http://", adapter)

    def _get(self, path: str) -> Optional[dict]:
        try:
            r = self._session.get(f"{self._base}{path}", timeout=self._timeout)
            r.raise_for_status()
            return r.json()
        except Exception as e:
            log.warning(f"[cam] GET {path} failed: {e}")
            return None

    def _put(self, path: str, body: dict) -> bool:
        try:
            r = self._session.put(f"{self._base}{path}", json=body, timeout=self._timeout)
            return r.status_code in (200, 204)
        except Exception as e:
            log.warning(f"[cam] PUT {path} failed: {e}")
            return False

    # ── Reachability ──────────────────────────────────────────────────────────

    def is_reachable(self) -> bool:
        try:
            r = self._session.get(f"{self._base}/transports/0", timeout=self._timeout)
            return r.status_code == 200
        except Exception:
            return False

    # ── Recording ─────────────────────────────────────────────────────────────

    def record_start(self, clip_name: str = "") -> bool:
        body: dict = {"recording": True}
        if clip_name:
            body["clipName"] = clip_name
        return self._put("/transports/0/record", body)

    def record_stop(self) -> bool:
        return self._put("/transports/0/record", {"recording": False})

    def is_recording(self) -> bool:
        data = self._get("/transports/0/record")
        if data is None:
            return False
        return bool(data.get("recording", False))

    # ── Exposure ──────────────────────────────────────────────────────────────

    def get_iso(self) -> Optional[int]:
        data = self._get("/video/iso")
        return data.get("iso") if data else None

    def set_iso(self, iso: int) -> bool:
        return self._put("/video/iso", {"iso": iso})

    def get_white_balance(self) -> Optional[int]:
        data = self._get("/video/whiteBalance")
        return data.get("whiteBalance") if data else None

    def set_white_balance(self, kelvin: int) -> bool:
        return self._put("/video/whiteBalance", {"whiteBalance": kelvin})

    def get_gain(self) -> Optional[int]:
        data = self._get("/video/gain")
        return data.get("gain") if data else None

    # ── Format ────────────────────────────────────────────────────────────────

    def get_format(self) -> Optional[dict]:
        return self._get("/system/format")

    def set_format(self, codec: str = None, frame_rate: str = None, **kwargs) -> bool:
        body = {}
        if codec is not None:
            body["codec"] = codec
        if frame_rate is not None:
            body["frameRate"] = frame_rate
        body.update(kwargs)
        if not body:
            return True
        return self._put("/system/format", body)

    # ── Media ─────────────────────────────────────────────────────────────────

    def get_active_media(self) -> Optional[dict]:
        return self._get("/media/active")

    # ── Full state (used by /status endpoint) ─────────────────────────────────

    def get_full_state(self) -> dict:
        result: dict = {
            "cam_reachable":             False,
            "cam_recording":             False,
            "cam_codec":                 None,
            "cam_frame_rate":            None,
            "cam_resolution":            None,
            "cam_iso":                   None,
            "cam_white_balance":         None,
            "cam_gain":                  None,
            "cam_active_media_slot":     None,
            "cam_remaining_record_time": None,
        }

        if not self.is_reachable():
            return result

        result["cam_reachable"] = True

        try:
            rec_data = self._get("/transports/0/record")
            if rec_data:
                result["cam_recording"] = bool(rec_data.get("recording", False))
        except Exception as e:
            log.warning(f"[cam] record state fetch: {e}")

        try:
            fmt = self.get_format()
            if fmt:
                result["cam_codec"]      = fmt.get("codec")
                result["cam_frame_rate"] = fmt.get("frameRate")
                res = fmt.get("recordResolution", {})
                if isinstance(res, dict) and "width" in res and "height" in res:
                    result["cam_resolution"] = f"{res['width']}x{res['height']}"
        except Exception as e:
            log.warning(f"[cam] format fetch: {e}")

        try:
            result["cam_iso"] = self.get_iso()
        except Exception as e:
            log.warning(f"[cam] iso fetch: {e}")

        try:
            result["cam_white_balance"] = self.get_white_balance()
        except Exception as e:
            log.warning(f"[cam] wb fetch: {e}")

        try:
            result["cam_gain"] = self.get_gain()
        except Exception as e:
            log.warning(f"[cam] gain fetch: {e}")

        try:
            media = self.get_active_media()
            if media:
                raw = media.get("deviceName") or media.get("slot")
                result["cam_active_media_slot"] = _SLOT_MAP.get(raw, raw) if raw else None
        except Exception as e:
            log.warning(f"[cam] media fetch: {e}")

        return result
