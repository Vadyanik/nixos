"""Smoke-test every real animation and ensure stopping leaves no PTY children."""
import concurrent.futures
import json
import os
from pathlib import Path
import re
import select
import subprocess
import sys
import time

package = Path(sys.argv[1]).resolve()
wrapper = (package / 'bin/desktop-widgets').read_text()
os.environ['PATH'] = ':'.join(re.findall(r"PATH='([^']+)'\$PATH", wrapper)) + ':' + os.environ['PATH']
os.environ['TERMINFO'] = re.search(r"export TERMINFO='?([^'\n]+)", wrapper).group(1)
qml = (package / 'share/desktop-widgets/shell.qml').read_text()
python = re.search(r'command: \["([^"]+/bin/python3)".*animation-bridge', qml).group(1)
bridge = package / 'share/desktop-widgets/animation-bridge.py'


def check(mode):
    proc = subprocess.Popen([python, str(bridge), mode], stdout=subprocess.PIPE, text=True)
    frames = set()
    children = []
    deadline = time.monotonic() + 6
    try:
        while time.monotonic() < deadline:
            if select.select([proc.stdout], [], [], 1)[0]:
                line = proc.stdout.readline()
                assert line, f'{mode}: bridge exited'
                frame = json.loads(line)
                assert len(frame['lines']) == frame['rows']
                assert all(sum(len(run[0]) for run in row) == frame['cols'] for row in frame['lines'])
                content = ''.join(run[0] for row in frame['lines'] for run in row).strip()
                assert not any(message in content.lower() for message in ['less than minimum', 'please resize', 'traceback', 'not found', 'unknown option']), f'{mode}: error frame: {content[:240]}'
                painted = sum(len(run[0]) for row in frame['lines'] for run in row if run[2] != 'default')
                if time.monotonic() > deadline - 4 and (content or painted):
                    frames.add(line)
        assert len(frames) >= 2, f'{mode}: no changing frames ({len(frames)})'
        children = Path(f'/proc/{proc.pid}/task/{proc.pid}/children').read_text().split()
    finally:
        proc.terminate()
        proc.wait(timeout=4)
    assert all(not Path(f'/proc/{pid}').exists() for pid in children), f'{mode}: orphan PTY'
    return f'PASS {mode}: changing frames, correct dimensions, clean stop'


seed_code = "import runpy, sys; print(runpy.run_path(sys.argv[1])['seed_for_wallpaper'](sys.argv[2]))"
source_id = 'ISS040-E-112233'
seed = subprocess.check_output([python, '-c', seed_code, str(bridge), source_id], text=True).strip()
assert seed == subprocess.check_output([python, '-c', seed_code, str(bridge), source_id], text=True).strip()
assert seed != subprocess.check_output([python, '-c', seed_code, str(bridge), 'ISS040-E-445566'], text=True).strip()
os.environ['TERM'] = 'xterm-256color'
first = subprocess.check_output(['cbonsai', '-p', '--seed', seed], timeout=5)
second = subprocess.check_output(['cbonsai', '-p', '--seed', seed], timeout=5)
assert first == second and len(first) > 100, 'cbonsai: same title must reproduce the tree'
print('PASS cbonsai: wallpaper ID seed is stable and reproduces the real tree', flush=True)

modes = ['lavat', 'cbonsai', 'pipes', 'aafire', 'genact', 'unimatrix']
with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
    for result in pool.map(check, modes):
        print(result, flush=True)
