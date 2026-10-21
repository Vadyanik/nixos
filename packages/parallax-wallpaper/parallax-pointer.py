"""Publish a bounded virtual pointer position from relative mouse motion.

Wayland does not expose the global cursor to background clients, so REL_X and
REL_Y events are integrated into a position clamped to [-1, 1]. Keyboard and
button events are never read, and devices are not grabbed.
"""
import json
import os
import select
import socket
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


class NiriPointer:
    """Ask the patched Niri for the real cursor position (`niri msg pointer-position`).

    Returns None when Niri is unreachable or lacks the request, so callers fall back
    to integrating raw mouse deltas.
    """

    def __init__(self):
        self.sock = None
        self.buf = b''

    def query(self):
        path = os.environ.get('NIRI_SOCKET')
        if not path:
            return None
        try:
            if self.sock is None:
                self.sock = socket.socket(socket.AF_UNIX)
                self.sock.settimeout(0.2)
                self.sock.connect(path)
                self.buf = b''
            self.sock.sendall(b'"PointerPosition"\n')
            while b'\n' not in self.buf:
                chunk = self.sock.recv(4096)
                if not chunk:
                    raise OSError('closed')
                self.buf += chunk
            line, _, self.buf = self.buf.partition(b'\n')
            reply = json.loads(line)
            position = reply.get('Ok', {}).get('PointerPosition')
            return position
        except (OSError, ValueError):
            if self.sock is not None:
                self.sock.close()
            self.sock = None
            return None


def main():
    devices = {}
    x = y = 0.0
    raw_x = raw_y = 0
    niri = NiriPointer()
    real = None
    next_query = 0.0
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
            raw_x += dx
            raw_y += dy
            x = max(-1.0, min(1.0, x + dx / 1400))
            y = max(-1.0, min(1.0, y + dy / 900))
            dirty = True
        now = time.monotonic()
        if now >= next_query:
            position = niri.query()
            next_query = now + (1 / 30 if position or niri.sock else 2)
            if position != real:
                real = position
                dirty = True
        if dirty and now - last_sent >= 1 / 60:
            message = {'x': x, 'y': y, 'rx': raw_x, 'ry': raw_y}
            if real:
                message.update(out=real['output'], px=real['x'], py=real['y'])
            print(json.dumps(message), flush=True)
            dirty = False
            last_sent = now


if __name__ == '__main__':
    main()
