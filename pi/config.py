# HHRCS Configuration
# All deployment parameters in one place

from dataclasses import dataclass, field
from typing import List, Tuple

@dataclass
class Config:
    # Deployment
    deployment_name: str = "HUNTER HOUSE"
    position_name: str = "NORTH MEADOW"

    # Location (Prospect Lake, Saanich, Victoria BC)
    latitude: float = 48.515
    longitude: float = -123.408
    timezone: str = "America/Vancouver"

    # Recording windows
    dawn_offset_minutes: int = -10        # open before civil twilight
    dawn_close_minutes: int = 90          # close after sunrise
    dusk_open_minutes: int = -90          # open before sunset
    dusk_close_minutes: int = 10          # close after civil twilight

    # Detection — MegaDetectorLite (MDv1000-spruce, YOLOv5s)
    detection_fps: int = 5                # inference rate (frames per second, not stream fps)
    detector_confidence_threshold: float = 0.6
    detector_input_size: int = 640        # pixels, square
    detector_animal_categories: List[str] = field(
        default_factory=lambda: ["animal"]  # MD category 1 (0-indexed: 0); triggers recording
    )
    detector_model_path: str = "/home/pi/hhrcs/models/md_v1000_spruce.onnx"

    # Legacy fields kept for state_machine.py and session logging compatibility
    detection_classes: List[str] = field(default_factory=lambda: ["animal", "person", "vehicle"])
    detection_confidence: float = 0.6     # alias for detector_confidence_threshold
    detection_resolution: Tuple[int, int] = (640, 640)

    grace_period_seconds: int = 900       # 15 min HOLDING window
    countdown_seconds: int = 120          # 2 min countdown before stop

    # Lux thresholds
    lux_min_record: float = 0.5
    lux_window_override: float = 50.0

    # Storage
    ssd_mount: str = "/media/ssd"
    house_drive_mount: str = "/media/house"
    house_drive_total_tb: float = 6.0

    # Camera settings (fixed per session)
    iso: int = 3200
    nd_filter: str = "ND4"
    shutter_angle: int = 180
    fps: int = 24
    format: str = "BRAW 12:1"
    resolution: str = "6K"

    # BLE
    ble_reconnect_interval: int = 10

    # Pi
    pi_cam_resolution: Tuple[int, int] = (1152, 648)
    pi_cam_sensor_mode: Tuple[int, int] = (2304, 1296)
    still_interval_minutes: int = 30

    # API
    api_host: str = "0.0.0.0"
    api_port: int = int(__import__('os').environ.get('PORT', 5001))

    # Agent
    agent_api_key: str = ""
    agent_model: str = "claude-haiku-4-5-20251001"
    agent_min_interval_minutes: int = 15

# Singleton
config = Config()

# ── Push notifications (ntfy.sh) ───────────────────────────────────────────────
NTFY_TOPIC = "hhrcs-4a4a678c"
NTFY_BASE_URL = "https://ntfy.sh"
NOTIFIER_INTERVAL_SECONDS = 300
NOTIFIER_DEDUP_HOURS = 6

# ── Layer 1 push notifications (in-app) ────────────────────────────────────────
NOTIFICATIONS_MAX_STORED = 500
