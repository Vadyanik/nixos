#!/usr/bin/env python3
"""Read Pace from the existing Waybar CSV, without writing any history."""
import csv
import fcntl
import gzip
from pathlib import Path
from datetime import datetime
import json
import math
import re
import sys


WINDOWS = {"five": (300, 3600, "five_hour"), "weekly": (10080, 86400, "weekly")}


def history(path, earliest=None):
    path = Path(path)
    try:
        with path.with_suffix('.csv.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_SH)
            return read_history(path, earliest)
    except OSError:
        return []


def read_history(path, earliest=None):
    rows = []
    path = Path(path)
    sources = sorted(path.parent.glob(f'{path.stem}.*.csv.gz')) + [path]
    for source in sources:
        # Archives older than the largest Pace horizon need not be rescanned.
        if earliest is not None and source != path and source.stat().st_mtime < earliest:
            continue
        try:
            opener = gzip.open if source.suffix == '.gz' else open
            with opener(source, 'rt', newline='') as stream:
                for row in csv.DictReader(stream):
                    try:
                        timestamp = datetime.fromisoformat(row['saved_at']).timestamp()
                    except (KeyError, ValueError, TypeError):
                        continue
                    if earliest is None or timestamp >= earliest:
                        rows.append((timestamp, row))
        except (OSError, csv.Error, UnicodeError, EOFError):
            continue
    return sorted(rows, key=lambda item: item[0])


def sample(timestamp, row, prefix):
    try:
        remaining = float(row[prefix + "_remaining_percent"])
        countdown = re.fullmatch(r"(?:(\d+)d )?(\d+)h (\d+)m", row[prefix + "_reset_in"])
        if not countdown or not math.isfinite(remaining) or not 0 <= remaining <= 100:
            return None
        days, hours, minutes = (int(value or 0) for value in countdown.groups())
        reset = timestamp + days * 86400 + hours * 3600 + minutes * 60
        return timestamp, remaining, reset
    except (KeyError, ValueError, TypeError):
        return None


def calculate(rows, limit, now, period, prefix):
    try:
        remaining = 100 - float(limit["usedPercent"])
        reset = float(limit["resetsAt"])
    except (KeyError, ValueError, TypeError):
        return "N/A"
    if not all(map(math.isfinite, (remaining, reset, now))):
        return "N/A"
    # Avoid exhausted limits and the minute immediately around reset.
    if not 0 < remaining <= 100 or reset - now <= 60:
        return "N/A"
    target = now - period
    # Sparse history is sufficient if the endpoints belong to the same reset.
    # Keep a substantial horizon: never fall back to the last few measurements.
    candidates = []
    for timestamp, row in rows:
        if not period / 2 <= now - timestamp <= period * 2:
            continue
        point = sample(timestamp, row, prefix)
        if point is not None and abs(point[2] - reset) <= 90:
            candidates.append((timestamp, row))
    if not candidates:
        return "N/A"
    anchor_time, anchor_row = min(candidates, key=lambda item: (abs(item[0] - target), item[0]))
    anchor = sample(anchor_time, anchor_row, prefix)
    if anchor is None:
        return "N/A"
    previous = anchor
    for timestamp, row in rows:
        if not anchor_time <= timestamp <= now:
            continue
        point = sample(timestamp, row, prefix)
        # CSV countdowns are rounded down to minutes; allow 90s of uncertainty.
        if point is None:
            continue
        if abs(point[2] - reset) > 90 or point[1] > previous[1]:
            return "N/A"
        previous = point
    # A stale/mismatched snapshot cannot provide a meaningful current Burn.
    if now - previous[0] > 300 or previous[1] != remaining:
        return "N/A"
    elapsed = now - anchor_time
    burn = (anchor[1] - remaining) / elapsed
    need = remaining / (reset - now)
    pace = burn / need
    if not math.isfinite(pace) or pace < 0:
        return "N/A"
    result = f"{pace:.2f}x"
    if abs(elapsed - period) > period * 0.10:
        result += f" (actual: {elapsed / 3600:.1f}h)"
    return result


def pace(path, limits, now):
    rows = history(path, earliest=now - 172800)
    result = {}
    for name, (duration, period, prefix) in WINDOWS.items():
        limit = next((limits.get(key) for key in ("primary", "secondary")
                      if isinstance(limits.get(key), dict)
                      and limits[key].get("windowDurationMins") == duration), None)
        result[name] = calculate(rows, limit, now, period, prefix)
    return result


if __name__ == "__main__":
    try:
        result = pace(sys.argv[1], json.loads(sys.argv[2]), float(sys.argv[3]))
    except (ValueError, TypeError, IndexError):
        result = {"five": "N/A", "weekly": "N/A"}
    print(json.dumps(result))
