import cv2
import threading
import time
import logging
import numpy as np
from datetime import datetime, timezone

from config import HDMI_DEVICE, HDMI_WIDTH, HDMI_HEIGHT, HDMI_FPS

log = logging.getLogger(__name__)


# ARRI/BMPCC false color LUT — narrow reference bands with luminance-preserving
# grayscale between them. Band IRE thresholds are empirically shifted to account
# for 8-bit Rec.709 HDMI vs 12-bit log sensor redistribution: the same scene
# content sits at higher pixel values in our 8-bit feed than in BMPCC's internal
# 12-bit log signal. Labels describe exposure intent (BMPCC reference scale),
# not the numeric pixel values used here.
#
# Empirically calibrated IRE bands (BGR for OpenCV):
#   0–5.5     Purple (130,0,100)  — BDL: black detail loss   (sensor ~0–2.5)
#   5.5–10    Blue   (255,100,0)  — NBDL: near-black          (sensor ~2.5–4)
#   58–62     Green  (0,220,0)    — 18%MG: middle grey         (sensor ~38–42)
#   73–77     Pink   (200,100,240)— MG+1: skin tone            (sensor ~52–56)
#   88–93     Yellow (0,220,240)  — 80%WC: near-white warning  (sensor ~78–95)
#   95+       Red    (0,0,255)    — 95%WC: clipping            (sensor ~99–100)
def _build_false_color_lut() -> np.ndarray:
    """ARRI/BMPCC-style false color, IRE-shifted for 8-bit HDMI log. Never raises."""
    PURPLE = (130,   0, 100)
    BLUE   = (255, 100,   0)
    GREEN  = (  0, 220,   0)
    PINK   = (200, 100, 240)
    YELLOW = (  0, 220, 240)
    RED    = (  0,   0, 255)

    lut = np.zeros((256, 1, 3), dtype=np.uint8)
    for v in range(256):
        ire = (v / 255.0) * 100.0
        if ire < 5.5:
            bgr = PURPLE
        elif ire < 10.0:
            bgr = BLUE
        elif 58.0 <= ire <= 62.0:
            bgr = GREEN
        elif 73.0 <= ire <= 77.0:
            bgr = PINK
        elif 88.0 <= ire <= 93.0:
            bgr = YELLOW
        elif ire >= 95.0:
            bgr = RED
        else:
            bgr = (v, v, v)
        lut[v, 0] = bgr
    return lut

_FALSE_COLOR_LUT = _build_false_color_lut()


def _detect_active_image_area(frame: np.ndarray) -> tuple[int, int, int, int]:
    """
    Return (y_start, y_end, x_start, x_end) bounding the active image area,
    excluding HDMI letterbox / pillarbox bars.

    Scans row and column luminance means from each edge; rows/columns whose
    mean is below threshold are treated as black bars.  A 50% sanity-check
    falls back to the full frame when the scene itself is very dark.
    """
    try:
        if frame is None or frame.size == 0:
            return (0, frame.shape[0], 0, frame.shape[1])

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) if frame.ndim == 3 else frame
        h, w = gray.shape
        row_means = gray.mean(axis=1)

        threshold = 8  # 8/255 — generous to handle HDMI noise floor

        y_start = 0
        for i in range(h):
            if row_means[i] > threshold:
                y_start = i
                break

        y_end = h
        for i in range(h - 1, -1, -1):
            if row_means[i] > threshold:
                y_end = i + 1
                break

        if (y_end - y_start) < (h * 0.5):
            return (0, h, 0, w)

        col_means = gray.mean(axis=0)

        x_start = 0
        for i in range(w):
            if col_means[i] > threshold:
                x_start = i
                break

        x_end = w
        for i in range(w - 1, -1, -1):
            if col_means[i] > threshold:
                x_end = i + 1
                break

        if (x_end - x_start) < (w * 0.5):
            x_start, x_end = 0, w

        return (y_start, y_end, x_start, x_end)
    except Exception:
        return (0, frame.shape[0], 0, frame.shape[1])


class HDMIStreamer:
    def __init__(self):
        self._cap: cv2.VideoCapture | None = None
        self._thread: threading.Thread | None = None
        self._running = False
        self._latest: bytes | None = None
        self._latest_histogram: dict | None = None
        self._latest_false_color_jpeg: bytes | None = None
        self._lock = threading.Lock()
        self._last_hist_ts: float = 0.0       # monotonic; read_loop only
        self._cached_crop: tuple | None = None # (y0, y1, x0, x1)
        self._crop_recheck_counter: int = 0    # recheck every 25 frames (~1s)

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

    def _get_crop(self, frame) -> tuple[int, int, int, int]:
        """Return cached (y0, y1, x0, x1) crop, refreshing every 25 frames."""
        if self._cached_crop is None or self._crop_recheck_counter >= 25:
            self._cached_crop = _detect_active_image_area(frame)
            self._crop_recheck_counter = 0
            log.debug(f"HDMIStreamer: crop detected {self._cached_crop}")
        self._crop_recheck_counter += 1
        return self._cached_crop

    def compute_histogram(self, frame) -> dict | None:
        """Per-channel 64-bin histogram (luma + R, G, B) on active image area. Never raises."""
        try:
            y0, y1, x0, x1 = self._get_crop(frame)
            cropped = frame[y0:y1, x0:x1]
            gray    = cv2.cvtColor(cropped, cv2.COLOR_BGR2GRAY)
            total   = cropped.shape[0] * cropped.shape[1]

            def _ch(arr):
                b, _ = np.histogram(arr, bins=64, range=(0, 256))
                return {
                    "bins":             b.astype(int).tolist(),
                    "clipped_low_pct":  round(float(b[0])  / total, 4),
                    "clipped_high_pct": round(float(b[-1]) / total, 4),
                }

            return {
                "luma": _ch(gray),
                "r":    _ch(cropped[:, :, 2]),   # OpenCV BGR: index 2 = R
                "g":    _ch(cropped[:, :, 1]),
                "b":    _ch(cropped[:, :, 0]),
                "ts":   datetime.now(timezone.utc).isoformat(),
            }
        except Exception as e:
            log.debug(f"HDMIStreamer.compute_histogram: {e}")
            return None

    def compute_false_color(self, frame) -> bytes | None:
        """Apply BMPCC IRE false-color LUT to active area; letterbox stays black. Never raises."""
        try:
            y0, y1, x0, x1 = self._get_crop(frame)
            cropped         = frame[y0:y1, x0:x1]
            gray            = cv2.cvtColor(cropped, cv2.COLOR_BGR2GRAY)
            colored_active  = _FALSE_COLOR_LUT[gray].squeeze(2)  # (crop_H, crop_W, 3) BGR
            output          = np.zeros_like(frame)                # full frame, black bars stay
            output[y0:y1, x0:x1] = colored_active
            ok, buf         = cv2.imencode(".jpg", output, [cv2.IMWRITE_JPEG_QUALITY, 80])
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
