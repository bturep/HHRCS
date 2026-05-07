import cv2
import threading
import time
import logging
import numpy as np
from datetime import datetime, timezone

from config import HDMI_DEVICE, HDMI_WIDTH, HDMI_HEIGHT, HDMI_FPS

log = logging.getLogger(__name__)


# BMPCC-style false color LUT — 256-entry lookup table mapping 8-bit luminance
# to BGR color. Matches Blackmagic's actual narrow-band scheme: most pixels stay
# monochrome grey; only specific IRE reference zones receive a distinct color so
# image definition is preserved and exposure is readable at a glance.
#
# Reference bands (IRE → color):
#   BDL   (0–2):    black          — clipped black
#   NBDL  (2–4):    bright blue    — near-black warning
#   18%MG (38–42):  green          — 18% middle grey reference
#   MG+1  (52–58):  pink           — one stop above middle grey (skin tone)
#   80%WC (78–82):  yellow         — highlight warning
#   95%WC (95–100): red            — clipped white
def _build_false_color_lut() -> np.ndarray:
    lut = np.zeros((256, 1, 3), dtype=np.uint8)
    for v in range(256):
        ire = (v / 255.0) * 100.0
        if ire <= 2:
            lut[v, 0] = (  0,   0,   0)   # BDL   — black
        elif ire <= 4:
            lut[v, 0] = (255, 100,   0)   # NBDL  — bright blue (BGR)
        elif 38 <= ire <= 42:
            lut[v, 0] = (  0, 220,   0)   # 18%MG — green
        elif 52 <= ire <= 58:
            lut[v, 0] = (200, 100, 240)   # MG+1  — pink
        elif 78 <= ire <= 82:
            lut[v, 0] = (  0, 220, 240)   # 80%WC — yellow
        elif ire >= 95:
            lut[v, 0] = (  0,   0, 255)   # 95%WC — red
        else:
            grey       = int(v * 0.7)     # dimmed grey preserves image definition
            lut[v, 0]  = (grey, grey, grey)
    return lut

_FALSE_COLOR_LUT = _build_false_color_lut()


class HDMIStreamer:
    def __init__(self):
        self._cap: cv2.VideoCapture | None = None
        self._thread: threading.Thread | None = None
        self._running = False
        self._latest: bytes | None = None
        self._latest_histogram: dict | None = None
        self._latest_false_color_jpeg: bytes | None = None
        self._lock = threading.Lock()
        self._last_hist_ts: float = 0.0  # monotonic; read_loop only

    def start(self):
        cap = cv2.VideoCapture(HDMI_DEVICE, cv2.CAP_V4L2)
        if not cap.isOpened():
            log.warning(f"HDMIStreamer: could not open {HDMI_DEVICE} — capture card absent?")
            return
        cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, HDMI_WIDTH)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, HDMI_HEIGHT)
        cap.set(cv2.CAP_PROP_FPS, HDMI_FPS)
        self._cap = cap
        self._running = True
        self._thread = threading.Thread(target=self._read_loop, daemon=True, name="hdmi-reader")
        self._thread.start()
        log.info(f"HDMIStreamer: started on {HDMI_DEVICE} {HDMI_WIDTH}x{HDMI_HEIGHT}@{HDMI_FPS}fps")

    def stop(self):
        self._running = False
        if self._thread:
            self._thread.join(timeout=3)
            self._thread = None
        if self._cap:
            self._cap.release()
            self._cap = None
        with self._lock:
            self._latest = None
        log.info("HDMIStreamer: stopped")

    def is_open(self) -> bool:
        return (
            self._cap is not None
            and self._cap.isOpened()
            and self._running
            and self._latest is not None
        )

    def capture_jpeg(self) -> bytes | None:
        with self._lock:
            return self._latest

    def generate_mjpeg(self):
        interval = 1.0 / HDMI_FPS
        while True:
            try:
                frame = self.capture_jpeg()
                if frame is not None:
                    yield (
                        b"--frame\r\n"
                        b"Content-Type: image/jpeg\r\n\r\n"
                        + frame
                        + b"\r\n"
                    )
                time.sleep(interval)
            except GeneratorExit:
                break
            except Exception as e:
                log.debug(f"HDMIStreamer.generate_mjpeg: {e}")
                time.sleep(interval)

    def compute_histogram(self, frame) -> dict | None:
        """Per-channel 64-bin histogram (luma + R, G, B). Never raises."""
        try:
            gray  = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            total = frame.shape[0] * frame.shape[1]

            def _ch(arr):
                b, _ = np.histogram(arr, bins=64, range=(0, 256))
                return {
                    "bins":             b.astype(int).tolist(),
                    "clipped_low_pct":  round(float(b[0])  / total, 4),
                    "clipped_high_pct": round(float(b[-1]) / total, 4),
                }

            return {
                "luma": _ch(gray),
                "r":    _ch(frame[:, :, 2]),   # OpenCV BGR: index 2 = R
                "g":    _ch(frame[:, :, 1]),
                "b":    _ch(frame[:, :, 0]),
                "ts":   datetime.now(timezone.utc).isoformat(),
            }
        except Exception as e:
            log.debug(f"HDMIStreamer.compute_histogram: {e}")
            return None

    def compute_false_color(self, frame) -> bytes | None:
        """Apply BMPCC IRE false-color LUT; return JPEG bytes. Never raises."""
        try:
            gray    = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            colored = _FALSE_COLOR_LUT[gray].squeeze(2)  # (H, W, 3) BGR
            ok, buf = cv2.imencode(".jpg", colored, [cv2.IMWRITE_JPEG_QUALITY, 80])
            return buf.tobytes() if ok else None
        except Exception as e:
            log.debug(f"HDMIStreamer.compute_false_color: {e}")
            return None

    def latest_histogram(self) -> dict | None:
        with self._lock:
            return self._latest_histogram

    def latest_false_color(self) -> bytes | None:
        with self._lock:
            return self._latest_false_color_jpeg

    def _read_loop(self):
        while self._running and self._cap and self._cap.isOpened():
            ok, frame = self._cap.read()
            if not ok:
                time.sleep(0.05)
                continue
            ok2, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 85])
            if ok2:
                with self._lock:
                    self._latest = buf.tobytes()

            # Throttle histogram + false color to 1 Hz to avoid burning CPU.
            now = time.monotonic()
            if now - self._last_hist_ts >= 1.0:
                hist = self.compute_histogram(frame)
                fc   = self.compute_false_color(frame)
                with self._lock:
                    if hist is not None:
                        self._latest_histogram = hist
                    if fc is not None:
                        self._latest_false_color_jpeg = fc
                self._last_hist_ts = now

        log.info("HDMIStreamer._read_loop: exiting")
