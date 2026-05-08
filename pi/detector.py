"""
Wildlife detector — Pi Camera Module 3 + MegaDetectorLite ONNX (md_v1000_spruce).
Falls back to simulated detections if hardware/packages are unavailable.

Detection triggers callback(class_name) for any detected target class.

NOTE: This is the emit-instrumented version of the Pi detector.
If the Pi's detector.py has been updated since this was generated, apply the
events import and _dispatch() emit call to the current Pi version manually.
The only additions are:
  1.  from events import emit as _emit  (try/except guarded)
  2.  _emit("detector.trigger", {...}) in _dispatch() before self.callback()
"""

import collections
import json
import os
import threading
import logging
import random
import time
from datetime import datetime, timezone
from typing import Callable, List, Optional

try:
    import cv2 as _cv2
    _cv2_available = True
except ImportError:
    _cv2 = None
    _cv2_available = False

log = logging.getLogger(__name__)

try:
    from events import emit as _emit
except ImportError:
    def _emit(*a, **kw): pass

try:
    from config import config as _config
except ImportError:
    class _FallbackConfig:
        pi_cam_resolution = (1280, 720)
        pi_cam_sensor_mode = (2304, 1296)
    _config = _FallbackConfig()

_CLASSES = ["deer", "rabbit", "bird"]
_WEIGHTS = [0.45, 0.30, 0.25]

_picamera2_available = False
_onnx_available = False

try:
    from picamera2 import Picamera2
    _picamera2_available = True
    log.info("picamera2 available")
except ImportError:
    log.warning("picamera2 not available")

try:
    import onnxruntime as ort
    import numpy as np
    _onnx_available = True
    log.info("onnxruntime available")
except ImportError:
    log.warning("onnxruntime not available")


_MEGADETECTOR_CLASSES = {0: "animal", 1: "person", 2: "vehicle"}
_MODEL_VERSION = "md_v1000_spruce"
_MODEL_INPUT_SIZE = 416

# ── Detection ring buffer (24h) + FPS tracking ────────────────────────────────
_DATA_DIR            = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
_recent_detections: collections.deque = collections.deque()   # dicts with "_ts" epoch key
_det_lock            = threading.Lock()
_inference_ts:       collections.deque = collections.deque()  # epoch times of recent inferences
_inference_lock      = threading.Lock()


class Detector:
    """
    Run MegaDetectorLite ONNX detection in a background thread.
    Calls callback(class_name) when a target class is detected.
    """

    def __init__(
        self,
        callback: Callable[[str], None],
        classes: Optional[List[str]] = None,
        confidence: float = 0.45,
        fps: int = 5,
        resolution: tuple = (1280, 720),
        model_path: str = "/home/pi/hhrcs/models/md_v1000_spruce.onnx",
    ):
        self.callback = callback
        self.classes = classes or _CLASSES
        self.confidence = confidence
        self.fps = fps
        self.resolution = resolution
        self.model_path = model_path

        self._thread: Optional[threading.Thread] = None
        self._running = False
        self._camera = None
        self._session = None

        # MJPEG frame subscribers
        self._frame_lock = threading.Lock()
        self._latest_jpeg: Optional[bytes] = None
        self._latest_frame = None  # raw capture array, shared between capture thread and inference
        self._last_inference_time: float | None = None

        # Respect DETECTOR_ENABLED env var OR a .sim_mode flag file (either forces simulation)
        _env_enabled = os.environ.get("DETECTOR_ENABLED", "1") != "0"
        _flag_file   = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".sim_mode")
        _flag_enabled = not os.path.exists(_flag_file)
        self._using_real = _picamera2_available and _onnx_available and _env_enabled and _flag_enabled

    def start(self):
        self._running = True
        target = self._real_loop if self._using_real else self._sim_loop
        self._thread = threading.Thread(target=target, daemon=True, name="detector")
        self._thread.start()
        log.info(f"Detector started ({'MegaDetectorLite ONNX' if self._using_real else 'simulation'})")

    def stop(self):
        self._running = False
        if self._camera:
            try:
                self._camera.stop()
            except Exception:
                pass

    # ── Real hardware loop ────────────────────────────────────────────────────

    def _letterbox(self, img: "np.ndarray", new_shape: int = 416):
        """Resize with padding to square, return resized image and scale/pad info."""
        h, w = img.shape[:2]
        scale = new_shape / max(h, w)
        nh, nw = int(h * scale), int(w * scale)
        if _cv2_available:
            resized = _cv2.resize(img, (nw, nh), interpolation=_cv2.INTER_LINEAR)
        else:
            resized = np.array(
                __import__("PIL").Image.fromarray(img).resize((nw, nh), __import__("PIL").Image.BILINEAR)
            )
        pad_h = (new_shape - nh) // 2
        pad_w = (new_shape - nw) // 2
        padded = np.full((new_shape, new_shape, 3), 114, dtype=np.uint8)
        padded[pad_h:pad_h + nh, pad_w:pad_w + nw] = resized
        return padded, scale, pad_w, pad_h

    def _nms(self, boxes, scores, iou_threshold=0.45):
        """Pure-NumPy NMS. boxes: [N,4] x1y1x2y2. Returns kept indices."""
        order = scores.argsort()[::-1]
        keep = []
        while order.size > 0:
            i = order[0]
            keep.append(i)
            if order.size == 1:
                break
            xx1 = np.maximum(boxes[i, 0], boxes[order[1:], 0])
            yy1 = np.maximum(boxes[i, 1], boxes[order[1:], 1])
            xx2 = np.minimum(boxes[i, 2], boxes[order[1:], 2])
            yy2 = np.minimum(boxes[i, 3], boxes[order[1:], 3])
            inter = np.maximum(0, xx2 - xx1) * np.maximum(0, yy2 - yy1)
            area_i = (boxes[i, 2] - boxes[i, 0]) * (boxes[i, 3] - boxes[i, 1])
            area_j = (boxes[order[1:], 2] - boxes[order[1:], 0]) * (boxes[order[1:], 3] - boxes[order[1:], 1])
            iou = inter / (area_i + area_j - inter + 1e-6)
            order = order[1:][iou <= iou_threshold]
        return keep

    def _real_loop(self):
        try:
            import onnxruntime as ort
            import numpy as np

            self._camera = Picamera2()
            cfg = self._camera.create_video_configuration(
                main={"size": _config.pi_cam_resolution, "format": "RGB888"},
                raw={"size": _config.pi_cam_sensor_mode},
            )
            log.info(f"Camera configured: output {_config.pi_cam_resolution[0]}x{_config.pi_cam_resolution[1]}, sensor {_config.pi_cam_sensor_mode[0]}x{_config.pi_cam_sensor_mode[1]}")
            self._camera.configure(cfg)
            self._camera.start()
            time.sleep(2)

            log.info(f"Loading ONNX model: {self.model_path}")
            t0 = time.time()
            opts = ort.SessionOptions()
            opts.intra_op_num_threads = 3   # Pi 4 has 4 cores; leaves 1 for system/Flask/capture
            opts.inter_op_num_threads = 1
            opts.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
            opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
            self._session = ort.InferenceSession(
                self.model_path,
                sess_options=opts,
                providers=["CPUExecutionProvider"],
            )
            log.info(f"Model loaded in {(time.time()-t0)*1000:.0f}ms — ONNX intra={opts.intra_op_num_threads}, inter={opts.inter_op_num_threads}")

            # Capture thread owns Picamera2 cadence (~10fps); inference reads _latest_frame.
            threading.Thread(target=self._capture_thread_loop, daemon=True, name="cam-capture").start()
            # Stream loop encodes _latest_frame to JPEG for /stream (~10fps).
            threading.Thread(target=self._camera_stream_loop, daemon=True, name="cam-stream").start()

        except Exception as e:
            log.error(f"Camera/model init failed ({e}) — falling back to simulation")
            self._sim_loop()
            return

        input_name = self._session.get_inputs()[0].name

        while self._running:
            t_frame_start = time.time()
            try:
                frame = self._latest_frame
                if frame is None:
                    time.sleep(0.1)
                    continue

                # Hot-reload threshold from config on every frame
                threshold = _config.detector_confidence_threshold

                # Preprocess
                padded, scale, pad_w, pad_h = self._letterbox(frame, _MODEL_INPUT_SIZE)
                inp = (padded.astype(np.float32) / 255.0).transpose(2, 0, 1)[np.newaxis]

                # Infer
                frame_ts = datetime.now(timezone.utc).isoformat(timespec="milliseconds")
                outputs = self._session.run(None, {input_name: inp})
                t_infer_done = time.time()
                self._last_inference_time = t_infer_done

                # Track rolling-30s FPS
                with _inference_lock:
                    _inference_ts.append(t_infer_done)
                    cutoff30 = t_infer_done - 30.0
                    while _inference_ts and _inference_ts[0] < cutoff30:
                        _inference_ts.popleft()

                preds = outputs[0][0]  # [N, 6] — x1,y1,x2,y2,conf,cls

                mask = preds[:, 4] >= threshold
                preds = preds[mask]
                if len(preds) > 0:
                    boxes = preds[:, :4]
                    scores = preds[:, 4]
                    class_ids = preds[:, 5].astype(int)
                    keep = self._nms(boxes, scores, iou_threshold=0.45)
                    for idx in keep:
                        cls_id  = class_ids[idx]
                        conf    = float(scores[idx])
                        box_raw = boxes[idx]
                        x1 = (box_raw[0] - pad_w) / (scale * frame.shape[1])
                        y1 = (box_raw[1] - pad_h) / (scale * frame.shape[0])
                        x2 = (box_raw[2] - pad_w) / (scale * frame.shape[1])
                        y2 = (box_raw[3] - pad_h) / (scale * frame.shape[0])
                        bbox = [max(0.0, min(1.0, x1)), max(0.0, min(1.0, y1)),
                                max(0.0, min(1.0, x2)), max(0.0, min(1.0, y2))]
                        md_category = _MEGADETECTOR_CLASSES.get(cls_id, "animal")
                        self._dispatch(md_category, conf, bbox, frame_ts,
                                       frame_w=frame.shape[1], frame_h=frame.shape[0])
                        break  # one trigger per frame

            except Exception as e:
                log.error(f"Detection frame error: {e}")
                time.sleep(1.0)
                continue

            # Target 2fps cadence (0.5s per frame)
            elapsed = time.time() - t_frame_start
            sleep_time = 0.5 - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)
            elif elapsed > 0.5:
                log.warning(f"Inference {elapsed*1000:.0f}ms exceeded 2fps budget (500ms/frame)")

    def _dispatch(self, category: str, confidence: float, bbox: list, frame_ts: str,
                  frame_w: int = 1280, frame_h: int = 720) -> None:
        """Write to ring buffer + JSONL, emit telemetry event, invoke callback."""
        record = {
            "ts":         frame_ts,
            "class":      category,
            "confidence": round(float(confidence), 4),
            "bbox":       [round(float(v), 4) for v in bbox],
            "frame_w":    frame_w,
            "frame_h":    frame_h,
        }
        _now = time.time()
        # 24h ring buffer
        with _det_lock:
            while _recent_detections and _recent_detections[0].get("_ts", 0) < _now - 86400:
                _recent_detections.popleft()
            _recent_detections.append({"_ts": _now, **record})
        # Daily JSONL — append-only, one file per day
        try:
            os.makedirs(_DATA_DIR, exist_ok=True)
            fname = os.path.join(_DATA_DIR, "detections_" + datetime.now().strftime("%Y-%m-%d") + ".jsonl")
            with open(fname, "a") as fh:
                fh.write(json.dumps(record) + "\n")
        except Exception as ex:
            log.warning(f"detections.jsonl write failed: {ex}")
        # Event bus (unchanged contract)
        _emit("detector.trigger", {
            "confidence":      round(float(confidence), 4),
            "category":        category,
            "bbox":            [round(float(v), 4) for v in bbox],
            "frame_timestamp": frame_ts,
            "model_version":   _MODEL_VERSION,
        })
        log.info(f"Detection: {category} conf={confidence:.2f}")
        self.callback(category)

    # ── Public accessors ──────────────────────────────────────────────────────

    def get_recent_detections(self, hours: int = 24) -> list:
        """Return detections from last `hours` hours, newest first, without internal fields."""
        cutoff = time.time() - hours * 3600
        with _det_lock:
            result = [
                {k: v for k, v in d.items() if k != "_ts"}
                for d in reversed(_recent_detections)
                if d.get("_ts", 0) >= cutoff
            ]
        return result

    def get_fps_actual(self) -> float:
        """Rolling 30s average inference FPS (0.0 when not running or insufficient data)."""
        with _inference_lock:
            count = len(_inference_ts)
        return round(count / 30.0, 2) if count >= 2 else 0.0

    # ── MJPEG frame provider (for /stream endpoint) ───────────────────────────

    def capture_jpeg(self) -> Optional[bytes]:
        """Return the latest JPEG byte string from the Pi camera, or None."""
        with self._frame_lock:
            return self._latest_jpeg

    @property
    def last_inference_ago_seconds(self) -> Optional[float]:
        if self._last_inference_time is None:
            return None
        return round(time.time() - self._last_inference_time, 1)

    def restart(self) -> None:
        """Stop the inference thread cleanly, clear state, and restart."""
        log.info("Detector restarting...")
        self._running = False
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=5.0)
        if self._camera:
            try:
                self._camera.stop()
            except Exception:
                pass
            self._camera = None
        self._session = None
        self._last_inference_time = None
        self._latest_frame = None
        self.start()
        log.info("Detector restarted")

    # ── Simulation fallback ────────────────────────────────────────────────────

    def _capture_thread_loop(self):
        """Owns Picamera2 capture cadence in real mode — ~10fps, updates _latest_frame."""
        while self._running:
            try:
                self._latest_frame = self._camera.capture_array()
            except Exception as e:
                log.warning(f"Capture thread error: {e}")
            time.sleep(0.1)

    def _camera_stream_loop(self):
        """JPEG encoding for /stream. Real mode: reads _latest_frame from capture thread.
        Sim mode: opens own Picamera2 instance (inference camera not available)."""
        import io
        from PIL import Image

        if self._using_real:
            log.info("Camera stream started (real mode, reads shared capture thread)")
            while self._running:
                frame = self._latest_frame
                if frame is not None:
                    try:
                        img = Image.fromarray(frame[:, :, ::-1])
                        buf = io.BytesIO()
                        img.save(buf, format="JPEG", quality=70)
                        with self._frame_lock:
                            self._latest_jpeg = buf.getvalue()
                    except Exception as e:
                        log.warning(f"Stream encode error: {e}")
                time.sleep(0.1)
            return

        # Sim mode: no inference camera open — open dedicated stream camera
        if not _picamera2_available:
            return
        cam = None
        try:
            cam = Picamera2()
            cfg = cam.create_video_configuration(
                main={"size": _config.pi_cam_resolution, "format": "RGB888"},
                raw={"size": _config.pi_cam_sensor_mode},
            )
            cam.configure(cfg)
            cam.start()
            time.sleep(2)
            log.info(f"Camera stream started (sim mode, {_config.pi_cam_resolution[0]}x{_config.pi_cam_resolution[1]}, ~10 fps)")
            while self._running:
                try:
                    frame = cam.capture_array()
                    img = Image.fromarray(frame[:, :, ::-1])
                    buf = io.BytesIO()
                    img.save(buf, format="JPEG", quality=70)
                    with self._frame_lock:
                        self._latest_jpeg = buf.getvalue()
                except Exception as e:
                    log.warning(f"Camera stream frame error: {e}")
                time.sleep(0.1)
        except Exception as e:
            log.error(f"Camera stream init failed: {e}")
        finally:
            if cam:
                try:
                    cam.stop()
                except Exception:
                    pass

    def _sim_loop(self):
        log.info("Simulated detector running")
        if _picamera2_available:
            t = threading.Thread(target=self._camera_stream_loop, daemon=True, name="cam-stream")
            t.start()
        while self._running:
            interval = random.uniform(8, 40)
            time.sleep(interval)
            if self._running:
                cls = random.choices(_CLASSES, weights=_WEIGHTS)[0]
                conf = random.uniform(0.55, 0.92)
                bbox = [random.uniform(0.1, 0.4), random.uniform(0.1, 0.4),
                        random.uniform(0.5, 0.9), random.uniform(0.5, 0.9)]
                frame_ts = datetime.now(timezone.utc).isoformat(timespec="milliseconds")
                log.debug(f"Sim detection: {cls}")
                self._dispatch(cls, conf, bbox, frame_ts)
