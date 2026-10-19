"""Run with the package's Pillow-enabled Python: python test_wallpaper.py."""

import concurrent.futures
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

import wallpaper as w
from PIL import Image


class WallpaperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.patches = [
            patch.object(w, "STATE", self.root / "state"),
            patch.object(w, "CACHE", self.root / "cache"),
            patch.object(w, "PANEL", self.root / "quickshell" / "bar"),
        ]
        for p in self.patches:
            p.start()
        w.CACHE.mkdir()
        w.STATE.mkdir()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        self.temp.cleanup()

    def test_notification_waits_for_session_and_is_delivered_once(self):
        pending = w.STATE / "notification.json"
        w.save(pending, {"count": 3})
        with patch.object(w, "run", side_effect=OSError("no Hyprland")):
            w.notify_new_wallpapers()
        self.assertEqual(w.read(pending, {}), {"count": 3})
        with w.lock("update"), patch.object(w, "run") as run:
            w.notify_new_wallpapers()
            run.assert_not_called()
        with patch.object(w, "run") as run:
            w.notify_new_wallpapers()
            self.assertEqual("New wallpapers: 3", run.call_args.args[0][-1])
            self.assertFalse(pending.exists())
            w.notify_new_wallpapers()
            self.assertEqual(run.call_count, 2)
        w.save(pending, {"count": 2})
        with patch.object(w, "run", side_effect=[None, OSError("notify failed")]):
            w.notify_new_wallpapers()
        self.assertTrue(pending.exists())

    def test_random_title_groups_choose_title_before_image(self):
        names = ["a.jpg", "b.jpg", "c.jpg", "d.jpg"]
        catalog = {
            "one": {"hash": "a", "title": "Earth Observation"},
            "two": {"hash": "b", "title": "Earth Observation"},
            "three": {"hash": "c", "title": "Galaxy"},
            "four": {"hash": "d", "title": "Galaxy"},
        }
        with patch.object(w.secrets, "choice", side_effect=lambda values: values[0]) as choose:
            self.assertEqual(w.random_titled_image(names, catalog=catalog), "a.jpg")
            self.assertEqual(choose.call_count, 2)
        with patch.object(w.secrets, "choice", side_effect=lambda values: values[0]):
            # Excluding one member leaves the other title peer eligible.
            self.assertEqual(
                w.random_titled_image(names, {"a.jpg"}, catalog=catalog), "b.jpg"
            )

    def test_workspace_return_draws_again_and_duplicate_events_are_ignored(self):
        names = [letter * 64 + ".jpg" for letter in "abcde"]
        for name in names:
            (w.CACHE / name).touch()
        w.save(w.WORKSPACES, {
            "last_workspace": "1",
            "assignments": {"1": {"image": names[0]}, "2": {"image": names[1]}},
        })
        w.save(w.STATE / "shuffle.json", {"current": names[0]})
        with patch.object(w, "display_wallpaper") as display:
            w.workspace_activate("2", skip_if_current=True)
            first = w.read(w.STATE / "shuffle.json", {})["current"]
            self.assertNotIn(first, names[:2])
            w.workspace_activate("2", skip_if_current=True)
            self.assertEqual(display.call_count, 1)
            w.workspace_activate("1", skip_if_current=True)
            second = w.read(w.STATE / "shuffle.json", {})["current"]
            self.assertNotIn(second, {names[0], first})
            w.workspace_activate("2", skip_if_current=True)
            third = w.read(w.STATE / "shuffle.json", {})["current"]
            self.assertNotIn(third, {first, second})
            self.assertEqual(display.call_count, 3)

    def test_workspace_display_failure_preserves_state(self):
        for letter in "abc":
            (w.CACHE / (letter * 64 + ".jpg")).touch()
        state = {"last_workspace": "1", "assignments": {"1": {"image": "a" * 64 + ".jpg"}}}
        w.save(w.WORKSPACES, state)
        with patch.object(w, "display_wallpaper", side_effect=OSError("unavailable")):
            with self.assertRaises(OSError):
                w.workspace_activate("2")
        self.assertEqual(w.read(w.WORKSPACES, {}), state)

    def test_random_title_groups_handle_empty_single_and_cache_changes(self):
        self.assertIsNone(w.random_titled_image([], catalog={}))
        self.assertIsNone(w.random_titled_image(["one"], {"one"}, catalog={}))
        self.assertEqual(w.random_titled_image(["one"], catalog={}), "one")
        self.assertEqual(w.random_titled_image(["new"], {"removed"}, catalog={}), "new")

    def test_large_title_pack_has_one_entry_in_group_draw(self):
        names = [f"earth{i}.jpg" for i in range(10)] + ["galaxy.jpg"]
        catalog = {name: {"hash": Path(name).stem, "title": "Earth Observation"}
                   for name in names[:-1]}
        catalog["galaxy"] = {"hash": "galaxy", "title": "Galaxy"}
        with patch.object(w.secrets, "choice", side_effect=lambda values: values[0]) as choice:
            w.random_titled_image(names, catalog=catalog)
        self.assertEqual(len(choice.call_args_list[0].args[0]), 2)
        self.assertEqual(len(choice.call_args_list[1].args[0]), 10)

    def raw(self, size, color="navy"):
        buf = io.BytesIO()
        Image.new("RGB", size, color).save(buf, "JPEG")
        return buf.getvalue()

    def test_resolution_and_no_upscale(self):
        for size in [(2560, 1440), (2160, 3840), (4000, 4000), (7000, 2160)]:
            with self.assertRaises(ValueError):
                w.normalize(self.raw(size))
        normalized, _, original = w.normalize(self.raw((4000, 2500)))
        self.assertEqual(Image.open(io.BytesIO(normalized)).size, (3840, 2160))
        self.assertEqual(original, [4000, 2500])

    def test_only_astronomical_photographs(self):
        for title in [
            "Orion cockpit",
            "James Webb Space Telescope Briefing",
            "Saturn V Launch",
            "Earth Day Celebration",
            "Galaxy illustration",
            "Ancient Earth Alien Earths Event",
            "First Comet Encounter",
            "Aurora Borealis at Kennedy Space Center",
            "It Raining Comets Artist Concept",
            "Comet 67P Changes",
            "Beyond the Deep Field: Hubble's Legacy and the Future of Cosmic Exploration",
            "Moon to Mars Architecture Workshop",
            "Moon to Mars Townhall",
            "Earth Selfie",
            "Atmospheric Circulation Cells on Earth and Jupiter",
            "Watts on the Moon Challenge Awards Ceremony",
            "NASA's COLDArm Operating on the Moon (Animation)",
            "Earth Information Center Student Engagement",
        ]:
            self.assertFalse(w.photographic({"title": title}))
        self.assertFalse(
            w.photographic(
                {
                    "title": "A spiral galaxy",
                    "description": "The left panel shows a diagram.",
                }
            )
        )
        for title in [
            "The Orion Nebula",
            "Hubble views Andromeda galaxy",
            "Earth from space",
            "Webb's First Deep Field",
        ]:
            self.assertTrue(w.photographic({"title": title}))

    def test_corrupt_download(self):
        with self.assertRaises(OSError):
            w.normalize(b"not an image")

    def test_caption_uses_catalog_and_preserves_original(self):
        path = w.CACHE / ("a" * 64 + ".jpg")
        original = self.raw((3840, 2160), "white")
        path.write_bytes(original)
        w.save(
            w.STATE / "catalog.json",
            {
                "NASA-TEST": {
                    "hash": path.stem,
                    "title": "A very long view of a distant galaxy " * 8,
                    "credit": "NASA / JPL-Caltech",
                }
            },
        )
        with patch.object(w, "FONT", None):
            rendered = w.render_caption(path)
        self.assertEqual(path.read_bytes(), original)
        self.assertEqual(rendered.suffix, ".bmp")
        with Image.open(rendered) as image:
            self.assertEqual(image.size, (3840, 2160))
            self.assertNotEqual(image.getpixel((10, 2150)), (255, 255, 255))
            self.assertEqual(image.getpixel((10, 10)), (255, 255, 255))

        missing = w.CACHE / ("b" * 64 + ".jpg")
        missing.write_bytes(original)
        self.assertEqual(w.render_caption(missing), missing)

    def test_untrusted_urls(self):
        for url in [
            "file:///etc/passwd",
            "https://nasa.gov.evil.test/x",
            "https://evil.test/x",
            "https://fakenasa.gov/x",
        ]:
            with self.assertRaises(ValueError):
                w.checked_url(url)

    def test_atomic_failure_retains_old_file(self):
        path = self.root / "example"
        w.atomic(path, "old")
        with patch.object(w.os, "replace", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                w.atomic(path, "new")
        self.assertEqual(path.read_text(), "old")
        self.assertFalse(list(self.root.glob(".tmp-*")))

    def test_network_failure_retains_state(self):
        w.save(w.STATE / "shuffle.json", {"current": "old"})
        with patch.object(w, "get_json", side_effect=urllib.error.URLError("offline")):
            w.update(1)
        self.assertEqual(w.read(w.STATE / "shuffle.json", {}), {"current": "old"})
        self.assertEqual(w.files(), [])

    def test_http_error_retains_cache(self):
        old = w.CACHE / ("a" * 64 + ".jpg")
        old.write_bytes(b"unchanged")
        with patch.object(
            w,
            "get_json",
            side_effect=urllib.error.HTTPError("url", 503, "Unavailable", {}, None),
        ):
            w.update(1)
        self.assertEqual(old.read_bytes(), b"unchanged")

    def test_dedup_and_current_protection(self):
        item = {"data": [{"nasa_id": "one", "title": "Nebula"}]}
        manifest = {
            "collection": {
                "items": [{"href": "https://images-assets.nasa.gov/one~orig.jpg"}]
            }
        }
        catalog = {}
        with (
            patch.object(w, "get_json", return_value=manifest),
            patch.object(w, "fetch", return_value=self.raw((3840, 2160))),
            patch.object(w, "palette", return_value="css"),
        ):
            self.assertEqual(w.ingest(item, catalog), "downloaded")
            item["data"][0]["nasa_id"] = "two"
            self.assertEqual(w.ingest(item, catalog), "duplicate")
        self.assertEqual(w.read(w.STATE / "notification.json", {}), {"count": 1})
        self.assertEqual(len(w.files()), 1)
        old = w.files()[0]
        w.save(w.STATE / "shuffle.json", {"current": old})
        with (
            patch.dict(w.SET, {"cache_limit": 1}),
            patch.object(w, "get_json", return_value=manifest),
            patch.object(w, "fetch", return_value=b"different source"),
            patch.object(
                w, "normalize", return_value=(b"new JPEG", "f" * 64, [3840, 2160])
            ),
            patch.object(w, "palette", return_value="css"),
        ):
            manifest["collection"]["items"][0]["href"] = (
                "https://images-assets.nasa.gov/two~orig.jpg"
            )
            self.assertEqual(w.ingest(item, catalog), "downloaded")
        self.assertEqual(w.read(w.STATE / "notification.json", {}), {"count": 2})
        self.assertTrue((w.CACHE / old).exists())
        self.assertEqual(len(w.files()), 1)

    def test_near_identical_renditions_are_duplicates(self):
        original = self.raw((3840, 2160), "navy")
        processed, fingerprint, _ = w.normalize(original)
        digest = w.hashlib.sha256(processed).hexdigest()
        w.atomic(w.CACHE / (digest + ".jpg"), processed)
        record = {"hash": digest, "fingerprint": fingerprint}
        self.assertTrue(w.visually_duplicate(self.raw((3840, 2160), "navy"), record))
        self.assertFalse(w.visually_duplicate(self.raw((3840, 2160), "red"), record))

    def test_offline_switch_and_theme_failure(self):
        for i, color in enumerate(["navy", "red", "green"]):
            (w.CACHE / (str(i) * 64 + ".jpg")).write_bytes(
                self.raw((3840, 2160), color)
            )
        with (
            patch.object(
                w, "run", return_value=subprocess.CompletedProcess([], 0, "", "")
            ),
            patch.object(w, "fetch", side_effect=AssertionError("network on switch")),
            patch.object(w, "palette", side_effect=RuntimeError("matugen failed")),
        ):
            history = []
            for _ in range(3):
                w.next_wallpaper()
                history.append(w.read(w.STATE / "shuffle.json", {})["current"])
        self.assertTrue(all(a != b for a, b in zip(history, history[1:])))

    def test_backend_failure_does_not_consume_queue(self):
        (w.CACHE / ("a" * 64 + ".jpg")).write_bytes(self.raw((3840, 2160)))
        old = {"current": "before"}
        w.save(w.STATE / "shuffle.json", old)
        with patch.object(w, "run", side_effect=OSError("daemon unavailable")):
            with self.assertRaises(OSError):
                w.next_wallpaper()
        self.assertEqual(w.read(w.STATE / "shuffle.json", {}), old)

    def test_lock_coalesces_concurrent_requests(self):
        with w.lock("switch"):

            def contender():
                with w.lock("switch", blocking=False) as acquired:
                    return acquired

            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                self.assertEqual(
                    list(pool.map(lambda _: contender(), range(20))), [False] * 20
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
