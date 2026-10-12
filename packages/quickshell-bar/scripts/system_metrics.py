#!/usr/bin/env python3
"""One on-demand Linux metrics sample; counters persist only in the runtime dir."""
import glob
import json
import os
from pathlib import Path
import subprocess
import time


def counters():
    cpu = list(map(int, Path('/proc/stat').read_text().splitlines()[0].split()[1:]))
    # guest time is already included in user/nice.
    network = {}
    for line in Path('/proc/net/dev').read_text().splitlines()[2:]:
        name, values = line.split(':')
        if name.strip() != 'lo':
            values = list(map(int, values.split()))
            network[name.strip()] = [values[0], values[8]]
    return {'time': time.monotonic(), 'total': sum(cpu[:8]), 'idle': sum(cpu[3:5]), 'network': network}


def sample(previous, current):
    total = current['total'] - previous.get('total', current['total'])
    elapsed = current['time'] - previous.get('time', current['time'])
    valid = 0 < elapsed < 15
    cpu = round(100 * (1 - (current['idle'] - previous['idle']) / total), 1) if valid and total > 0 else None
    rates = [0, 0]
    if valid:
        for name, values in current['network'].items():
            if name in previous.get('network', {}):
                for i in (0, 1):
                    rates[i] += max(0, values[i] - previous['network'][name][i]) / elapsed
    return cpu, rates if valid else [None, None]


def main():
    state = Path(os.environ.get('XDG_RUNTIME_DIR', '/tmp')) / ('quickshell-metrics-' + str(os.getuid()) + '.json')
    current = counters()
    try:
        previous = json.loads(state.read_text())
    except (OSError, ValueError):
        previous = {}
    cpu, rates = sample(previous, current)
    temporary = state.with_suffix('.tmp')
    temporary.write_text(json.dumps(current))
    temporary.replace(state)
    memory = {line.split(':')[0]: int(line.split()[1]) for line in Path('/proc/meminfo').read_text().splitlines() if len(line.split()) >= 2 and line.split()[1].isdigit()}
    gpu = None
    try:
        busy = glob.glob('/sys/class/drm/card*/device/gpu_busy_percent')
        if busy:
            gpu = int(Path(busy[0]).read_text())
        else:
            output = subprocess.check_output(['nvidia-smi', '--query-gpu=utilization.gpu', '--format=csv,noheader,nounits'], text=True, timeout=1.5, stderr=subprocess.DEVNULL)
            gpu = int(output.splitlines()[0])
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    print(json.dumps({'cpu': cpu, 'gpu': gpu, 'ramUsed': round((memory['MemTotal'] - memory['MemAvailable']) / 1048576, 1), 'ramTotal': round(memory['MemTotal'] / 1048576, 1), 'rx': rates[0], 'tx': rates[1]}))


if __name__ == '__main__':
    main()
