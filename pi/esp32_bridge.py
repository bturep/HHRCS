"""
esp32_bridge.py — persistent serial daemon for ESP32 BLE bridge
Owns /dev/ttyUSB0, exposes HTTP on port 5002.
"""
import re

import serial
import threading
import time
import logging
from flask import Flask, request, jsonify

try:
    from events import emit as _emit, recent as _recent, format_as_log_line as _fmt
except ImportError:
    def _emit(*a, **kw): pass
    def _recent(*a, **kw): return []
    def _fmt(e): return str(e)

SERIAL_PORT = "/dev/ttyUSB0"
BAUD = 115200
HTTP_PORT = 5002

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [bridge] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("bridge")

app = Flask(__name__)

# Shared state — written by serial thread, read by HTTP handlers
state = {
    "ble_state": "Unknown",
    "last_line": "",
    "log": [],          # last 100 lines
}
state_lock = threading.Lock()
serial_port = None
serial_lock = threading.Lock()
_flash_in_progress = False

# Track BLE connection start time for duration_seconds on disconnect
_ble_connect_time: float = 0.0
_ble_device_name: str = ""
_ble_device_addr: str = ""
_ble_reconnect_count: int = 0

_emit("system.startup", {"subsystem": "esp32_bridge"})


def serial_reader():
    """Background thread: opens serial, reads lines, updates state."""
    global serial_port
    buf = b""

    while True:
        try:
            log.info(f"Opening {SERIAL_PORT} at {BAUD} baud")
            ser = serial.Serial(SERIAL_PORT, BAUD, timeout=0.1)
            # Clear DTR and RTS immediately — on this board DTR→GPIO0, RTS→EN.
            # If DTR is left asserted (True), GPIO0 stays LOW and any subsequent
            # reset puts the ESP32 into ROM download mode instead of normal boot.
            ser.dtr = False
            ser.rts = False
            with serial_lock:
                serial_port = ser
            log.info("Serial open (DTR=0, RTS=0)")

            while True:
                chunk = ser.read(256)
                if not chunk:
                    continue
                buf += chunk
                # Drop non-ASCII / ROM-bootloader garbage (74880-baud noise)
                if len(buf) > 4096:
                    buf = buf[-512:]
                while b"\n" in buf:
                    line_bytes, buf = buf.split(b"\n", 1)
                    try:
                        line = line_bytes.decode("utf-8", errors="replace").strip()
                    except Exception:
                        continue
                    if not line:
                        continue
                    # Skip lines that are mostly non-printable (ROM bootloader garbage)
                    printable = sum(1 for c in line if 0x20 <= ord(c) < 0x7F)
                    if printable < len(line) * 0.7:
                        continue

                    log.info(f"ESP32: {line}")

                    with state_lock:
                        state["last_line"] = line
                        state["log"].append(line)
                        if len(state["log"]) > 100:
                            state["log"].pop(0)

                        # Track BLE state from our [BLE] state=XXX lines
                        if line.startswith("[BLE] state="):
                            _raw = line[len("[BLE] state="):]
                            _m = re.match(r"[A-Za-z]+", _raw)
                            new_ble_state = _m.group() if _m else _raw
                            old_ble_state = state["ble_state"]
                            state["ble_state"] = new_ble_state
                            _handle_ble_state_change(old_ble_state, new_ble_state, line)

        except serial.SerialException as e:
            log.warning(f"Serial error: {e} — retrying in 3s")
            with serial_lock:
                serial_port = None
            time.sleep(3)
            if _flash_in_progress:
                while _flash_in_progress:
                    time.sleep(0.5)
        except Exception as e:
            log.error(f"Unexpected error in serial thread: {e}")
            _emit("system.error", {"subsystem": "esp32_bridge", "error_type": "serial_exception", "message": str(e)})
            with serial_lock:
                serial_port = None
            time.sleep(3)


def _handle_ble_state_change(old: str, new: str, raw_line: str) -> None:
    """Emit BLE connect/disconnect events on relevant state transitions. Called under state_lock."""
    global _ble_connect_time, _ble_device_name, _ble_device_addr, _ble_reconnect_count

    # Parse device name/address from lines like: [BLE] state=Connected device=BMPCC addr=AA:BB:CC:DD:EE:FF
    dev_m = re.search(r"device=(\S+)", raw_line)
    addr_m = re.search(r"addr=(\S+)", raw_line)
    dev  = dev_m.group(1) if dev_m else _ble_device_name or "unknown"
    addr = addr_m.group(1) if addr_m else _ble_device_addr or ""

    if new == "Connected" and old != "Connected":
        _ble_device_name = dev
        _ble_device_addr = addr
        _ble_connect_time = time.time()
        _emit("ble.connected", {
            "device_name": dev,
            "address": addr,
            "reconnect_count": _ble_reconnect_count,
        })
        _ble_reconnect_count += 1

    elif old == "Connected" and new != "Connected":
        dur = time.time() - _ble_connect_time if _ble_connect_time else 0
        _emit("ble.disconnected", {
            "device_name": _ble_device_name or dev,
            "address": _ble_device_addr or addr,
            "duration_seconds": round(dur, 1),
        })
        _ble_connect_time = 0.0


def send_to_esp32(cmd_str: str) -> bool:
    """Send a raw command string to the ESP32. Returns True on success."""
    with serial_lock:
        ser = serial_port
    if ser is None:
        return False
    try:
        ser.write(cmd_str.encode("utf-8"))
        ser.flush()
        return True
    except Exception as e:
        log.error(f"Write error: {e}")
        return False


def reset_esp32() -> bool:
    """
    Reset the ESP32.

    Hardware wiring on ELEGOO CP2102 board: RTS → EN (reset), DTR → GPIO0 (boot mode).
    - RTS=True  → EN LOW  → chip in reset
    - RTS=False → EN HIGH → chip runs
    - DTR must be False (GPIO0 HIGH) at reset time or chip enters ROM download mode.

    Strategy:
    1. Software reset via (RESET:) if firmware is responsive (fastest, cleanest).
    2. Hardware RTS pulse — DTR explicitly cleared first to avoid download mode.
    """
    with serial_lock:
        ser = serial_port
    if ser is None:
        return False

    with state_lock:
        state["ble_state"] = "Resetting"
        state["log"].append("[BRIDGE] ESP32 reset triggered")
    log.info("ESP32 reset triggered")

    try:
        # Ensure GPIO0 is HIGH (normal boot, not download mode)
        ser.dtr = False

        # 1. Software reset via serial command (works when firmware is up)
        ser.write(b"(RESET:)")
        ser.flush()
        log.info("ESP32 reset: sent (RESET:)")
        time.sleep(3.0)

        # 2. Hardware RTS reset (EN pulse) — covers the case where firmware
        #    wasn't running or didn't respond to the serial command.
        ser.rts = True    # EN LOW — hold reset
        time.sleep(0.1)
        ser.rts = False   # EN HIGH — release, boot normally
        ser.reset_input_buffer()
        log.info("ESP32 reset: RTS pulse sent")
        # Give the ESP32 time to boot and stabilize BLE stack
        time.sleep(5.0)

    except Exception as e:
        log.error(f"Reset error: {e}")
        return False

    return True


# "Resetting" is not a bad state for watchdog — we're waiting for it to come back.
BAD_STATES = frozenset({"Unknown"})
_watchdog_bad_count = 0

def ble_watchdog():
    """Background thread: auto-reset ESP32 if BLE stuck outside connected for 120s."""
    global _watchdog_bad_count
    while True:
        time.sleep(60)
        with state_lock:
            current = state["ble_state"]
        if current in BAD_STATES:
            _watchdog_bad_count += 1
            log.info(f"Watchdog: BLE state '{current}' — bad count {_watchdog_bad_count}/2")
            if _watchdog_bad_count >= 2:
                log.warning(f"Watchdog: BLE state '{current}' for 120s — auto-reset triggered")
                reset_esp32()
                _watchdog_bad_count = 0
                # After reset, give chip 30s to come back before counting again
                time.sleep(30)
        else:
            if _watchdog_bad_count > 0:
                log.info(f"Watchdog: BLE state '{current}' — bad count cleared")
            _watchdog_bad_count = 0

# ── HTTP endpoints ────────────────────────────────────────────────────────────

@app.route("/esp32/state", methods=["GET"])
def get_state():
    with state_lock:
        return jsonify({
            "ble_state": state["ble_state"],
            "last_line": state["last_line"],
            "serial_open": serial_port is not None,
        })


@app.route("/esp32/passkey", methods=["POST"])
def post_passkey():
    data = request.get_json(force=True, silent=True) or {}
    passkey = str(data.get("passkey", "")).strip()
    if not passkey.isdigit() or len(passkey) != 6:
        return jsonify({"error": "passkey must be 6 digits"}), 400
    cmd = f"(PASSKEY:{passkey})"
    ok = send_to_esp32(cmd)
    if ok:
        _emit("command.sent", {"command": "PASSKEY", "target": "esp32"})
    else:
        _emit("command.failed", {"command": "PASSKEY", "target": "esp32", "error": "serial not open"})
    log.info(f"Sent passkey command: {cmd} — ok={ok}")
    return jsonify({"sent": ok, "cmd": cmd})


@app.route("/esp32/send", methods=["POST"])
def post_send():
    data = request.get_json(force=True, silent=True) or {}
    cmd = str(data.get("cmd", "")).strip()
    if not cmd:
        return jsonify({"error": "cmd required"}), 400
    # Wrap in parens if not already
    if not (cmd.startswith("(") and cmd.endswith(")")):
        cmd = f"({cmd})"
    ok = send_to_esp32(cmd)
    cmd_name = cmd.strip("()").split(":")[0]
    if ok:
        _emit("command.sent", {"command": cmd_name, "target": "esp32", "raw": cmd})
    else:
        _emit("command.failed", {"command": cmd_name, "target": "esp32", "error": "serial not open", "raw": cmd})
    log.info(f"Sent cmd: {cmd} — ok={ok}")
    return jsonify({"sent": ok, "cmd": cmd})


@app.route("/esp32/reset", methods=["POST"])
def post_reset():
    ok = reset_esp32()
    return jsonify({"reset": ok})


@app.route("/esp32/log", methods=["GET"])
def get_log():
    with state_lock:
        return jsonify({"lines": list(state["log"])})


@app.route("/esp32/events", methods=["GET"])
def get_events():
    window = int(request.args.get("window", 300))
    types_param = request.args.get("types", "")
    types = [t.strip() for t in types_param.split(",") if t.strip()] or None
    return jsonify(_recent(window_seconds=window, types=types))




@app.route("/esp32/flash", methods=["POST"])
def post_flash():
    """Close serial, flash firmware.bin via esptool, reopen serial. Blocks until done."""
    import subprocess
    global serial_port, _flash_in_progress
    _flash_in_progress = True
    with serial_lock:
        if serial_port and serial_port.is_open:
            serial_port.close()
            serial_port = None
    time.sleep(1)  # let serial_reader notice the close before esptool grabs port
    result = subprocess.run(
        [
            "/home/pi/hhrcs/venv/bin/esptool",
            "--port", SERIAL_PORT,
            "--baud", "460800",
            "write-flash",
            "--flash-mode", "dio",
            "--flash-freq", "40m",
            "--flash-size", "detect",
            "0x1000", "/home/pi/hhrcs/bootloader.bin",
            "0x8000", "/home/pi/hhrcs/partitions.bin",
            "0x10000", "/home/pi/hhrcs/firmware.bin",
        ],
        capture_output=True,
        text=True,
        timeout=120,
    )
    output = result.stdout + result.stderr
    _flash_in_progress = False
    return jsonify({"exit_code": result.returncode, "output": output})
if __name__ == "__main__":
    t = threading.Thread(target=serial_reader, daemon=True)
    t.start()
    w = threading.Thread(target=ble_watchdog, daemon=True)
    w.start()
    time.sleep(1)   # let serial open before accepting requests
    app.run(host="0.0.0.0", port=HTTP_PORT, threaded=True)
