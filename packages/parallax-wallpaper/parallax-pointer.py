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


class NiriIpc:
    """Talk to Niri over NIRI_SOCKET on one persistent connection.

    `call` returns None when Niri is unreachable or lacks the request, so callers
    fall back to integrating raw mouse deltas.
    """

    def __init__(self):
        self.sock = None
        self.buf = b''

    def call(self, request):
        path = os.environ.get('NIRI_SOCKET')
        if not path:
            return None
        try:
            if self.sock is None:
                self.sock = socket.socket(socket.AF_UNIX)
                self.sock.settimeout(0.2)
                self.sock.connect(path)
                self.buf = b''
            self.sock.sendall(json.dumps(request).encode() + b'\n')
            while b'\n' not in self.buf:
                chunk = self.sock.recv(4096)
                if not chunk:
                    raise OSError('closed')
                self.buf += chunk
            line, _, self.buf = self.buf.partition(b'\n')
            return json.loads(line).get('Ok', {}).get(request)
        except (OSError, ValueError):
            if self.sock is not None:
                self.sock.close()
            self.sock = None
            return None

    def workspaces(self):
        """Per output: active workspace index, workspace count and column strip.

        Niri does not report its scroll offset, so `before` (summed width of the
        columns left of the focused one) and `strip` (all columns) let the wallpaper
        approximate the horizontal camera.
        """
        windows = self.call('Windows') or []
        columns = {}
        focused = {}
        for win in windows:
            pos = (win.get('layout') or {}).get('pos_in_scrolling_layout')
            if pos and win.get('workspace_id') is not None:
                cols = columns.setdefault(win['workspace_id'], {})
                cols[pos[0]] = max(cols.get(pos[0], 0), win['layout']['window_size'][0])
                focused[win['id']] = pos[0]
        result = {}
        for ws in self.call('Workspaces') or []:
            entry = result.setdefault(
                ws['output'], {'active': 1, 'count': 0, 'before': 0, 'strip': 0})
            entry['count'] = max(entry['count'], ws['idx'])
            cols = columns.get(ws['id'], {})
            entry['strip'] = max(entry['strip'], sum(cols.values()))
            if ws['is_active']:
                entry['active'] = ws['idx']
                column = focused.get(ws.get('active_window_id'), 1)
                entry['before'] = sum(w for c, w in cols.items() if c < column)
                entry['own_strip'] = sum(cols.values())
        return result


def main():
    devices = {}
    x = y = 0.0
    raw_x = raw_y = 0
    niri = NiriIpc()
    real = None
    spaces = {}
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
            position = niri.call('PointerPosition')
            workspaces = niri.workspaces()
            next_query = now + (1 / 30 if niri.sock else 2)
            if position != real or workspaces != spaces:
                real, spaces = position, workspaces
                dirty = True
        if dirty and now - last_sent >= 1 / 60:
            message = {'x': x, 'y': y, 'rx': raw_x, 'ry': raw_y}
            if real:
                message.update(out=real['output'], px=real['x'], py=real['y'])
            if spaces:
                message['ws'] = spaces
            print(json.dumps(message), flush=True)
            dirty = False
            last_sent = now


if __name__ == '__main__':
    main()
