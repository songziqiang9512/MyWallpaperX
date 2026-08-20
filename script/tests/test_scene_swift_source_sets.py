#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_ROOT = REPOSITORY_ROOT / "script"
sys.path.insert(0, str(SCRIPT_ROOT))

from scene_swift_source_sets import (  # noqa: E402
    SceneSwiftSourceSetError,
    scene_swift_source_relpaths,
    scene_swift_source_relpaths_by_basename,
    scene_swift_sources,
)


class SceneSwiftSourceSetTests(unittest.TestCase):
    def test_authored_shader_frontend_set_conserves_its_complete_type_family(self) -> None:
        support = scene_swift_source_relpaths("authored_shader_frontend_support")
        implementation = scene_swift_source_relpaths(
            "authored_shader_frontend_implementation"
        )
        core = scene_swift_source_relpaths("authored_shader_frontend_core")

        self.assertEqual(len(support), 3)
        self.assertEqual(len(implementation), 43)
        self.assertEqual(core, (*support, *implementation))
        syntax = next(
            index for index, path in enumerate(implementation)
            if path.endswith("/SceneAuthoredShaderSyntax.swift")
        )
        references = next(
            index for index, path in enumerate(implementation)
            if path.endswith("/SceneAuthoredShaderGlobalReferenceAnalyzer.swift")
        )
        frontend = next(
            index for index, path in enumerate(implementation)
            if path.endswith("/SceneAuthoredShaderFrontend.swift")
        )
        self.assertLess(syntax, references)
        self.assertLess(references, frontend)
        frontend_directory = (
            REPOSITORY_ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderFrontend"
        )
        self.assertEqual(
            {path.resolve() for path in scene_swift_sources(
                "authored_shader_frontend_implementation"
            )},
            {path.resolve() for path in frontend_directory.glob("*.swift")},
        )

    def test_shader_contract_resolution_and_effect_planning_sets_conserve_order(self) -> None:
        frontend_support = scene_swift_source_relpaths(
            "authored_shader_frontend_support"
        )
        resolution = scene_swift_source_relpaths(
            "shader_contract_resource_resolution"
        )
        planning = scene_swift_source_relpaths(
            "authored_effect_planning_support"
        )

        self.assertEqual(len(resolution), 9)
        self.assertEqual(resolution[:3], frontend_support)
        self.assertEqual(
            resolution[3:],
            (
                "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneShaderSourceGraphBuilder.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneShaderSourceResolver.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneResourceView.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneResourceIndex.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderContract/SceneShaderContractLoader.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderContract/SceneShaderContractLoader+SourceGraph.swift",
            ),
        )
        self.assertEqual(len(planning), 12)
        self.assertEqual(
            planning,
            (
                "MyWallpaperX/Core/SteamWorkshopScene/Format/SceneJSONValue.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneEffectDefinition.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredMaterialResolver.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderContract/SceneShaderSourceGraph.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderContract/SceneShaderContract.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneShaderSourceGraphBuilder.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneShaderSourceResolver.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneResourceView.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneResourceIndex.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderContract/SceneShaderContractLoader.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderContract/SceneShaderContractLoader+SourceGraph.swift",
            ),
        )
        self.assertEqual(
            set(planning),
            set(resolution)
            | {
                "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneEffectDefinition.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredMaterialResolver.swift",
            },
        )

    def test_shader_contract_and_effect_planning_consumers_use_canonical_sets(self) -> None:
        resolution_consumers = [
            "script/tests/test_scene_asset_catalog_resource_view.py",
            "script/tests/test_scene_material_render_state.py",
            "script/tests/test_scene_procedural_noise_profile.py",
            "script/tests/test_scene_runtime_input.py",
            "script/tests/test_scene_shader_contract.py",
        ]
        planning_consumers = [
            "script/tests/test_scene_blend_planner.py",
            "script/tests/test_scene_depth_parallax_planner.py",
            "script/tests/test_scene_godrays_planner.py",
            "script/tests/test_scene_pulse_planner.py",
            "script/tests/test_scene_shake_planner.py",
            "script/tests/test_scene_shine_planner.py",
            "script/tests/test_scene_transform_planner.py",
            "script/tests/test_scene_water_ripple_planner.py",
            "script/tests/test_scene_waterwaves_profile.py",
            "script/tests/test_scene_workshop_shift_hue_planner.py",
        ]
        for relative in resolution_consumers:
            text = (REPOSITORY_ROOT / relative).read_text(encoding="utf-8")
            with self.subTest(source_set="resolution", consumer=relative):
                self.assertIn("shader_contract_resource_resolution", text)
                self.assertNotIn("RenderGraph/ShaderContract/SceneShader", text)
                self.assertNotIn("Resources/SceneShaderSource", text)
                self.assertNotIn("Resources/SceneResourceView.swift", text)
                self.assertNotIn("Resources/SceneResourceIndex.swift", text)

        for relative in planning_consumers:
            text = (REPOSITORY_ROOT / relative).read_text(encoding="utf-8")
            with self.subTest(source_set="planning", consumer=relative):
                self.assertIn("authored_effect_planning_support", text)
                self.assertNotIn("RenderGraph/ShaderContract/SceneShader", text)
                self.assertNotIn("Resources/SceneShaderSource", text)
                self.assertNotIn("Resources/SceneResourceView.swift", text)
                self.assertNotIn("Resources/SceneResourceIndex.swift", text)
                self.assertNotIn("RenderGraph/SceneEffectDefinition.swift", text)
                self.assertNotIn(
                    "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
                    text,
                )
                self.assertNotIn("RenderGraph/SceneAuthoredMaterialResolver.swift", text)

        for relative in (
            "script/scene_material_program_census.py",
            "script/scene_shader_preparation_census.py",
        ):
            text = (REPOSITORY_ROOT / relative).read_text(encoding="utf-8")
            with self.subTest(source_set="census", consumer=relative):
                self.assertIn("authored_effect_planning_support", text)

    def test_shader_preparation_sets_conserve_the_complete_type_family(self) -> None:
        environment = scene_swift_source_relpaths("shader_variant_environment")
        preprocessing = scene_swift_source_relpaths(
            "shader_preprocessing_and_variant_implementation"
        )
        preparation = scene_swift_source_relpaths(
            "authored_shader_preparation_implementation"
        )
        generic_compiler = scene_swift_source_relpaths(
            "generic_shader_compiler_preparation_implementation"
        )

        self.assertEqual(len(environment), 2)
        self.assertEqual(len(preprocessing), 12)
        self.assertEqual(preprocessing[:2], environment)
        self.assertEqual(len(preparation), 14)
        self.assertEqual(preparation[:12], preprocessing)
        self.assertEqual(len(generic_compiler), 8)
        preparation_directory = (
            REPOSITORY_ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderPreparation"
        )
        self.assertEqual(
            {
                path.resolve()
                for source_set in (
                    "authored_shader_preparation_implementation",
                    "generic_shader_compiler_preparation_implementation",
                )
                for path in scene_swift_sources(source_set)
            },
            {path.resolve() for path in preparation_directory.glob("*.swift")},
        )

    def test_material_program_sets_conserve_the_complete_producer_lifecycle(self) -> None:
        model = scene_swift_source_relpaths("resolved_material_program_model")
        uniform = scene_swift_source_relpaths(
            "resolved_material_uniform_encoding"
        )
        schema = scene_swift_source_relpaths("resolved_material_shader_schema")
        texture_finalization = scene_swift_source_relpaths(
            "resolved_material_texture_finalization"
        )
        variant_preparation = scene_swift_source_relpaths(
            "resolved_material_variant_preparation"
        )
        frame_finalization = scene_swift_source_relpaths(
            "resolved_material_frame_finalization"
        )
        template_compilation = scene_swift_source_relpaths(
            "resolved_material_template_compilation"
        )
        complete = scene_swift_source_relpaths("resolved_material_program_all")

        self.assertEqual(len(model), 7)
        self.assertEqual(len(uniform), 1)
        self.assertEqual(len(schema), 4)
        self.assertEqual(len(texture_finalization), 7)
        self.assertEqual(len(variant_preparation), 9)
        self.assertEqual(
            frame_finalization,
            (
                *model,
                *uniform,
                *schema,
                *variant_preparation,
                *texture_finalization,
            ),
        )
        self.assertEqual(len(frame_finalization), 28)
        self.assertEqual(len(template_compilation), 3)
        self.assertEqual(
            complete,
            (
                *template_compilation,
                *frame_finalization,
            ),
        )
        self.assertEqual(len(complete), 31)

        material_program_directory = (
            REPOSITORY_ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/MaterialProgram"
        )
        self.assertEqual(
            {
                path.resolve()
                for path in scene_swift_sources("resolved_material_program_all")
            },
            {
                path.resolve()
                for path in material_program_directory.glob("*.swift")
            },
        )

    def test_frontend_consumers_use_the_canonical_source_set(self) -> None:
        consumers = [
            "script/scene_shader_preparation_census.py",
            "script/tests/test_scene_authored_shader_frontend.py",
            "script/tests/test_scene_graph_texture_publication.py",
            "script/tests/test_scene_resolved_material_pass_encoder.py",
            "script/tests/test_scene_resolved_material_program_derivation.py",
            "script/tests/test_scene_resolved_material_program_finalizer.py",
            "script/tests/test_scene_shader_color_contract.py",
        ]
        for relative in consumers:
            text = (REPOSITORY_ROOT / relative).read_text(encoding="utf-8")
            with self.subTest(consumer=relative):
                self.assertIn("scene_swift_source", text)
                self.assertNotIn(
                    "RenderGraph/ShaderFrontend/SceneAuthoredShader",
                    text,
                    "frontend implementation paths belong only in the canonical manifest",
                )

    def test_shader_preparation_consumers_use_the_canonical_source_set(self) -> None:
        consumers = {
            "authored_shader_preparation_implementation": [
                "script/scene_shader_preparation_census.py",
                "script/scene_material_program_census.py",
                "script/tests/test_scene_graph_texture_publication.py",
                "script/tests/test_scene_resolved_material_program_finalizer.py",
            ],
            "shader_preprocessing_and_variant_implementation": [
                "script/tests/test_scene_shader_preprocessor.py",
                "script/tests/test_scene_shader_variant_environment.py",
            ],
            "shader_variant_environment": [
                "script/tests/test_scene_resolved_material_pass_encoder.py",
                "script/tests/test_scene_resolved_material_program_derivation.py",
            ],
            "generic_shader_compiler_preparation_implementation": [
                "script/tests/test_scene_graph_texture_publication.py",
                "script/tests/test_scene_resolved_material_program_finalizer.py",
            ],
        }
        for source_set, paths in consumers.items():
            for relative in paths:
                text = (REPOSITORY_ROOT / relative).read_text(encoding="utf-8")
                with self.subTest(source_set=source_set, consumer=relative):
                    self.assertIn(source_set, text)
                    self.assertNotIn(
                        "RenderGraph/ShaderPreparation/Scene",
                        text,
                        "shader preparation implementation paths belong only "
                        "in the canonical manifest",
                    )

    def test_material_program_consumers_use_the_canonical_source_sets(self) -> None:
        consumers = {
            "resolved_material_frame_finalization": [
                "script/tests/test_scene_graph_texture_publication.py",
                "script/tests/test_scene_resolved_material_program_finalizer.py",
            ],
            "resolved_material_program_model": [
                "script/tests/test_scene_resolved_material_pass_encoder.py",
                "script/tests/test_scene_resolved_material_program_derivation.py",
            ],
        }
        for source_set, paths in consumers.items():
            for relative in paths:
                text = (REPOSITORY_ROOT / relative).read_text(encoding="utf-8")
                with self.subTest(source_set=source_set, consumer=relative):
                    self.assertIn(source_set, text)
                    self.assertNotIn(
                        "RenderGraph/MaterialProgram/SceneResolvedMaterial",
                        text,
                        "MaterialProgram implementation paths belong only "
                        "in the canonical manifest",
                    )

    def test_material_program_indirect_consumers_inherit_canonical_fixtures(self) -> None:
        inherited = {
            "script/tests/test_scene_resolved_material_execution_capability.py": (
                "runpy.run_path",
                "test_scene_resolved_material_program_finalizer.py",
            ),
            "script/tests/test_scene_resolved_material_graph_executor.py": (
                "runpy.run_path",
                "test_scene_graph_texture_publication.py",
            ),
        }
        for relative, markers in inherited.items():
            text = (REPOSITORY_ROOT / relative).read_text(encoding="utf-8")
            with self.subTest(consumer=relative):
                for marker in markers:
                    self.assertIn(marker, text)

    def test_loader_rejects_cycles_duplicates_unsafe_paths_and_missing_files(self) -> None:
        cases = {
            "cycle": {
                "a": {"includes": ["b"], "sources": []},
                "b": {"includes": ["a"], "sources": []},
            },
            "duplicate": {
                "a": {"includes": [], "sources": ["One.swift", "One.swift"]},
            },
            "unsafe": {
                "a": {"includes": [], "sources": ["../One.swift"]},
            },
            "missing": {
                "a": {"includes": [], "sources": ["Missing.swift"]},
            },
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source_root = root / "Scene"
            source_root.mkdir()
            (source_root / "One.swift").write_text("struct One {}\n", encoding="utf-8")
            for name, sets in cases.items():
                manifest = root / f"{name}.json"
                manifest.write_text(
                    json.dumps({
                        "schema_version": 1,
                        "source_root": "Scene",
                        "sets": sets,
                    }),
                    encoding="utf-8",
                )
                with self.subTest(name=name):
                    with self.assertRaises(SceneSwiftSourceSetError):
                        scene_swift_source_relpaths(
                            "a",
                            repository_root=root,
                            manifest_path=manifest,
                        )

    def test_basename_lookup_rejects_ambiguous_sources(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Scene/A").mkdir(parents=True)
            (root / "Scene/B").mkdir(parents=True)
            (root / "Scene/A/Shared.swift").write_text(
                "struct A {}\n", encoding="utf-8"
            )
            (root / "Scene/B/Shared.swift").write_text(
                "struct B {}\n", encoding="utf-8"
            )
            manifest = root / "ambiguous.json"
            manifest.write_text(
                json.dumps({
                    "schema_version": 1,
                    "source_root": "Scene",
                    "sets": {
                        "ambiguous": {
                            "includes": [],
                            "sources": ["A/Shared.swift", "B/Shared.swift"],
                        }
                    },
                }),
                encoding="utf-8",
            )

            with self.assertRaises(SceneSwiftSourceSetError):
                scene_swift_source_relpaths_by_basename(
                    "ambiguous",
                    repository_root=root,
                    manifest_path=manifest,
                )


if __name__ == "__main__":
    unittest.main()
