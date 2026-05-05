import time
import threading
from enum import Enum
from typing import Optional, Callable
from config import config

try:
    from events import emit as _emit
except ImportError:
    def _emit(*a, **kw): pass


class RecordState(Enum):
    IDLE = "IDLE"
    ACTIVE = "ACTIVE"
    HOLDING = "HOLDING"
    COUNTDOWN = "COUNTDOWN"

class TriggerType(Enum):
    NONE = "NONE"
    MANUAL = "MANUAL"
    SCHEDULED = "SCHEDULED"
    DEER = "DEER"
    RABBIT = "RABBIT"
    BIRD = "BIRD"

class StateMachine:
    def __init__(self):
        self.state = RecordState.IDLE
        self.trigger_type = TriggerType.NONE
        self.last_class: Optional[str] = None
        self.last_detection_time: Optional[float] = None
        self.recording_start_time: Optional[float] = None
        self.countdown_start_time: Optional[float] = None
        self.window_open: bool = False

        self.manual_override: bool = False

        self._lock = threading.Lock()
        self._timer: Optional[threading.Timer] = None

        # Callbacks
        self.on_record_start: Optional[Callable] = None
        self.on_record_stop: Optional[Callable] = None
        self.on_countdown_start: Optional[Callable] = None
        self.on_state_change: Optional[Callable] = None

    def open_window(self, trigger: TriggerType = TriggerType.SCHEDULED):
        with self._lock:
            if self.manual_override:
                return
            self.window_open = True
            if self.state == RecordState.IDLE:
                self._start_recording(trigger)

    def close_window(self):
        with self._lock:
            self.window_open = False
            if self.state in (RecordState.ACTIVE, RecordState.HOLDING):
                self._begin_countdown()

    def detection_event(self, class_name: str):
        with self._lock:
            if self.manual_override:
                return
            self.last_class = class_name
            self.last_detection_time = time.time()
            trigger = TriggerType[class_name.upper()] if class_name.upper() in TriggerType.__members__ else TriggerType.NONE

            if self.state == RecordState.IDLE and self.window_open:
                self._start_recording(trigger)
            elif self.state == RecordState.IDLE and not self.window_open:
                self._start_recording(trigger)
            elif self.state == RecordState.HOLDING:
                prev = self.state
                self.state = RecordState.ACTIVE
                self.trigger_type = trigger
                self._cancel_timer()
                _emit("state.transition", {"from_state": prev.value, "to_state": self.state.value, "reason": f"detection resumed ({class_name})"})
                self._notify_state_change()
            elif self.state == RecordState.COUNTDOWN:
                prev = self.state
                self.state = RecordState.ACTIVE
                self.trigger_type = trigger
                self._cancel_timer()
                _emit("state.transition", {"from_state": prev.value, "to_state": self.state.value, "reason": f"detection during countdown ({class_name})"})
                self._notify_state_change()

    def no_detection(self):
        with self._lock:
            if self.state == RecordState.ACTIVE:
                prev = self.state
                self.state = RecordState.HOLDING
                _emit("state.transition", {"from_state": prev.value, "to_state": self.state.value, "reason": "no detection"})
                self._start_grace_timer()
                self._notify_state_change()

    def _start_recording(self, trigger: TriggerType):
        prev = self.state
        self.state = RecordState.ACTIVE
        self.trigger_type = trigger
        self.recording_start_time = time.time()
        _emit("state.transition", {"from_state": prev.value, "to_state": self.state.value, "reason": f"recording started ({trigger.value})"})
        self._notify_state_change()
        if self.on_record_start:
            self.on_record_start(trigger)

    def _begin_countdown(self):
        prev = self.state
        self.state = RecordState.COUNTDOWN
        self.countdown_start_time = time.time()
        _emit("state.transition", {"from_state": prev.value, "to_state": self.state.value, "reason": "countdown started"})
        self._notify_state_change()
        if self.on_countdown_start:
            self.on_countdown_start()
        self._start_countdown_timer()

    def _start_grace_timer(self):
        self._cancel_timer()
        self._timer = threading.Timer(config.grace_period_seconds, self._grace_expired)
        self._timer.daemon = True
        self._timer.start()

    def _start_countdown_timer(self):
        self._cancel_timer()
        self._timer = threading.Timer(config.countdown_seconds, self._countdown_expired)
        self._timer.daemon = True
        self._timer.start()

    def _grace_expired(self):
        with self._lock:
            if self.state == RecordState.HOLDING:
                self._begin_countdown()

    def _countdown_expired(self):
        with self._lock:
            if self.state == RecordState.COUNTDOWN:
                prev = self.state
                self.state = RecordState.IDLE
                elapsed = time.time() - self.recording_start_time if self.recording_start_time else 0
                self.recording_start_time = None
                self.countdown_start_time = None
                _emit("state.transition", {"from_state": prev.value, "to_state": self.state.value, "reason": "countdown expired"})
                self._notify_state_change()
                if self.on_record_stop:
                    self.on_record_stop(elapsed)

    def _cancel_timer(self):
        if self._timer:
            self._timer.cancel()
            self._timer = None

    def _notify_state_change(self):
        if self.on_state_change:
            self.on_state_change(self.state)

    def force_start(self):
        with self._lock:
            self.manual_override = False
            self._start_recording(TriggerType.MANUAL)

    def force_idle(self):
        with self._lock:
            self._cancel_timer()
            prev = self.state
            self.state = RecordState.IDLE
            self.trigger_type = TriggerType.NONE
            self.recording_start_time = None
            self.countdown_start_time = None
            self.manual_override = True
            _emit("state.transition", {"from_state": prev.value, "to_state": self.state.value, "reason": "manual override stop"})
            self._notify_state_change()

    def force_stop(self):
        with self._lock:
            self._cancel_timer()
            prev = self.state
            elapsed = time.time() - self.recording_start_time if self.recording_start_time else 0
            self.state = RecordState.IDLE
            self.recording_start_time = None
            _emit("state.transition", {"from_state": prev.value, "to_state": self.state.value, "reason": "force stop"})
            self._notify_state_change()
            if self.on_record_stop:
                self.on_record_stop(elapsed)

    def extend(self, seconds: int):
        with self._lock:
            if self.state in (RecordState.COUNTDOWN, RecordState.HOLDING):
                self._cancel_timer()
                prev = self.state
                self.state = RecordState.ACTIVE
                _emit("state.transition", {"from_state": prev.value, "to_state": self.state.value, "reason": "manual extend"})
                self._notify_state_change()

    @property
    def elapsed_seconds(self) -> float:
        if self.recording_start_time:
            return time.time() - self.recording_start_time
        return 0.0

    @property
    def countdown_remaining(self) -> int:
        if self.state == RecordState.COUNTDOWN and self.countdown_start_time:
            remaining = config.countdown_seconds - (time.time() - self.countdown_start_time)
            return max(0, int(remaining))
        return 0

    def to_dict(self) -> dict:
        elapsed = self.elapsed_seconds
        return {
            "state": self.state.value,
            "trigger_type": self.trigger_type.value,
            "last_class": self.last_class,
            "last_detection_time": self.last_detection_time,
            "recording_start_time": self.recording_start_time,
            "elapsed_seconds": elapsed,
            "elapsed_formatted": self._format_elapsed(elapsed),
            "countdown_remaining": self.countdown_remaining,
            "window_open": self.window_open,
            "manual_override": self.manual_override,
        }

    @staticmethod
    def _format_elapsed(seconds: float) -> str:
        s = int(seconds)
        h, rem = divmod(s, 3600)
        m, sec = divmod(rem, 60)
        return f"{h:02d}:{m:02d}:{sec:02d}"
