"""Executable gate selection for documentation and product capability inputs."""
from __future__ import annotations

import unittest
from pathlib import Path

from script.tests.test_verify_scene_change import arguments, verify


class SceneValidationRoutingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.registry = verify.load_registry()

    def gate_ids(self, paths: list[str], args) -> list[str]:
        gates, _ = verify.build_plan(paths, args, self.registry)
        return [gate.gate_id for gate in gates]

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


if __name__ == "__main__":
    unittest.main()
