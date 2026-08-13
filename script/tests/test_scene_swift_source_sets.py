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
        self.assertEqual(len(implementation), 35)
        self.assertEqual(core, (*support, *implementation))
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

    def test_shader_preparation_sets_conserve_the_complete_type_family(self) -> None:
        environment = scene_swift_source_relpaths("shader_variant_environment")
        preprocessing = scene_swift_source_relpaths(
            "shader_preprocessing_and_variant_implementation"
        )
        preparation = scene_swift_source_relpaths(
            "authored_shader_preparation_implementation"
        )

        self.assertEqual(len(environment), 2)
        self.assertEqual(len(preprocessing), 12)
        self.assertEqual(preprocessing[:2], environment)
        self.assertEqual(len(preparation), 14)
        self.assertEqual(preparation[:12], preprocessing)
        preparation_directory = (
            REPOSITORY_ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/ShaderPreparation"
        )
        self.assertEqual(
            {
                path.resolve()
                for path in scene_swift_sources(
                    "authored_shader_preparation_implementation"
                )
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

        self.assertEqual(len(model), 6)
        self.assertEqual(len(uniform), 1)
        self.assertEqual(len(schema), 4)
        self.assertEqual(len(texture_finalization), 7)
        self.assertEqual(len(variant_preparation), 5)
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
        self.assertEqual(len(frame_finalization), 23)
        self.assertEqual(len(template_compilation), 3)
        self.assertEqual(complete, (*template_compilation, *frame_finalization))
        self.assertEqual(len(complete), 26)

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


if __name__ == "__main__":
    unittest.main()
