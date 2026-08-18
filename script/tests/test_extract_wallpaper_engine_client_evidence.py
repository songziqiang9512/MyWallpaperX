#!/usr/bin/env python3

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

import extract_wallpaper_engine_client_evidence as extractor


class ClientRootTests(unittest.TestCase):
    def test_default_client_root_uses_repository_reference_project(self) -> None:
        self.assertEqual(
            extractor.DEFAULT_CLIENT_ROOT,
            REPOSITORY_ROOT / "Reference Project/wallpaper_engine",
        )


class ChangelogExtractionTests(unittest.TestCase):
    def write_scripts_js(self, directory: Path, body: str) -> Path:
        path = directory / "scripts.js"
        path.write_text(body, encoding="utf-8")
        return path

    def test_pairs_headlines_with_bodies_and_parses_entries(self) -> None:
        body = (
            'x<div class="changelogHeadline">REV 4401</div> '
            '<pre class="changelogBody">- Locale updates.\\n</pre>'
            '<div class="changelogHeadline">REV 4400</div> '
            '<pre class="changelogBody">- First change.\\n- Second\\'
            "'s change.\\n</pre>"
        )
        with tempfile.TemporaryDirectory() as tmp:
            payload = extractor.extract_changelog(
                self.write_scripts_js(Path(tmp), body)
            )
        self.assertEqual(payload["revisionCount"], 2)
        self.assertEqual(payload["entryCount"], 3)
        self.assertEqual(payload["revisions"][0]["revision"], 4401)
        self.assertEqual(payload["revisions"][0]["entries"], ["Locale updates."])
        self.assertEqual(
            payload["revisions"][1]["entries"],
            ["First change.", "Second's change."],
        )

    def test_mismatched_headline_and_body_counts_fail_closed(self) -> None:
        body = (
            '<div class="changelogHeadline">REV 1</div> '
            '<pre class="changelogBody">- a\\n</pre>'
            '<div class="changelogHeadline">REV 2</div>'
        )
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(SystemExit):
                extractor.extract_changelog(self.write_scripts_js(Path(tmp), body))


class LocaleExtractionTests(unittest.TestCase):
    def test_collects_en_us_tables_and_language_count(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            locale_dir = Path(tmp)
            (locale_dir / "ui_en-us.json").write_text(
                json.dumps({"ui_editor_effect_blur_title": "Blur"}),
                encoding="utf-8",
            )
            (locale_dir / "ui_de-de.json").write_text("{}", encoding="utf-8")
            (locale_dir / "core_en-us.json").write_text(
                json.dumps({"core_tray_settings": "Settings"}), encoding="utf-8"
            )
            payload = extractor.extract_locale(locale_dir)
        self.assertEqual(payload["tables"]["ui_en-us.json"]["keyCount"], 1)
        self.assertEqual(payload["tables"]["core_en-us.json"]["keyCount"], 1)
        self.assertEqual(payload["languageCount"], 2)
        self.assertEqual(
            payload["strings"]["ui_en-us.json"]["ui_editor_effect_blur_title"],
            "Blur",
        )


class BinaryManifestTests(unittest.TestCase):
    def test_records_bin_files_and_top_level_executables(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            client_root = Path(tmp)
            (client_root / "bin").mkdir()
            (client_root / "bin/scenescript64.dll").write_bytes(b"dll")
            (client_root / "wallpaper64.exe").write_bytes(b"exe")
            payload = extractor.extract_binary_manifest(client_root)
        paths = {entry["path"] for entry in payload["files"]}
        self.assertEqual(paths, {"bin/scenescript64.dll", "wallpaper64.exe"})
        for entry in payload["files"]:
            self.assertEqual(len(entry["sha256"]), 64)
            self.assertGreater(entry["bytes"], 0)


if __name__ == "__main__":
    unittest.main()
