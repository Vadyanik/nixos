#!/usr/bin/env python3
"""Select the parallax wallpaper and apply its matching system palette."""
import argparse
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

SHARE = Path(os.environ.get("PARALLAX_WALLPAPER_SHARE", Path(__file__).resolve().parent))
STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "parallax-wallpaper"
PANEL = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "quickshell" / "bar"
META = json.loads((SHARE / "wallpapers.json").read_text())


def atomic(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".tmp-", dir=path.parent)
    with os.fdopen(fd, "w") as f:
        f.write(content)
    os.replace(name, path)


def current():
    try:
        wid = (STATE / "current").read_text().strip()
    except FileNotFoundError:
        wid = ""
    return wid if wid in META["wallpapers"] else META["default"]


def resolve(value):
    wid = value.zfill(5)
    if wid not in META["wallpapers"]:
        sys.exit(f"Unknown wallpaper {value!r}. Available: {', '.join(META['wallpapers'])}")
    return wid


def apply_palette(wid):
    atomic(PANEL / "colors.css", (SHARE / "assets" / wid / "palette.css").read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["set", "list", "apply", "current"])
    parser.add_argument("id", nargs="?")
    args = parser.parse_args()
    if args.command == "set":
        if not args.id:
            parser.error("set requires a wallpaper ID, for example 4 or 00004")
        wid = resolve(args.id)
        atomic(STATE / "current", wid + "\n")
        apply_palette(wid)
    elif args.command == "apply":
        apply_palette(current())
    elif args.command == "current":
        print(current())
    else:
        for wid, info in META["wallpapers"].items():
            print(("* " if wid == current() else "  ") + f"{wid}  {info['title']}")


if __name__ == "__main__":
    main()
