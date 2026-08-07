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

from scene_real_test_fixture_config import load_fixture_config


class SceneRealTestFixtureConfigTests(unittest.TestCase):
    def write_json(self, path: Path, payload: object) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload), encoding="utf-8")

    def test_tracked_schema_two_resolves_ignored_local_paths(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-fixture-config-") as directory:
            root = Path(directory)
            tracked = root / "script/fixture.json"
            local = root / ".codex/fixture.local.json"
            self.write_json(tracked, {
                "schema_version": 2,
                "local_config": ".codex/fixture.local.json",
            })
            self.write_json(local, {
                "schema_version": 1,
                "sample_root": ".codex/samples/Scene",
                "runtime_homes": ".codex/run/runtime-homes",
                "report": ".codex/run/report.json",
            })

            resolved = load_fixture_config(tracked, root, environ={})
            self.assertEqual(resolved["schema_version"], 1)
            self.assertEqual(
                resolved["sample_root"],
                str((root / ".codex/samples/Scene").resolve()),
            )

    def test_environment_overrides_local_config(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-fixture-config-") as directory:
            root = Path(directory)
            tracked = root / "script/fixture.json"
            local = root / ".codex/fixture.local.json"
            self.write_json(tracked, {
                "schema_version": 2,
                "local_config": ".codex/fixture.local.json",
            })
            self.write_json(local, {
                "sample_root": ".codex/old/Scene",
            })
            replacement = root / "external-samples"

            resolved = load_fixture_config(
                tracked,
                root,
                environ={"MWX_SCENE_TEST_SAMPLE_ROOT": str(replacement)},
            )
            self.assertEqual(resolved["sample_root"], str(replacement.resolve()))

    def test_local_config_must_stay_inside_codex_workspace(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-fixture-config-") as directory:
            root = Path(directory)
            tracked = root / "script/fixture.json"
            self.write_json(tracked, {
                "schema_version": 2,
                "local_config": "outside.json",
            })

            with self.assertRaisesRegex(ValueError, "inside .codex"):
                load_fixture_config(tracked, root, environ={})

    def test_environment_mapping_cannot_drift_from_loader_contract(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-fixture-config-") as directory:
            root = Path(directory)
            tracked = root / "script/fixture.json"
            self.write_json(tracked, {
                "schema_version": 2,
                "local_config": ".codex/fixture.local.json",
                "environment": {"sample_root": "SOME_OTHER_VARIABLE"},
            })

            with self.assertRaisesRegex(ValueError, "environment mapping"):
                load_fixture_config(tracked, root, environ={})


if __name__ == "__main__":
    unittest.main()
