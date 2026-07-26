#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

import scene_sample_snapshot as snapshot


class SceneSampleSnapshotTests(unittest.TestCase):
    def test_create_and_verify_snapshot_ignores_derived_files(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-snapshot-") as directory:
            root = Path(directory)
            source_root = root / "source"
            sample = source_root / "123"
            sample.mkdir(parents=True)
            (sample / "project.json").write_text(
                json.dumps({"title": "Fixture", "file": "scene.json"}),
                encoding="utf-8",
            )
            (sample / "scene.pkg").write_bytes(b"PKGV")
            (sample / "texture.bin").write_bytes(b"texture")
            (sample / ".mywallpaperx-scene-interpretation.json").write_text("{}")
            output_root = root / "isolated"
            create_args = argparse.Namespace(
                source_root=source_root,
                output_root=output_root,
                name="fixture",
                interpretation_format=25,
            )

            self.assertEqual(snapshot.create_snapshot(create_args), 0)
            self.assertFalse(
                (
                    output_root
                    / "Scene/123/.mywallpaperx-scene-interpretation.json"
                ).exists()
            )
            matrix = json.loads((output_root / "matrix-probe.json").read_text())
            self.assertEqual(matrix["samples"][0]["expected_interpretation_format"], 25)
            verify_args = argparse.Namespace(
                manifest=output_root / "source-manifest.json"
            )
            self.assertEqual(snapshot.verify_snapshot(verify_args), 0)

            (output_root / "Scene/123/texture.bin").write_bytes(b"changed")
            self.assertEqual(snapshot.verify_snapshot(verify_args), 1)


if __name__ == "__main__":
    unittest.main()
