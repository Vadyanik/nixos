#!/usr/bin/env python3
"""Private PolterType 0.36.4 compatibility transport for Niri.

PolterType already supports synchronous Hyprland socket calls. Translate only
its small request surface to Niri IPC; do not install a global hyprctl shim.
"""
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import threading


def request(message):
    with socket.socket(socket.AF_UNIX) as conn:
        conn.settimeout(0.3)
        conn.connect(os.environ['NIRI_SOCKET'])
        conn.sendall((json.dumps(message) + '\n').encode())
        response = json.loads(conn.makefile('rb').readline())
        if 'Err' in response:
            raise RuntimeError(response['Err'])
        return response['Ok']


def reply(command):
    command = command.removeprefix('j/').strip()
    if command == 'devices':
        layouts = request('KeyboardLayouts')['KeyboardLayouts']
        active = layouts['names'][layouts['current_idx']]
        return f'Keyboard at 0:\n  niri-keyboard\n  active keymap: {active}\n  main: yes\n'
    if command == 'getoption input:kb_layout':
        layouts = request('KeyboardLayouts')['KeyboardLayouts']['names']
        codes = {'English (US)': 'us', 'Ukrainian': 'ua', 'Russian': 'ru'}
        return 'str: ' + ','.join(codes[name] for name in layouts) + '\n'
    if command.startswith('switchxkblayout '):
        index = int(command.split()[-1])
        request({'Action': {'SwitchLayout': {'layout': {'Index': index}}}})
        return 'ok\n'
    if command == 'activewindow':
        window = request('FocusedWindow')['FocusedWindow']
        if not window:
            return 'Invalid\n'
        return f"pid: {window['pid'] or 0}\nclass: {window['app_id'] or ''}\n"
    return 'unknown request\n'


def serve(server):
    while True:
        try:
            conn, _ = server.accept()
        except OSError:
            return
        with conn:
            conn.settimeout(0.3)
            try:
                conn.sendall(reply(conn.recv(4096).decode()).encode())
            except (OSError, ValueError, KeyError, RuntimeError) as error:
                try:
                    conn.sendall(('unknown request: ' + str(error)).encode())
                except OSError:
                    pass


def main():
    executable = sys.argv[1]
    if not os.environ.get('NIRI_SOCKET'):
        os.execv(executable, [executable, *sys.argv[2:]])
    # Fail before opening input devices when the graphical session is stale.
    request('KeyboardLayouts')
    directory = Path(os.environ['XDG_RUNTIME_DIR']) / 'hypr' / 'poltertype-niri'
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = directory / '.socket.sock'
    path.unlink(missing_ok=True)
    server = socket.socket(socket.AF_UNIX)
    server.bind(str(path))
    server.listen(8)
    threading.Thread(target=serve, args=(server,), daemon=True).start()
    environment = os.environ.copy()
    environment['HYPRLAND_INSTANCE_SIGNATURE'] = 'poltertype-niri'
    environment['POLTERTYPE_LAYOUT_BACKEND'] = 'hyprland'
    child = subprocess.Popen([executable, *sys.argv[2:]], env=environment)
    def stop(_signal, _frame):
        child.terminate()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        return child.wait()
    finally:
        server.close()
        path.unlink(missing_ok=True)
        directory.rmdir()


if __name__ == '__main__':
    raise SystemExit(main())
