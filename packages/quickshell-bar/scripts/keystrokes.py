#!/usr/bin/env python3
"""Stream pressed keys and chords from evdev keyboards as JSON lines.

Events (one JSON object per line):
  {"type": "state", "mods": ["super", "shift"], "key": "a"}   live view of what is held
  {"type": "chord", "mods": ["ctrl"], "key": "c"}             a completed press for the history
  {"type": "boundary"}                                       focus moved to another field or a
                                                             mouse button was pressed: a new word starts

Keys are physical (US layout) names; Esc and Caps Lock are swapped (xkb caps:swapescape),
so evdev code 58 is reported as esc and code 1 as caps; the shell maps them to icons.
Needs read access to /dev/input (the `input` group).

While a password is being typed nothing is reported except
  {"type": "state", "mods": [], "key": "", "secret": true}
See secret_input() for what counts as a password prompt.
"""
import glob
import json
import os
import re
import select
import socket
import struct
import sys
import termios
import threading
import time

EVENT = struct.Struct("llHHi")
EV_KEY = 1
MODS = {
    42: "shift", 54: "shift", 29: "ctrl", 97: "ctrl", 56: "alt", 100: "altgr",
    125: "super", 126: "super",
}
MOD_ORDER = ["super", "ctrl", "alt", "altgr", "shift"]
NAMES = {
    1: "caps", 14: "backspace", 15: "tab", 28: "enter", 57: "space", 58: "esc",
    69: "numlock", 70: "scrolllock", 99: "print", 119: "pause", 110: "insert",
    111: "delete", 102: "home", 107: "end", 104: "pageup", 109: "pagedown",
    103: "up", 108: "down", 105: "left", 106: "right", 127: "menu", 96: "kpenter",
    113: "mute", 114: "volumedown", 115: "volumeup", 164: "playpause",
    163: "next", 165: "previous", 224: "brightnessdown", 225: "brightnessup",
}
CHARS = {
    2: "1", 3: "2", 4: "3", 5: "4", 6: "5", 7: "6", 8: "7", 9: "8", 10: "9", 11: "0",
    12: "-", 13: "=", 16: "q", 17: "w", 18: "e", 19: "r", 20: "t", 21: "y", 22: "u",
    23: "i", 24: "o", 25: "p", 26: "[", 27: "]", 30: "a", 31: "s", 32: "d", 33: "f",
    34: "g", 35: "h", 36: "j", 37: "k", 38: "l", 39: ";", 40: "'", 41: "`", 43: "\\",
    44: "z", 45: "x", 46: "c", 47: "v", 48: "b", 49: "n", 50: "m", 51: ",", 52: ".",
    53: "/", 55: "kp*", 74: "kp-", 78: "kp+", 98: "kp/", 86: "<",
}
for i in range(10):  # F1..F10, F11, F12, keypad digits
    NAMES[59 + i] = f"f{i + 1}"
NAMES[87], NAMES[88] = "f11", "f12"
for code, digit in zip((82, 79, 80, 81, 75, 76, 77, 71, 72, 73), "0123456789"):
    CHARS[code] = digit


def key_name(code):
    return NAMES.get(code) or CHARS.get(code) or f"key{code}"


MOUSE_BUTTONS = range(272, 277)  # BTN_LEFT .. BTN_EXTRA


def input_devices():
    """Keyboards, plus mice whose button presses only mark word boundaries."""
    found = {}
    for kind in ("kbd", "mouse"):
        for link in glob.glob(f"/dev/input/by-path/*-event-{kind}") + glob.glob(f"/dev/input/by-id/*-event-{kind}"):
            found[os.path.realpath(link)] = True
    return list(found)


# Windows that ask for secrets, matched on Niri app-id or title.
SECRET_APPS = re.compile(r"polkit|pinentry|askpass|gcr-prompter|keepass|bitwarden|1password|kwallet|seahorse", re.I)
SECRET_TITLES = re.compile(r"password|passphrase|passcode|\bpin\b|sign[ -]?in|log[ -]?in|authenticat|пароль|вход|увійти|автентиф|аутентиф", re.I)
LOCKERS = {"hyprlock", "swaylock", "gtklock", "waylock"}
_locker_cache = [0.0, False]


def terminal_password_prompt():
    """A pty in canonical mode with echo off is waiting for a hidden line.

    sudo, su, ssh, passwd and `read -s` read passwords this way. Shells and
    full-screen programs also turn echo off, but they leave canonical mode too.
    """
    uid = os.getuid()
    for name in os.listdir("/dev/pts"):
        if not name.isdigit():
            continue
        path = "/dev/pts/" + name
        try:
            if os.stat(path).st_uid != uid:
                continue
            fd = os.open(path, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
        except OSError:
            continue
        try:
            lflag = termios.tcgetattr(fd)[3]
        except termios.error:
            continue
        finally:
            os.close(fd)
        if lflag & termios.ICANON and not lflag & termios.ECHO:
            return True
    return False


def focused_window():
    path = os.environ.get("NIRI_SOCKET")
    if not path:
        return {}
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.2)
            sock.connect(path)
            sock.sendall(b'"FocusedWindow"\n')
            reply = sock.makefile().readline()
        return (json.loads(reply).get("Ok") or {}).get("FocusedWindow") or {}
    except (OSError, ValueError):
        return {}


def window_asks_secret(window):
    return bool(SECRET_APPS.search(window.get("app_id") or "") or SECRET_TITLES.search(window.get("title") or ""))


def screen_locked():
    now = time.monotonic()
    if now - _locker_cache[0] > 0.25:
        running = False
        for pid in os.listdir("/proc"):
            if not pid.isdigit():
                continue
            try:
                with open(f"/proc/{pid}/comm") as comm:
                    if comm.read().strip() in LOCKERS:
                        running = True
                        break
            except OSError:
                continue
        _locker_cache[:] = [now, running]
    return _locker_cache[1]


class PasswordFocus:
    """Tracks which Niri window has keyboard focus in a password field, in any app that
    exposes accessibility (GTK, Qt, Firefox/LibreWolf, Chromium, Electron).

    Listens to AT-SPI focus events on a GLib loop in a background thread.
    Without PyGObject/Atspi it stays inactive and only the other checks apply.
    """

    def __init__(self):
        self.window = None
        try:
            import gi
            gi.require_version("Atspi", "2.0")
            from gi.repository import Atspi, GLib
        except (ImportError, ValueError) as error:
            print(f"AT-SPI password detection unavailable: {error}", file=sys.stderr)
            return
        threading.Thread(target=self._run, args=(Atspi, GLib), daemon=True).start()

    def _run(self, Atspi, GLib):
        Atspi.init()  # the main thread never touches GLib, so the default context is ours

        def on_focus(event):
            if not event.detail1:  # focus left this object; the next gain decides
                return
            try:
                secret = event.source.get_role() == Atspi.Role.PASSWORD_TEXT
            except Exception:  # the object may already be gone
                secret = False
            # Remember the Niri window; the flag only counts while it stays focused,
            # so leaving for an app without accessibility does not keep it stuck.
            self.window = focused_window().get("id") if secret else None
            emit(type="boundary")  # another field: what follows is a new word

        self._listener = Atspi.EventListener.new(on_focus)
        self._listener.register("object:state-changed:focused")
        GLib.MainLoop().run()


password_focus = None


def secret_input():
    if screen_locked() or terminal_password_prompt():
        return True
    window = focused_window()
    if window_asks_secret(window):
        return True
    return bool(password_focus and password_focus.window is not None and password_focus.window == window.get("id"))


_emit_lock = threading.Lock()


def emit(**event):
    with _emit_lock:  # the AT-SPI thread emits too
        sys.stdout.write(json.dumps(event) + "\n")
        sys.stdout.flush()


def main():
    global password_focus
    password_focus = PasswordFocus()
    devices = {}  # fd -> path
    held_mods = {}  # code -> name
    held_keys = []  # non-modifier codes in press order
    pending_mod_chord = False
    last_scan = 0.0
    secret = False

    def mods_now():
        names = set(held_mods.values())
        return [m for m in MOD_ORDER if m in names]

    def state():
        if secret:
            emit(type="state", mods=[], key="", secret=True)
        else:
            emit(type="state", mods=mods_now(), key=key_name(held_keys[-1]) if held_keys else "")

    while True:
        if time.monotonic() - last_scan > 3:
            last_scan = time.monotonic()
            known = set(devices.values())
            for path in input_devices():
                if path in known:
                    continue
                try:
                    devices[os.open(path, os.O_RDONLY | os.O_NONBLOCK)] = path
                except OSError as error:
                    print(f"cannot open {path}: {error}", file=sys.stderr)
        if not devices:
            time.sleep(1)
            continue
        ready, _, _ = select.select(list(devices), [], [], 1.0)
        for fd in ready:
            try:
                data = os.read(fd, EVENT.size * 64)
            except BlockingIOError:
                continue
            except OSError:  # unplugged
                os.close(fd)
                del devices[fd]
                continue
            for offset in range(0, len(data) - EVENT.size + 1, EVENT.size):
                _, _, etype, code, value = EVENT.unpack_from(data, offset)
                if etype != EV_KEY or value == 2:
                    continue
                if code in MOUSE_BUTTONS:
                    if value:
                        emit(type="boundary")
                    continue
                if value:  # decide on every press, before anything is reported
                    secret = secret_input()
                if code in MODS:
                    if value:
                        held_mods[code] = MODS[code]
                        pending_mod_chord = not held_keys
                    else:
                        if pending_mod_chord and not secret:
                            emit(type="chord", mods=mods_now(), key="")
                            pending_mod_chord = False
                        held_mods.pop(code, None)
                elif value:
                    held_keys.append(code)
                    pending_mod_chord = False
                    if not secret:
                        emit(type="chord", mods=mods_now(), key=key_name(code))
                elif code in held_keys:
                    held_keys.remove(code)
                state()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
