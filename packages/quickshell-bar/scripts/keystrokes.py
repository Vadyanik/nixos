#!/usr/bin/env python3
"""Stream pressed keys and chords from evdev keyboards as JSON lines.

Events (one JSON object per line):
  {"type": "state", "mods": ["super", "shift"], "key": "a"}   live view of what is held
  {"type": "chord", "mods": ["ctrl"], "key": "c"}             a completed press for the history

Keys are physical (US layout) names; the shell maps them to icons.
Needs read access to /dev/input (the `input` group).
"""
import glob
import json
import os
import select
import struct
import sys
import time

EVENT = struct.Struct("llHHi")
EV_KEY = 1
MODS = {
    42: "shift", 54: "shift", 29: "ctrl", 97: "ctrl", 56: "alt", 100: "altgr",
    125: "super", 126: "super",
}
MOD_ORDER = ["super", "ctrl", "alt", "altgr", "shift"]
NAMES = {
    1: "esc", 14: "backspace", 15: "tab", 28: "enter", 57: "space", 58: "caps",
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


def keyboards():
    found = {}
    for link in glob.glob("/dev/input/by-path/*-event-kbd") + glob.glob("/dev/input/by-id/*-event-kbd"):
        found[os.path.realpath(link)] = True
    return list(found)


def emit(**event):
    sys.stdout.write(json.dumps(event) + "\n")
    sys.stdout.flush()


def main():
    devices = {}  # fd -> path
    held_mods = {}  # code -> name
    held_keys = []  # non-modifier codes in press order
    pending_mod_chord = False
    last_scan = 0.0

    def mods_now():
        names = set(held_mods.values())
        return [m for m in MOD_ORDER if m in names]

    def state():
        emit(type="state", mods=mods_now(), key=key_name(held_keys[-1]) if held_keys else "")

    while True:
        if time.monotonic() - last_scan > 3:
            last_scan = time.monotonic()
            known = set(devices.values())
            for path in keyboards():
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
                if code in MODS:
                    if value:
                        held_mods[code] = MODS[code]
                        pending_mod_chord = not held_keys
                    else:
                        if pending_mod_chord:
                            emit(type="chord", mods=mods_now(), key="")
                            pending_mod_chord = False
                        held_mods.pop(code, None)
                elif value:
                    held_keys.append(code)
                    pending_mod_chord = False
                    emit(type="chord", mods=mods_now(), key=key_name(code))
                elif code in held_keys:
                    held_keys.remove(code)
                state()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
