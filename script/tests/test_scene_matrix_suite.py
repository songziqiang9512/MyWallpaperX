#!/usr/bin/env python3

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_ROOT = Path(__file__).resolve().parents[1]
if str(SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPT_ROOT))

from scene_matrix_suite import (
    compact_suite_payload,
    load_scene_matrix,
    sha256,
)


class SceneMatrixSuiteTests(unittest.TestCase):
    def write_json(self, path: Path, payload: object) -> None:
        path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    def test_compact_suite_round_trips_exact_derived_matrix(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-matrix-suite-") as directory:
            root = Path(directory)
            base_path = root / "full.json"
            suite_path = root / "fixed.json"
            base = {
                "schema_version": 1,
                "name": "full",
                "samples": [
                    {"id": "1", "shared": 1, "full_only": 2},
                    {"id": "2", "shared": 2},
                ],
            }
            derived = {
                "schema_version": 1,
                "name": "fixed",
                "samples": [{"id": "1", "shared": 3, "fixed_only": 4}],
            }
            self.write_json(base_path, base)
            payload = compact_suite_payload(
                base_path,
                derived,
                suite_path=suite_path,
            )
            self.write_json(suite_path, payload)

            self.assertEqual(load_scene_matrix(suite_path), derived)
            self.assertEqual(payload["sample_ids"], ["1"])
            self.assertEqual(
                payload["sample_overrides"]["1"],
                {
                    "set": {"shared": 3, "fixed_only": 4},
                    "remove": ["full_only"],
                },
            )

    def test_suite_fails_when_base_changes_without_regeneration(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-matrix-suite-") as directory:
            root = Path(directory)
            base_path = root / "full.json"
            suite_path = root / "fixed.json"
            base = {
                "schema_version": 1,
                "name": "full",
                "samples": [{"id": "1", "value": 1}],
            }
            derived = {
                "schema_version": 1,
                "name": "fixed",
                "samples": [{"id": "1", "value": 1}],
            }
            self.write_json(base_path, base)
            self.write_json(
                suite_path,
                compact_suite_payload(base_path, derived, suite_path=suite_path),
            )
            base["samples"][0]["value"] = 2
            self.write_json(base_path, base)

            with self.assertRaisesRegex(ValueError, "base digest changed"):
                load_scene_matrix(suite_path)

    def test_suite_rejects_escape_duplicate_and_identity_overrides(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-matrix-suite-") as directory:
            root = Path(directory)
            base_path = root / "full.json"
            self.write_json(
                base_path,
                {
                    "schema_version": 1,
                    "name": "full",
                    "samples": [{"id": "1"}],
                },
            )
            cases = (
                (
                    {
                        "schema_version": 2,
                        "name": "fixed",
                        "base_matrix": "../outside.json",
                        "base_matrix_sha256": "unused",
                        "sample_ids": ["1"],
                    },
                    "escapes",
                ),
                (
                    {
                        "schema_version": 2,
                        "name": "fixed",
                        "base_matrix": "full.json",
                        "base_matrix_sha256": sha256(base_path),
                        "sample_ids": ["1", "1"],
                    },
                    "duplicate",
                ),
                (
                    {
                        "schema_version": 2,
                        "name": "fixed",
                        "base_matrix": "full.json",
                        "base_matrix_sha256": sha256(base_path),
                        "sample_ids": ["1"],
                        "sample_overrides": {"1": {"remove": ["id"]}},
                    },
                    "changes sample id",
                ),
            )
            for index, (payload, message) in enumerate(cases):
                with self.subTest(message=message):
                    suite_path = root / f"suite-{index}.json"
                    self.write_json(suite_path, payload)
                    with self.assertRaisesRegex(ValueError, message):
                        load_scene_matrix(suite_path)


if __name__ == "__main__":
    unittest.main()
