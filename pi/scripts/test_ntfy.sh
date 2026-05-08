#!/bin/bash
# HHRCS ntfy.sh end-to-end test
# Usage: bash test_ntfy.sh [condition]
#   condition: ssd_critical | ssd_warning | ssd_high | temp_high | cam_unreachable | yolo_down | all (default)
set -e
cd /home/pi/hhrcs
source venv/bin/activate
python3 - "$@" <<'PYEOF'
import sys
import time
import notifier

condition = sys.argv[1] if len(sys.argv) > 1 else 'all'

CONDITIONS = ['ssd_critical', 'ssd_warning', 'ssd_high', 'temp_high', 'temp_warning', 'cam_unreachable', 'yolo_down']


def fake_summary(c):
    base = {
        'cam_reachable': True,
        'yolo_running':  True,
        'cpu_temp_c':    55,
        'storage': {
            'free_gb':        1500,
            'used_pct':       30,
            'days_remaining': 30.0,
        },
    }
    if c == 'ssd_critical':
        base['storage']['days_remaining'] = 1.5
        base['storage']['free_gb']        = 100
    elif c == 'ssd_warning':
        base['storage']['days_remaining'] = 5.0
        base['storage']['free_gb']        = 600
    elif c == 'ssd_high':
        base['storage']['used_pct']       = 95
        base['storage']['free_gb']        = 200
        base['storage']['days_remaining'] = None
    elif c == 'temp_high':
        base['cpu_temp_c'] = 85   # above 80°C production threshold
    elif c == 'temp_warning':
        base['cpu_temp_c'] = 70   # between 65°C warning and 80°C critical thresholds
    elif c == 'cam_unreachable':
        base['cam_reachable'] = False
    elif c == 'yolo_down':
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
