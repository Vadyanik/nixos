#!/usr/bin/env python3
"""Read Chromium's bookmark JSON and a local snapshot of its favicon database."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from urllib.parse import urlparse


def profile():
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
    user_dir, selected = config / 'chromium', None
    for proc in Path('/proc').glob('[0-9]*/cmdline'):
        try:
            args = proc.read_bytes().decode().strip('\0').split('\0')
        except (OSError, UnicodeError):
            continue
        if not args or Path(args[0]).name not in ('chromium', 'chromium-browser') or any(a.startswith('--type=') for a in args):
            continue
        for i, arg in enumerate(args):
            if arg.startswith('--user-data-dir='):
                user_dir = Path(arg.split('=', 1)[1])
            elif arg == '--user-data-dir' and i + 1 < len(args):
                user_dir = Path(args[i + 1])
            elif arg.startswith('--profile-directory='):
                selected = arg.split('=', 1)[1]
        break
    try:
        info = json.loads((user_dir / 'Local State').read_text()).get('profile', {})
    except (OSError, ValueError):
        info = {}
    candidates = [selected, info.get('last_used'), *(info.get('last_active_profiles') or []), 'Default']
    for name in candidates:
        if name and Path(name).name == name and (user_dir / name / 'Bookmarks').is_file():
            return user_dir, user_dir / name
    candidates = sorted(user_dir.glob('*/Bookmarks'), key=lambda f: f.stat().st_mtime, reverse=True)
    if candidates:
        return user_dir, candidates[0].parent
    return user_dir, user_dir / 'Default'


def sections(roots):
    output = []
    def visit(node, parents):
        title = node.get('name') or 'Bookmarks'
        path = parents + [title]
        bookmarks = [{'id': str(c.get('id', '')), 'title': c.get('name') or urlparse(c.get('url', '')).hostname or 'Bookmark', 'url': c['url'], 'icon': ''}
                     for c in node.get('children', []) if c.get('type') == 'url' and c.get('url')]
        if bookmarks:
            output.append({'title': ' / '.join(path), 'bookmarks': bookmarks})
        for child in node.get('children', []):
            if child.get('type') == 'folder':
                visit(child, path)
    for node in roots.values():
        if isinstance(node, dict) and node.get('type') == 'folder':
            visit(node, [])
    return output


def icons(directory, groups):
    cache = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache')) / 'quickshell/bookmark-icons'
    cache.mkdir(parents=True, exist_ok=True)
    try:
        # Chromium locks its live SQLite connection exclusively. Copy only favicon
        # data; never open or change the browser database in read/write mode.
        with tempfile.TemporaryDirectory(prefix='quickshell-favicons-') as tmp:
            target = Path(tmp) / 'Favicons'
            for suffix in ('', '-wal'):
                src = directory / ('Favicons' + suffix)
                if src.exists():
                    shutil.copyfile(src, Path(str(target) + suffix))
            with sqlite3.connect(target) as db:
                mappings = db.execute('SELECT m.page_url,b.image_data,b.width FROM icon_mapping m JOIN favicon_bitmaps b ON m.icon_id=b.icon_id WHERE length(b.image_data)>0 ORDER BY b.width DESC').fetchall()
            exact, origins = {}, {}
            for url, blob, width in mappings:
                exact.setdefault(url, blob)
                host = urlparse(url).hostname
                if host:
                    origins.setdefault(host, blob)
            for group in groups:
                for item in group['bookmarks']:
                    blob = exact.get(item['url']) or origins.get(urlparse(item['url']).hostname)
                    if blob:
                        file = cache / (hashlib.sha256(blob).hexdigest() + '.png')
                        if not file.exists():
                            file.write_bytes(blob)
                        item['icon'] = file.as_uri()
    except (OSError, sqlite3.Error):
        pass  # UI uses an accent-colored initial when no local icon exists.


def main():
    user_dir, directory = profile()
    if len(sys.argv) == 3 and sys.argv[1] == '--open':
        # Resolve an existing bookmark ID again instead of treating UI input as a command.
        groups = sections(json.loads((directory / 'Bookmarks').read_text()).get('roots', {}))
        item = next((b for g in groups for b in g['bookmarks'] if b['id'] == sys.argv[2]), None)
        if item:
            url = item['url']
            if urlparse(url).scheme in ('http', 'https', 'file', 'chrome', 'chrome-extension', 'ftp'):
                subprocess.Popen(['chromium', '--user-data-dir=' + str(user_dir), '--profile-directory=' + directory.name, url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return
    result = {'path': str(directory / 'Bookmarks'), 'profile': directory.name, 'sections': [], 'error': ''}
    try:
        result['sections'] = sections(json.loads((directory / 'Bookmarks').read_text()).get('roots', {}))
        icons(directory, result['sections'])
    except (OSError, ValueError) as error:
        result['error'] = str(error)
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
