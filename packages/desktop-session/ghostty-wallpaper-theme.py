#!/run/current-system/sw/bin/python3
"""Follow the active wallpaper Material palette used by Quickshell."""
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile


def blend(a, b, weight):
    a, b = a.lstrip("#"), b.lstrip("#")
    return "#" + "".join(f"{round(int(a[i:i+2], 16) * (1-weight) + int(b[i:i+2], 16) * weight):02x}" for i in (0, 2, 4))


def render(css):
    colors = dict(re.findall(r"@define-color\s+([\w-]+)\s+(#[0-9a-fA-F]{6})\s*;", css))
    required = ("background", "foreground", "surface", "primary", "secondary", "tertiary", "error", "on-primary", "charcoal-2")
    for key in required:
        if key not in colors:
            raise ValueError(f"Wallpaper palette is missing {key}")
    settings = {
        "background": colors["background"],
        "foreground": colors["foreground"],
        "cursor-color": colors["primary"],
        "cursor-text": colors["on-primary"],
        "selection-background": colors["primary"],
        "selection-foreground": colors["on-primary"],
    }
    # Keep red/green/yellow recognizable for command output, with wallpaper tint.
    normal = [colors["surface"], colors["error"], blend("#a6d6a0", colors["primary"], .25),
              blend("#e5ce95", colors["secondary"], .25), colors["primary"],
              colors["tertiary"], colors["secondary"], colors["foreground"]]
    bright = [colors["charcoal-2"]] + [blend(color, colors["foreground"], .18) for color in normal[1:7]] + [colors["foreground"]]
    return ("# Generated from Quickshell's active wallpaper palette.\n"
            + "".join(f"{key} = {value}\n" for key, value in settings.items())
            + "".join(f"palette = {i}={color}\n" for i, color in enumerate(normal + bright)))


def main():
    config = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
    source = config / "quickshell/bar/colors.css"
    target = config / "ghostty/wallpaper-theme.conf"
    content = render(source.read_text())
    if target.exists() and target.read_text() == content:
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".wallpaper-theme-", dir=target.parent)
    try:
        with os.fdopen(fd, "w") as output:
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, target)
    finally:
        Path(temporary).unlink(missing_ok=True)
    systemctl = "/run/current-system/sw/bin/systemctl"
    unit = "app-com.mitchellh.ghostty.service"
    active = subprocess.run([systemctl, "--user", "is-active", "--quiet", unit])
    if active.returncode == 0:
        subprocess.run([systemctl, "--user", "reload", unit], check=True)
    else:
        # Hyprland's direct CLI launch does not use Ghostty's systemd unit.
        executable = Path("/run/current-system/sw/bin/ghostty").resolve()
        wrapped = executable.parent / ".ghostty-wrapped"
        for process in Path("/proc").iterdir():
            if not process.name.isdigit():
                continue
            try:
                if process.stat().st_uid == os.getuid() and (process / "exe").resolve() in (executable, wrapped):
                    os.kill(int(process.name), signal.SIGUSR2)
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                continue


if __name__ == "__main__":
    main()
