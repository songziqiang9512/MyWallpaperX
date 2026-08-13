#!/usr/bin/env python3

from __future__ import annotations

import argparse
import io
import json
import subprocess
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
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
        self.assertIn("test_document_role_index", gates[0].command)
        self.assertIn("test_scene_semantics_coverage", gates[0].command)
        self.assertIn("__scene_validation_no_scope_match__", gates[0].command)

    def test_non_scene_documentation_change_selects_repository_link_contract(self) -> None:
        gates, groups = verify.build_plan(
            ["docs/architecture/technology-stack-boundaries.md"],
            arguments(),
            self.registry,
        )
        self.assertEqual([gate.gate_id for gate in gates], ["focused-tests"])
        self.assertIn("documentation", groups)
        self.assertIn("test_document_role_index", gates[0].command)
        self.assertIn("test_scene_semantics_coverage", gates[0].command)

    def test_document_role_index_change_selects_role_and_link_contracts(self) -> None:
        gates, groups = verify.build_plan(
            ["docs/document-role-index.json"],
            arguments(),
            self.registry,
        )
        self.assertEqual([gate.gate_id for gate in gates], ["focused-tests"])
        self.assertIn("documentation", groups)
        self.assertIn("test_document_role_index", gates[0].command)
        self.assertIn("test_scene_semantics_coverage", gates[0].command)

    def test_shader_source_changes_select_source_set_conservation(self) -> None:
        paths = (
            "ShaderFrontend/SceneAuthoredShaderFrontend.swift",
            "ShaderPreparation/SceneAuthoredShaderPreparation.swift",
        )
        for path in paths:
            with self.subTest(path=path):
                gates, groups = verify.build_plan(
                    [
                        "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/"
                        + path
                    ],
                    arguments(),
                    self.registry,
                )
                self.assertIn("shader-source-set-conservation", groups)
                focused = next(
                    gate for gate in gates if gate.gate_id == "focused-tests"
                )
                self.assertIn("test_scene_swift_source_sets", focused.command)

    def test_authored_graph_change_selects_ir_admission_and_executor_contracts(self) -> None:
        gates, groups = verify.build_plan(
            [
                "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/"
                "AuthoredGraph/SceneGraphAdmissionCompiler.swift"
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("authored-graph", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        for module in (
            "test_scene_effect_render_graph",
            "test_scene_graph_admission_compiler",
            "test_scene_resolved_material_execution_capability",
            "test_scene_resolved_material_graph_executor",
        ):
            with self.subTest(module=module):
                self.assertIn(module, focused.command)

    def test_layer_dependency_change_selects_planning_pool_and_consumers(self) -> None:
        gates, groups = verify.build_plan(
            [
                "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/"
                "LayerDependencies/SceneDependencyRenderPlan.swift"
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("layer-dependencies", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        for module in (
            "test_scene_dependency_render_plan",
            "test_scene_named_render_target_pool",
            "test_scene_framebuffer_capture",
            "test_scene_utility_layers",
        ):
            with self.subTest(module=module):
                self.assertIn(module, focused.command)

    def test_effect_execution_change_selects_stage_graph_and_encoder_contracts(self) -> None:
        gates, groups = verify.build_plan(
            [
                "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/"
                "EffectExecution/SceneAuthoredEffectPipelineSet.swift"
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("effect-execution", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        for module in (
            "test_scene_authored_effect_execution",
            "test_scene_framebuffer_capture",
            "test_scene_graph_resource_pass_encoder",
            "test_scene_graph_texture_publication",
            "test_scene_resolved_material_execution_capability",
            "test_scene_resolved_material_graph_executor",
            "test_scene_resolved_material_pass_encoder",
        ):
            with self.subTest(module=module):
                self.assertIn(module, focused.command)

    def test_material_program_change_selects_schema_program_and_executor_contracts(self) -> None:
        gates, groups = verify.build_plan(
            [
                "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/"
                "MaterialProgram/SceneResolvedMaterialProgram.swift"
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("material-program", groups)
        self.assertIn("shader-source-set-conservation", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        self.assertIn("test_scene_swift_source_sets", focused.command)
        for module in (
            "test_scene_effect_texture_purposes",
            "test_scene_graph_texture_publication",
            "test_scene_material_program_census",
            "test_scene_resolved_material_execution_capability",
            "test_scene_resolved_material_graph_executor",
            "test_scene_resolved_material_pass_encoder",
            "test_scene_resolved_material_program_derivation",
            "test_scene_resolved_material_program_finalizer",
            "test_scene_resolved_material_template",
        ):
            with self.subTest(module=module):
                self.assertIn(module, focused.command)

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

    def test_integration_runs_scene_suite_and_requires_real_sample(self) -> None:
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
        self.assertEqual(runtime.status, "skipped")
        self.assertIn("CI has no private Workshop corpus", runtime.reason)

        for gate in gates:
            if gate.status == "planned":
                gate.status = "passed"
        payload = verify.validation_payload(
            arguments(
                phase="integration",
                ci=True,
                skip_runtime=True,
                reason="CI has no private Workshop corpus",
            ),
            ["MyWallpaperX/Core/SteamWorkshopScene/Format/SceneProject.swift"],
            {"format"},
            gates,
            execution="completed",
        )
        self.assertEqual(payload["validation_scope"], "structural-only")
        self.assertFalse(payload["closure_complete"])

    def test_all_scene_product_surfaces_trigger_integration_closure(self) -> None:
        paths = [
            "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneRuntime.swift",
            "MyWallpaperX/App/DebugScenePlaybackRunner+Performance.swift",
            (
                "MyWallpaperX/Modules/SteamWorkshop/Scene/"
                "SteamWorkshopSceneService+ScenePlayback.swift"
            ),
            "MyWallpaperX/Core/Playback/SystemAudioSceneSpectrumAnalyzer.swift",
        ]
        for path in paths:
            with self.subTest(path=path):
                gates, _ = verify.build_plan(
                    [path],
                    arguments(phase="integration"),
                    self.registry,
                )
                gate_ids = [gate.gate_id for gate in gates]
                self.assertIn("scene-all-tests", gate_ids)
                self.assertIn("targeted-sample", gate_ids)

    def test_integration_keeps_explicit_modules_alongside_scene_suite(self) -> None:
        gates, groups = verify.build_plan(
            ["MyWallpaperX/App/DebugScenePlaybackRunner.swift"],
            arguments(phase="integration"),
            self.registry,
        )
        self.assertIn("scene-debug-runner", groups)
        self.assertEqual(gates[0].gate_id, "focused-tests")
        self.assertEqual(gates[1].gate_id, "scene-all-tests")
        self.assertIn("test_scene_wallpaper_benchmark", gates[0].command)
        self.assertIn("__scene_validation_no_scope_match__", gates[0].command)

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
        targeted_output = targeted.command[targeted.command.index("--output-dir") + 1]
        matrix_output = matrix.command[matrix.command.index("--output-dir") + 1]
        self.assertEqual(targeted_output, "reports/targeted")
        self.assertEqual(matrix_output, "reports/fixed")
        self.assertNotEqual(targeted_output, matrix_output)

    def test_milestone_matrix_contract_without_tier_is_blocked(self) -> None:
        gates, groups = verify.build_plan(
            ["script/scene_wallpaper_benchmark.py"],
            arguments(phase="milestone"),
            self.registry,
        )
        self.assertIn("matrix", groups)
        blocker = gates[-1]
        self.assertEqual(blocker.gate_id, "matrix-tier-selection")
        self.assertEqual(blocker.status, "blocked")
        self.assertIn("matrix-tier", blocker.unresolved)

        with patch.object(verify.subprocess, "run") as run:
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                return_code = verify.main(
                    [
                        "--phase",
                        "milestone",
                        "--path",
                        "script/scene_wallpaper_benchmark.py",
                        "--run",
                    ]
                )
        self.assertEqual(return_code, 2)
        run.assert_not_called()

    def test_plan_json_marks_commands_as_not_executed(self) -> None:
        output = io.StringIO()
        with redirect_stdout(output):
            return_code = verify.main(
                [
                    "--path",
                    "docs/scene/semantics/coverage-ledger.md",
                    "--format",
                    "json",
                ]
            )
        self.assertEqual(return_code, 0)
        payload = json.loads(output.getvalue())
        self.assertEqual(payload["execution"], "not-run")
        self.assertFalse(payload["closure_complete"])
        self.assertEqual(payload["gates"][0]["status"], "planned")
        self.assertIsNone(payload["gates"][0]["return_code"])

    def test_gate_execution_records_passed_and_failed_states(self) -> None:
        passed = verify.Gate("passed", ("true",), "test", False)
        failed = verify.Gate("failed", ("false",), "test", False)
        with patch.object(
            verify.subprocess,
            "run",
            side_effect=[
                subprocess.CompletedProcess(("true",), 0),
                subprocess.CompletedProcess(("false",), 9),
            ],
        ):
            with redirect_stdout(io.StringIO()):
                return_code = verify.run_gates([passed, failed])
        self.assertEqual(return_code, 9)
        self.assertEqual(passed.status, "passed")
        self.assertEqual(passed.return_code, 0)
        self.assertEqual(failed.status, "failed")
        self.assertEqual(failed.return_code, 9)

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
