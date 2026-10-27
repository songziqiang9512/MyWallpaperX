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
            marker = sample / ".mywallpaperx-steam-version.json"
            marker.write_text('{"installation":"source-only"}')
            neighbor = sample / (marker.name + ".author")
            neighbor.write_bytes(b"authored neighbor")
            output_root = root / "isolated"
            create_args = argparse.Namespace(
                source_root=source_root,
                output_root=output_root,
                name="fixture",
                runtime_evidence_schema=1,
            )

            self.assertEqual(snapshot.create_snapshot(create_args), 0)
            self.assertFalse(
                (
                    output_root
                    / "Scene/123/.mywallpaperx-scene-interpretation.json"
                ).exists()
            )
            copied = output_root / "Scene/123"
            self.assertFalse((copied / marker.name).exists())
            self.assertEqual((copied / neighbor.name).read_bytes(), neighbor.read_bytes())
            self.assertEqual(marker.read_text(), '{"installation":"source-only"}')
            matrix = json.loads((output_root / "matrix-probe.json").read_text())
            self.assertEqual(
                matrix["samples"][0]["expected_runtime_evidence_schema"], 1
            )
            verify_args = argparse.Namespace(
                manifest=output_root / "source-manifest.json"
            )
            self.assertEqual(snapshot.verify_snapshot(verify_args), 0)

            (output_root / "Scene/123/texture.bin").write_bytes(b"changed")
            self.assertEqual(snapshot.verify_snapshot(verify_args), 1)

    def test_loose_snapshot_keeps_tree_identity_without_fabricating_package(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-loose-snapshot-") as directory:
            root = Path(directory)
            sample = root / "source/124"
            sample.mkdir(parents=True)
            (sample / "project.json").write_text('{"type":"scene","file":"scene.json"}')
            (sample / "scene.json").write_text('{"objects":[]}')
            (sample / "authored.bin").write_bytes(b"loose content")
            missing_project = root / "source/125"
            missing_project.mkdir()
            output = root / "isolated"
            self.assertEqual(snapshot.create_snapshot(argparse.Namespace(
                source_root=root / "source", output_root=output,
                name="loose", runtime_evidence_schema=1,
            )), 0)
            manifest = json.loads((output / "source-manifest.json").read_text())
            matrix = json.loads((output / "matrix-probe.json").read_text())
            row, probe = manifest["samples"][0], matrix["samples"][0]
            self.assertEqual(manifest["skipped"], [{"id": "125", "reason": "missing project.json"}])
            for value in (row, probe):
                self.assertIsNone(value["package_file"])
                self.assertIsNone(value["package_sha256"])
                self.assertEqual(value["tree_sha256"], snapshot.tree_manifest(sample)[0])
            copied = output / "Scene/124"
            self.assertEqual(snapshot.tree_manifest(sample), snapshot.tree_manifest(copied))
            args = argparse.Namespace(manifest=output / "source-manifest.json")
            self.assertEqual(snapshot.verify_snapshot(args), 0)
            (copied / "authored.bin").write_bytes(b"changed")
            self.assertEqual(snapshot.verify_snapshot(args), 1)
            (copied / "authored.bin").write_bytes(b"loose content")
            (sample / "scene.json").write_text('{"objects":[1]}')
            self.assertEqual(snapshot.verify_snapshot(args), 1)


if __name__ == "__main__":
    unittest.main()
