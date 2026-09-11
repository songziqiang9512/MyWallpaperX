#!/usr/bin/env python3
"""Focused contract tests for the Scene sample debug archive."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from script.scene_sample_debug_archive import build_archive


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

            archive = build_archive(samples, snapshot, [report])

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


if __name__ == "__main__":
    unittest.main()
