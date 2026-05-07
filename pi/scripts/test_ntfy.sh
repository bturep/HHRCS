#!/bin/bash
# HHRCS ntfy.sh end-to-end test
# Usage: bash test_ntfy.sh [condition]
#   condition: ssd_critical | ssd_warning | temp_high | cam_unreachable | ble_down | all (default)
#   ble_down is an alias for yolo_down (BLE removed; maps to YOLO-down condition)
set -e
cd /home/pi/hhrcs
source venv/bin/activate
python3 - "$@" <<'PYEOF'
import sys
import time
import notifier

condition = sys.argv[1] if len(sys.argv) > 1 else 'all'

CONDITIONS = ['ssd_critical', 'ssd_warning', 'temp_high', 'cam_unreachable', 'ble_down']


def fake_summary(c):
    base = {
        'cam_reachable': True,
        'yolo_running':  True,
        'cpu_temp_c':    55,
        'storage': {'days_remaining': 8, 'free_gb': 120, 'used_pct': 30},
    }
    if c == 'ssd_critical':
        base['storage'] = {'days_remaining': 0.5, 'free_gb': 5, 'used_pct': 99}
    elif c == 'ssd_warning':
        # falls back to used_pct path (>= 90) when days_remaining is None
        base['storage'] = {'days_remaining': None, 'free_gb': 40, 'used_pct': 92}
    elif c == 'temp_high':
        base['cpu_temp_c'] = 85
    elif c == 'cam_unreachable':
        base['cam_reachable'] = False
    elif c == 'ble_down':
        # BLE removed; mapped to YOLO-down (same alert path)
        base['yolo_running'] = False
    return base


if condition == 'all':
    for c in CONDITIONS:
        print(f'>> testing: {c}')
        notifier._last_sent.clear()
        notifier.evaluate_and_notify(fake_summary(c))
        time.sleep(2)
elif condition in CONDITIONS:
    print(f'>> testing: {condition}')
    notifier._last_sent.clear()
    notifier.evaluate_and_notify(fake_summary(condition))
else:
    print(f'Unknown condition: {condition}')
    print(f'Valid: {", ".join(CONDITIONS)}, all')
    sys.exit(1)

print('done.')
PYEOF
