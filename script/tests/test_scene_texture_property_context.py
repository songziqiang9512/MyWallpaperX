#!/usr/bin/env python3
"""Real Project/Document/AssetCatalog/SourceFacts texture-context identity gate."""
from __future__ import annotations
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from script.tests.test_scene_property_live_routing import (
    CONTEXT_LEAF_STUBS, REPOSITORY_ROOT, SCENE_ROOT, SERVICE_SOURCE, method_body,
)


class SceneTexturePropertyContextTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        from script.tests import test_scene_alpha_display_builder_fixture as builder

        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-texture-context-")
        cls.work = Path(cls.temp.name)
        # Compile the real CPU identity declarations without the candidate's
        # Metal resource storage; do not copy their validation into this test.
        candidate = (SCENE_ROOT / "Resources/Textures/SceneTextureCandidate.swift").read_text()
        identities = candidate.split("/// Identity of raw scene color", 1)[0]
        purpose = (SCENE_ROOT / "Resources/Textures/SceneImageTextureUploader.swift").read_text()
        purpose = method_body(purpose, "nonisolated enum SceneTextureLoadPurpose:")
        purpose_reports = candidate[candidate.index("nonisolated extension SceneTextureLoadPurpose {") :]
        purpose_reports = purpose_reports.split("private nonisolated extension SceneTextureLoadPurpose", 1)[0]
        registry = (SCENE_ROOT / "Resources/Textures/SceneFrameTextureRegistry.swift").read_text()
        system_identity = method_body(registry, "nonisolated struct SceneSystemProviderTextureIdentity:")
        builder_leaves = builder.HARNESS_SOURCE.split("@main", 1)[0]
        modulation = (SCENE_ROOT / "Compilation/Material/SceneBaseMaterialColorModulationCompiler.swift").read_text()
        # Keep the provider's actual proof DTO as its declaration evolves;
        # this fixture still supplies no shader proof or renderer resource.
        modulation_stub = method_body(builder_leaves, "enum SceneBaseMaterialColorModulationCompiler {")
        builder_leaves = builder_leaves.replace(
            modulation_stub,
            modulation_stub.replace(
                method_body(modulation_stub, "struct Binding {"),
                method_body(modulation, "struct Binding: Sendable {"),
            ),
        )
        # This gate compiles the real provider compiler below. The shared
        # builder's no-material-proof leaf must not shadow the same owner.
        builder_leaves = builder_leaves.replace(method_body(
            builder_leaves, "enum SceneBaseMaterialProviderBindingCompiler {"
        ), "")
        harness = cls.work / "Probe.swift"
        harness.write_text("\n".join([
            builder_leaves, identities,
            purpose, purpose_reports, system_identity, CONTEXT_LEAF_STUBS,
            method_body((REPOSITORY_ROOT / "MyWallpaperX/Core/PlaybackControl/WallpaperEngineCommand.swift").read_text(),
                        "nonisolated enum ScenePlaybackTextureUpdateOutcome:"),
        ]))
        sources = builder.SWIFT_SOURCES + [
            REPOSITORY_ROOT / "MyWallpaperX/Core/PlaybackControl/ScenePlaybackShortcut.swift",
            SCENE_ROOT / "Runtime/Session/SceneDesktopWallpaperLaunchModels.swift",
            SCENE_ROOT / "Compilation/Material/SceneBaseMaterialProviderBindingProgram.swift",
            SCENE_ROOT / "Compilation/Material/SceneBaseMaterialProviderBindingCompiler.swift",
            SCENE_ROOT / "Compilation/Material/SceneBaseMaterialLightingProfile.swift",
            SCENE_ROOT / "Resources/Assets/SceneStockTextureSemanticRegistry.swift",
            SCENE_ROOT / "Rendering/Lighting/SceneLightSnapshot.swift",
            SCENE_ROOT / "Rendering/Lighting/SceneAuthoredShaderLightingInputs.swift",
            SCENE_ROOT / "Systems/Properties/SceneDynamicLayerValues.swift",
            REPOSITORY_ROOT / "MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopWebPropertyModels.swift",
            REPOSITORY_ROOT / "MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebDisplayConditionParsing.swift",
            REPOSITORY_ROOT / "MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebDisplayConditionSupport.swift",
            SERVICE_SOURCE,
        ]
        cls.binary = cls.work / "context"
        compiled = subprocess.run(
            ["swiftc", *map(str, sources), str(harness), "-module-cache-path", str(cls.work / "cache"),
             "-o", str(cls.binary)], capture_output=True, text=True,
        )
        if compiled.returncode:
            cls.temp.cleanup()
            raise AssertionError(compiled.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def probe(self, objects: list[dict], *, material_usertextures=None, definitions=None) -> dict:
        root = Path(tempfile.mkdtemp(dir=self.work, prefix="input-"))
        properties = {
            key: {"type": "scenetexture", "value": "", "order": index}
            for index, key in enumerate(definitions or [
                "effectCover", "instanceCover", "materialCover", "unusedCover",
                "systemCover", "path.png", "unknownCover", "overflowCover",
                "unsupportedBase", "mismatchCover", "shadowedCover",
            ])
        }
        if isinstance(definitions, dict):
            for key, kind in definitions.items():
                properties[key]["type"] = kind
                if kind == "bool":
                    properties[key]["value"] = False
        properties["group"] = {"type": "group", "text": "Cover controls", "order": -1}
        properties["help"] = {"type": "text", "text": "Choose an image", "order": 100}
        material = {"shader": "genericimage2", "textures": ["materials/fallback.png"]}
        if material_usertextures is not None:
            material["usertextures"] = material_usertextures
        files = {
            "project.json": {"type": "scene", "file": "scene.json", "general": {"properties": properties}},
            "scene.json": {"version": 3, "objects": objects},
            "models/image.json": {"material": "materials/image.json"},
            "materials/image.json": {"passes": [material]},
            "effects/custom/effect.json": {"passes": [{"material": "materials/effect.json"}]},
            "materials/effect.json": {"passes": [{"shader": "own_effect", "textures": [None, "materials/fallback.png"]}]},
        }
        for path, data in files.items():
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps(data))
        result = subprocess.run([str(self.binary), str(root)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertTrue(payload["parsed"])
        self.assertFalse(payload["wrongContentExists"])
        return payload

    @staticmethod
    def image(layer_id: int, **fields) -> dict:
        return {"id": layer_id, "image": "models/image.json", "size": "64 64", **fields}

    @staticmethod
    def effect(usertextures, **fields) -> dict:
        return {"file": "effects/custom/effect.json", "passes": [{"usertextures": usertextures, **fields}]}

    def test_effect_and_base_instance_consumers_are_actionable_with_group_context(self) -> None:
        result = self.probe([
            self.image(1, effects=[self.effect([None, "effectCover"])]),
            self.image(2, instance={"textures": ["materials/fallback.png"], "usertextures": ["instanceCover"]}),
        ])
        self.assertEqual(result["actionable"], ["effectCover", "instanceCover"])
        self.assertIn("unusedCover", result["declared"])
        self.assertNotIn("unusedCover", result["actionable"])
        self.assertIn("group", result["definitions"])

    def test_material_consumer_and_instance_precedence_use_real_base_contract(self) -> None:
        material = self.probe([self.image(1)], material_usertextures=["materialCover"])
        self.assertEqual(material["actionable"], ["materialCover"])
        replacement = self.probe([
            self.image(1, instance={"textures": ["materials/fallback.png"], "usertextures": ["instanceCover"]}),
        ], material_usertextures=["shadowedCover"])
        self.assertEqual(replacement["actionable"], ["instanceCover"])
        rejected = self.probe([
            self.image(1, instance={"textures": ["materials/fallback.png", "materials/fallback.png"],
                                  "usertextures": [None, "unsupportedBase"]}),
            self.image(2, instance={"textures": ["materials/other.png"], "usertextures": ["mismatchCover"]}),
        ])
        self.assertFalse(rejected["contextExists"])
        self.assertEqual(rejected["actionable"], [])

    def test_system_path_unknown_undeclared_and_out_of_range_inputs_are_not_controls(self) -> None:
        result = self.probe([
            self.image(1, effects=[self.effect([
                None, {"type": "system", "name": "systemCover"}, "path.png",
                {"name": "unknownCover"}, "notDeclared",
            ])]),
            self.image(2, effects=[self.effect([None] * 8 + ["overflowCover"])]),
        ])
        self.assertFalse(result["contextExists"])
        self.assertEqual(result["actionable"], [])
        # One valid authored candidate in a separate supported slot/pass keeps
        # its control; system providers do not become file properties.
        mixed = self.probe([
            self.image(1, effects=[self.effect(["effectCover", {"type": "system", "name": "systemCover"}])]),
        ])
        self.assertEqual(mixed["actionable"], ["effectCover"])

    def test_unreferenced_texture_definitions_do_not_create_a_context(self) -> None:
        result = self.probe([self.image(1)])
        self.assertTrue(result["declared"])
        self.assertFalse(result["contextExists"])

    def test_declared_underscore_keys_survive_document_catalog_and_source_facts(self) -> None:
        result = self.probe([
            self.image(1, effects=[self.effect([None, "_1"])]),
            self.image(2, instance={"textures": ["materials/fallback.png"],
                                    "usertextures": ["_renamedCover"]}),
        ], definitions=["_1", "_renamedCover"])
        self.assertEqual(result["actionable"], ["_1", "_renamedCover"])
        self.assertEqual(result["documentTextureInputs"], ["property:_1", "property:_renamedCover"])
        material = self.probe([self.image(1)], material_usertextures=["_material"],
                              definitions=["_material"])
        self.assertEqual(material["actionable"], ["_material"])
        self.assertEqual(material["materialTextureInputs"], ["property:_material"])
        precedence = self.probe([
            self.image(1, instance={"textures": ["materials/fallback.png"],
                                    "usertextures": ["_instance"]}),
        ], material_usertextures=["_material"], definitions=["_material", "_instance"])
        self.assertEqual(precedence["actionable"], ["_instance"])
        self.assertEqual(precedence["documentTextureInputs"], ["property:_instance"])
        self.assertEqual(precedence["materialTextureInputs"], ["property:_material"])

    def test_declaration_kind_paths_and_explicit_objects_keep_their_own_identity(self) -> None:
        definitions = {"_1": "scenetexture", "_badKind": "bool", "path.png": "scenetexture",
                       "_rt_FullFrameBuffer": "scenetexture"}
        result = self.probe([self.image(1, effects=[self.effect([
            None, "_badKind", "_notDeclared", "path.png", "_rt_FullFrameBuffer",
            {"type": "system", "name": "_1"}, {"type": "usershortcut", "name": "_1"},
            {"type": "future", "name": "_1"},
        ])])], definitions=definitions)
        self.assertFalse(result["contextExists"])
        self.assertEqual(result["documentTextureInputs"], [
            "path:_badKind", "path:_notDeclared", "path:path.png", "path:_rt_FullFrameBuffer",
            "system:_1", "userShortcut:_1", "unknown:_1",
        ])
        material = self.probe([self.image(1)], material_usertextures=["_badKind"],
                              definitions=definitions)
        self.assertFalse(material["contextExists"])
        self.assertEqual(material["materialTextureInputs"], ["path:_badKind"])


if __name__ == "__main__":
    unittest.main()
