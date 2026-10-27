#!/usr/bin/env python3
"""Focused contract tests for the Scene sample debug archive."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from script.scene_sample_debug_archive import _json, build_archive


class SceneSampleDebugArchiveTests(unittest.TestCase):
    def _write(self, path: Path, value: object) -> Path:
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def test_unreported_samples_are_explicit_and_reported_chain_is_not_visual_pass(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            samples = root / "Scene"
            (samples / "10").mkdir(parents=True)
            (samples / "20").mkdir()
            snapshot = self._write(root / "snapshot.json", {
                "samples": [
                    {
                        "sample_id": "10", "title": "Ten",
                        "project_sha256": "p10", "package_sha256": "k10",
                        "parse_state": "parsed", "object_count": 1,
                        "occurrence_count": 1, "visible_occurrence_count": 1,
                        "effect_instance_count": 0, "particle_layer_count": 0,
                        "dynamic_feature_counts": {},
                    },
                    {
                        "sample_id": "20", "title": "Twenty",
                        "project_sha256": "p20", "package_sha256": "k20",
                        "parse_state": "parsed", "object_count": 1,
                        "occurrence_count": 1, "visible_occurrence_count": 1,
                        "effect_instance_count": 0, "particle_layer_count": 0,
                        "dynamic_feature_counts": {},
                    },
                ]
            })
            report = self._write(root / "report.json", {
                "matrix": "identity.json", "matrix_sha256": "matrix",
                "app_identity": {"bundle_id": "test"},
                "samples": [{
                    "id": "10", "passed": True, "failures": [],
                    "exit_code": 0, "timed_out": False,
                    "evidence": {"ready_non_black": True, "after_non_black": True},
                    "runtime": {
                        "surfaces": 1,
                        "resolved_material_graph_execution": {
                            "has_evidence": True,
                            "executor": {"failure_count": 0},
                            "layer_routes": {
                                "accepted_layer_ids": [1],
                                "compositor_consumed_layer_ids": [1],
                                "next_frame_layer_ids": [1],
                            },
                            "graph_observations": {},
                        },
                    },
                }]
            })

            expected = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in (snapshot, report)}
            reads = {path: 0 for path in expected}
            original_open = Path.open

            def observed_open(path: Path, *args: object, **kwargs: object):
                if path in reads:
                    reads[path] += 1
                return original_open(path, *args, **kwargs)

            with patch.object(Path, "open", observed_open):
                archive = build_archive(samples, snapshot, [report])

            self.assertEqual(reads, {snapshot: 1, report: 1})
            self.assertEqual(archive["source"]["censusSnapshot"]["sha256"], expected[snapshot])
            self.assertEqual(archive["reports"][0]["sha256"], expected[report])
            self.assertEqual(archive["samples"][0]["evidence"]["report"]["sha256"], expected[report])

        self.assertEqual(archive["summary"]["sampleCount"], 2)
        self.assertEqual(archive["summary"]["reportedSampleCount"], 1)
        statuses = {item["id"]: item["runtime"]["status"] for item in archive["samples"]}
        self.assertEqual(statuses, {
            "10": "structural-chain-complete-visual-review",
            "20": "not-run",
        })
        self.assertEqual(
            archive["samples"][0]["nextAction"],
            "perform-authored-preview-and-next-frame-visual-review",
        )
        self.assertEqual(
            archive["claimBoundary"],
            "runtime-first-breakpoint-and-lifecycle-diagnostics-only-not-visual-correctness",
        )

    def test_json_uses_same_utf8_bytes_for_value_and_digest_and_keeps_errors(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "input.json"
            raw = '{\r\n  "title": "壁纸", "value": 1\r\n}\n'.encode("utf-8")
            path.write_bytes(raw)
            self.assertEqual(_json(path), ({"title": "壁纸", "value": 1}, hashlib.sha256(raw).hexdigest()))
            for encoding in ("utf-16", "utf-32"):
                path.write_bytes('{"value": 1}'.encode(encoding))
                with self.subTest(encoding=encoding), self.assertRaises(UnicodeDecodeError):
                    _json(path)
            path.write_text("[1, 2]", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "JSON document is not an object"):
                _json(path)
            path.write_text("{", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "cannot load JSON") as raised:
                _json(path)
            self.assertIsInstance(raised.exception.__cause__, json.JSONDecodeError)
            path.unlink()
            with self.assertRaisesRegex(ValueError, "cannot load JSON") as raised:
                _json(path)
            self.assertIsInstance(raised.exception.__cause__, OSError)


if __name__ == "__main__":
    unittest.main()
