"""Typed media-properties runtime evidence for isolated Scene checks."""

from __future__ import annotations

import re
from typing import Any


MEDIA_PROPERTIES_CALLBACK_RE = re.compile(
    r"MWX SceneScript VM: target=text\(layerID: (?P<layer>\d+), "
    r"field: [^)]+\) event=mediaPropertiesChanged "
    r"generation=(?P<generation>\d+) "
    r"titleUTF8Bytes=(?P<title>\d+) artistUTF8Bytes=(?P<artist>\d+) "
    r"subTitleUTF8Bytes=(?P<sub_title>\d+) "
    r"albumTitleUTF8Bytes=(?P<album_title>\d+) "
    r"albumArtistUTF8Bytes=(?P<album_artist>\d+) "
    r"genresUTF8Bytes=(?P<genres>\d+) "
    r"contentTypeUTF8Bytes=(?P<content_type>\d+) "
    r"outputUTF8Bytes=(?P<output>\d+) route=(?P<route>\S+)"
)


def media_properties_callback_metrics(log_text: str) -> list[dict[str, Any]]:
    return [
        {
            "layer_id": int(match.group("layer")),
            "generation": int(match.group("generation")),
            "title_utf8_bytes": int(match.group("title")),
            "artist_utf8_bytes": int(match.group("artist")),
            "sub_title_utf8_bytes": int(match.group("sub_title")),
            "album_title_utf8_bytes": int(match.group("album_title")),
            "album_artist_utf8_bytes": int(match.group("album_artist")),
            "genres_utf8_bytes": int(match.group("genres")),
            "content_type_utf8_bytes": int(match.group("content_type")),
            "output_utf8_bytes": int(match.group("output")),
            "route": match.group("route"),
        }
        for match in MEDIA_PROPERTIES_CALLBACK_RE.finditer(log_text)
    ]


def media_properties_expectation_failures(
    sample: dict[str, Any],
    callbacks: list[dict[str, Any]],
) -> list[str]:
    failures: list[str] = []
    if "expected_media_properties_callback_count" in sample:
        expected = sample["expected_media_properties_callback_count"]
        if isinstance(expected, bool) or not isinstance(expected, int) or expected < 0:
            failures.append("invalid media properties callback count")
        elif len(callbacks) != expected:
            failures.append("media properties callback count mismatch")
    if "expected_media_properties_callbacks" not in sample:
        return failures
    expected_callbacks = sample["expected_media_properties_callbacks"]
    allowed = {
        "layer_id", "generation", "title_utf8_bytes", "artist_utf8_bytes",
        "sub_title_utf8_bytes", "album_title_utf8_bytes",
        "album_artist_utf8_bytes", "genres_utf8_bytes",
        "content_type_utf8_bytes", "output_utf8_bytes", "route",
    }
    if (
        not isinstance(expected_callbacks, list)
        or any(
            not isinstance(item, dict)
            or not {"layer_id", "generation", "route"}.issubset(item)
            or not set(item).issubset(allowed)
            for item in expected_callbacks
        )
    ):
        failures.append("invalid media properties callbacks")
        return failures
    ordered_expected = sorted(
        expected_callbacks, key=lambda item: (item["layer_id"], item["generation"])
    )
    ordered_actual = sorted(
        callbacks, key=lambda item: (item["layer_id"], item["generation"])
    )
    if len(ordered_expected) != len(ordered_actual) or any(
        any(actual.get(key) != value for key, value in expected.items())
        for expected, actual in zip(ordered_expected, ordered_actual, strict=False)
    ):
        failures.append("media properties callbacks mismatch")
    return failures
