import cv2
import threading
import time
import logging

from config import HDMI_DEVICE, HDMI_WIDTH, HDMI_HEIGHT, HDMI_FPS

log = logging.getLogger(__name__)


class HDMIStreamer:
    def __init__(self):
        self._cap: cv2.VideoCapture | None = None
        self._thread: threading.Thread | None = None
        self._running = False
        self._latest: bytes | None = None
        self._lock = threading.Lock()

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
        log.info("HDMIStreamer._read_loop: exiting")
