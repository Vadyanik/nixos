#!/usr/bin/env python3
"""Stream pressed keys and chords from evdev keyboards as JSON lines.

Events (one JSON object per line):
  {"type": "state", "mods": ["super", "shift"], "key": "a"}   live view of what is held
  {"type": "chord", "mods": ["ctrl"], "key": "c"}             a completed press for the history;
                                                             "vim": mode is added when Neovim gets it
  {"type": "vim", "mode": "n", "pending": false}             focused Neovim's mode after the
                                                             last key (pending: a command is unfinished)
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


# --- Neovim -----------------------------------------------------------------
# When a terminal is focused, the Neovim instance that has focus is asked for its
# mode (nvim_get_mode over its RPC socket), so the bar can tell typed text from
# commands. Focus is learnt from a FocusGained/FocusLost autocmd installed once
# per instance over RPC; Neovim's own config is not touched.

TERMINALS = re.compile(r"ghostty|kitty|foot|alacritty|wezterm|konsole|xterm|terminal", re.I)
FOCUS_LUA = """
if vim.g.keystroke_echo_focus == nil then
  vim.g.keystroke_echo_focus = 0
  vim.api.nvim_create_autocmd({ "FocusGained", "FocusLost" }, {
    group = vim.api.nvim_create_augroup("keystroke_echo", {}),
    callback = function(args)
      vim.g.keystroke_echo_focus = args.event == "FocusGained" and vim.uv.hrtime() or 0
    end,
  })
end
return vim.g.keystroke_echo_focus
"""


def pack(o):
    if o is None: return b"\xc0"
    if o is True: return b"\xc3"
    if o is False: return b"\xc2"
    if isinstance(o, int):
        if 0 <= o < 128: return bytes([o])
        return b"\xd3" + struct.pack(">q", o)
    if isinstance(o, str):
        b = o.encode()
        return (bytes([0xa0 | len(b)]) if len(b) < 32 else b"\xdb" + struct.pack(">I", len(b))) + b
    if isinstance(o, (list, tuple)):
        return (bytes([0x90 | len(o)]) if len(o) < 16 else b"\xdd" + struct.pack(">I", len(o))) + b"".join(map(pack, o))
    if isinstance(o, dict):
        return (bytes([0x80 | len(o)]) if len(o) < 16 else b"\xdf" + struct.pack(">I", len(o))) + b"".join(pack(k) + pack(v) for k, v in o.items())
    raise TypeError(o)

class Reader:
    def __init__(self, sock): self.sock, self.buf = sock, b""
    def take(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk: raise EOFError
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out
    def read(self):
        t = self.take(1)[0]
        if t <= 0x7f: return t
        if t >= 0xe0: return t - 256
        if 0x80 <= t <= 0x8f: return {self.read(): self.read() for _ in range(t & 15)}
        if 0x90 <= t <= 0x9f: return [self.read() for _ in range(t & 15)]
        if 0xa0 <= t <= 0xbf: return self.take(t & 31).decode(errors="replace")
        simple = {0xc0: None, 0xc2: False, 0xc3: True}
        if t in simple: return simple[t]
        sizes = {0xcc: ">B", 0xcd: ">H", 0xce: ">I", 0xcf: ">Q", 0xd0: ">b", 0xd1: ">h", 0xd2: ">i", 0xd3: ">q", 0xca: ">f", 0xcb: ">d"}
        if t in sizes:
            fmt = sizes[t]; return struct.unpack(fmt, self.take(struct.calcsize(fmt)))[0]
        if t in (0xd9, 0xda, 0xdb):
            n = struct.unpack({0xd9: ">B", 0xda: ">H", 0xdb: ">I"}[t], self.take({0xd9: 1, 0xda: 2, 0xdb: 4}[t]))[0]; return self.take(n).decode(errors="replace")
        if t in (0xc4, 0xc5, 0xc6):
            n = struct.unpack({0xc4: ">B", 0xc5: ">H", 0xc6: ">I"}[t], self.take({0xc4: 1, 0xc5: 2, 0xc6: 4}[t]))[0]; return self.take(n)
        if t in (0xdc, 0xdd):
            n = struct.unpack(">H" if t == 0xdc else ">I", self.take(2 if t == 0xdc else 4))[0]; return [self.read() for _ in range(n)]
        if t in (0xde, 0xdf):
            n = struct.unpack(">H" if t == 0xde else ">I", self.take(2 if t == 0xde else 4))[0]; return {self.read(): self.read() for _ in range(n)}
        if 0xd4 <= t <= 0xd8:  # fixext: nvim handles (buffer/window ids)
            n = {0xd4: 1, 0xd5: 2, 0xd6: 4, 0xd7: 8, 0xd8: 16}[t]; self.take(1 + n); return None
        if t in (0xc7, 0xc8, 0xc9):
            n = struct.unpack({0xc7: ">B", 0xc8: ">H", 0xc9: ">I"}[t], self.take({0xc7: 1, 0xc8: 2, 0xc9: 4}[t]))[0]; self.take(1 + n); return None
        raise ValueError(hex(t))


def nvim_call(path, method, *args):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.15)
        sock.connect(path)
        sock.sendall(pack([0, 1, method, list(args)]))
        reader = Reader(sock)
        while True:
            message = reader.read()
            if message[0] == 1 and message[1] == 1:
                if message[2]:
                    raise RuntimeError(message[2])
                return message[3]


_nvim_focus = {}  # socket path -> last known focus time (0 = unfocused)


def focused_nvim(window):
    """Socket of the Neovim that receives keys, or None."""
    if not TERMINALS.search(window.get("app_id") or ""):
        return None
    runtime = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    sockets = glob.glob(f"{runtime}/nvim.*.0")
    for path in list(_nvim_focus):
        if path not in sockets:
            del _nvim_focus[path]
    for path in sockets:
        try:
            # get_mode is answered even while Neovim waits for the rest of a
            # command; anything else would stall until that input arrives.
            if not nvim_call(path, "nvim_get_mode").get("blocking"):
                _nvim_focus[path] = nvim_call(path, "nvim_exec_lua", FOCUS_LUA, []) or 0
        except (OSError, EOFError, ValueError, RuntimeError, IndexError):
            _nvim_focus.pop(path, None)
    focused = [(at, path) for path, at in _nvim_focus.items() if at]
    if focused:
        return max(focused)[1]
    return sockets[0] if len(sockets) == 1 and sockets[0] in _nvim_focus else None


def nvim_mode(path):
    """(mode, pending) of a Neovim, or None if it does not answer."""
    try:
        state = nvim_call(path, "nvim_get_mode")
    except (OSError, EOFError, ValueError, RuntimeError, IndexError):
        return None
    mode = state.get("mode") or ""
    return mode, bool(state.get("blocking")) or mode.startswith("no")


def secret_input(window):
    if screen_locked() or terminal_password_prompt():
        return True
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
    nvim = None  # socket of the focused Neovim for the current press
    vim_check_at = None  # when to report Neovim's mode after the last key

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
        timeout = 1.0 if vim_check_at is None else max(0.0, vim_check_at - time.monotonic())
        ready, _, _ = select.select(list(devices), [], [], timeout)
        if vim_check_at is not None and time.monotonic() >= vim_check_at:
            # Shortly after a key Neovim has handled it: report whether the command is complete.
            vim_check_at = None
            vim_state = nvim_mode(nvim) if nvim else None
            if vim_state:
                emit(type="vim", mode=vim_state[0], pending=vim_state[1])
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
                    window = focused_window()
                    secret = secret_input(window)
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
                        # The mode before this key decides how it reads (text or command);
                        # the state also closes the previous command if it is complete.
                        nvim = focused_nvim(window)
                        vim_state = nvim_mode(nvim) if nvim else None
                        if vim_state:
                            emit(type="vim", mode=vim_state[0], pending=vim_state[1])
                            emit(type="chord", mods=mods_now(), key=key_name(code), vim=vim_state[0])
                            vim_check_at = time.monotonic() + 0.03
                        else:
                            emit(type="chord", mods=mods_now(), key=key_name(code))
                elif code in held_keys:
                    held_keys.remove(code)
                state()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
