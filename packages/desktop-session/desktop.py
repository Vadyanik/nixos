"""Shared desktop actions for the declarative Hyprland and Niri sessions."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import time
import tomllib


def run(argv, **kwargs):
    return subprocess.run(argv, check=True, **kwargs)


def query(command):
    argv = ['niri', 'msg', '-j', command] if os.environ.get('NIRI_SOCKET') else ['hyprctl', command, '-j']
    return json.loads(subprocess.check_output(argv, text=True))


def action(*args):
    run(['niri', 'msg', 'action', *map(str, args)], stdout=subprocess.DEVNULL)


def normalize(value):
    value = re.sub(r'[^a-z0-9]', '', Path(value or '').name.lower().removesuffix('.desktop'))
    return 'codexdesktop' if value == 'chatgpt' else value


def notify(text):
    subprocess.run(['notify-send', 'Desktop', text], check=False)


def focus(args):
    parser = argparse.ArgumentParser()
    parser.add_argument('name', nargs='?')
    parser.add_argument('--app')
    parser.add_argument('--desktop')
    parser.add_argument('--pid', type=lambda value: int(value) if value else None)
    parser.add_argument('--launch')
    opts = parser.parse_args(args)
    needles = {normalize(n) for n in (opts.name, opts.app, opts.desktop) if n}
    for attempt in range(8):
        windows = query('windows' if os.environ.get('NIRI_SOCKET') else 'clients')
        window = next((w for w in windows if (opts.pid and w.get('pid') == opts.pid) or normalize(w.get('app_id', w.get('class'))) in needles), None)
        if window:
            if os.environ.get('NIRI_SOCKET'):
                action('focus-window', '--id', window['id'])
            else:
                run(['hyprctl', 'dispatch', 'focuswindow', 'address:' + window['address']])
            return
        if opts.launch:
            subprocess.Popen([opts.launch], start_new_session=True)
            return
        time.sleep(.25)
    raise SystemExit(1)


def layout(index):
    if os.environ.get('NIRI_SOCKET'):
        action('switch-layout', index)
    else:
        run(['hyprctl', 'switchxkblayout', 'all', str(index)], stdout=subprocess.DEVNULL)


def mru():
    state = Path(os.environ['XDG_RUNTIME_DIR']) / ('niri-language-mru.json' if os.environ.get('NIRI_SOCKET') else 'hypr-language-mru.json')
    with (state.with_suffix('.lock')).open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        data = json.loads(state.read_text()) if state.exists() else {'stack': [0, 1, 2], 'time': 0}
        stack = data['stack']
        current = query('keyboard-layouts')['current_idx'] if os.environ.get('NIRI_SOCKET') else next((k['active_layout_index'] for k in query('devices')['keyboards'] if k.get('main')), stack[0])
        if current != stack[0]:
            stack = [current] + [i for i in stack if i != current]
        now = time.monotonic()
        stack = [stack[-1], *stack[:-1]] if now - data['time'] < .8 else [stack[1], stack[0], *stack[2:]]
        layout(stack[0])
        state.write_text(json.dumps({'stack': stack, 'time': now}))


def scratchpad(mode):
    if not os.environ.get('NIRI_SOCKET'):
        run(['hyprctl', 'dispatch', 'movetoworkspacesilent' if mode == 'move' else 'togglespecialworkspace', 'special:magic' if mode == 'move' else 'magic'])
        return
    if mode == 'move':
        action('move-window-to-workspace', '--focus', 'false', 'magic')
    else:
        active = next(w for w in query('workspaces') if w['is_focused'])
        action('focus-workspace-previous') if active.get('name') == 'magic' else action('focus-workspace', 'magic')


def focused():
    return query('focused-window' if os.environ.get('NIRI_SOCKET') else 'activewindow')


def poltertype():
    window = focused()
    if not window or not window.get('pid'):
        notify('Focused application does not expose a process ID')
        return
    exe = Path(os.readlink('/proc/' + str(window['pid']) + '/exe')).name
    path = Path.home() / '.config/poltertype/config.toml'
    source = path.read_text()
    apps = tomllib.loads(source)['exceptions']['disabled_apps']
    present = any(app.casefold() == exe.casefold() for app in apps)
    apps = [app for app in apps if app.casefold() != exe.casefold()] if present else [*apps, exe]
    section = re.search(r'(?ms)^\[exceptions\]\n(.*?)(?=^\[|\Z)', source)
    if section is None:
        raise ValueError('missing [exceptions] section')
    updated, count = re.subn(r'(?ms)^disabled_apps[ \t]*=[ \t]*\[[^\]]*\]', lambda _: 'disabled_apps = ' + json.dumps(apps, ensure_ascii=False), section.group(1), count=1)
    if count != 1:
        raise ValueError('missing disabled_apps setting')
    path.write_text(source[:section.start(1)] + updated + source[section.end(1):])
    notify(f"{window.get('title') or exe} {'removed from' if present else 'added to'} exceptions")


def screenshot(mode):
    if not os.environ.get('NIRI_SOCKET'):
        if mode == 'quick':
            selection = subprocess.run(['slurp'], capture_output=True, text=True)
            if selection.returncode or not selection.stdout.strip():
                return
            command = ['grim', '-g', selection.stdout.strip(), '-']
        else:
            command = ['flameshot', 'gui', '--raw']
        image = run(command, stdout=subprocess.PIPE).stdout
    elif mode == 'quick':
        action('screenshot', '--show-pointer', 'false')
        return
    else:
        # Niri's native capture supplies the image to a Wayland annotation editor.
        with tempfile.TemporaryDirectory(prefix='niri-screenshot-', dir=os.environ['XDG_RUNTIME_DIR']) as directory:
            path = Path(directory) / 'capture.png'
            action('screenshot', '--show-pointer', 'false', '--path', path)
            deadline = time.monotonic() + 120
            while not path.exists():
                if time.monotonic() >= deadline:
                    return
                time.sleep(.1)
            image = run(['swappy', '-f', str(path), '-o', '-'], stdout=subprocess.PIPE).stdout
    if image:
        run(['wl-copy', '--sensitive', '--type', 'image/png'], input=image)


def main():
    import sys
    command, *args = sys.argv[1:]
    if command == 'focus':
        focus(args)
    elif command == 'mru':
        mru()
    elif command == 'scratchpad':
        scratchpad(args[0])
    elif command == 'force-close':
        window = focused()
        if window and window.get('pid'):
            os.kill(window['pid'], signal.SIGKILL)
    elif command == 'lock':
        layout(0)
        if subprocess.run(['pgrep', '-x', 'hyprlock'], stdout=subprocess.DEVNULL).returncode:
            run(['hyprlock', '--config', os.environ['DESKTOP_LOCK_CONFIG']])
    elif command == 'poltertype':
        poltertype()
    elif command == 'screenshot':
        screenshot(args[0] if args else 'edit')
    else:
        raise ValueError(command)


if __name__ == '__main__':
    main()
