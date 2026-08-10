#!/usr/bin/env python3

from __future__ import annotations

import argparse
import sys
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT_ROOT = Path(__file__).resolve().parents[1]
if str(SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPT_ROOT))

import verify_scene_change as verify


def arguments(**overrides: object) -> argparse.Namespace:
    values: dict[str, object] = {
        "base": "HEAD",
        "phase": "checkpoint",
        "path": [],
        "run": False,
        "ci": False,
        "format": "text",
        "sample_id": [],
        "sample_root": None,
        "output_dir": None,
        "app": Path("app"),
        "matrix_tier": None,
        "skip_runtime": False,
        "reason": "",
    }
    values.update(overrides)
    return argparse.Namespace(**values)


class SceneValidationSelectionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.registry = verify.load_registry()

    def gate_ids(self, paths: list[str], args: argparse.Namespace) -> list[str]:
        gates, _ = verify.build_plan(paths, args, self.registry)
        return [gate.gate_id for gate in gates]

    def test_registry_requires_complete_lifecycle_metadata(self) -> None:
        required = {"risk", "trigger", "cost", "serialized", "retirement"}
        for gate_id, metadata in self.registry["gates"].items():
            with self.subTest(gate=gate_id):
                self.assertEqual(set(metadata), required)
                for field in required - {"serialized"}:
                    self.assertIsInstance(metadata[field], str)
                    self.assertTrue(metadata[field].strip())
                self.assertIsInstance(metadata["serialized"], bool)
                self.assertNotEqual(metadata["retirement"], "permanent")

    def test_docs_change_selects_link_contract_without_build(self) -> None:
        gates, groups = verify.build_plan(
            ["docs/scene/semantics/coverage-ledger.md"],
            arguments(),
            self.registry,
        )
        self.assertEqual([gate.gate_id for gate in gates], ["focused-tests"])
        self.assertIn("semantics", groups)
        self.assertIn("test_scene_semantics_coverage", gates[0].command)
        self.assertIn("__scene_validation_no_scope_match__", gates[0].command)

    def test_render_graph_checkpoint_reuses_build_wrapper_code_health(self) -> None:
        gates, groups = verify.build_plan(
            [
                "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/"
                "SceneGraphExecutionState.swift"
            ],
            arguments(),
            self.registry,
        )
        self.assertEqual(
            [gate.gate_id for gate in gates],
            ["focused-tests", "build-verify"],
        )
        self.assertIn("render-graph", groups)
        self.assertEqual(gates[-1].command, ("script/build_and_run.sh", "verify"))

    def test_ci_build_adds_code_health_without_local_wrapper(self) -> None:
        gates, _ = verify.build_plan(
            ["MyWallpaperX/Core/SteamWorkshopScene/Text/SceneText.swift"],
            arguments(ci=True),
            self.registry,
        )
        self.assertEqual(
            [gate.gate_id for gate in gates],
            ["focused-tests", "code-health", "build-verify"],
        )
        self.assertEqual(gates[-1].command[0], "xcodebuild")

    def test_fixture_config_does_not_trigger_corpus_compilation(self) -> None:
        gates, groups = verify.build_plan(
            ["script/scene_real_test_fixture_config.py"],
            arguments(),
            self.registry,
        )
        command = gates[0].command
        self.assertIn("real-fixture", groups)
        self.assertIn("test_scene_real_test_fixture_config", command)
        self.assertNotIn("test_scene_shader_preparation_census", command)
        self.assertNotIn("test_scene_material_program_census", command)

    def test_census_change_selects_only_its_corpus_contract(self) -> None:
        gates, groups = verify.build_plan(
            ["script/scene_shader_preparation_census.py"],
            arguments(),
            self.registry,
        )
        command = gates[0].command
        self.assertIn("shader-census", groups)
        self.assertIn("test_scene_shader_preparation_census", command)
        self.assertNotIn("test_scene_material_program_census", command)

    def test_integration_replaces_focused_tests_and_requires_real_sample(self) -> None:
        gates, _ = verify.build_plan(
            ["MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneTexture.swift"],
            arguments(phase="integration"),
            self.registry,
        )
        self.assertEqual(
            [gate.gate_id for gate in gates],
            ["scene-all-tests", "build-verify", "targeted-sample"],
        )
        self.assertIn("--sample-id", gates[-1].unresolved)

    def test_ci_can_record_why_runtime_is_unavailable(self) -> None:
        gates, _ = verify.build_plan(
            ["MyWallpaperX/Core/SteamWorkshopScene/Format/SceneProject.swift"],
            arguments(
                phase="integration",
                ci=True,
                skip_runtime=True,
                reason="CI has no private Workshop corpus",
            ),
            self.registry,
        )
        runtime = gates[-1]
        self.assertEqual(runtime.gate_id, "targeted-sample")
        self.assertIsNone(runtime.command)
        self.assertIsNone(runtime.unresolved)
        self.assertIn("CI has no private Workshop corpus", runtime.reason)

    def test_milestone_matrix_gate_requires_explicit_inputs(self) -> None:
        gates, _ = verify.build_plan(
            ["script/scene_wallpaper_full_sample_matrix.json"],
            arguments(
                phase="milestone",
                matrix_tier="full",
                reason="release candidate corpus verification",
            ),
            self.registry,
        )
        self.assertEqual(gates[-1].gate_id, "full45")
        self.assertIn("sample-root", gates[-1].unresolved)

    def test_milestone_matrix_does_not_inherit_targeted_sample_filter(self) -> None:
        gates, _ = verify.build_plan(
            ["MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneRuntime.swift"],
            arguments(
                phase="milestone",
                matrix_tier="fixed",
                reason="shared runtime milestone",
                sample_id=["123"],
                sample_root=Path("samples"),
                output_dir=Path("reports"),
            ),
            self.registry,
        )
        targeted = next(gate for gate in gates if gate.gate_id == "targeted-sample")
        matrix = next(gate for gate in gates if gate.gate_id == "fixed13")
        self.assertIn("--sample-id", targeted.command)
        self.assertNotIn("--sample-id", matrix.command)

    def test_explicit_paths_are_normalized_without_git_lookup(self) -> None:
        self.assertEqual(
            verify.changed_paths("HEAD", ["/script/a.py", "script/a.py"]),
            ["script/a.py"],
        )

    def test_deleted_test_path_is_not_selected_for_execution(self) -> None:
        deleted_test = "script/tests/test_scene_removed_contract.py"
        with patch.object(Path, "is_file", return_value=False):
            gates, _ = verify.build_plan([deleted_test], arguments(), self.registry)
        self.assertEqual(gates, [])


if __name__ == "__main__":
    unittest.main()
