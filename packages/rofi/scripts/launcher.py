#!/usr/bin/env python3
"""One-field Rofi application launcher with Chromium search fallback."""
import configparser
import fcntl
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import time
import sys
from urllib.parse import quote_plus


def search_url(query):
    return 'https://www.google.com/search?q=' + quote_plus(re.sub(r'^[gп]\s+', '', query.strip(), count=1, flags=re.IGNORECASE))


def applications():
    roots = [os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))]
    roots += os.environ.get('XDG_DATA_DIRS', '/usr/local/share:/usr/share').split(':')
    seen, result = set(), []
    desktops = set(os.environ.get('XDG_CURRENT_DESKTOP', '').split(':'))
    for root in roots:
        directory = Path(root) / 'applications'
        for path in sorted(directory.glob('**/*.desktop')):
            identity = str(path.relative_to(directory)).replace('/', '-')
            if identity in seen:
                continue
            seen.add(identity)
            entry = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                entry.read(path, encoding='utf-8')
                app = entry['Desktop Entry']
                if app.get('Type') != 'Application' or any(app.get(k, '').lower() == 'true' for k in ('Hidden', 'NoDisplay')):
                    continue
                if app.get('OnlyShowIn') and not desktops.intersection(app['OnlyShowIn'].split(';')):
                    continue
                if desktops.intersection(app.get('NotShowIn', '').split(';')):
                    continue
                if app.get('TryExec') and not shutil.which(app['TryExec']):
                    continue
                name = app['Name']
                metadata = ' '.join(app.get(k, '') for k in ('GenericName', 'Keywords', 'Exec'))
                row = name + '\0icon\x1f' + app.get('Icon', '') + '\x1fmeta\x1f' + metadata
                result.append((name.casefold(), path, row, identity))
            except (configparser.Error, KeyError, UnicodeError):
                continue
    return sorted(result, key=lambda item: item[0])


def open_history(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    history = sqlite3.connect(path)
    path.chmod(0o600)
    history.execute('CREATE TABLE IF NOT EXISTS launches (desktop_id TEXT PRIMARY KEY, count INTEGER NOT NULL, last_used INTEGER NOT NULL)')
    history.commit()
    return history


def ranked_applications(apps, history):
    usage = {identity: (count, last) for identity, count, last in history.execute('SELECT desktop_id, count, last_used FROM launches')}
    return sorted(apps, key=lambda app: (-usage.get(app[3], (0, 0))[0], -usage.get(app[3], (0, 0))[1], app[0]))


def record_launch(history, identity):
    history.execute('INSERT INTO launches VALUES (?, 1, ?) ON CONFLICT(desktop_id) DO UPDATE SET count = count + 1, last_used = excluded.last_used', (identity, time.time_ns()))
    history.commit()


def forced_search(query):
    return bool(re.match(r'^[gп]\s+', query.strip(), re.IGNORECASE))


def dynamic_theme():
    palette = Path.home() / '.config/quickshell/bar/colors.css'
    colors = dict(re.findall(r'@define-color\s+([\w-]+)\s+(#[\da-fA-F]{6});', palette.read_text())) if palette.exists() else {}
    # Match Quickshell's grayscale-mixed wallpaper tint, not Material card colors.
    accent = colors.get('primary', '#ebb5ed')
    rgb = [int(accent[i:i + 2], 16) for i in (1, 3, 5)]
    gray = sum(channel * weight for channel, weight in zip(rgb, (0.2126, 0.7152, 0.0722)))
    surface = '#' + ''.join(f'{round((channel * 0.7 + gray * 0.3) * 0.14):02x}' for channel in rgb)
    foreground = colors.get('foreground', '#eadfe6')
    theme_colors = {'background': surface + 'f7', 'foreground': foreground, 'primary': accent,
                    'secondary': foreground + 'a6', 'separator': accent + '40',
                    'selection': accent + '1a', 'urgent': colors.get('error', '#ffb4ab')}
    return '* { ' + ' '.join(f'{key}: {value};' for key, value in theme_colors.items()) + ' }'


def launch():
    with open(Path(os.environ['XDG_RUNTIME_DIR']) / 'rofi-launcher.lock', 'w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        layout_command = ['niri', 'msg', 'action', 'switch-layout', '0'] if os.environ.get('NIRI_SOCKET') else ['hyprctl', 'switchxkblayout', 'all', '0']
        subprocess.run(layout_command, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        dynamic = dynamic_theme()
        state = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state')))
        history = open_history(state / 'rofi-launcher/history.sqlite3')
        apps = ranked_applications(applications(), history)
        config_dir = os.environ.get('ROFI_CONFIG_DIR', str(Path(__file__).resolve().parent.parent))
        selection = subprocess.run(['rofi', '-config', str(Path(config_dir) / 'config.rasi'), '-dmenu', '-i', '-format', 'i\x1ff', '-sort', '-sorting-method', 'fzf', '-theme-str', dynamic],
                                   input='\n'.join(app[2] for app in apps), text=True, capture_output=True,
                                   env={**os.environ, 'LANGUAGE': 'en', 'LC_MESSAGES': 'C'})
        if selection.returncode != 0:
            return
        index, query = selection.stdout.rstrip('\n').split('\x1f', 1)
        if forced_search(query) or int(index) < 0:
            if query.strip():
                subprocess.Popen(['chromium', '--new-tab', search_url(query)],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        else:
            app = apps[int(index)]
            launched = subprocess.run(['gio', 'launch', str(app[1])],
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            if launched.returncode == 0:
                record_launch(history, app[3])


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--check':
        for prefix in ('g', 'G', 'п', 'П'):
            assert forced_search(prefix + ' chromium')
            assert search_url(prefix + ' rofi launcher') == 'https://www.google.com/search?q=rofi+launcher'
        assert not forced_search('ghostty') and not forced_search('погода')
        assert search_url('2^8') == 'https://www.google.com/search?q=2%5E8'
        assert search_url('cats & dogs') == 'https://www.google.com/search?q=cats+%26+dogs'
        assert any('chromium' in row.lower() for _, _, row, _ in applications())
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'history.sqlite3'
            history = open_history(path)
            apps = [('alpha', Path('/old/a'), '', 'a.desktop'), ('beta', Path('/old/b'), '', 'b.desktop')]
            assert ranked_applications(apps, history)[0][3] == 'a.desktop'
            record_launch(history, 'b.desktop')
            assert ranked_applications(apps, history)[0][3] == 'b.desktop'
            record_launch(history, 'a.desktop')
            assert ranked_applications(apps, history)[0][3] == 'a.desktop'
            record_launch(history, 'b.desktop')
            history.close()
            history = open_history(path)
            apps[1] = ('renamed beta', Path('/new/nix/store/b'), '', 'b.desktop')
            assert ranked_applications(apps, history)[0][3] == 'b.desktop'
            assert history.execute('SELECT count FROM launches WHERE desktop_id = ?', ('b.desktop',)).fetchone()[0] == 2
            history.close()
        print('Search, application ranking, and persistence checks passed')
    else:
        launch()
