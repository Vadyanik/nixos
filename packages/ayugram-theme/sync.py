#!/usr/bin/env python3
"""Build an AyuGram/Telegram Desktop theme from the shared Quickshell palette; never control the app."""
import argparse
import os
from pathlib import Path
import re
import struct
import tempfile
import zlib
import zipfile

# key -> (surface level, alpha 0-255). Only UI surfaces: media, stickers and avatars are not palette-driven.
SURFACES = {
    'windowBg': (.10, 0xb8), 'dialogsBg': None, 'historyComposeAreaBg': (.10, 0xb8),
    'historyPinnedBg': (.14, 0xc8), 'historyUnreadBarBg': (.14, 0xc8), 'searchedBarBg': (.14, 0xc8),
    'emojiPanHeaderBg': (.14, 0xe0), 'historyToDownBg': (.14, 0xd8),
    'windowBgOver': (.14, 0xc8), 'dialogsBgOver': (.14, 0xc8), 'windowBgRipple': (.20, 0xc8),
    'dialogsRippleBg': (.20, 0xc8), 'lightButtonBg': (.10, 0xb8), 'lightButtonBgOver': (.14, 0xc8),
    'lightButtonBgRipple': (.20, 0xc8), 'filterInputInactiveBg': (.14, 0xc8),
    'titleBg': (.10, 0xb8), 'titleBgActive': (.14, 0xc8),
    'boxBg': (.10, 0xf0), 'boxSearchBg': (.10, 0xf0), 'menuBg': (.10, 0xf0),
    'menuBgRipple': (.20, 0xf0), 'tooltipBg': (.14, 0xf0), 'msgInBg': (.14, 0xe8),
}
ACCENT = {'windowBgActive': 'primary', 'activeButtonBg': 'primary', 'windowActiveTextFg': 'primary',
          'activeLineFg': 'primary', 'windowFgActive': 'on-primary', 'activeButtonFg': 'on-primary',
          'windowFg': 'foreground', 'windowBoldFg': 'foreground'}


def palette(text):
    colors = dict(re.findall(r'@define-color\s+([\w-]+)\s+(#[\da-fA-F]{6})\s*;', text))
    for name in ('primary', 'foreground', 'on-primary'):
        if name not in colors:
            raise ValueError(f'Missing shared palette color: {name}')
    return colors


def tint(accent, level):
    rgb = [int(accent[i:i+2], 16) / 255 for i in (1, 3, 5)]
    gray = sum(c * w for c, w in zip(rgb, (.2126, .7152, .0722)))
    return ''.join(f'{round((c * .7 + gray * .3) * level * 255):02x}' for c in rgb)


def build_palette(colors, base):
    out = []
    for line in base.splitlines():
        m = re.match(r'(\w+):\s*([^;]+);(.*)', line)
        key = m.group(1) if m else None
        if key in ACCENT:
            line = f'{key}: {colors[ACCENT[key]]};'
        elif key in SURFACES and SURFACES[key]:
            level, alpha = SURFACES[key]
            line = f'{key}: #{tint(colors["primary"], level)}{alpha:02x};'
        out.append(line)
    return '\n'.join(out) + '\n'


def solid_png(rgb):
    def chunk(tag, data):
        body = tag + data
        return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(b'\x00' + bytes.fromhex(rgb))) + chunk(b'IEND', b''))


def write_theme(path, palette_text, wallpaper):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='.quickshell-', dir=path.parent)
    os.close(fd)
    try:
        with zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED) as z:
            z.writestr('colors.tdesktop-theme', palette_text)
            # Telegram forces theme wallpapers opaque (forceOpaque), so the chat area gets a solid surface tint.
            z.writestr('tiled.png', solid_png(wallpaper))
        os.replace(tmp, path)
    finally:
        Path(tmp).unlink(missing_ok=True)


def main():
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=config / 'quickshell/bar/colors.css')
    parser.add_argument('--output', type=Path, default=config / 'ayugram-quickshell/quickshell.tdesktop-theme')
    parser.add_argument('--base', type=Path, default=Path(os.environ.get('AYUGRAM_THEME_BASE', Path(__file__).parent / 'night-base.palette')))
    args = parser.parse_args()
    colors = palette(args.source.read_text())
    text = build_palette(colors, args.base.read_text())  # validate before writing
    write_theme(args.output, text, tint(colors['primary'], .10))
    print(f'AyuGram theme written to {args.output}; apply it once via Settings > Chat Settings > Choose from file.')


if __name__ == '__main__':
    main()
