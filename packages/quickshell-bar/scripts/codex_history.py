#!/usr/bin/env python3
"""Append the existing CSV format; archive large chunks losslessly."""
import csv
import fcntl
from datetime import datetime
import gzip
import io
import json
import os
from pathlib import Path
import sys
import time

FIELDS = ['saved_at', 'five_hour_remaining_percent', 'five_hour_reset_in',
          'weekly_remaining_percent', 'weekly_reset_in']
MAX_BYTES = 1024 * 1024


def values(data):
    return sorted((limit['windowDurationMins'], limit['usedPercent'], limit['resetsAt'])
                  for key in ('primary', 'secondary') if isinstance(limit := data.get(key), dict)
                  and limit.get('windowDurationMins') in (300, 10080))


def same_limits(data, previous):
    current, old = values(data), values(previous)
    return len(current) == len(old) and all(
        a[:2] == b[:2] and abs(a[2] - b[2]) <= 90 for a, b in zip(current, old))


def append(path, data, previous, now):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.with_suffix('.csv.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return append_locked(path, data, previous, now)


def append_locked(path, data, previous, now):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and now - path.stat().st_mtime < 60 and same_limits(data, previous):
        return False
    row = dict.fromkeys(FIELDS, '?')
    row['saved_at'] = datetime.fromtimestamp(now).astimezone().isoformat(timespec='seconds')
    for duration, used, reset in values(data):
        prefix = 'five_hour' if duration == 300 else 'weekly'
        seconds = max(0, int(reset - now))
        remaining = 100 - used
        row[prefix + '_remaining_percent'] = f'{remaining:g}'
        row[prefix + '_reset_in'] = ((f'{seconds // 86400}d ' if duration == 10080 else '')
                                    + f'{seconds // 3600 % (24 if duration == 10080 else 1000):02}h {seconds % 3600 // 60:02}m')
    output = io.StringIO(newline='')
    writer = csv.DictWriter(output, fieldnames=FIELDS, lineterminator='\n')
    if not path.exists() or path.stat().st_size == 0:
        writer.writeheader()
    writer.writerow(row)
    with path.open('a', newline='') as destination:
        destination.write(output.getvalue())
        destination.flush()
        os.fsync(destination.fileno())
    if path.stat().st_size >= MAX_BYTES:
        archive(path)
    return True


def archive(path):
    # Publish and verify the complete archive before replacing the active CSV.
    raw = path.read_bytes()
    compressed = gzip.compress(raw, compresslevel=9, mtime=0)
    if gzip.decompress(compressed) != raw:
        raise RuntimeError('History archive verification failed')
    target = path.with_name(f'{path.stem}.{time.time_ns()}.csv.gz')
    temporary = target.with_suffix('.tmp')
    with temporary.open('wb') as out:
        out.write(compressed)
        out.flush()
        os.fsync(out.fileno())
    os.replace(temporary, target)
    directory = os.open(path.parent, os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)
    if gzip.decompress(target.read_bytes()) != raw:
        raise RuntimeError('Saved history archive verification failed')
    header = path.with_suffix('.csv.tmp')
    with header.open('w', newline='') as out:
        csv.writer(out, lineterminator='\n').writerow(FIELDS)
        out.flush()
        os.fsync(out.fileno())
    os.replace(header, path)
    directory = os.open(path.parent, os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


if __name__ == '__main__':
    append(sys.argv[1], json.loads(sys.argv[2]), json.loads(sys.argv[3]), float(sys.argv[4]))
