"""
Pi Camera Module 3 — dual-stream via one Picamera2 instance.

  main  : 3072x1728 @ 24fps   ISP full-res (Phase 4: attach H264Encoder here to record)
  lores : 1280x720  @ 24fps   hardware MJPEG encoder -> StreamingOutput

StreamingOutput is a condition-variable buffer; the Flask generator blocks on it
and yields each JPEG as the hardware delivers it — no color conversion, no PIL, no numpy.

Phase 4 wiring (do not restructure, just add):
    from picamera2.encoders import H264Encoder
    from picamera2.outputs import FfmpegOutput
    streamer.camera.start_recording(H264Encoder(bitrate=10_000_000), FfmpegOutput(path), name="main")
    streamer.camera.stop_recording(name="main")  # or stop_encoder depending on version
"""

import io
import logging
import threading
import time
from typing import Optional

log = logging.getLogger(__name__)

try:
    from picamera2 import Picamera2
    from picamera2.encoders import MJPEGEncoder
    from picamera2.outputs import FileOutput
    _PICAMERA2_OK = True
except ImportError:
    _PICAMERA2_OK = False
    log.warning("picamera2 not available — stream disabled")


class StreamingOutput(io.BufferedIOBase):
    """Single-frame ring buffer with condition variable for the MJPEG generator."""
    def __init__(self):
        self.frame     = None
        self.condition = threading.Condition()
        self._count    = 0
        self._t0       = None
        self._subs     = []
        self._sub_lock = threading.Lock()

    def add_subscriber(self, cb):
        with self._sub_lock:
            self._subs.append(cb)

    def remove_subscriber(self, cb):
        with self._sub_lock:
            self._subs = [s for s in self._subs if s is not cb]

    def write(self, buf):
        import time as _time
        if self._t0 is None:
            self._t0 = _time.monotonic()
        self._count += 1
        if self._count % 24 == 0:
            elapsed = _time.monotonic() - self._t0
            log.info("HW encoder rate: %.1f fps (%d frames)", self._count / elapsed, self._count)
        with self.condition:
            self.frame = buf
            self.condition.notify_all()
        with self._sub_lock:
            for cb in self._subs:
                try:
                    cb(buf)
                except Exception:
                    pass


class PiCameraStreamer:
    """
    One Picamera2 instance; two streams:
      main  (3072x1728, YUV420) : self.camera exposed for Phase 4
      lores (1280x720)           : hardware MJPEG encoder -> StreamingOutput

    generate() is the MJPEG frame generator for Flask.
    capture_jpeg() returns the most recent frame for still snapshots.
    """

    MAIN_SIZE  = (2304, 1296)
    LORES_SIZE = (1280, 720)
    FRAMERATE  = 24

    def __init__(self):
        self.camera:   Optional["Picamera2"]     = None
        self._output:  Optional[StreamingOutput] = None
        self._running  = False

    def start(self):
        if not _PICAMERA2_OK:
            log.warning("PiCameraStreamer: picamera2 unavailable")
            return
        try:
            cam = Picamera2()
            cfg = cam.create_video_configuration(
                main     = {"size": self.MAIN_SIZE,  "format": "YUV420"},
                lores    = {"size": self.LORES_SIZE, "format": "YUV420"},
                controls = {"FrameRate": self.FRAMERATE},
                buffer_count = 6,
            )
            cam.configure(cfg)
            output = StreamingOutput()
            cam.start_recording(MJPEGEncoder(), FileOutput(output), name="lores")
            time.sleep(1)
            self.camera   = cam
            self._output  = output
            self._running = True
            log.info(
                "PiCameraStreamer: main=%s lores=%s @ %dfps (hardware MJPEG)",
                self.MAIN_SIZE, self.LORES_SIZE, self.FRAMERATE,
            )
        except Exception as e:
            log.error("PiCameraStreamer.start failed: %s", e)
            self.camera = None

    def stop(self):
        self._running = False
        cam, self.camera = self.camera, None
        if cam:
            try:
                cam.stop_recording()
                cam.stop()
                cam.close()
            except Exception:
                pass

    def capture_jpeg(self) -> Optional[bytes]:
        """Most recent hardware-encoded JPEG frame. Non-blocking."""
        return self._output.frame if self._output else None

    @property
    def available(self) -> bool:
        return self.camera is not None and self._running


    def start_recording(self, path=None):
        log.info("PiCameraStreamer.start_recording called (stub)")
        return True

    def stop_recording(self):
        log.info("PiCameraStreamer.stop_recording called (stub)")
        return True

    def generate(self):
        """
        MJPEG frame generator for Flask Response.
        Blocks on the hardware encoder's condition variable — no polling, no sleep.
        """
        if not self._output:
            return
        while self._running:
            with self._output.condition:
                self._output.condition.wait()
                frame = self._output.frame
            if frame:
                yield (
                    b"--frame\r\n"
                    b"Content-Type: image/jpeg\r\n\r\n" + frame + b"\r\n"
                )
