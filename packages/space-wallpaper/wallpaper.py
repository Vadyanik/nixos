#!/usr/bin/env python3
"""Offline random wallpaper selection; NASA acquisition is a separate command."""

import argparse
import contextlib
import fcntl
import hashlib
import io
import json
import logging
import os
from pathlib import Path
import random
import re
import secrets
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import warnings

from PIL import Image, ImageCms, ImageDraw, ImageFont, ImageOps

LOG = logging.getLogger("space-wallpaper")
BASE = Path(__file__).resolve().parent
CONFIG = Path(
    os.environ.get("SPACE_WALLPAPER_CONFIG", "/etc/space-wallpaper/settings.json")
)
if not CONFIG.exists():
    CONFIG = BASE / "settings.json"
SET = json.loads(CONFIG.read_text())
STATE = (
    Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
    / "space-wallpaper"
)
WORKSPACES = STATE / "workspaces.json"
CACHE = (
    Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))
    / "space-wallpaper"
)
PANEL = (
    Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "quickshell" / "bar"
)
FONT = (
    Path(os.environ["SPACE_WALLPAPER_FONT"])
    if os.environ.get("SPACE_WALLPAPER_FONT")
    else None
)
Image.MAX_IMAGE_PIXELS = 180_000_000
warnings.simplefilter("error", Image.DecompressionBombWarning)


def atomic(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".tmp-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(content if isinstance(content, bytes) else content.encode())
            f.flush()
            os.fsync(f.fileno())
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def save(path, value):
    atomic(path, json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def read(path, default):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return default
    except (ValueError, UnicodeError):
        # Keep damaged data for diagnosis and recover from the actual cache.
        LOG.warning("Invalid state %s; recovering", path)
        return default


@contextlib.contextmanager
def lock(name, blocking=True):
    STATE.mkdir(parents=True, exist_ok=True)
    with (STATE / (name + ".lock")).open("a") as f:
        try:
            fcntl.flock(f, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
        except BlockingIOError:
            yield False
            return
        try:
            yield True
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


def files():
    return sorted(
        p.name
        for p in CACHE.glob("*.jpg")
        if re.fullmatch(r"[0-9a-f]{64}\.jpg", p.name)
    )


def random_image(available, excluded=()):
    candidates = sorted(set(available) - set(excluded))
    return secrets.choice(candidates) if candidates else None


def random_titled_image(available, excluded=(), catalog=None):
    """Choose a title uniformly, then choose one image with that title."""
    candidates = sorted(set(available) - set(excluded))
    if not candidates:
        return None
    catalog = catalog if catalog is not None else read(STATE / "catalog.json", {})
    titles_by_hash = {
        record.get("hash"): record.get("title", "")
        for record in catalog.values()
        if record.get("hash")
    }
    groups = {}
    for name in candidates:
        title = titles_by_hash.get(Path(name).stem, "")
        # Missing catalog metadata has no known title; keep each image distinct.
        group = ("title", title) if title else ("image", name)
        groups.setdefault(group, []).append(name)
    group = secrets.choice(sorted(groups, key=lambda item: (item[0], item[1])))
    return secrets.choice(groups[group])


def run(args, **kwargs):
    return subprocess.run(
        args,
        check=True,
        timeout=kwargs.pop("timeout", 30),
        capture_output=True,
        text=True,
        **kwargs,
    )


def palette(path):
    # Explicit empty config isolates this application from unrelated matugen hooks.
    empty = STATE / "matugen.toml"
    atomic(empty, "[config]\n[templates]\n")
    data = json.loads(
        run(
            [
                "matugen",
                "--config",
                str(empty),
                "image",
                str(path),
                "--json",
                "hex",
                "--dry-run",
                "--mode",
                "dark",
                "--source-color-index",
                "0",
            ]
        ).stdout
    )
    colors = {key: value["dark"]["color"] for key, value in data["colors"].items()}
    aliases = {
        "background": "background",
        "surface": "surface_container",
        "foreground": "on_surface",
        "primary": "primary",
        "secondary": "secondary",
        "tertiary": "tertiary",
        "error": "error",
        "on-error": "on_error",
        "on-primary": "on_primary",
        "white": "on_surface",
        "white-2": "primary",
        "cool-steel": "secondary",
        "charcoal": "surface_container_high",
        "charcoal-2": "outline",
        "shadow-grey": "surface_container",
        "black": "background",
    }
    values = {name: colors[key] for name, key in aliases.items()}
    if not all(re.fullmatch(r"#[0-9a-fA-F]{6}", c) for c in values.values()):
        raise ValueError("Invalid palette colors")
    return "/* Generated by space-wallpaper; dark Material palette. */\n" + "".join(
        f"@define-color {name} {color};\n" for name, color in values.items()
    )


def apply_palette(path):
    try:
        css = path.with_suffix(".css")
        content = css.read_text() if css.exists() else palette(path)
        atomic(PANEL / "colors.css", content)
    except Exception as error:
        LOG.warning("Wallpaper installed; previous panel theme retained: %s", error)


def ellipsize(draw, text, font, width):
    text = " ".join(str(text).split())
    if draw.textlength(text, font=font) <= width:
        return text
    suffix = "..."
    while text and draw.textlength(text + suffix, font=font) > width:
        text = text[:-1].rstrip()
    return text + suffix


def fit_lines(draw, text, font, width, limit=2):
    """Wrap a caption by rendered width and ellipsize the final line."""
    words = " ".join(str(text).split()).split()
    lines = []
    while words and len(lines) < limit:
        line = words.pop(0)
        while words and draw.textlength(line + " " + words[0], font=font) <= width:
            line += " " + words.pop(0)
        lines.append(line)
    if words:
        lines[-1] += "..."
    return [ellipsize(draw, line, font, width) for line in lines]


def caption_record(path):
    catalog = read(STATE / "catalog.json", {})
    for source_id, record in catalog.items():
        if record.get("hash") == path.stem and record.get("title"):
            return source_id, record
    return None, None


def render_caption(path):
    config = {
        "enabled": True,
        "title_size": 52,
        "credit_size": 27,
        "margin_x": 96,
        "margin_bottom": 74,
        "max_width_fraction": 0.72,
        "line_spacing": 8,
        "title_credit_gap": 18,
        "gradient_height": 390,
        "gradient_opacity": 178,
        "shadow_offset": 3,
        **SET.get("caption", {}),
    }
    if not config.get("enabled", True):
        return path
    source_id, record = caption_record(path)
    if not record:
        return path
    rendered = CACHE / "rendered" / (path.stem + ".bmp")
    if rendered.exists():
        return rendered

    title_font = (
        ImageFont.truetype(str(FONT), config["title_size"])
        if FONT and FONT.exists()
        else ImageFont.load_default(size=config["title_size"])
    )
    credit_font = (
        ImageFont.truetype(str(FONT), config["credit_size"])
        if FONT and FONT.exists()
        else ImageFont.load_default(size=config["credit_size"])
    )
    with Image.open(path) as source:
        image = source.convert("RGBA")
    width, height = image.size
    margin_x = config["margin_x"]
    margin_bottom = config["margin_bottom"]
    text_width = int(width * config["max_width_fraction"])
    measure = ImageDraw.Draw(image)
    lines = fit_lines(measure, record["title"], title_font, text_width)
    title = "\n".join(lines)
    credit = "  /  ".join(part for part in [record.get("credit"), source_id] if part)
    credit = ellipsize(measure, credit, credit_font, text_width)
    title_box = measure.multiline_textbbox(
        (0, 0), title, font=title_font, spacing=config["line_spacing"]
    )
    credit_box = measure.textbbox((0, 0), credit, font=credit_font)
    title_height = title_box[3] - title_box[1]
    credit_height = credit_box[3] - credit_box[1]
    credit_y = height - margin_bottom - credit_height
    title_y = credit_y - config["title_credit_gap"] - title_height

    gradient_height = max(config["gradient_height"], height - title_y + 70)
    alpha = Image.new("L", (1, gradient_height))
    alpha.putdata(
        [
            round(config["gradient_opacity"] * (i / max(1, gradient_height - 1)) ** 2)
            for i in range(gradient_height)
        ]
    )
    alpha = alpha.resize((width, gradient_height))
    shade = Image.new("RGBA", (width, gradient_height), "black")
    shade.putalpha(alpha)
    image.alpha_composite(shade, (0, height - gradient_height))

    draw = ImageDraw.Draw(image)
    shadow = config["shadow_offset"]
    draw.multiline_text(
        (margin_x + shadow, title_y + shadow),
        title,
        font=title_font,
        fill=(0, 0, 0, 210),
        spacing=config["line_spacing"],
    )
    draw.multiline_text(
        (margin_x, title_y),
        title,
        font=title_font,
        fill=(255, 255, 255, 245),
        spacing=config["line_spacing"],
    )
    draw.text(
        (margin_x + shadow, credit_y + shadow),
        credit,
        font=credit_font,
        fill=(0, 0, 0, 210),
    )
    draw.text(
        (margin_x, credit_y),
        credit,
        font=credit_font,
        fill=(225, 230, 238, 235),
    )

    output = io.BytesIO()
    # BMP is lossless and encodes a 4K frame much faster than photographic PNG.
    # Only the current rendered frame is retained, so its 24 MiB size is bounded.
    image.convert("RGB").save(output, "BMP")
    atomic(rendered, output.getvalue())
    return rendered


def next_wallpaper():
    # Coalesce rapid clicks instead of queueing many long transitions.
    with lock("switch", blocking=False) as acquired:
        if not acquired:
            return
        with lock("cache"):
            state = read(STATE / "shuffle.json", {})
            available = files()
            while available:
                selected = random_titled_image(available, {state.get("current")})
                if not selected:
                    selected = random_titled_image(available)
                path = CACHE / selected
                proposed = {"current": selected, "changed_at": time.time()}
                try:
                    with Image.open(path) as im:
                        if im.size != tuple(SET["desired_resolution"]):
                            raise ValueError("wrong dimensions")
                        im.verify()
                    break
                except (OSError, ValueError) as error:
                    LOG.warning("Skipping invalid cached image %s: %s", selected, error)
                    available.remove(selected)
            else:
                LOG.warning(
                    "Cache is empty; keeping current wallpaper. Run wallpaper-update."
                )
                return
            # Check writable state before changing the desktop.
            atomic(STATE / "pending.json", json.dumps(proposed))
            display_wallpaper(path)
            os.replace(STATE / "pending.json", STATE / "shuffle.json")


def display_wallpaper(path, transition="fade", duration="0.5", retain=None):
    try:
        cached = CACHE / "rendered" / (path.stem + ".bmp")
        displayed = cached if cached.exists() else render_caption(path)
    except Exception as error:
        LOG.warning("Caption rendering failed; using clean wallpaper: %s", error)
        displayed = path
    command = [
        "awww", "img", str(displayed),
        "--transition-type", transition,
        "--transition-duration", duration,
        "--transition-fps", "60",
        "--transition-bezier", "0.65,0.05,0.36,1",
    ]
    try:
        # Send the transition immediately. A separate `awww query` round trip
        # here delayed every wallpaper change after Hyprland had already moved.
        run(command, timeout=20)
    except (subprocess.SubprocessError, OSError):
        run(["systemctl", "--user", "start", "space-wallpaper-daemon.service"], timeout=10)
        for _ in range(40):
            try:
                run(["awww", "query"], timeout=2)
                break
            except subprocess.SubprocessError:
                time.sleep(0.1)
        else:
            raise RuntimeError("Wallpaper daemon did not become ready")
        run(command, timeout=20)
    keep = {displayed}
    if retain is not None:
        keep.update(retain)
    for old in (CACHE / "rendered").glob("*.bmp"):
        if old not in keep:
            old.unlink(missing_ok=True)
    apply_palette(path)


def workspace_rendered(assignments):
    return {
        CACHE / "rendered" / (Path(item["image"]).stem + ".bmp")
        for item in assignments.values()
        if item.get("image")
    }


def active_workspace():
    return json.loads(run(["hyprctl", "activeworkspace", "-j"]).stdout)


def workspace_assignments(state):
    return state.setdefault("assignments", {})


def workspace_initialize():
    with lock("workspaces"), lock("cache"):
        workspaces = json.loads(run(["hyprctl", "workspaces", "-j"]).stdout)
        active = active_workspace()
        available = files()
        assignments = {}
        for workspace in sorted(workspaces, key=lambda item: int(item["id"])):
            if str(workspace.get("name", "")).startswith("special:"):
                continue
            assigned = {item["image"] for item in assignments.values()}
            selected = random_titled_image(name for name in available if name not in assigned)
            if not selected:
                break
            assignments[str(workspace["id"])] = {"image": selected}
        active_id = str(active["id"])
        state = {
            "assignments": assignments,
            "last_workspace": active_id,
            "hyprland_instance": os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"),
        }
        record = assignments.get(active_id)
        if record and (CACHE / record["image"]).exists():
            for item in assignments.values():
                render_caption(CACHE / item["image"])
            display_wallpaper(
                CACHE / record["image"], "fade", "0.4", workspace_rendered(assignments)
            )
        save(WORKSPACES, state)
        if record:
            save(STATE / "shuffle.json", {"current": record["image"]})


def workspace_activate(workspace_id=None, skip_if_current=False):
    with lock("workspaces"), lock("cache"):
        workspace_id = str(workspace_id if workspace_id is not None else active_workspace()["id"])
        state = read(WORKSPACES, {})
        assignments = workspace_assignments(state)
        record = assignments.get(workspace_id)
        if (
            skip_if_current
            and state.get("last_workspace") == workspace_id
            and record
            and (CACHE / record.get("image", "")).exists()
        ):
            return
        # A workspace visit is a new draw, never a restore of its old image.
        current = read(STATE / "shuffle.json", {}).get("current")
        old_image = record.get("image") if record else None
        available = files()
        selected = random_titled_image(available, {current, old_image})
        if not selected:
            selected = random_titled_image(available, {current})
        if not selected:
            selected = random_titled_image(available)
        if not selected:
            return
        record = {"image": selected}
        assignments[workspace_id] = record
        previous = state.get("last_workspace")
        try:
            before, after = int(previous), int(workspace_id)
            direction = "right" if after > before else "left" if after < before else "fade"
        except (TypeError, ValueError):
            direction = "fade"
        display_wallpaper(
            CACHE / record["image"], direction, "0.4", workspace_rendered(assignments)
        )
        state["last_workspace"] = workspace_id
        state["hyprland_instance"] = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
        save(WORKSPACES, state)
        save(STATE / "shuffle.json", {"current": selected})


def workspace_next():
    with lock("workspaces"), lock("cache"):
        workspace_id = str(active_workspace()["id"])
        state = read(WORKSPACES, {})
        assignments = workspace_assignments(state)
        record = assignments.get(workspace_id, {})
        current = read(STATE / "shuffle.json", {}).get("current")
        available = files()
        selected = random_titled_image(available, {current, record.get("image")})
        if not selected:
            selected = random_titled_image(available, {current})
        if not selected:
            selected = random_titled_image(available)
        if not selected:
            return
        assignments[workspace_id] = {"image": selected}
        state["last_workspace"] = workspace_id
        state["hyprland_instance"] = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
        display_wallpaper(
            CACHE / selected, "fade", "0.4", workspace_rendered(assignments)
        )
        save(WORKSPACES, state)
        save(STATE / "shuffle.json", {"current": selected})


def workspace_remove(workspace_id):
    with lock("workspaces"):
        state = read(WORKSPACES, {})
        assignments = workspace_assignments(state)
        assignments.pop(str(workspace_id), None)
        keep = workspace_rendered(assignments)
        for old in (CACHE / "rendered").glob("*.bmp"):
            if old not in keep:
                old.unlink(missing_ok=True)
        save(WORKSPACES, state)


def watch_workspaces():
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not signature or not runtime:
        raise RuntimeError("Hyprland session environment is unavailable")
    event_socket = Path(runtime) / "hypr" / signature / ".socket2.sock"
    while True:
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
                connection.connect(str(event_socket))
                state = read(WORKSPACES, {})
                if state.get("hyprland_instance") != signature or not state.get("assignments"):
                    workspace_initialize()
                else:
                    workspace_activate()
                stream = connection.makefile("r", encoding="utf-8")
                for line in stream:
                    event, _, data = line.rstrip("\n").partition(">>")
                    if event == "workspacev2":
                        workspace_id, _, _ = data.partition(",")
                        workspace_activate(workspace_id, skip_if_current=True)
                    elif event == "focusedmonv2":
                        _, _, workspace_id = data.rpartition(",")
                        workspace_activate(workspace_id, skip_if_current=True)
                    elif event == "destroyworkspacev2":
                        workspace_remove(data.split(",", 1)[0])
        except (OSError, subprocess.SubprocessError, ValueError) as error:
            LOG.warning("Workspace wallpaper watcher reconnecting: %s", error)
            time.sleep(1)


def checked_url(url):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or not (parsed.hostname or "").endswith(".nasa.gov"):
        raise ValueError("Untrusted image URL")
    return url


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        checked_url(new_url)
        return super().redirect_request(request, fp, code, message, headers, new_url)


def fetch(url, limit=None):
    if url.startswith("http://"):
        url = "https://" + url[7:]
    checked_url(url)
    limit = limit or SET["max_download_mb"] * 1024 * 1024
    request = urllib.request.Request(
        url, headers={"User-Agent": "SpaceWallpaper/1.0 (personal NASA image cache)"}
    )
    with urllib.request.build_opener(SafeRedirect).open(
        request, timeout=SET["request_timeout"]
    ) as response:
        checked_url(response.url)
        if int(response.headers.get("Content-Length", 0)) > limit:
            raise ValueError("download size limit")
        chunks = []
        size = 0
        started = time.monotonic()
        while chunk := response.read(256 * 1024):
            size += len(chunk)
            if size > limit or time.monotonic() - started > 120:
                raise ValueError("download size/time limit")
            chunks.append(chunk)
        return b"".join(chunks)


def get_json(url):
    return json.loads(fetch(url, 8 * 1024 * 1024))


def normalize(raw):
    with Image.open(io.BytesIO(raw)) as test:
        if test.format not in {"JPEG", "PNG", "TIFF", "WEBP"}:
            raise ValueError("unsupported format")
        test.verify()
    with Image.open(io.BytesIO(raw)) as source:
        image = ImageOps.exif_transpose(source)
        w, h = image.size
        tw, th = SET["desired_resolution"]
        mw, mh = SET["minimum_resolution"]
        if w < max(tw, mw) or h < max(th, mh):
            raise ValueError("insufficient resolution")
        retained = min((w / h) / (tw / th), (tw / th) / (w / h))
        if w < h or 1 - retained > SET["max_crop_fraction"]:
            raise ValueError("aspect ratio / excessive crop")
        image = ImageOps.fit(image, (tw, th), method=Image.Resampling.LANCZOS)
        icc = source.info.get("icc_profile")
        if icc:
            try:
                image = ImageCms.profileToProfile(
                    image,
                    ImageCms.ImageCmsProfile(io.BytesIO(icc)),
                    ImageCms.createProfile("sRGB"),
                    outputMode="RGB",
                )
            except (ImageCms.PyCMSError, OSError):
                image = image.convert("RGB")
        else:
            image = image.convert("RGB")
        # Coarse perceptual signature catches the same photograph at different resolutions.
        small = image.resize((17, 16), Image.Resampling.LANCZOS).convert("L")
        pixels = list(small.tobytes())
        bits = [
            pixels[y * 17 + x] > pixels[y * 17 + x + 1]
            for y in range(16)
            for x in range(16)
        ]
        fingerprint = format(sum(int(bit) << i for i, bit in enumerate(bits)), "064x")
        output = io.BytesIO()
        image.save(
            output, "JPEG", quality=SET["jpeg_quality"], subsampling=0, optimize=True
        )
        return output.getvalue(), fingerprint, [w, h]


def visually_duplicate(processed, record):
    """Catch near-identical renditions that survive the directional hash."""
    existing = CACHE / (record.get("hash", "") + ".jpg")
    if not existing.exists():
        return False
    with Image.open(io.BytesIO(processed)) as candidate, Image.open(existing) as cached:
        candidate = candidate.resize((64, 36), Image.Resampling.LANCZOS).convert("L")
        cached = cached.resize((64, 36), Image.Resampling.LANCZOS).convert("L")
        difference = sum(
            abs(left - right)
            for left, right in zip(candidate.tobytes(), cached.tobytes(), strict=True)
        ) / (64 * 36)
    return difference < 5


def photographic(meta):
    title = meta.get("title", "")
    if not re.search(
        r"nebula|galax|cluster|milky|aurora|saturn|jupiter|comet|moon|lunar|earth|andromeda|magellanic|\bNGC\b|\bIC\s*\d|messier|\bM\d|star|cosmic|solar|carina|deep field|supernova|universe|planet|mars|venus|mercury|neptune|uranus|pluto",
        title,
        re.I,
    ):
        return False
    if re.search(
        r"launch|astronaut|crew|portrait|selfie|conference|briefing|workshop|townhall|symposium|webinar|meeting|awards|ceremony|dedication|animation|student engagement|information center|moon to mars|engineer|technician|capsule|rocket|spacesuit|clean room|assembly|earth day|saturn v|press event|celebrat|anniversary|event|encounter|kennedy space center|artist concept|comet.*changes|beyond the deep field.*legacy|eagle with moon|moon joy|observing the features|moon venus conjunction|circulation cells|under jupiter.*cloud tops|x-rays detected|artemis ii approaches the moon|venus, earth and its moon, and mars|moon base.*update|en route to the moon",
        title,
        re.I,
    ):
        return False
    if "orion" in title.lower() and "nebula" not in title.lower():
        return False
    text = title + " " + meta.get("description", "")
    return not re.search(
        r"illustration|artist.?s? (?:concept|impression)|diagram|chart|annotat|infographic|"
        r"simulat|\bpanels?\b|collage|montage|\binset\b|spectrum|spectra|all.sky|"
        r"four famous|pentagon turns hexagon|glimpse the galaxy all the way|star map|map of|mapping",
        text,
        re.I,
    )


def download_image(meta):
    source_id = meta["nasa_id"]
    manifest = get_json(
        "https://images-api.nasa.gov/asset/" + urllib.parse.quote(source_id, safe="")
    )
    urls = [x["href"] for x in manifest["collection"]["items"]]
    originals = [
        u
        for u in urls
        if "~orig." in u
        and urllib.parse.urlsplit(u)
        .path.lower()
        .endswith((".jpg", ".jpeg", ".png", ".tif", ".tiff", ".webp"))
    ]
    if not originals:
        raise ValueError("no supported original")
    url = sorted(originals, key=lambda u: not u.lower().endswith((".jpg", ".jpeg")))[0]
    return url, fetch(url)


def ingest(item, catalog, downloaded=None):
    meta = item["data"][0]
    source_id = meta["nasa_id"]
    url, raw = downloaded if downloaded is not None else download_image(meta)
    if any(record.get("url") == url for record in catalog.values()):
        return "duplicate"
    raw_hash = hashlib.sha256(raw).hexdigest()
    if any(record.get("raw_hash") == raw_hash for record in catalog.values()):
        return "duplicate"
    processed, fingerprint, dimensions = normalize(raw)
    del raw
    digest = hashlib.sha256(processed).hexdigest()
    for record in catalog.values():
        if record.get("hash") == digest:
            return "duplicate"
        if record.get("fingerprint"):
            distance = (
                int(record["fingerprint"], 16) ^ int(fingerprint, 16)
            ).bit_count()
            if (
                distance <= 5
                or distance <= 24
                and visually_duplicate(processed, record)
            ):
                return "duplicate"
    name = digest + ".jpg"
    with lock("cache"):
        atomic(CACHE / name, processed)
        catalog[source_id] = {
            "url": url,
            "title": meta.get("title"),
            "credit": meta.get("secondary_creator", meta.get("center")),
            "hash": digest,
            "raw_hash": raw_hash,
            "fingerprint": fingerprint,
            "original_size": dimensions,
            "added": time.time(),
        }
        save(STATE / "catalog.json", catalog)
        with lock("notification"):
            pending = STATE / "notification.json"
            count = read(pending, {}).get("count", 0)
            save(pending, {"count": count + 1})
    try:
        atomic((CACHE / name).with_suffix(".css"), palette(CACHE / name))
    except Exception as error:
        LOG.warning("Palette precomputation failed: %s", error)
    with lock("cache"):
        current_state = read(STATE / "shuffle.json", {})
        current = current_state.get("current")
        seen = set(current_state.get("seen", []))
        cached = files()
        # Prefer evicting already-viewed old photos; protect the installed image.
        victims = sorted(
            (n for n in cached if n != current),
            key=lambda n: (n not in seen, (CACHE / n).stat().st_mtime),
        )
        for victim in victims[: max(0, len(cached) - SET["cache_limit"])]:
            (CACHE / victim).unlink(missing_ok=True)
            (CACHE / victim).with_suffix(".css").unlink(missing_ok=True)
    LOG.info(
        "Added %s (%s -> %sx%s)",
        meta.get("title", source_id),
        dimensions,
        *SET["desired_resolution"],
    )
    return "downloaded"


def notify_new_wallpapers():
    with lock("update", blocking=False) as acquired:
        if not acquired:
            return
        with lock("notification"):
            pending = STATE / "notification.json"
            count = read(pending, {}).get("count", 0)
            if not count:
                return
            try:
                # The imported session environment may outlive Hyprland itself.
                run(["hyprctl", "monitors"], timeout=3)
                run([
                    "hyprctl", "notify", "1", "15000", "rgb(89b4fa)",
                    f"New wallpapers: {count}",
                ], timeout=3)
            except (subprocess.SubprocessError, OSError) as error:
                LOG.info("Wallpaper notification deferred: %s", error)
                return
            pending.unlink(missing_ok=True)


def update(batch=None):
    with lock("update", blocking=False) as acquired:
        if not acquired:
            LOG.info("Updater already running")
            return
        CACHE.mkdir(parents=True, exist_ok=True)
        catalog = read(STATE / "catalog.json", {})
        progress = read(
            STATE / "updater.json", {"pages": {}, "rejected": {}, "term": 0}
        )
        counts = dict(found=0, downloaded=0, rejected=0, duplicate=0, errors=0)
        limit = (
            batch
            if batch is not None
            else (
                SET["fill_batch"]
                if len(files()) < SET["cache_limit"]
                else SET["update_batch"]
            )
        )
        terms = SET["search_terms"]
        LOG.info(
            "Update started: %s/%s cached, goal %s additions",
            len(files()),
            SET["cache_limit"],
            limit,
        )
        try:
            for offset in range(-1, len(terms)):
                term = terms[(progress["term"] + offset) % len(terms)]
                recent = offset == -1
                page = 1 if recent else progress["pages"].get(term, 1)
                params = urllib.parse.urlencode(
                    {
                        "title": term,
                        "media_type": "image",
                        "page_size": 100,
                        "page": page,
                        **(
                            {"year_start": str(int(time.strftime("%Y")) - 1)}
                            if recent
                            else {}
                        ),
                    }
                )
                try:
                    result = get_json("https://images-api.nasa.gov/search?" + params)[
                        "collection"
                    ]
                except (
                    urllib.error.URLError,
                    TimeoutError,
                    OSError,
                    ValueError,
                ) as error:
                    LOG.warning("NASA search %r page %s failed: %s", term, page, error)
                    counts["errors"] += 1
                    if counts["errors"] >= 3:
                        break
                    continue
                items = result["items"]
                LOG.info("NASA title=%r page=%s: %s candidates", term, page, len(items))
                random.shuffle(items)
                completed_page = True
                for item in items:
                    counts["found"] += 1
                    meta = item["data"][0]
                    sid = meta["nasa_id"]
                    if sid in catalog or sid in progress["rejected"]:
                        counts["duplicate"] += 1
                        continue
                    try:
                        if not photographic(meta):
                            raise ValueError("non-photographic/annotated content")
                        status = ingest(item, catalog)
                        counts[status] += 1
                        if status == "duplicate":
                            progress["rejected"][sid] = "duplicate"
                    except (urllib.error.URLError, TimeoutError) as error:
                        LOG.warning("NASA %s network error: %s", sid, error)
                        counts["errors"] += 1
                    except (
                        ValueError,
                        OSError,
                        Image.DecompressionBombError,
                        Image.DecompressionBombWarning,
                    ) as error:
                        # ENOSPC and other local I/O errors must not blacklist an image.
                        if isinstance(error, OSError) and error.errno is not None:
                            raise
                        progress["rejected"][sid] = str(error)
                        counts["rejected"] += 1
                        LOG.info("Rejected %s: %s", sid, error)
                    save(STATE / "updater.json", progress)
                    if (
                        counts["downloaded"] >= limit
                        or counts["found"] >= SET["candidates_per_run"]
                        or counts["errors"] >= 5
                    ):
                        completed_page = False
                        break
                if completed_page and not recent:
                    progress["pages"][term] = (
                        page + 1
                        if any(x.get("rel") == "next" for x in result.get("links", []))
                        else 1
                    )
                if (
                    counts["downloaded"] >= limit
                    or counts["found"] >= SET["candidates_per_run"]
                    or counts["errors"] >= 5
                ):
                    break
            progress["term"] = (progress["term"] + 1) % len(terms)
            save(STATE / "updater.json", progress)
        finally:
            LOG.info("Update finished: %s; cached=%s", counts, len(files()))
    notify_new_wallpapers()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command", choices=["next", "update", "theme", "notify", "workspace"]
    )
    parser.add_argument("action", nargs="?")
    parser.add_argument("action_id", nargs="?")
    parser.add_argument("--batch", type=int)
    args = parser.parse_args()
    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s"
    )
    try:
        if args.command == "update":
            update(args.batch)
        elif args.command == "notify":
            notify_new_wallpapers()
        elif args.command == "workspace":
            actions = {
                "init": workspace_initialize,
                "activate": workspace_activate,
                "next": workspace_next,
                "remove": lambda: workspace_remove(args.action_id),
                "watch": watch_workspaces,
            }
            if args.action not in actions:
                parser.error("workspace action must be init, activate, next, remove, or watch")
            if args.action == "remove" and not args.action_id:
                parser.error("workspace remove requires an ID")
            if args.action == "remove":
                actions["remove"] = lambda: workspace_remove(args.action_id)
            actions[args.action]()
        elif args.command == "theme":
            state = read(STATE / "shuffle.json", {})
            if state.get("current") in files():
                apply_palette(CACHE / state["current"])
        else:
            next_wallpaper()
    except Exception as error:
        LOG.error("%s failed: %s", args.command, error)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
