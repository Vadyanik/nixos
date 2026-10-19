"""Publish a bounded virtual pointer position from relative mouse motion.

Wayland does not expose the global cursor to background clients, so REL_X and
REL_Y events are integrated into a position clamped to [-1, 1]. Keyboard and
button events are never read, and devices are not grabbed.
"""
import json
import select
import time

from evdev import InputDevice, ecodes, list_devices


def scan(devices):
    for path in list_devices():
        if path in devices:
            continue
        device = None
        try:
            device = InputDevice(path)
            rel = device.capabilities().get(ecodes.EV_REL, [])
            if ecodes.REL_X in rel and ecodes.REL_Y in rel:
                devices[path] = device
            else:
                device.close()
        except OSError:
            if device is not None:
                device.close()


def main():
    devices = {}
    x = y = 0.0
    next_scan = last_sent = 0.0
    dirty = True
    while True:
        now = time.monotonic()
        if now >= next_scan:
            scan(devices)
            next_scan = now + 5
        if devices:
            ready, _, _ = select.select(list(devices.values()), [], [], 0.016)
        else:
            time.sleep(0.25)
            ready = []
        dx = dy = 0
        for device in ready:
            try:
                for event in device.read():
                    if event.type == ecodes.EV_REL:
                        if event.code == ecodes.REL_X:
                            dx += event.value
                        elif event.code == ecodes.REL_Y:
                            dy += event.value
            except BlockingIOError:
                pass
            except OSError:
                devices.pop(device.path, None)
                device.close()
        if dx or dy:
            x = max(-1.0, min(1.0, x + dx / 1400))
            y = max(-1.0, min(1.0, y + dy / 900))
            dirty = True
        now = time.monotonic()
        if dirty and now - last_sent >= 1 / 60:
            print(json.dumps({'x': x, 'y': y}), flush=True)
            dirty = False
            last_sent = now


if __name__ == '__main__':
    main()
