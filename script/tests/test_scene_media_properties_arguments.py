#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "script"))

from scene_wallpaper_media_event import append_media_properties_arguments


class SceneMediaPropertiesArgumentsTests(unittest.TestCase):
    def test_complete_public_event_fields_are_forwarded_atomically(self) -> None:
        command = ["MyWallpaperX"]
        failures: list[str] = []
        append_media_properties_arguments(
            command,
            "Track",
            "Artist",
            failures,
            sub_title="Live",
            album_title="Album",
            album_artist="Album Artist",
            genres="Rock,Pop",
            content_type="music",
        )
        self.assertEqual(failures, [])
        self.assertEqual(command, [
            "MyWallpaperX",
            "--mwx-debug-scene-media-title", "Track",
            "--mwx-debug-scene-media-artist", "Artist",
            "--mwx-debug-scene-media-sub-title", "Live",
            "--mwx-debug-scene-media-album-title", "Album",
            "--mwx-debug-scene-media-album-artist", "Album Artist",
            "--mwx-debug-scene-media-genres", "Rock,Pop",
            "--mwx-debug-scene-media-content-type", "music",
        ])

    def test_optional_field_without_required_identity_is_rejected(self) -> None:
        command = ["MyWallpaperX"]
        failures: list[str] = []
        append_media_properties_arguments(
            command, None, None, failures, album_title="Album"
        )
        self.assertEqual(
            failures, ["media properties require title and artist together"]
        )
        self.assertEqual(command, ["MyWallpaperX"])


if __name__ == "__main__":
    unittest.main()
