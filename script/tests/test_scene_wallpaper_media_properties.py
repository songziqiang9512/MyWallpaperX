#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "script"))

from scene_wallpaper_media_properties import (
    media_properties_callback_metrics,
    media_properties_expectation_failures,
)


class SceneWallpaperMediaPropertiesTests(unittest.TestCase):
    def test_exact_album_callback_is_parsed_and_checked(self) -> None:
        log = (
            "MWX SceneScript VM: target=text(layerID: 629, field: "
            "MyWallpaperX.SceneTextDynamicField.content) "
            "event=mediaPropertiesChanged generation=1 titleUTF8Bytes=5 "
            "artistUTF8Bytes=6 subTitleUTF8Bytes=4 albumTitleUTF8Bytes=7 "
            "albumArtistUTF8Bytes=8 genresUTF8Bytes=9 "
            "contentTypeUTF8Bytes=5 outputUTF8Bytes=8 route=generic-only"
        )
        callbacks = media_properties_callback_metrics(log)
        self.assertEqual(callbacks, [{
            "layer_id": 629,
            "generation": 1,
            "title_utf8_bytes": 5,
            "artist_utf8_bytes": 6,
            "sub_title_utf8_bytes": 4,
            "album_title_utf8_bytes": 7,
            "album_artist_utf8_bytes": 8,
            "genres_utf8_bytes": 9,
            "content_type_utf8_bytes": 5,
            "output_utf8_bytes": 8,
            "route": "generic-only",
        }])
        sample = {
            "expected_media_properties_callback_count": 1,
            "expected_media_properties_callbacks": [{
                "layer_id": 629,
                "generation": 1,
                "album_artist_utf8_bytes": 8,
                "output_utf8_bytes": 8,
                "route": "generic-only",
            }],
        }
        self.assertEqual(
            media_properties_expectation_failures(sample, callbacks), []
        )

    def test_missing_or_malformed_evidence_fails_closed(self) -> None:
        self.assertEqual(
            media_properties_expectation_failures(
                {"expected_media_properties_callback_count": 1}, []
            ),
            ["media properties callback count mismatch"],
        )
        self.assertEqual(
            media_properties_expectation_failures(
                {"expected_media_properties_callbacks": [{"layer_id": 1}]}, []
            ),
            ["invalid media properties callbacks"],
        )


if __name__ == "__main__":
    unittest.main()
