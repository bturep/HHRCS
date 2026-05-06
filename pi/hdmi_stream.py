import cv2
import threading
import time
import logging
import numpy as np
from datetime import datetime, timezone

from config import HDMI_DEVICE, HDMI_WIDTH, HDMI_HEIGHT, HDMI_FPS

log = logging.getLogger(__name__)


class HDMIStreamer:
    def __init__(self):
        self._cap: cv2.VideoCapture | None = None
        self._thread: threading.Thread | None = None
        self._running = False
        self._latest: bytes | None = None
        self._latest_histogram: dict | None = None
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
        """Convert BGR frame to 64-bin grayscale histogram. Never raises."""
        try:
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            bins, _ = np.histogram(gray, bins=64, range=(0, 256))
            total = frame.shape[0] * frame.shape[1]
            clipped_low  = float(bins[0])  / total
            clipped_high = float(bins[-1]) / total
            return {
                "bins": bins.astype(int).tolist(),
                "clipped_low_pct":  round(clipped_low,  4),
                "clipped_high_pct": round(clipped_high, 4),
                "ts": datetime.now(timezone.utc).isoformat(),
            }
        except Exception as e:
            log.debug(f"HDMIStreamer.compute_histogram: {e}")
            return None

    def latest_histogram(self) -> dict | None:
        with self._lock:
            return self._latest_histogram

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

            # Throttle histogram to once per second to avoid burning CPU.
            now = time.monotonic()
            if now - self._last_hist_ts >= 1.0:
                hist = self.compute_histogram(frame)
                if hist is not None:
                    with self._lock:
                        self._latest_histogram = hist
                self._last_hist_ts = now

        log.info("HDMIStreamer._read_loop: exiting")
