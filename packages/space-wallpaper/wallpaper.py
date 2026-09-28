#!/usr/bin/env python3
"""Offline shuffle-bag wallpapers; NASA acquisition is a separate command."""

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
CACHE = (
    Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))
    / "space-wallpaper"
)
WAYBAR = (
    Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "waybar"
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


def choose(state, available):
    available = set(available)
    current = state.get("current")
    seen = set(state.get("seen", [])) & available
    queue = [n for n in state.get("queue", []) if n in available and n not in seen]
    queue = list(dict.fromkeys(queue))
    additions = list(available - seen - set(queue))
    random.shuffle(additions)
    queue.extend(additions)
    if not queue:
        queue = list(available)
        random.shuffle(queue)
        seen = set()
    if not queue:
        return None, state
    if len(queue) > 1 and queue[0] == current:
        queue[0], queue[1] = queue[1], queue[0]
    # A removed/reintroduced current image must not cause an immediate repeat.
    if len(available) > 1 and queue == [current]:
        seen.add(current)
        queue = list(available - {current})
        random.shuffle(queue)
        seen = {current}
    selected = queue.pop(0)
    seen.add(selected)
    return selected, {
        "current": selected,
        "queue": queue,
        "seen": sorted(seen),
        "changed_at": time.time(),
    }


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
        atomic(WAYBAR / "colors.css", content)
        # Waybar monitors imports as well as style.css; touch also supports older builds.
        if (WAYBAR / "style.css").exists():
            (WAYBAR / "style.css").touch()
    except Exception as error:
        LOG.warning("Wallpaper installed; previous Waybar theme retained: %s", error)


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
    rendered = CACHE / "rendered" / (path.stem + ".bmp")
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
                selected, proposed = choose(state, available)
                path = CACHE / selected
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
            try:
                displayed = render_caption(path)
            except Exception as error:
                LOG.warning(
                    "Caption rendering failed; using clean wallpaper: %s", error
                )
                displayed = path
            try:
                run(["awww", "query"], timeout=3)
            except (subprocess.SubprocessError, OSError):
                run(
                    ["systemctl", "--user", "start", "space-wallpaper-daemon.service"],
                    timeout=10,
                )
                for _ in range(40):
                    try:
                        run(["awww", "query"], timeout=2)
                        break
                    except subprocess.SubprocessError:
                        time.sleep(0.1)
                else:
                    raise RuntimeError("Wallpaper daemon did not become ready")
            run(
                [
                    "awww",
                    "img",
                    str(displayed),
                    "--transition-type",
                    "fade",
                    "--transition-duration",
                    "0.5",
                    "--transition-fps",
                    "60",
                ],
                timeout=20,
            )
            os.replace(STATE / "pending.json", STATE / "shuffle.json")
            if displayed != path:
                for old in (CACHE / "rendered").iterdir():
                    if old != displayed:
                        old.unlink(missing_ok=True)
        apply_palette(path)


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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["next", "update", "theme"])
    parser.add_argument("--batch", type=int)
    args = parser.parse_args()
    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s"
    )
    try:
        if args.command == "update":
            update(args.batch)
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
