"""
Real hardware sensor layer.
Reads lux from TSL2591 or BH1750 (I2C) and temp/humidity/pressure from BMP280/BME280.
Falls back to simulated values if hardware is not connected.
"""

import math
import time
import random
import logging
from typing import Optional

log = logging.getLogger(__name__)

# ── I2C hardware init ──────────────────────────────────────────────────────────

_tsl = None       # TSL2591 lux sensor
_bh1750 = None    # BH1750 lux sensor (alternative)
_bmp = None       # BMP280 / BME280 env sensor
_hardware_lux = False
_hardware_env = False

try:
    import board
    import busio
    _i2c = busio.I2C(board.SCL, board.SDA)

    try:
        import adafruit_tsl2591
        _tsl = adafruit_tsl2591.TSL2591(_i2c)
        _tsl.gain = adafruit_tsl2591.GAIN_LOW
        _hardware_lux = True
        log.info("TSL2591 lux sensor initialised")
    except Exception as e:
        log.debug(f"TSL2591 not found: {e}")

    if not _hardware_lux:
        try:
            import adafruit_bh1750
            _bh1750 = adafruit_bh1750.BH1750(_i2c)
            _hardware_lux = True
            log.info("BH1750 lux sensor initialised")
        except Exception as e:
            log.debug(f"BH1750 not found: {e}")

    try:
        import adafruit_bmp280
        _bmp = adafruit_bmp280.Adafruit_BMP280_I2C(_i2c)
        _hardware_env = True
        log.info("BMP280 env sensor initialised")
    except Exception:
        try:
            import adafruit_bme280.basic as adafruit_bme280
            _bmp = adafruit_bme280.Adafruit_BME280_I2C(_i2c)
            _hardware_env = True
            log.info("BME280 env sensor initialised")
        except Exception as e:
            log.debug(f"BMP/BME280 not found: {e}")

except Exception as e:
    log.warning(f"I2C bus not available, using simulated sensors: {e}")

if not _hardware_lux:
    log.warning("No lux sensor found — simulating light values")
if not _hardware_env:
    log.warning("No env sensor found — simulating temperature/humidity/pressure")

# ── Mutable state ──────────────────────────────────────────────────────────────

_recording = False
_nd_filter = "ND4"
_iso = 3200
_ssd_free_gb = 1800.0
_house_drive_used_gb = 400.0

# ── Lux ───────────────────────────────────────────────────────────────────────

def read_lux() -> float:
    if _hardware_lux:
        try:
            if _tsl:
                lux = _tsl.lux
                return float(lux) if lux is not None else 0.1
            if _bh1750:
                return float(_bh1750.lux)
        except Exception as e:
            log.debug(f"Lux read error: {e}")
    # Diurnal simulation
    t = time.localtime()
    hour = t.tm_hour + t.tm_min / 60.0
    if hour < 4 or hour > 22:
        return round(random.uniform(0.05, 0.5), 2)
    peak = 13.0
    base = 45000 * math.exp(-0.5 * ((hour - peak) / 5.5) ** 2)
    return round(max(0.1, base + random.uniform(-base * 0.04, base * 0.04)), 2)

def read_ev() -> float:
    lux = read_lux()
    return round(math.log2(max(lux, 0.01) / 2.5), 2)

# ── Environment ───────────────────────────────────────────────────────────────

def read_temperature() -> float:
    if _hardware_env and _bmp:
        try:
            return round(float(_bmp.temperature), 1)
        except Exception as e:
            log.debug(f"Temp read error: {e}")
    return round(12.0 + random.uniform(-0.3, 0.3), 1)

def read_humidity() -> float:
    if _hardware_env and _bmp:
        try:
            if hasattr(_bmp, "humidity"):   # BME280 has humidity; BMP280 does not
                return round(float(_bmp.humidity), 1)
        except Exception as e:
            log.debug(f"Humidity read error: {e}")
    return round(72.0 + random.uniform(-1.5, 1.5), 1)

def read_pressure() -> float:
    if _hardware_env and _bmp:
        try:
            return round(float(_bmp.pressure), 1)
        except Exception as e:
            log.debug(f"Pressure read error: {e}")
    return round(1013.0 + random.uniform(-0.5, 0.5), 1)

def read_dew_point() -> float:
    t = read_temperature()
    h = read_humidity()
    a, b = 17.27, 237.7
    alpha = (a * t / (b + t)) + math.log(max(h, 1) / 100.0)
    return round((b * alpha) / (a - alpha), 1)

def read_cpu_temp() -> float:
    try:
        with open("/sys/class/thermal/thermal_zone0/temp") as f:
            return round(int(f.read().strip()) / 1000.0, 1)
    except Exception:
        return round(45.0 + (8.0 if _recording else 0.0) + random.uniform(-0.5, 0.5), 1)

# ── Recording state ────────────────────────────────────────────────────────────

def start_recording():
    global _recording
    _recording = True

def stop_recording():
    global _recording
    _recording = False

def set_nd(nd: str):
    global _nd_filter
    _nd_filter = nd

def set_iso(iso: int):
    global _iso
    _iso = iso

# ── Storage ───────────────────────────────────────────────────────────────────

def read_ssd_free_gb() -> float:
    global _ssd_free_gb
    try:
        import shutil
        from config import config
        usage = shutil.disk_usage(config.ssd_mount)
        return round(usage.free / 1e9, 1)
    except Exception:
        if _recording:
            _ssd_free_gb = max(0.0, _ssd_free_gb - 65.0 * 2 / 1024)
        return round(_ssd_free_gb, 1)

def read_house_drive_used_tb() -> float:
    try:
        import shutil
        from config import config
        usage = shutil.disk_usage(config.house_drive_mount)
        return round(usage.used / 1e12, 3)
    except Exception:
        return round(_house_drive_used_gb / 1000, 3)

# ── Timecode ──────────────────────────────────────────────────────────────────

def get_timecode() -> str:
    total_frames = int(time.time() * 24) % (24 * 3600 * 24)
    h = total_frames // (24 * 3600)
    rem = total_frames % (24 * 3600)
    m = rem // (24 * 60)
    rem = rem % (24 * 60)
    s = rem // 24
    f = rem % 24
    return f"{h:02d}:{m:02d}:{s:02d}:{f:02d}"

# ── Aggregates ────────────────────────────────────────────────────────────────

def to_dict() -> dict:
    return {
        "lux": read_lux(),
        "ev": read_ev(),
        "temperature_c": read_temperature(),
        "humidity_pct": read_humidity(),
        "pressure_hpa": read_pressure(),
        "dew_point_c": read_dew_point(),
        "cpu_temp_c": read_cpu_temp(),
        "hardware_lux": _hardware_lux,
        "hardware_env": _hardware_env,
    }

def get_camera_state() -> dict:
    return {
        "recording": _recording,
        "nd_filter": _nd_filter,
        "iso": _iso,
        "ssd_free_gb": read_ssd_free_gb(),
        "timecode": get_timecode(),
        "shutter_angle": 180,
        "fps": 24,
    }
