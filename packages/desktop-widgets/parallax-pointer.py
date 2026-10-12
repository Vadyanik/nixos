"""Read pointer motion without grabbing devices; publish output wallpaper state.

Wayland does not expose a global cursor position to background clients. Integrate
relative mouse motion into a bounded virtual position instead. Only REL_X/REL_Y
are consumed; keyboard input is never read and button events are ignored.
"""
import json
import re
import select
import subprocess
import time

from evdev import InputDevice, ecodes, list_devices


def main():
    devices = {}
    x = y = 0.0
    screens = {}
    next_scan = next_wallpaper = 0
    last_sent = 0
    dirty = True
    while True:
        now = time.monotonic()
        if now >= next_scan:
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
            next_scan = now + 5
        if now >= next_wallpaper:
            try:
                query = subprocess.check_output(['awww', 'query'], text=True,
                                                timeout=2, stderr=subprocess.DEVNULL)
                updated = {}
                for line in query.splitlines():
                    match = re.search(r'(?:^|: )([^:]+): (\d+)x(\d+), scale: [\d.]+, '
                                      r'currently displaying: image: (.+)$', line)
                    if match:
                        name, width, height, image = match.groups()
                        updated[name.strip()] = {'width': int(width), 'height': int(height),
                                                 'image': image}
                if updated != screens:
                    screens = updated
                    dirty = True
            except (OSError, subprocess.SubprocessError):
                pass
            next_wallpaper = time.monotonic() + 0.75
        ready, _, _ = select.select(list(devices.values()), [], [], 0.016)
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
            # A full ordinary mouse sweep traverses the effect. Clamping also
            # keeps reversing direction immediately responsive at screen edges.
            x = max(-1.0, min(1.0, x + dx / 1400))
            y = max(-1.0, min(1.0, y + dy / 900))
            dirty = True
        now = time.monotonic()
        if dirty and now - last_sent >= 1 / 60:
            print(json.dumps({'x': x, 'y': y, 'screens': screens,
                              'devices': len(devices)}), flush=True)
            dirty = False
            last_sent = now


if __name__ == '__main__':
    main()
