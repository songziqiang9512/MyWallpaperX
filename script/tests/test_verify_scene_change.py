#!/usr/bin/env python3

from __future__ import annotations

import argparse
import copy
import io
import importlib
import json
import subprocess
import sys
import tempfile
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
        "app": Path("/usr/bin/true"),
        "matrix_tier": None,
        "skip_runtime": False,
        "reason": "",
    }
    values.update(overrides)
    return argparse.Namespace(**values)


def missing_registry_modules(registry: dict, tests_directory: Path) -> list[str]:
    return sorted({f"{group['id']}: {module}"
                   for group in registry['path_groups']
                   for module in group.get('modules', [])
                   if not (tests_directory / f'{module}.py').is_file()})


class SceneValidationSelectionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.registry = verify.load_registry()

    def gate_ids(self, paths: list[str], args: argparse.Namespace) -> list[str]:
        gates, _ = verify.build_plan(paths, args, self.registry)
        return [gate.gate_id for gate in gates]

    def test_new_governance_gates_follow_real_authority_inputs(self) -> None:
        new_gates = {'scene-dependencies', 'document-health', 'repository-residue'}
        new_gates.add('repository-debt')  # Retired gate must stay absent from every route.
        cases = [
            ('docs/README.md', {'document-health'}),
            ('AGENTS.md', {'document-health'}),
            ('MyWallpaperX/Core/SteamWorkshopScene/AGENTS.md', {'document-health', 'repository-residue'}),
            ('MyWallpaperX/Core/SteamWorkshopScene/Format/SceneProject.swift', {'scene-dependencies', 'repository-residue'}),
            ('MyWallpaperX/App/AppDelegate.swift', {'repository-residue'}),
            ('SteamService/WorkshopDownloader.cs', {'repository-residue'}),
            ('script/scene_source_layout.json', set()),
            ('script/scene_dependency_baseline.json', {'scene-dependencies'}),
            ('script/document_health_baseline.json', {'document-health'}),
            ('script/tests/test_document_health.py', {'scene-dependencies', 'document-health'}),
            ('script/scene_wallpaper_benchmark.py', set()),
        ]
        for path, expected in cases:
            for phase in ('inner', 'checkpoint'):
                with self.subTest(path=path, phase=phase):
                    actual = set(self.gate_ids([path], arguments(phase=phase))) & new_gates
                    self.assertEqual(actual, expected)

    def test_governance_ratcheting_commands_preserve_the_requested_base(self) -> None:
        gates, _ = verify.build_plan([
            'script/scene_source_layout.json', 'docs/document-role-index.json',
            'script/scene_dependency_baseline.json',
        ], arguments(base='review-base', phase='inner'), self.registry)
        commands = {gate.gate_id: gate.command for gate in gates}
        self.assertEqual(commands['scene-dependencies'], (sys.executable, '-B',
                         'script/check_scene_dependencies.py', '--check', '--base-ref', 'review-base'))
        self.assertEqual(commands['document-health'], (sys.executable, '-B',
                         'script/document_health.py', '--check', '--base', 'review-base'))
        self.assertNotIn('repository-debt', commands)
        self.assertNotIn('repository-residue', commands)

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

    def test_every_registry_path_group_references_existing_modules(self) -> None:
        self.assertEqual(missing_registry_modules(self.registry, SCRIPT_ROOT / 'tests'), [])

    def test_deleted_test_audit_rejects_stale_reference_in_unmatched_group(self) -> None:
        registry = copy.deepcopy(self.registry)
        registry['path_groups'].append({
            'id': 'unmatched-product-fixture',
            'patterns': ['MyWallpaperX/UnchangedFixture.swift'],
            'modules': ['test_removed_fixture'],
        })
        gates, groups = verify.build_plan(
            ['script/tests/test_removed_fixture.py'], arguments(), registry)
        self.assertNotIn('unmatched-product-fixture', groups)
        self.assertIn('test_verify_scene_change', gates[0].command)
        self.assertEqual(missing_registry_modules(registry, SCRIPT_ROOT / 'tests'),
                         ['unmatched-product-fixture: test_removed_fixture'])

    def test_docs_change_selects_link_contract_without_build(self) -> None:
        gates, groups = verify.build_plan(
            ["docs/scene/capabilities/coverage-ledger.md"],
            arguments(),
            self.registry,
        )
        self.assertEqual([gate.gate_id for gate in gates], ["focused-tests", "document-links", "repository-artifacts", "document-health"])
        self.assertNotIn("semantics", groups)
        self.assertIn("documentation", groups)
        self.assertIn("test_document_role_index", gates[0].command)
        for module in ("test_scene_semantics_coverage", "test_scene_swift_source_sets", "test_source_relocations"):
            self.assertNotIn(module, gates[0].command)
        self.assertNotIn("__scene_validation_no_scope_match__", gates[0].command)
        self.assertNotIn("--keyword", gates[0].command)

    def test_inner_docs_gate_skips_repository_wide_link_walk(self) -> None:
        gates, _ = verify.build_plan(
            ["docs/scene/development/development-workflow.md"],
            arguments(phase="inner"),
            self.registry,
        )
        self.assertEqual([gate.gate_id for gate in gates], ["focused-tests", "repository-artifacts", "document-health"])
        self.assertIn("test_document_role_index", gates[0].command)
        self.assertIn("test_scene_governance_contract", gates[0].command)
        self.assertNotIn("test_scene_semantics_coverage", gates[0].command)

    def test_non_scene_documentation_change_selects_repository_link_contract(self) -> None:
        gates, groups = verify.build_plan(
            ["docs/architecture/technology-stack-boundaries.md"],
            arguments(),
            self.registry,
        )
        self.assertEqual([gate.gate_id for gate in gates], ["focused-tests", "document-links", "repository-artifacts", "document-health"])
        self.assertIn("documentation", groups)
        self.assertIn("test_document_role_index", gates[0].command)
        self.assertNotIn("test_scene_semantics_coverage", gates[0].command)

    def test_document_role_index_change_selects_role_and_link_contracts(self) -> None:
        gates, groups = verify.build_plan(
            ["docs/document-role-index.json"],
            arguments(),
            self.registry,
        )
        self.assertEqual([gate.gate_id for gate in gates], ["focused-tests", "document-links", "repository-artifacts", "document-health"])
        self.assertIn("documentation", groups)
        self.assertIn("test_document_role_index", gates[0].command)
        self.assertNotIn("test_scene_semantics_coverage", gates[0].command)

    def test_repository_skill_change_selects_governance_contract(self) -> None:
        gates, groups = verify.build_plan(
            [".agents/skills/mywallpaperx-maintainer/SKILL.md"],
            arguments(),
            self.registry,
        )
        self.assertEqual([gate.gate_id for gate in gates], ["focused-tests", "repository-artifacts"])
        self.assertIn("repository-skill-governance", groups)
        self.assertIn("test_scene_governance_contract", gates[0].command)

    def test_root_governance_change_selects_repository_contracts(self) -> None:
        gates, groups = verify.build_plan(
            ["AGENTS.md"],
            arguments(),
            self.registry,
        )
        self.assertEqual([gate.gate_id for gate in gates], ["focused-tests", "scene-structure", "document-links", "document-health"])
        self.assertIn("repository-governance", groups)
        for module in (
            "test_document_role_index",
            "test_scene_governance_contract",
        ):
            with self.subTest(module=module):
                self.assertIn(module, gates[0].command)

    def test_release_workflow_change_selects_operational_contract(self) -> None:
        gates, groups = verify.build_plan(
            [".github/workflows/build.yml"],
            arguments(),
            self.registry,
        )
        self.assertEqual([gate.gate_id for gate in gates], ["focused-tests", "scene-structure", "document-links", "app-debug-layout", "repository-artifacts", "repository-residue"])
        self.assertIn("release-workflow-governance", groups)
        self.assertIn("test_document_role_index", gates[0].command)

    def test_unmapped_change_is_blocked_instead_of_succeeding_with_zero_gates(self) -> None:
        gates, groups = verify.build_plan(
            ["script/unmapped_fixture.json"],
            arguments(),
            self.registry,
        )
        self.assertEqual(groups, set())
        self.assertEqual([gate.gate_id for gate in gates], ["repository-artifacts", "unmapped-change"])
        self.assertEqual(gates[-1].status, "blocked")

    def test_unmapped_change_remains_blocked_beside_mapped_change(self) -> None:
        gates, _ = verify.build_plan(
            ["docs/README.md", "script/unmapped_fixture.json"],
            arguments(),
            self.registry,
        )
        self.assertIn("focused-tests", [gate.gate_id for gate in gates])
        self.assertEqual(gates[-1].gate_id, "unmapped-change")
        self.assertEqual(gates[-1].status, "blocked")

    def test_capability_family_map_selects_capability_census_gate(self) -> None:
        gates, groups = verify.build_plan(
            ["script/scene_capability_family_map.json"],
            arguments(phase="inner"),
            self.registry,
        )
        self.assertEqual([gate.gate_id for gate in gates], ["focused-tests", "repository-artifacts"])
        self.assertIn("capability-census", groups)
        self.assertIn("test_scene_capability_census", gates[0].command)

    def test_scene_daemon_change_selects_protocol_and_launch_contracts(self) -> None:
        gates, groups = verify.build_plan(
            [
                'MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonRuntime.swift'
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("scene-daemon-runtime", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        self.assertIn("test_scene_daemon_protocol", focused.command)
        self.assertIn("test_scene_wallpaper_async_launch", focused.command)

    def test_daemon_kit_change_selects_shared_line_framing_contract(self) -> None:
        gates, groups = verify.build_plan(
            ["MyWallpaperX/Core/DaemonKit/DaemonNewlineJSON.swift"],
            arguments(),
            self.registry,
        )
        self.assertIn("daemon-line-framing", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        self.assertIn("test_daemon_line_framing", focused.command)

    def test_scene_daemon_client_change_selects_control_plane_contracts(self) -> None:
        for path in (
            "MyWallpaperX/App/Debug/DebugSceneDaemonClientRunner.swift",
            "MyWallpaperX/App/Debug/DebugSceneDaemonSwitchControlPolicy.swift",
        ):
            with self.subTest(path=path):
                gates, groups = verify.build_plan(
                    [path],
                    arguments(),
                    self.registry,
                )
                self.assertIn("scene-daemon-control-plane", groups)
                focused = next(
                    gate for gate in gates if gate.gate_id == "focused-tests"
                )
                self.assertIn("test_daemon_process_transport", focused.command)
                self.assertIn(
                    "test_playback_command_multiplexer", focused.command
                )
                self.assertIn(
                    "test_scene_daemon_client_wiring", focused.command
                )
                self.assertIn("test_scene_daemon_protocol", focused.command)

    def test_steam_helper_change_selects_helper_and_protocol_contracts(self) -> None:
        gates, groups = verify.build_plan(
            ["SteamService/WorkshopDownloader.cs"],
            arguments(),
            self.registry,
        )
        self.assertEqual(
            [gate.gate_id for gate in gates],
            ["focused-tests", "repository-residue", "design-gate", "build-verify"],
        )
        self.assertIn("steam-helper-runtime", groups)
        self.assertIn("test_steam_helper_offline", gates[0].command)
        self.assertIn("test_steam_protocol_golden", gates[0].command)

    def test_steam_download_control_change_selects_product_contracts(self) -> None:
        gates, groups = verify.build_plan(
            [
                "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+Downloads.swift",
                "script/tests/fixtures/SteamDownloadExecutionHarness.swift",
            ],
            arguments(),
            self.registry,
        )
        self.assertEqual(
            [gate.gate_id for gate in gates],
            ["focused-tests", "scene-structure", "repository-artifacts", "scene-dependencies", "repository-residue", "code-health", "design-gate", "build-verify"],
        )
        self.assertIn("steam-download-control", groups)
        focused = gates[0]
        for module in (
            "test_steam_client_lifecycle",
            "test_steam_download_execution",
            "test_steam_download_progress",
            "test_steam_protocol_golden",
        ):
            with self.subTest(module=module):
                self.assertIn(module, focused.command)

    def test_launch_change_selects_existing_fallback_admission_module(self) -> None:
        gates, groups = verify.build_plan(
            [
                'MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Launch.swift'
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("authored-fallback-owner-revocation", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        self.assertIn(
            "test_scene_resolved_material_previous_blurred_composite_graph_admission",
            focused.command,
        )
        self.assertNotIn(
            "test_scene_resolved_material_unit_previous_blurred_composite_graph_admission",
            focused.command,
        )

    def test_shader_source_changes_select_source_set_conservation(self) -> None:
        paths = (
            "ShaderFrontend/SceneAuthoredShaderFrontend.swift",
            "ShaderPreparation/SceneAuthoredShaderPreparation.swift",
        )
        for path in paths:
            with self.subTest(path=path):
                gates, groups = verify.build_plan(
                    [
                        "MyWallpaperX/Core/SteamWorkshopScene/Compilation/"
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

    def test_shader_contract_change_selects_contract_vfs_and_census_consumers(
        self,
    ) -> None:
        gates, groups = verify.build_plan(
            [
                'MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderContract/SceneShaderContractLoader.swift'
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("shader-contract", groups)
        self.assertIn("shader-source-set-conservation", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        for module in (
            "test_scene_asset_catalog_resource_view",
            "test_scene_material_program_census",
            "test_scene_runtime_input",
            "test_scene_shader_contract",
            "test_scene_shader_preparation_census",
            "test_scene_shader_preprocessor",
            "test_scene_swift_source_sets",
        ):
            with self.subTest(module=module):
                self.assertIn(module, focused.command)

    def test_resolved_material_runtime_execution_selects_atomic_consumers(
        self,
    ) -> None:
        gates, groups = verify.build_plan(
            [
                'MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator.swift'
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("resolved-material-runtime-execution", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        for module in (
            "test_scene_graph_execution_telemetry",
            "test_scene_graph_texture_publication",
            "test_scene_resolved_material_execution_capability",
            "test_scene_resolved_material_graph_executor",
            "test_scene_resolved_material_runtime_bridge",
            "test_scene_utility_layers",
        ):
            with self.subTest(module=module):
                self.assertIn(module, focused.command)

    def test_graph_target_plan_change_selects_address_mode_contract(self) -> None:
        gates, groups = verify.build_plan(
            [
                'MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetPlan.swift'
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("graph-target-address-mode", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        self.assertIn("test_scene_graph_target_address_mode", focused.command)

    def test_rendering_change_selects_compositor_and_renderer_wiring_contracts(
        self,
    ) -> None:
        gates, groups = verify.build_plan(
            [
                'MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayerCompositor.swift'
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("rendering", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        for module in (
            "test_scene_resolved_material_runtime_bridge",
            "test_scene_source_update_transaction",
        ):
            with self.subTest(module=module):
                self.assertIn(module, focused.command)

    def test_layer_source_passthrough_selects_publication_and_gpu_contracts(
        self,
    ) -> None:
        gates, groups = verify.build_plan(
            [
                'MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneLayerSourcePassthroughPlan.swift'
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("layer-source-passthrough", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        for module in (
            "test_scene_resolved_material_runtime_bridge",
            "test_scene_source_update_transaction",
            "test_scene_texture_candidate",
            "test_scene_frame_texture_registry",
            "test_scene_media_thumbnail_provider",
            "test_scene_base_material_provider_binding",
            "test_scene_wallpaper_benchmark",
        ):
            with self.subTest(module=module):
                self.assertIn(module, focused.command)

    def test_properties_change_selects_shared_alpha_and_generic_vector_contracts(
        self,
    ) -> None:
        gates, groups = verify.build_plan(
            [
                'MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneSharedLayerAlphaRuntime.swift'
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("properties", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        for module in (
            "test_scene_shared_layer_alpha_transition",
            "test_scene_property_vector_script",
            "test_scene_vector_media_events",
            "test_scene_vector_owner_admission",
        ):
            with self.subTest(module=module):
                self.assertIn(module, focused.command)

    def test_scene_script_change_selects_split_vm_contracts(self) -> None:
        gates, groups = verify.build_plan(
            [
                "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/"
                "SceneQuickJSValueHost.c"
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("scene-script-runtime", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        for module in (
            "test_scene_frame_vm_routing",
            "test_scene_property_vector_script",
            "test_scene_quickjs_layer_snapshot_atomicity",
            "test_scene_script_quickjs",
            "test_scene_script_quickjs_media_lifecycle",
            "test_scene_vector_media_events",
            "test_scene_vector_owner_admission",
        ):
            with self.subTest(module=module):
                self.assertIn(module, focused.command)

    def test_cursor_change_selects_capture_continuity_contract(self) -> None:
        gates, groups = verify.build_plan(
            [
                "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/"
                "SceneScriptCursorProgram.swift"
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("scene-script-runtime", groups)
        self.assertIn("scene-script-cursor", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        self.assertIn("test_scene_cursor_audio_consumer", focused.command)
        self.assertIn("test_scene_cursor_capture_continuity", focused.command)
        self.assertIn("test_scene_frame_vm_routing", focused.command)
        self.assertIn("test_scene_surface_pointer_event_buffer", focused.command)

    def test_split_cursor_owner_sources_select_cursor_contract(self) -> None:
        for path in (
            "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/"
            "SceneScriptCursorProgramModels.swift",
            "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/"
            "SceneScriptValueOwner+Cursor.swift",
        ):
            with self.subTest(path=path):
                gates, groups = verify.build_plan(
                    [path],
                    arguments(),
                    self.registry,
                )
                self.assertIn("scene-script-cursor", groups)
                focused = next(
                    gate for gate in gates if gate.gate_id == "focused-tests"
                )
                self.assertIn(
                    "test_scene_cursor_capture_continuity", focused.command
                )

    def test_launch_models_select_sync_and_daemon_launch_contracts(self) -> None:
        gates, groups = verify.build_plan(
            [
                "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/"
                "SceneDesktopWallpaperLaunchModels.swift"
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("scene-launch", groups)
        self.assertIn("scene-daemon-runtime", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        self.assertIn("test_scene_sync_launch_generation", focused.command)
        self.assertIn("test_scene_wallpaper_async_launch", focused.command)

    def test_vector_owner_admission_harness_selects_consumers(self) -> None:
        gates, groups = verify.build_plan(
            ["script/tests/scene_vector_owner_admission_harness.py"],
            arguments(),
            self.registry,
        )
        self.assertIn("scene-harness-support", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        self.assertIn("test_scene_cursor_candidate_collision", focused.command)
        self.assertIn("test_scene_vector_owner_admission", focused.command)

    def test_cursor_audio_demand_change_selects_cursor_audio_contract(self) -> None:
        gates, groups = verify.build_plan(
            [
                "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/"
                "SceneDesktopWallpaperSession+AudioDemand.swift"
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("scene-script-cursor", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        self.assertIn("test_scene_cursor_audio_consumer", focused.command)

    def test_pointer_producer_change_selects_cursor_transaction_contract(self) -> None:
        gates, groups = verify.build_plan(
            [
                'MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+PointerEvents.swift'
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("scene-script-cursor", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        self.assertIn("test_scene_cursor_capture_continuity", focused.command)
        self.assertIn("test_scene_surface_pointer_event_buffer", focused.command)

    def test_resource_catalog_change_selects_catalog_and_material_contracts(
        self,
    ) -> None:
        gates, groups = verify.build_plan(
            [
                'MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneAssetCatalog.swift'
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("resources", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        for module in (
            "test_scene_asset_catalog_resource_view",
            "test_scene_material_render_state",
        ):
            with self.subTest(module=module):
                self.assertIn(module, focused.command)

    def test_scene_script_source_evidence_selects_current_consumers(
        self,
    ) -> None:
        gates, groups = verify.build_plan(
            [
                "MyWallpaperX/Core/SteamWorkshopScene/Format/"
                "SceneScriptSourceEvidence.swift"
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("scene-script-source-evidence", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        for module in (
            "test_scene_frame_context",
            "test_scene_shared_layer_alpha_transition",
            "test_scene_script_binding_parser",
            "test_scene_solid_layers",
            "test_scene_text_row_limit",
            "test_scene_timeline_document",
            "test_scene_timeline_runtime",
            "test_scene_timeline_target_compiler",
        ):
            with self.subTest(module=module):
                self.assertIn(module, focused.command)

    def test_authored_graph_change_selects_ir_admission_and_executor_contracts(self) -> None:
        gates, groups = verify.build_plan(
            [
                'MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneGraphAdmissionCompiler.swift'
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

    def test_effect_compilation_change_selects_compile_admission_and_consumers(self) -> None:
        gates, groups = verify.build_plan(
            [
                'MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneEffectStageAdmission.swift'
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("effect-compilation", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        for module in (
            "test_scene_effect_execution_telemetry",
            "test_scene_effect_render_graph",
            "test_scene_graph_admission_compiler",
            "test_scene_graph_texture_publication",
            "test_scene_resolved_material_execution_capability",
            "test_scene_resolved_material_graph_executor",
            "test_scene_resolved_material_program_finalizer",
            "test_scene_utility_layers",
        ):
            with self.subTest(module=module):
                self.assertIn(module, focused.command)

    def test_layer_dependency_change_selects_planning_pool_and_consumers(self) -> None:
        gates, groups = verify.build_plan(
            [
                'MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneDependencyRenderPlan.swift'
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("layer-dependencies", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        for module in (
            "test_scene_dependency_graph_output_runtime",
            "test_scene_dependency_render_plan",
            "test_scene_named_render_target_pool",
            "test_scene_utility_layers",
        ):
            with self.subTest(module=module):
                self.assertIn(module, focused.command)

    def test_effect_execution_change_selects_stage_graph_and_encoder_contracts(self) -> None:
        gates, groups = verify.build_plan(
            [
                'MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor.swift'
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("effect-execution", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        for module in (
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
                'MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialProgram.swift'
            ],
            arguments(),
            self.registry,
        )
        self.assertIn("material-program", groups)
        self.assertIn("shader-source-set-conservation", groups)
        focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
        self.assertIn("test_scene_swift_source_sets", focused.command)
        for module in (
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

    def test_render_graph_checkpoint_uses_pure_build_and_code_health(self) -> None:
        gates, groups = verify.build_plan(
            [
                "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphExecutionState.swift"
            ],
            arguments(),
            self.registry,
        )
        self.assertEqual(
            [gate.gate_id for gate in gates],
            ["focused-tests", "scene-structure", "scene-dependencies", "repository-residue", "code-health", "scene-defense", "design-gate", "build-verify"],
        )
        self.assertIn("render-graph", groups)
        self.assertEqual(
            gates[-1].command,
            ("/bin/bash", "script/run_checkpoint_build.sh"),
        )

    def test_ci_build_adds_code_health_without_local_wrapper(self) -> None:
        gates, _ = verify.build_plan(
            ["MyWallpaperX/Core/SteamWorkshopScene/Systems/Text/SceneText.swift"],
            arguments(ci=True),
            self.registry,
        )
        self.assertEqual(
            [gate.gate_id for gate in gates],
            ["focused-tests", "scene-structure", "scene-dependencies", "repository-residue", "code-health", "scene-defense", "design-gate", "build-verify"],
        )
        self.assertEqual(
            gates[-1].command,
            ("/bin/bash", "script/run_checkpoint_build.sh"),
        )

    def test_every_xcode_product_input_root_triggers_checkpoint_build(self) -> None:
        for path in (
            "MyWallpaperX/App/AppDelegate.swift",
            "MyWallpaperX.xcodeproj/project.pbxproj",
            "MyWallpaperXHelp/en.lproj/index.html",
            "WallpaperDaemonSources/main.swift",
        ):
            with self.subTest(path=path):
                self.assertIn("build-verify", self.gate_ids([path], arguments()))

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

    def test_integration_runs_focused_tests_and_requires_real_sample(self) -> None:
        gates, _ = verify.build_plan(
            ["MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTexture.swift"],
            arguments(phase="integration"),
            self.registry,
        )
        self.assertEqual(
            [gate.gate_id for gate in gates],
            ["focused-tests", "scene-structure", "scene-dependencies", "repository-residue", "code-health", "scene-defense", "design-gate", "build-verify", "targeted-sample"],
        )
        self.assertIn("test_scene_frame_texture_registry", gates[0].command)
        self.assertNotIn("--keyword", gates[0].command)
        self.assertIn("--sample-id", gates[-1].unresolved)

    def test_integration_requires_explicit_frozen_staged_app(self) -> None:
        gates, _ = verify.build_plan(
            ["MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTexture.swift"],
            arguments(
                phase="integration",
                app=None,
                sample_id=["fixture"],
                sample_root=Path("samples"),
                output_dir=Path("output"),
            ),
            self.registry,
        )
        runtime = gates[-1]
        self.assertEqual(runtime.gate_id, "targeted-sample")
        self.assertEqual(runtime.status, "blocked")
        self.assertIn("frozen staged executable", runtime.unresolved)

    def test_cli_has_no_shared_derived_data_app_default(self) -> None:
        self.assertIsNone(verify.parse_args([]).app)

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
            "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRuntime.swift",
            "MyWallpaperX/App/Debug/DebugScenePlaybackRunner+Performance.swift",
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
                self.assertIn("focused-tests", gate_ids)
                self.assertNotIn("scene-all-tests", gate_ids)
                self.assertIn("targeted-sample", gate_ids)

    def test_integration_keeps_explicit_modules_in_focused_gate(self) -> None:
        gates, groups = verify.build_plan(
            ["MyWallpaperX/App/Debug/DebugScenePlaybackRunner.swift"],
            arguments(phase="integration"),
            self.registry,
        )
        self.assertIn("scene-debug-runner", groups)
        self.assertEqual(gates[0].gate_id, "focused-tests")
        self.assertNotIn("scene-all-tests", [gate.gate_id for gate in gates])
        self.assertIn("test_scene_wallpaper_benchmark", gates[0].command)
        self.assertIn("test_scene_wallpaper_benchmark_media_event", gates[0].command)
        self.assertIn("test_scene_frame_vm_routing", gates[0].command)
        self.assertNotIn("__scene_validation_no_scope_match__", gates[0].command)
        self.assertNotIn("--keyword", gates[0].command)

    def test_milestone_runs_complete_scene_regression_suite(self) -> None:
        gates, _ = verify.build_plan(
            ["MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTexture.swift"],
            arguments(phase="milestone"),
            self.registry,
        )
        gate_ids = [gate.gate_id for gate in gates]
        self.assertEqual(gate_ids[:2], ["focused-tests", "scene-all-tests"])
        self.assertIn("targeted-sample", gate_ids)

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
            ["MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRuntime.swift"],
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
                    "docs/scene/capabilities/coverage-ledger.md",
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

    def test_gate_execution_overrides_only_the_structural_comparison_base(self) -> None:
        gate = verify.Gate('fixture', ('true',), 'test', False)
        with patch.dict(verify.os.environ, {'MWX_VALIDATION_BASE': 'stale-base', 'UNCHANGED_TEST_ENV': 'keep'}), \
             patch.object(verify.subprocess, 'run', return_value=subprocess.CompletedProcess(('true',), 0)) as run, \
             redirect_stdout(io.StringIO()):
            self.assertEqual(verify.run_gates([gate], 'review-base'), 0)
        run.assert_called_once()
        self.assertEqual(run.call_args.args, (('true',),))
        self.assertEqual(run.call_args.kwargs['env']['MWX_VALIDATION_BASE'], 'review-base')
        self.assertEqual(run.call_args.kwargs['env']['UNCHANGED_TEST_ENV'], 'keep')
        self.assertEqual(run.call_args.kwargs['cwd'], verify.ROOT)
        self.assertEqual(gate.status, 'passed')

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

    def test_deleted_tests_keep_affected_checks_without_forcing_all_products(self) -> None:
        for deleted_test in ('test_scene_removed_contract', 'test_document_removed_contract'):
            gates, _ = verify.build_plan([f'script/tests/{deleted_test}.py'], arguments(), self.registry)
            self.assertEqual([gate.gate_id for gate in gates],
                             ['focused-tests', 'test-assertions', 'repository-artifacts', 'scene-dependencies'])
            command = gates[0].command
            self.assertNotIn(deleted_test, command)
            self.assertIn('test_scene_test_runner', command)
            self.assertIn('test_verify_scene_change', command)
            self.assertNotIn('all', command)

    def test_deleted_test_does_not_discard_other_affected_groups(self) -> None:
        gates, _ = verify.build_plan(
            ['script/tests/test_scene_removed_contract.py', 'docs/README.md'],
            arguments(ci=True), self.registry)
        command = gates[0].command
        self.assertIn('test_document_role_index', command)
        self.assertIn('test_scene_test_runner', command)
        self.assertIn('--fail-fast', command)
        self.assertIn('document-links', [gate.gate_id for gate in gates])

    def test_ci_focused_suite_stops_on_failure(self) -> None:
        gates, _ = verify.build_plan(["docs/README.md"], arguments(ci=True), self.registry)
        self.assertIn("--fail-fast", gates[0].command)

    def test_explicit_release_or_all_scope_replaces_focused_tests(self) -> None:
        for scope in ("release", "all"):
            with self.subTest(scope=scope):
                gates, _ = verify.build_plan(
                    ["MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader.swift"],
                    arguments(ci=True, test_scope=scope), self.registry,
                )
                self.assertEqual([gate.gate_id for gate in gates],
                                 [f"{scope}-tests", *(["scene-structure"] if scope == "release" else []), "scene-dependencies", "repository-residue", "code-health", "scene-defense", "design-gate", "build-verify"])
                self.assertIn(scope, gates[0].command)
                self.assertIn("--fail-fast", gates[0].command)

    def test_video_command_fixture_selects_its_executable_consumer(self) -> None:
        gates, _ = verify.build_plan(
            ["script/tests/fixtures/SceneVideoRepeatedCommandsHarness.swift"],
            arguments(), self.registry,
        )
        self.assertFalse(any(gate.unresolved for gate in gates))
        self.assertIn("test_scene_video_repeated_commands", gates[0].command)

    def test_checkpoint_build_script_is_isolated_and_does_not_launch(self) -> None:
        script = (SCRIPT_ROOT / "run_checkpoint_build.sh").read_text(encoding="utf-8")
        self.assertIn("/private/tmp/mywallpaperx-checkpoint-build.", script)
        self.assertIn("CHECKPOINT_LOCK_DIR", script)
        self.assertIn("CODE_SIGNING_ALLOWED=NO", script)
        self.assertNotIn("pkill", script)
        self.assertNotIn("/usr/bin/open", script)
        self.assertNotIn(".codex/DerivedData", script)


    def test_scene_defense_gate_tracks_scene_product_paths(self) -> None:
        gates, _ = verify.build_plan(
            ["MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTexture.swift"],
            arguments(),
            self.registry,
        )
        defense = [gate for gate in gates if gate.gate_id == "scene-defense"]
        self.assertEqual(len(defense), 1)
        self.assertIn("script/check_scene_defense.py", defense[0].command)
        self.assertIn("--base-ref", defense[0].command)
        self.assertEqual(
            self.gate_ids(
                ["MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService.swift"],
                arguments(),
            ).count("scene-defense"),
            0,
        )
        header_gates = self.gate_ids(
            ["MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJS.h"],
            arguments(),
        )
        self.assertIn("scene-defense", header_gates)
        self.assertLess(header_gates.index("scene-defense"), header_gates.index("build-verify"))


class OwnedPathsAndGateRegistryTests(unittest.TestCase):
    def test_exact_source_move_closes_only_after_build_and_loses_proof_on_edit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(['git', 'init', '-q', directory], check=True)
            old, new = 'MyWallpaperX/App/DebugFixture.swift', 'MyWallpaperX/App/Debug/DebugFixture.swift'
            (root / old).parent.mkdir(parents=True)
            (root / old).write_text('enum Fixture {}\n')
            subprocess.run(['git', 'add', old], cwd=root, check=True)
            subprocess.run(['git', '-c', 'user.name=Fixture', '-c', 'user.email=f@example.test',
                            'commit', '-qm', 'fixture'], cwd=root, check=True)
            (root / new).parent.mkdir()
            (root / old).rename(root / new)
            registry = {'path_groups': [], 'method_gates': {}}
            gate = verify.Gate('build-verify', ('true',), 'fixture', True)
            with patch.object(verify, 'ROOT', root):
                def payload():
                    return verify.validation_payload(arguments(), [old, new], set(), [gate],
                                                     execution='completed', registry=registry)
                self.assertFalse(payload()['closure_complete'])
                gate.status = 'passed'
                result = payload()
                self.assertTrue(result['closure_complete'])
                self.assertEqual(result['focused_test_mapping']['unmapped_paths'], sorted([old, new]))
                self.assertEqual(result['verified_source_relocations'], {old: new})
                (root / new).write_text('enum Changed {}\n')
                self.assertFalse(payload()['closure_complete'])

    def setUp(self) -> None:
        self.registry = verify.load_registry()
        self.doc = "docs/README.md"
        self.swift = "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTexture.swift"

    def test_owned_selection_excludes_parallel_product_change_from_plan_and_report(self) -> None:
        for execute in (False, True):
            with self.subTest(execute=execute):
                output = io.StringIO()
                def complete(gates: list[verify.Gate], base: str) -> int:
                    self.assertEqual(base, "owned-review-base")
                    for gate in gates:
                        gate.status = "passed"
                    return 0
                with patch.object(verify, "changed_paths", return_value=[self.doc, self.swift]), \
                     patch.object(verify, "run_gates", side_effect=complete), redirect_stdout(output):
                    result = verify.main([
                        "--owned-path", self.doc, "--format", "json", "--base", "owned-review-base",
                        *(["--run"] if execute else []),
                    ])
                self.assertEqual(result, 0)
                payload = json.loads(output.getvalue())
                self.assertEqual(payload["path_selection"], "owned-only")
                self.assertEqual(payload["paths"], [self.doc])
                self.assertEqual(payload["owned_paths"], [self.doc])
                self.assertEqual(payload["excluded_paths"], [self.swift])
                self.assertEqual([gate["gate_id"] for gate in payload["gates"]], ["focused-tests", "document-links", "repository-artifacts", "document-health"])
                self.assertEqual(payload["execution"], "completed" if execute else "not-run")

    def test_owned_text_preview_exposes_excluded_files(self) -> None:
        output = io.StringIO()
        with patch.object(verify, "changed_paths", return_value=[self.doc, self.swift]), redirect_stdout(output):
            self.assertEqual(verify.main(["--owned-path", self.doc]), 0)
        self.assertIn(f"excluded changed paths: {self.swift}", output.getvalue())

    def test_default_selection_still_includes_every_change(self) -> None:
        output = io.StringIO()
        with patch.object(verify, "changed_paths", return_value=[self.doc, self.swift]), redirect_stdout(output):
            self.assertEqual(verify.main(["--format", "json"]), 0)
        payload = json.loads(output.getvalue())
        self.assertEqual(payload["paths"], [self.doc, self.swift])
        self.assertEqual(payload["path_selection"], "all-changes")
        self.assertEqual(payload["excluded_paths"], [])
        self.assertIn("build-verify", [gate["gate_id"] for gate in payload["gates"]])

    def test_invalid_owned_paths_fail_before_gate_execution(self) -> None:
        for path in ("", " ", "/docs/README.md", "../README.md", "docs/../README.md",
                     "./docs/README.md", "docs//README.md", "docs/**", "docs", "docs/",
                     "docs\\README.md", "docs/README.md\n", "docs/no-such-owned-file.md"):
            with self.subTest(path=path), \
                 patch.object(verify, "changed_paths", return_value=[self.doc]), \
                 patch.object(verify, "run_gates") as run, redirect_stderr(io.StringIO()):
                self.assertEqual(verify.main(["--owned-path", path, "--run"]), 2)
                run.assert_not_called()

    def test_owned_selection_without_matching_changes_fails_closed(self) -> None:
        for paths in ([], [self.swift]):
            with self.subTest(paths=paths), \
                 patch.object(verify, "changed_paths", return_value=paths), \
                 patch.object(verify, "run_gates") as run, redirect_stderr(io.StringIO()):
                self.assertEqual(verify.main(["--owned-path", self.doc, "--run"]), 2)
                run.assert_not_called()
        with self.assertRaises(ValueError):
            verify.select_owned_paths([self.doc], [])

    def test_owned_and_synthetic_path_modes_are_mutually_exclusive(self) -> None:
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            verify.parse_args(["--owned-path", self.doc, "--path", self.swift])
        self.assertEqual(error.exception.code, 2)

    def test_owned_paths_preserve_deleted_and_untracked_files_from_git(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args: str) -> None:
                subprocess.run(["git", *args], cwd=root, check=True, capture_output=True)
            git("init", "--quiet")
            (root / "removed.md").write_text("original")
            (root / "parallel.swift").write_text("original")
            git("add", "removed.md", "parallel.swift")
            git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--quiet", "-m", "fixture")
            (root / "removed.md").unlink()
            (root / "parallel.swift").write_text("changed")
            (root / "new file.md").write_text("untracked")
            with patch.object(verify, "ROOT", root):
                dirty = verify.changed_paths("HEAD", [])
                selected, excluded = verify.select_owned_paths(dirty, ["removed.md", "new file.md", "removed.md"])
            self.assertEqual(selected, ["new file.md", "removed.md"])
            self.assertEqual(excluded, ["parallel.swift"])

    def test_owned_symlink_escape_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as outside:
            root = Path(directory)
            target = Path(outside) / "external.md"
            target.write_text("external")
            (root / "escape.md").symlink_to(target)
            with patch.object(verify, "ROOT", root), self.assertRaises(ValueError):
                verify.select_owned_paths(["escape.md"], ["escape.md"])

    def test_owned_staged_rename_retains_both_paths_and_deleted_test_obligation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            old = "script/tests/test_original.py"
            new = "script/renamed_helper.py"
            def git(*args: str) -> None:
                subprocess.run(["git", *args], cwd=root, check=True, capture_output=True)
            git("init", "--quiet")
            (root / old).parent.mkdir(parents=True)
            (root / old).write_text("# fixture\n")
            git("add", old)
            git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--quiet", "-m", "fixture")
            git("mv", old, new)
            with patch.object(verify, "ROOT", root):
                dirty = verify.changed_paths("HEAD", [])
                selected, excluded = verify.select_owned_paths(dirty, [old, new])
                gates, _ = verify.build_plan(selected, arguments(), self.registry)
            self.assertEqual(selected, sorted([old, new]))
            self.assertEqual(excluded, [])
            self.assertIn("focused-tests", [gate.gate_id for gate in gates])
            self.assertIn("test_scene_test_runner", gates[0].command)

    def test_owned_unmapped_change_still_blocks(self) -> None:
        path = "script/unmapped_owned_fixture.json"
        selected, excluded = verify.select_owned_paths([path, self.swift], [path])
        gates, _ = verify.build_plan(selected, arguments(), self.registry)
        self.assertEqual(excluded, [self.swift])
        self.assertEqual(gates[-1].gate_id, "unmapped-change")
        self.assertEqual(gates[-1].status, "blocked")

    def test_inner_metal_product_change_requires_design_approval(self) -> None:
        gates, _ = verify.build_plan(
            ["MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneStaticModel.metal"],
            arguments(phase="inner"), self.registry,
        )
        ids = [gate.gate_id for gate in gates]
        self.assertIn("design-gate", ids)
        self.assertIn("scene-defense", ids)
        self.assertNotIn("build-verify", ids)
        self.assertNotIn("code-health", ids)

    def test_every_emitted_gate_has_registration_and_all_registered_gates_are_reachable(self) -> None:
        emitted = set()
        paths = [self.doc, self.swift, "script/scene_wallpaper_benchmark.py",
                 "script/unmapped_fixture.json", "script/tests/test_removed_fixture.py"]
        for phase in verify.PHASES:
            for scope in ("changed", "release", "all"):
                for tier in ((None, "fixed", "full") if phase == "milestone" else (None,)):
                    gates, _ = verify.build_plan(paths, arguments(
                        phase=phase, test_scope=scope, matrix_tier=tier,
                    ), self.registry)
                    emitted.update(gate.gate_id for gate in gates)
        # A deleted test replaces focused and Scene-wide tests, so also cover
        # the corresponding normal milestone plan.
        gates, _ = verify.build_plan([self.swift], arguments(phase="milestone"), self.registry)
        emitted.update(gate.gate_id for gate in gates)
        debug_gates, _ = verify.build_plan(["MyWallpaperX/App/Debug/DebugWebPlaybackRunner.swift"], arguments(phase="inner"), self.registry)
        emitted.update(gate.gate_id for gate in debug_gates)
        self.assertEqual(emitted, set(self.registry["gates"]))

    def test_missing_registration_rejects_an_actual_emitted_gate(self) -> None:
        registry = copy.deepcopy(self.registry)
        del registry["gates"]["design-gate"]
        with self.assertRaisesRegex(ValueError, "unregistered validation gate: design-gate"):
            verify.build_plan([self.swift], arguments(), registry)

    def test_runtime_serialization_uses_registered_metadata(self) -> None:
        registry = copy.deepcopy(self.registry)
        registry["gates"]["focused-tests"]["serialized"] = True
        gates, _ = verify.build_plan([self.doc], arguments(), registry)
        self.assertTrue(gates[0].serialized)

    def test_invalid_registration_lifecycle_metadata_is_rejected(self) -> None:
        for key, value in (("serialized", "false"), ("retirement", "  "), ("cost", None)):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as directory:
                registry = copy.deepcopy(self.registry)
                registry["gates"]["design-gate"][key] = value
                path = Path(directory) / "registry.json"
                path.write_text(json.dumps(registry))
                with self.assertRaises(ValueError):
                    verify.load_registry(path)

    def test_split_method_gates_cover_the_complete_mixed_module_without_overlap(self) -> None:
        selections = {}
        for selection in self.registry["method_gates"].values():
            identity = (selection['module'], selection['class'])
            selections.setdefault(identity, []).extend(selection['methods'])
        for (module_name, class_name), selected in selections.items():
            with self.subTest(module=module_name, test_class=class_name):
                module = importlib.import_module(f'script.tests.{module_name}')
                test_class = getattr(module, class_name)
                expected = set(unittest.defaultTestLoader.getTestCaseNames(test_class))
                self.assertEqual(set(selected), expected)
                self.assertEqual(len(selected), len(set(selected)))

    def test_structure_is_inner_and_links_checkpoint_without_whole_module_repetition(self) -> None:
        for phase in verify.PHASES[:3]:
            with self.subTest(phase=phase):
                gates, _ = verify.build_plan(["script/scene_source_layout.json"], arguments(phase=phase), self.registry)
                ids = [gate.gate_id for gate in gates]
                self.assertIn("scene-structure", ids)
                self.assertEqual("document-links" in ids, phase != "inner")
                focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
                self.assertNotIn("test_scene_semantics_coverage", focused.command)
                structure = next(gate for gate in gates if gate.gate_id == "scene-structure")
                self.assertIn("unittest", structure.command)
                self.assertTrue(all("markdown" not in value for value in structure.command))

    def test_ci_method_gates_use_unittest_flag_and_checker_receives_no_runner_flag(self) -> None:
        gates, _ = verify.build_plan(["script/tests/test_scene_semantics_coverage.py"], arguments(ci=True), self.registry)
        structure = next(gate for gate in gates if gate.gate_id == "scene-structure")
        checker = next(gate for gate in gates if gate.gate_id == "test-assertions")
        self.assertIn("--failfast", structure.command)
        self.assertNotIn("--fail-fast", structure.command)
        self.assertNotIn("--failfast", checker.command)
        self.assertNotIn("--fail-fast", checker.command)

    def test_shape_checker_is_selected_for_test_checker_and_baseline_changes(self) -> None:
        for path in ("script/tests/test_verify_scene_change.py", "script/check_test_assertions.py",
                     "script/test_assertion_baseline.json", "script/scene_validation_gates.json"):
            with self.subTest(path=path):
                gates, _ = verify.build_plan([path], arguments(phase="inner", base="review-base"), self.registry)
                checker = next(gate for gate in gates if gate.gate_id == "test-assertions")
                self.assertEqual(checker.command[-3:], ("--check", "--base-ref", "review-base"))

    def test_full_suite_does_not_repeat_registered_method_gates(self) -> None:
        gates, _ = verify.build_plan([self.doc, self.swift], arguments(test_scope="all"), self.registry)
        ids = {gate.gate_id for gate in gates}
        self.assertIn("all-tests", ids)
        self.assertTrue(ids.isdisjoint(self.registry["method_gates"]))

    def test_artifact_gate_covers_governed_roots_without_product_media(self) -> None:
        for path in ("docs/README.md", "script/check_repository_artifacts.py",
                     ".agents/skills/mywallpaperx-maintainer/SKILL.md", ".github/workflows/ci.yml"):
            with self.subTest(path=path):
                gates, _ = verify.build_plan([path], arguments(phase="inner"), self.registry)
                gate = next(gate for gate in gates if gate.gate_id == "repository-artifacts")
                self.assertEqual(gate.command[2:], ("script/check_repository_artifacts.py", "--check", "--base-ref", "HEAD"))
        gates, _ = verify.build_plan(["MyWallpaperX/Assets.xcassets/example.png"], arguments(phase="inner"), self.registry)
        self.assertNotIn("repository-artifacts", [gate.gate_id for gate in gates])


class ProductTestMappingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.registry = verify.load_registry()
        self.available = [path.stem for path in (verify.ROOT / "script/tests").glob("test_*.py")]

    def test_keyword_only_groups_preserve_selection_when_mixed_with_explicit_modules(self) -> None:
        from run_scene_tests import discover_modules
        def selected(paths: list[str]) -> set[str]:
            gates, _ = verify.build_plan(paths, arguments(phase="inner"), self.registry)
            command = next(gate.command for gate in gates if gate.gate_id == "focused-tests")
            modules = [command[index + 1] for index, value in enumerate(command) if value == "--module"]
            keywords = [command[index + 1] for index, value in enumerate(command) if value == "--keyword"]
            return set(discover_modules(self.available, scope="scene", requested_modules=modules, keywords=keywords))
        doc_tests = selected(["docs/README.md"])
        for path in (
            "MyWallpaperX/Core/SteamWorkshopScene/Systems/Text/SceneTextTextureLoader.swift",
            "MyWallpaperX/Core/SteamWorkshopScene/Format/SceneDocument+General.swift",
            "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneEffectStageRuntimeDisposition.swift",
        ):
            with self.subTest(path=path):
                alone = selected([path])
                mixed = selected([path, "docs/README.md"])
                self.assertTrue(alone)
                self.assertEqual(mixed, alone | doc_tests)
                self.assertLess(len(mixed), len(self.available))

    def test_group_with_explicit_modules_does_not_expand_its_own_keywords(self) -> None:
        registry = {"path_groups": [
            {"id": "explicit", "patterns": ["fixture"], "modules": ["test_nearest"], "keywords": ["broad"]},
            {"id": "fallback", "patterns": ["other"], "keywords": ["narrow"]},
        ]}
        modules, keywords, _ = verify.mapped_tests(["fixture", "other"], registry)
        self.assertEqual(modules, {"test_nearest"})
        self.assertEqual(keywords, {"narrow"})
        command = verify.focused_test_command(modules, keywords)
        self.assertIn("test_nearest", command)
        self.assertIn("narrow", command)
        self.assertNotIn("broad", command)

    def test_exact_producers_and_consumers_select_nearest_existing_contracts(self) -> None:
        cases = {
            "MyWallpaperX/App/ImportedVideoPlaybackObserver.swift": "test_imported_video_autoplay_gate",
            "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+ImportProcessing.swift": "test_imported_video_autoplay_gate",
            "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+WallpaperApplication.swift": "test_imported_video_autoplay_gate",
            "MyWallpaperX/Core/PlaybackControl/WallpaperRuntimeSwitch.swift": "test_imported_video_autoplay_gate",
            "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+Persistence.swift": "test_playback_policy",
            "MyWallpaperX/Modules/VideoLibrary/Core/BundledVideoLibrary.swift": "test_bundled_video_library",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopLibraryPublication.swift": "test_steam_library_publication",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopLibraryTransaction.swift": "test_steam_library_transaction",
            "MyWallpaperX/Shell/AppKitMainSplitView+SteamSelection.swift": "test_steam_library_interactions",
            "MyWallpaperX/Modules/VideoLibrary/UI/VideoLibraryInspectorView.swift": "test_video_inspector_preview_reload",
        }
        for path, module in cases.items():
            with self.subTest(path=path):
                gates, _ = verify.build_plan([path], arguments(phase="inner"), self.registry)
                focused = next(gate for gate in gates if gate.gate_id == "focused-tests")
                self.assertIn(module, focused.command)
                self.assertNotIn("--keyword", focused.command)
                report = verify.product_test_mapping([path], self.registry, self.available)
                self.assertEqual(report["mapped_paths"], [path])
                self.assertEqual(report["unmapped_paths"], [])
                self.assertIn(module, report["mappings"][0]["selected_modules"])

    def test_local_video_policy_does_not_expand_to_unrelated_scene_daemon_suite(self) -> None:
        path = "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+Persistence.swift"
        modules, _, _ = verify.mapped_tests([path], self.registry)
        self.assertEqual(modules, {"test_playback_policy", "test_playback_policy_delivery"})

    def test_untested_static_image_and_shell_neighbors_remain_visible(self) -> None:
        paths = ["MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift",
                 "MyWallpaperX/Shell/AppKitMainSplitView+ModuleRouting.swift",
                 "MyWallpaperX/Core/PlaybackControl/PlaybackPerformanceProfile.swift"]
        report = verify.product_test_mapping(paths, self.registry, self.available)
        self.assertEqual(report["unmapped_paths"], sorted(paths))
        self.assertEqual(report["mapped_paths"], [])

    def test_build_success_cannot_close_unmapped_product_test_debt(self) -> None:
        path = "MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift"
        args = arguments()
        gates, groups = verify.build_plan([path], args, self.registry)
        self.assertIn("build-verify", [gate.gate_id for gate in gates])
        self.assertNotIn("unmapped-change", [gate.gate_id for gate in gates])
        for gate in gates:
            gate.status = "passed"
        payload = verify.validation_payload(args, [path], groups, gates,
                                           execution="completed", registry=self.registry)
        self.assertFalse(payload["closure_complete"])
        self.assertEqual(payload["focused_test_mapping"]["unmapped_paths"], [path])
        output = io.StringIO()
        with redirect_stdout(output):
            verify.print_payload(payload, "text")
        self.assertIn("[TEST MAPPING DEBT] " + path, output.getvalue())

    def test_unmapped_inner_product_stays_blocked_next_to_a_mapped_source(self) -> None:
        paths = ["MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift",
                 "MyWallpaperX/Core/PlaybackControl/WallpaperRuntimeSwitch.swift"]
        gates, _ = verify.build_plan(paths, arguments(phase="inner"), self.registry)
        self.assertEqual(gates[-1].gate_id, "unmapped-change")
        self.assertEqual(gates[-1].status, "blocked")
        self.assertIn(paths[0], gates[-1].unresolved)
        self.assertNotIn(paths[1], gates[-1].unresolved)

    def test_mapping_uses_supplied_inventory_and_rejects_stale_test_reference(self) -> None:
        path = "MyWallpaperX/Fixture.swift"
        registry = copy.deepcopy(self.registry)
        registry["path_groups"] = [{"id": "fixture", "patterns": [path],
                                   "modules": ["test_missing_fixture"]}]
        report = verify.product_test_mapping([path, "docs/README.md"], registry, [])
        self.assertEqual(report["product_paths"], [path])
        self.assertEqual(report["unmapped_paths"], [path])
        self.assertEqual(report["stale_modules"], ["test_missing_fixture"])
        with self.assertRaisesRegex(ValueError, "mapped test modules no longer exist"):
            verify.build_plan([path], arguments(), registry)

    def test_governance_methods_and_keyword_groups_do_not_count_as_focused_mapping(self) -> None:
        path = "MyWallpaperX/Fixture.swift"
        registry = copy.deepcopy(self.registry)
        registry["path_groups"] = [{"id": "fixture", "patterns": [path],
                                   "modules": ["test_scene_semantics_coverage"],
                                   "keywords": ["fixture"]}]
        report = verify.product_test_mapping([path], registry, self.available)
        self.assertEqual(report["unmapped_paths"], [path])

    def test_owned_selection_keeps_excluded_product_debt_out_of_batch_report(self) -> None:
        owned = "MyWallpaperX/Core/PlaybackControl/WallpaperRuntimeSwitch.swift"
        excluded = "MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift"
        output = io.StringIO()
        with patch.object(verify, "changed_paths", return_value=[owned, excluded]), redirect_stdout(output):
            self.assertEqual(verify.main(["--owned-path", owned, "--format", "json"]), 0)
        report = json.loads(output.getvalue())
        self.assertEqual(report["excluded_paths"], [excluded])
        self.assertEqual(report["focused_test_mapping"]["product_paths"], [owned])
        self.assertEqual(report["focused_test_mapping"]["unmapped_paths"], [])

    def test_registry_rejects_duplicate_groups_and_string_module_lists(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "registry.json"
            duplicate = copy.deepcopy(self.registry)
            duplicate["path_groups"].append(duplicate["path_groups"][0])
            malformed = copy.deepcopy(self.registry)
            malformed["path_groups"][0]["modules"] = "test_fixture"
            for registry, message in ((duplicate, "duplicate path-group"), (malformed, "invalid path-group modules")):
                with self.subTest(message=message):
                    path.write_text(json.dumps(registry))
                    with self.assertRaisesRegex(ValueError, message):
                        verify.load_registry(path)


if __name__ == "__main__":
    unittest.main()
