#!/usr/bin/env python3
"""Generate Vesktop's quickCss from the shared Quickshell palette; never control the app."""
import argparse
import datetime
import os
from pathlib import Path
import re
import shutil
import tempfile


def palette(text):
    colors = dict(re.findall(r'@define-color\s+([\w-]+)\s+(#[\da-fA-F]{6})\s*;', text))
    for name in ('primary', 'foreground', 'on-primary', 'error'):
        if name not in colors:
            raise ValueError(f'Missing shared palette color: {name}')
    accent = [int(colors['primary'][i:i+2], 16) / 255 for i in (1, 3, 5)]
    gray = sum(c * w for c, w in zip(accent, (.2126, .7152, .0722)))
    def tint(level):
        return '#' + ''.join(f'{round((c * .7 + gray * .3) * level * 255):02x}' for c in accent)
    values = {'bg': tint(.10), 'surface': tint(.14), 'elevated': tint(.20),
              'fg': colors['foreground'], 'accent': colors['primary'],
              'on-accent': colors['on-primary'], 'error': colors['error'],
              'muted': f"color-mix(in srgb, {colors['foreground']} 65%, transparent)"}
    return '/* Generated from Quickshell colors.css and Theme.qml surface formula. */\n:root {\n' + ''.join(f'  --qs-{k}: {v};\n' for k, v in values.items()) + '}\n\n'


def atomic(path, content, backup_root=None):
    if path.exists() and path.read_text() == content:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    if backup_root and path.exists():
        target = backup_root / path.name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    fd, tmp = tempfile.mkstemp(prefix='.quickshell-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as out:
            out.write(content)
            out.flush()
            os.fsync(out.fileno())
        os.replace(tmp, path)
    finally:
        Path(tmp).unlink(missing_ok=True)
    return True


def main():
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=config / 'quickshell/bar/colors.css')
    parser.add_argument('--output', type=Path, default=config / 'vesktop/settings/quickCss.css')
    parser.add_argument('--theme', type=Path, default=Path(os.environ.get('VESKTOP_THEME_CSS', Path(__file__).parent / 'theme.css')))
    args = parser.parse_args()
    # Validate source before touching the output; retain last good CSS on failure.
    css = palette(args.source.read_text()) + args.theme.read_text()
    state = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state'))
    archive = state / 'vesktop-quickshell/backups' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    changed = atomic(args.output, css, archive)
    print('Vesktop palette ' + ('updated; Vesktop reloads quickCss live.' if changed else 'already current.'))


if __name__ == '__main__':
    main()
