#!/usr/bin/env python3
"""Read LibreWolf bookmarks and favicons without writing to browser databases."""
import configparser
from contextlib import contextmanager
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


def config_root():
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "librewolf" / "librewolf"


def active_profile_override(root):
    for cmdline in Path("/proc").glob("[0-9]*/cmdline"):
        try:
            args = cmdline.read_bytes().decode().strip("\0").split("\0")
        except (OSError, UnicodeError):
            continue
        if not args or Path(args[0]).name not in ("librewolf", "librewolf-bin", ".librewolf-wrapped"):
            continue
        if any(arg == "-contentproc" or arg == "--contentproc" for arg in args):
            continue
        for index, arg in enumerate(args):
            if arg.startswith("--profile="):
                return Path(arg.split("=", 1)[1]).expanduser()
            if arg in ("--profile", "-profile") and index + 1 < len(args):
                return Path(args[index + 1]).expanduser()
    return None


def profile_path(root):
    override = active_profile_override(root)
    if override:
        candidate = override if override.is_absolute() else root / override
        return candidate

    ini = root / "profiles.ini"
    parser = configparser.ConfigParser(interpolation=None)
    parser.read(ini, encoding="utf-8")
    install_defaults = []
    for section in parser.sections():
        if section.startswith("Install") and parser.has_option(section, "Default"):
            install_defaults.append(parser.get(section, "Default"))
    profile_sections = [section for section in parser.sections() if section.startswith("Profile")]
    paths = {}
    for section in profile_sections:
        relative = parser.getboolean(section, "IsRelative", fallback=True)
        raw_path = parser.get(section, "Path", fallback="")
        if not raw_path:
            continue
        path = root / raw_path if relative else Path(raw_path)
        paths[section] = path

    candidates = []
    candidates.extend(root / raw for raw in install_defaults)
    candidates.extend(paths[s] for s in profile_sections if parser.getboolean(s, "Default", fallback=False) and s in paths)
    candidates.extend(paths[s] for s in profile_sections if s in paths)
    for path in candidates:
        if (path / "places.sqlite").is_file():
            return path
    if candidates:
        return candidates[0]
    return root


@contextmanager
def read_transaction(path):
    db = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True, timeout=0.15)
    try:
        db.execute("PRAGMA query_only=ON")
        db.execute("BEGIN")
        # Force SQLite to acquire its read lock before the caller starts querying.
        db.execute("SELECT name FROM sqlite_master LIMIT 1").fetchone()
    except sqlite3.OperationalError as error:
        db.close()
        if not any(word in str(error).lower() for word in ("locked", "busy")):
            raise
        with snapshot_transaction(path) as snapshot:
            yield snapshot
        return
    try:
        yield db
    finally:
        db.close()


def file_signature(path):
    signature = []
    for source in (path, Path(str(path) + "-wal")):
        try:
            stat = source.stat()
            signature.append((source.name, stat.st_size, stat.st_mtime_ns))
        except FileNotFoundError:
            signature.append((source.name, None, None))
    return tuple(signature)


@contextmanager
def snapshot_transaction(path):
    """Read a stable base/WAL copy when LibreWolf prevents an external reader."""
    last_error = None
    with tempfile.TemporaryDirectory(prefix="librewolf-bookmarks-") as directory:
        target = Path(directory) / path.name
        for _attempt in range(3):
            before = file_signature(path)
            try:
                shutil.copyfile(path, target)
                wal_source = Path(str(path) + "-wal")
                wal_target = Path(str(target) + "-wal")
                if wal_source.exists():
                    shutil.copyfile(wal_source, wal_target)
                elif wal_target.exists():
                    wal_target.unlink()
            except OSError as error:
                last_error = error
                continue
            if before != file_signature(path):
                last_error = sqlite3.OperationalError("database changed during snapshot")
                continue

            db = None
            try:
                # This copy lives only in the temporary directory. RW mode lets
                # SQLite construct its temporary WAL index; SQL writes stay disabled.
                db = sqlite3.connect(target, timeout=0.2)
                db.execute("PRAGMA query_only=ON")
                db.execute("BEGIN")
                db.execute("SELECT name FROM sqlite_master LIMIT 1").fetchone()
            except sqlite3.OperationalError as error:
                last_error = error
                if db is not None:
                    db.close()
                if not any(word in str(error).lower() for word in ("locked", "busy", "malformed")):
                    raise
                continue
            try:
                yield db
            finally:
                db.close()
            return
        if last_error:
            raise last_error
        raise sqlite3.OperationalError("could not create a stable database snapshot")


def read_bookmarks(database):
    with read_transaction(database) as db:
        rows = db.execute(
            "SELECT b.id, b.type, b.fk, b.parent, b.position, b.title, b.guid, p.url "
            "FROM moz_bookmarks b LEFT JOIN moz_places p ON p.id=b.fk "
            "ORDER BY b.parent, b.position, b.id"
        ).fetchall()

    children = {}
    page_urls = {}
    for row_id, kind, fk, parent, position, title, guid, url in rows:
        children.setdefault(parent, []).append(
            {"id": row_id, "type": kind, "fk": fk, "title": title or "", "guid": guid or "", "url": url or ""}
        )
        if kind == 1 and fk and url:
            page_urls[fk] = url

    roots = [row for row in children.get(1, []) if row["type"] == 2 and row["guid"] != "tags________"]
    root_titles = {"toolbar_____": "Bookmarks toolbar", "menu________": "Bookmarks menu",
                   "unfiled_____": "Other bookmarks", "mobile______": "Mobile bookmarks"}
    for root in roots:
        root["title"] = root_titles.get(root["guid"], root["title"])
    groups = []

    def visit(folder, parents, seen):
        folder_id = folder["id"]
        if folder_id in seen:
            return
        path = parents + [folder["title"] or "Bookmarks"]
        bookmarks = []
        subfolders = []
        for child in children.get(folder_id, []):
            if child["type"] == 1:
                url = child["url"]
                if url:
                    bookmarks.append({
                        "id": str(child["id"]),
                        "title": child["title"] or urlparse(url).hostname or "Bookmark",
                        "url": url,
                        "icon": "",
                    })
            elif child["type"] == 2:
                subfolders.append(child)
        if bookmarks:
            groups.append({"title": " / ".join(path), "bookmarks": bookmarks})
        for child in subfolders:
            visit(child, path, seen | {folder_id})

    for folder in roots:
        visit(folder, [], set())
    return groups, page_urls


def read_icons(profile, groups, page_urls):
    if not any(group["bookmarks"] for group in groups):
        return
    database = profile / "favicons.sqlite"
    icons = {}
    try:
        if database.is_file():
            with read_transaction(database) as db:
                tables = {name for (name,) in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                if {"moz_pages_w_icons", "moz_icons"} <= tables:
                    urls = list(page_urls.values())
                    for start in range(0, len(urls), 500):
                        batch = urls[start:start + 500]
                        placeholders = ",".join("?" for _ in batch)
                        query = (
                            "SELECT p.page_url, i.data, i.width "
                            "FROM moz_pages_w_icons p "
                            "JOIN moz_icons_to_pages m ON m.page_id=p.id "
                            "JOIN moz_icons i ON i.id=m.icon_id "
                            f"WHERE p.page_url IN ({placeholders}) AND length(i.data)>0 "
                            "ORDER BY i.width DESC"
                        )
                        for url, data, width in db.execute(query, batch):
                            mime = "image/svg+xml" if width == 65535 else "image/png"
                            icons.setdefault(url, (data, mime))
    except (OSError, sqlite3.Error):
        pass

    # Older Firefox-derived profiles kept moz_favicons beside moz_places.
    if not icons:
        try:
            with read_transaction(profile / "places.sqlite") as db:
                tables = {name for (name,) in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                if "moz_favicons" in tables:
                    page_ids = list(page_urls)
                    for start in range(0, len(page_ids), 500):
                        batch = page_ids[start:start + 500]
                        placeholders = ",".join("?" for _ in batch)
                        query = (
                            "SELECT p.id, f.data, f.mime_type "
                            "FROM moz_places p JOIN moz_favicons f ON f.id=p.favicon_id "
                            f"WHERE p.id IN ({placeholders}) AND length(f.data)>0"
                        )
                        for page_id, data, mime in db.execute(query, batch):
                            icons.setdefault(page_urls[page_id], (data, mime))
        except (OSError, sqlite3.Error):
            pass

    if not icons:
        return
    cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "quickshell/bookmark-icons"
    cache.mkdir(parents=True, exist_ok=True)
    for group in groups:
        for bookmark in group["bookmarks"]:
            found = icons.get(bookmark["url"])
            if not found:
                continue
            data, mime = found
            if not data:
                continue
            extension = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp", "image/gif": ".gif", "image/svg+xml": ".svg"}.get(mime, ".ico")
            target = cache / (hashlib.sha256(data).hexdigest() + extension)
            if not target.exists():
                target.write_bytes(data)
            bookmark["icon"] = target.as_uri()


def main():
    root = config_root()
    profile = profile_path(root)
    database = profile / "places.sqlite"
    if len(sys.argv) == 3 and sys.argv[1] == "--open":
        try:
            groups, _page_urls = read_bookmarks(database)
            item = next((bookmark for group in groups for bookmark in group["bookmarks"]
                         if bookmark["id"] == sys.argv[2]), None)
        except (OSError, sqlite3.Error):
            item = None
        if item:
            url = item["url"]
            if urlparse(url).scheme.lower() in ("http", "https", "file", "ftp"):
                subprocess.Popen(
                    ["librewolf", "--profile", str(profile), "--new-tab", url],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
                )
        return

    result = {"path": str(database), "profile": profile.name, "sections": [], "error": ""}
    try:
        result["sections"], page_urls = read_bookmarks(database)
        read_icons(profile, result["sections"], page_urls)
    except (OSError, sqlite3.Error) as error:
        result["error"] = error.__class__.__name__
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
