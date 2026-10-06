"""Run terminal animations in a PTY and stream styled frames to Quickshell."""
import fcntl
import hashlib
import json
import os
import pty
import select
import signal
import struct
import sys
import termios
import time

import pyte

MODES = {
    'lavat': (120, 35, ['lavat', '-c', 'white', '-b', '8', '-r', '4', '-s', '6']),
    'cbonsai': (90, 30, ['cbonsai', '-l']),
    'pipes': (90, 32, ['pipes.sh', '-p', '5', '-f', '20']),
    'aafire': (90, 32, ['aafire', '-driver', 'curses']),
    'genact': (80, 28, ['genact']),
    'unimatrix': (90, 32, ['unimatrix', '-s', '95']),
}


def seed_for_wallpaper(source_id):
    return (int.from_bytes(hashlib.sha256(source_id.encode("utf-8")).digest()[:4], "big") & 0x7fffffff) or 1


def render(screen, lava):
    rows = []
    for y in range(screen.lines):
        runs = []
        for x in range(screen.columns):
            cell = screen.buffer[y][x]
            text = '█' if lava and cell.bg != 'default' else cell.data
            style = ['default' if lava else cell.fg, 'default' if lava else cell.bg, cell.bold]
            if cell.reverse and not lava:
                style = [cell.bg if cell.bg != 'default' else 'black',
                         cell.fg if cell.fg != 'default' else 'foreground', cell.bold]
            if runs and runs[-1][1:] == style:
                runs[-1][0] += text
            else:
                runs.append([text, *style])
        rows.append(runs)
    return rows


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else 'lavat'
    cols, rows, command = MODES[mode]
    if mode == 'cbonsai':
        source_id = sys.argv[2] if len(sys.argv) > 2 else ''
        command = command + ['--seed', str(seed_for_wallpaper(source_id))]
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    # Restart naturally finite animations without a shell or accumulating children.
    while True:
        pid, fd = pty.fork()
        if pid == 0:
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))
            os.environ['TERM'] = 'xterm-256color'
            os.environ['LANG'] = 'C.UTF-8'
            os.execvp(command[0], command)
        screen = pyte.Screen(cols, rows)
        stream = pyte.ByteStream(screen)
        last = 0.0
        try:
            while True:
                ready, _, _ = select.select([fd], [], [], 0.04)
                if ready:
                    try:
                        data = os.read(fd, 65536)
                    except OSError:
                        break
                    if not data:
                        break
                    stream.feed(data)
                now = time.monotonic()
                if screen.dirty and now - last >= 1 / 20:
                    print(json.dumps({'cols': cols, 'rows': rows,
                                      'lines': render(screen, mode == 'lavat')},
                                     ensure_ascii=False), flush=True)
                    screen.dirty.clear()
                    last = now
        finally:
            os.close(fd)
            try:
                os.killpg(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            # A PTY child owns its process group, including sortty's subprocess.
            deadline = time.monotonic() + 1
            while os.waitpid(pid, os.WNOHANG) == (0, 0):
                if time.monotonic() >= deadline:
                    try:
                        os.killpg(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    os.waitpid(pid, 0)
                    break
                time.sleep(0.02)
        time.sleep(1)


if __name__ == '__main__':
    main()
