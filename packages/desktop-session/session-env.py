"""Resolve Niri's live sockets before launching a session process."""
import os
from pathlib import Path
import re
import subprocess
import sys


def session_environment(environ):
    env = dict(environ)
    path = Path(env.get('NIRI_SOCKET', '/nonexistent'))
    match = re.fullmatch(r'niri\.(.+)\.(\d+)\.sock', path.name)
    if not match or not path.exists():
        return env
    display, pid = match.groups()
    runtime = path.parent
    if not (runtime / display).exists():
        raise RuntimeError('Niri Wayland socket is unavailable')
    env.update(WAYLAND_DISPLAY=display, XDG_CURRENT_DESKTOP='niri', XDG_SESSION_TYPE='wayland')
    env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
    # Niri owns the X11 listening sockets before Satellite starts. Derive the
    # display from its descriptors rather than guessing :0 or inheriting Hyprland.
    inodes = set()
    for descriptor in Path('/proc', pid, 'fd').iterdir():
        try:
            socket = re.fullmatch(r'socket:\[(\d+)\]', str(descriptor.readlink()))
            if socket:
                inodes.add(socket[1])
        except OSError:
            continue
    env.pop('DISPLAY', None)
    for line in Path('/proc/net/unix').read_text().splitlines()[1:]:
        fields = line.split()
        if len(fields) > 7 and fields[6] in inodes:
            x11 = re.fullmatch(r'@?/tmp/\.X11-unix/X(\d+)', fields[7])
            if x11:
                env['DISPLAY'] = ':' + x11[1]
                break
    return env


def main():
    env = session_environment(os.environ)
    args = sys.argv[1:]
    if args == ['--import']:
        keys = ('WAYLAND_DISPLAY', 'DISPLAY', 'XDG_CURRENT_DESKTOP', 'XDG_SESSION_TYPE', 'NIRI_SOCKET', 'HYPRLAND_INSTANCE_SIGNATURE')
        missing = [key for key in keys if key not in env]
        if missing:
            subprocess.run(['systemctl', '--user', 'unset-environment', *missing], env=env, check=True)
        values = [key + '=' + env[key] for key in keys if key in env]
        subprocess.run(['dbus-update-activation-environment', '--systemd', *values], env=env, check=True)
    elif args:
        os.execvpe(args[0], args, env)
    else:
        raise SystemExit('Usage: desktop-session-env --import | COMMAND [ARG ...]')


if __name__ == '__main__':
    main()
