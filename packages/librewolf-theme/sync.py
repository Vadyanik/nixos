#!/usr/bin/env python3
"""Adapt Quickshell's existing palette; never control the browser process."""
import argparse
import configparser
import datetime
import os
from pathlib import Path
import re
import shutil
import tempfile

PREFS = '''// BEGIN Quickshell LibreWolf integration
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("browser.compactmode.show", true);
user_pref("browser.uidensity", 1);
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.startup.homepage", "about:blank");
user_pref("sidebar.verticalTabs", false);
user_pref("sidebar.visibility", "hide-launcher");
user_pref("browser.theme.content-theme", 0);
user_pref("browser.theme.toolbar-theme", 0);
user_pref("layout.css.prefers-color-scheme.content-override", 0);
// Allow Canvas extraction globally; retain other available FPP targets.
// WebGLRandomization also randomizes Canvas 2D extraction in Firefox.
user_pref("privacy.resistFingerprinting", false);
user_pref("privacy.resistFingerprinting.pbmode", false);
user_pref("privacy.fingerprintingProtection", true);
user_pref("privacy.fingerprintingProtection.pbmode", true);
user_pref("privacy.fingerprintingProtection.remoteOverrides.enabled", false);
user_pref("privacy.fingerprintingProtection.overrides", "+AllTargets,-CanvasRandomization,-CanvasImageExtractionPrompt,-CanvasExtractionFromThirdPartiesIsBlocked,-CanvasExtractionBeforeUserInputIsBlocked,-EfficientCanvasRandomization,-WebGLRandomization");
// END Quickshell LibreWolf integration
'''


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
    return '/* Generated from Quickshell colors.css and Theme.qml surface formula. */\n:root {\n' + ''.join(f'  --qs-{k}: {v};\n' for k, v in values.items()) + '}\n'


def atomic(path, content, backup_root=None):
    if path.exists() and path.read_text() == content:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    if backup_root and (path.exists() or path.is_symlink()):
        target = backup_root / str(path).lstrip('/')
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


def profiles(root):
    ini = root / 'profiles.ini'
    if not ini.exists():
        return []
    parser = configparser.ConfigParser(interpolation=None)
    parser.read(ini)
    found = []
    for section in parser.sections():
        if section.startswith('Profile') and parser.has_option(section, 'Path'):
            p = Path(parser[section]['Path'])
            if parser.getboolean(section, 'IsRelative', fallback=True):
                p = root / p
            if p.is_dir():
                found.append(p.resolve())
    return list(dict.fromkeys(found))


def install(profile, assets, css, archive):
    for name in ('userChrome.css', 'userContent.css'):
        content = (assets / name).read_text()
        atomic(profile / 'chrome/quickshell' / name, content, archive)
        top = profile / 'chrome' / name
        old = top.read_text() if top.exists() else ''
        line = f'@import url("quickshell/{name}"); /* Quickshell integration */\n'
        if line not in old:
            # Imports must precede style rules and namespace declarations.
            atomic(top, line + old, archive)
    atomic(profile / 'chrome/quickshell/quickshell-colors.css', css)
    prefs = profile / 'user.js'
    old = prefs.read_text() if prefs.exists() else ''
    old = re.sub(r'// BEGIN Quickshell LibreWolf integration\n.*?// END Quickshell LibreWolf integration\n?', '', old, flags=re.S)
    atomic(prefs, old.rstrip() + ('\n\n' if old.strip() else '') + PREFS, archive)


def main():
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=config / 'quickshell/bar/colors.css')
    parser.add_argument('--profile', type=Path, help='Install into one explicit profile (for isolated testing)')
    parser.add_argument('--assets', type=Path, default=Path(os.environ.get('LIBREWOLF_THEME_ASSETS', Path(__file__).parent)))
    args = parser.parse_args()
    # Validate source before any profile mutation; retain last good output on failure.
    css = palette(args.source.read_text())
    targets = [args.profile] if args.profile else profiles(config / 'librewolf/librewolf')
    state = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state'))
    archive = state / 'librewolf-quickshell/backups' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    for target in targets:
        install(target, args.assets, css, archive)
    print(f'LibreWolf palette synchronized: {len(targets)} profile(s); running browser CSS updates on next launch.')


if __name__ == '__main__':
    main()
