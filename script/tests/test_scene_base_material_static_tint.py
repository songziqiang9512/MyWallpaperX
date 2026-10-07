#!/usr/bin/env python3
"""Real prepared neutral-tint admission for static and scripted material colors.

The fixture uses self-authored shader stages. Only descriptor/value leaves are
doubled; preprocessing, schema, the neutral shader proof and compiler are real.
No Metal device, Workshop shader body or VM is executed.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_sampler_default_purpose as schema_fixture


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
FIXTURE = Path(__file__).with_name("fixtures") / "SceneBaseMaterialStaticTintHarness.swift"
SOURCES = list(dict.fromkeys([
    *schema_fixture.SWIFT_SOURCES,
    SCENE / "Compilation/Material/SceneEffectTextureInput.swift",
    SCENE / "Compilation/Material/SceneBaseMaterialColorModulationCompiler.swift",
]))

# Retain the nearest schema harness's unrelated failure DTOs. The descriptor
# leaves below are the only extra linkage and do not implement admission.
SUPPORT = schema_fixture.SUPPORT.partition(
    "nonisolated struct SceneRenderDescriptor"
)[0] + r'''
nonisolated enum SceneDocument {
    enum UserKind { case string, null }
    struct ShaderValue {
        var rawValue: String
        var components: [Double]?
        var userValueKind: UserKind? = nil
        var userBinding: String? = nil
        var timeline: Bool? = nil
        var timelineDiagnostics: [String] = []
        var scriptSource: String? = nil
        var scriptProperties: [String: SceneJSONValue]? = nil
        var bindingKeys: [String] = []
    }
}
nonisolated struct SceneRenderDescriptor {
    struct Layer {
        var id: Int = 57
        var imagePath: String? = "models/unseen/tint.json"
        var contentKind = "image"
        var visible: Bool? = true
        var utilityLayer: Bool? = nil
        var puppetMeshPath: String? = nil
        var staticModelPath: String? = nil
        var staticBaseTexturePath: String? = nil
        var usesPerspective: Bool? = false
        var effects: [Int] = []
        var dependencyLayerIDs: [Int] = []
        var authoredDependencies: [Int] = []
        var parentID: Int? = nil
        var childLayerIDs: [Int] = []
    }
    struct ModelMaterialLink {
        var modelPath: String
        var materialPath: String?
    }
    struct MaterialPassDescriptor {
        var materialPath = "materials/unseen/tint.json"
        var shaderPath: String? = "unseen/tint"
        var passIndex = 0
        var textureSlots: [String?] = ["unseen/source"]
        var texturePaths = ["unseen/source"]
        var userTextureInputs: [SceneEffectTextureInput?] = []
        var userShaderValues: [String: String] = [:]
        var blending: String? = "translucent"
        var depthTest: String? = "disabled"
        var depthWrite: String? = "disabled"
        var cullMode: String? = "nocull"
        var alphaWriting: String? = "default"
        var combos: [String: Int] = [:]
        var constantShaderValues: [String: SceneDocument.ShaderValue] = [:]
    }
    var layers: [Layer] = [.init()]
    var modelMaterialLinks: [ModelMaterialLink] = [
        .init(modelPath: "models/unseen/tint.json", materialPath: "materials/unseen/tint.json")
    ]
    var materialPasses: [MaterialPassDescriptor] = [.init()]
}
'''


class SceneBaseMaterialStaticTintTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-static-material-tint-")
        cls.addClassCleanup(cls.temporary.cleanup)
        root = Path(cls.temporary.name)
        support = root / "Support.swift"
        support.write_text(SUPPORT, encoding="utf-8")
        binary = root / "static-material-tint"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-modules")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-modules")
        environment["MWX_SCENE_GENERIC_SHADER_CACHE"] = str(root / "preparation-cache")
        compiled = subprocess.run(
            [swiftc, "-parse-as-library", *map(str, SOURCES), str(support), str(FIXTURE),
             "-framework", "Metal", "-framework", "CoreGraphics", "-framework", "ImageIO",
             "-module-cache-path", str(root / "swift-modules"), "-o", str(binary)],
            cwd=ROOT, capture_output=True, text=True, env=environment, timeout=180,
        )
        if compiled.returncode:
            raise AssertionError(compiled.stderr)
        completed = subprocess.run(
            [str(binary)], cwd=ROOT, capture_output=True, text=True,
            env=environment, check=True, timeout=30,
        )
        cls.result = json.loads(completed.stdout)

    def test_static_black_and_nonwhite_are_immutable_bindings(self) -> None:
        self.assertEqual(self.result["staticBlack"]["color"], [0, 0, 0])
        self.assertEqual(self.result["staticNonwhite"]["color"], [0.2, 0.4, 0.6])
        self.assertEqual(self.result["staticComma"]["color"], [0.2, 0.4, 0.6])
        for name in ["staticBlack", "staticNonwhite", "staticComma", "directVec2UV"]:
            with self.subTest(name=name):
                self.assertEqual(self.result[name]["count"], 1)
                self.assertFalse(self.result[name]["hasScript"])

    def test_script_binding_retains_the_existing_dynamic_resource_boundary(self) -> None:
        self.assertEqual(self.result["scriptDynamic"]["count"], 1)
        self.assertTrue(self.result["scriptDynamic"]["hasScript"])
        self.assertEqual(self.result["scriptDynamic"]["properties"], 1)
        self.assertEqual(self.result["scriptWithoutDynamicResource"]["count"], 0)

    def test_static_and_script_bindings_preserve_the_real_material_key(self) -> None:
        for name in ["staticBlack", "scriptDynamic"]:
            with self.subTest(name=name):
                self.assertEqual(self.result[name]["material"], "materials/unseen/tint.json")
                self.assertEqual(self.result[name]["key"], "surface-key")

    def test_normalized_duplicate_model_requests_have_one_binding(self) -> None:
        self.assertEqual(self.result["normalizedDuplicate"]["count"], 1)
        self.assertEqual(self.result["normalizedDuplicate"]["model"], "models/unseen/tint.json")

    def test_unknown_user_and_conflicting_wrappers_are_unadmitted(self) -> None:
        for name in ["unknownWrapper", "userColor", "userAlpha", "userShaderValue",
                     "partialScript", "scriptStaticConflict", "animatedColor"]:
            with self.subTest(name=name):
                self.assertEqual(self.result[name]["count"], 0)

    def test_non_neutral_scalar_operations_are_not_lowered(self) -> None:
        for name in ["brightnessTwo", "powerHalf", "scrollNonzero"]:
            with self.subTest(name=name):
                self.assertEqual(self.result[name]["count"], 0)

    def test_static_alpha_uses_the_proven_material_declaration(self) -> None:
        for name, want in [("alphaHalf", 0.5), ("staticAlphaZero", 0),
                           ("staticAlphaOne", 1), ("defaultAlphaQuarter", 0.25),
                           ("arbitraryStaticAlpha", 0.3), ("authoredStockAliasUsesExactAlphaKey", 0.25)]:
            with self.subTest(name=name):
                row = self.result[name]
                self.assertEqual(row["count"], 1)
                self.assertAlmostEqual(row["alpha"], want, places=6)
                self.assertFalse(row["alphaIsDynamic"])
        self.assertEqual(self.result["arbitraryStaticAlpha"]["alphaKey"], "coverage-parameter")
        self.assertEqual(self.result["defaultAlphaQuarter"]["alphaKey"], "")

    def test_strict_user_alpha_retains_prototype_material_identity(self) -> None:
        for name, key in [("strictUserAlpha", "opacity-key"),
                          ("arbitraryUserAlpha", "coverage-parameter")]:
            with self.subTest(name=name):
                row = self.result[name]
                self.assertEqual(row["count"], 1)
                self.assertEqual(row["alphaUserKey"], "liveOpacity")
                self.assertEqual(row["alphaKey"], key)
                self.assertTrue(row["alphaIsDynamic"])
                self.assertTrue(row["alphaTargetMatches"])

    def test_alpha_rejects_ambiguous_invalid_or_non_property_inputs(self) -> None:
        for name in ["negativeAlpha", "oversizedAlpha", "nonfiniteAlpha",
                     "alphaComponentMismatch", "extraAlphaToken", "multipleAlphaAliases",
                     "unknownAlphaWrapper", "emptyAlphaUser", "nullAlphaUser",
                     "scriptedAlpha", "animatedAlpha", "missingAlphaDeclaration", "hostAlphaUniform"]:
            with self.subTest(name=name):
                self.assertEqual(self.result[name]["count"], 0)

    def test_preserved_raw_tokens_must_agree_with_numeric_components(self) -> None:
        for name in ["malformedColor", "componentMismatch", "extraColorToken",
                     "nonfiniteColor", "outOfRangeColor", "malformedAlpha",
                     "malformedPower", "malformedScroll"]:
            with self.subTest(name=name):
                self.assertEqual(self.result[name]["count"], 0)

    def test_non_neutral_shader_body_cannot_borrow_the_color_interface(self) -> None:
        for name in ["alphaReplacement", "extraSample", "offsetUV", "fragmentOffsetUV",
                     "fragmentSwizzledUV", "fragmentUnlinkedVarying", "fragmentConstantUV"]:
            with self.subTest(name=name):
                self.assertEqual(self.result[name]["count"], 0)

    def test_position_requires_the_unoverridden_host_matrix(self) -> None:
        for name in ["customPositionMatrix", "explicitMVPOverride", "defaultMVPSeed"]:
            with self.subTest(name=name):
                self.assertEqual(self.result[name]["count"], 0)

    def test_position_and_uv_use_the_prepared_image_quad_attributes(self) -> None:
        for name in ["customPositionAttribute", "customUVAttribute"]:
            with self.subTest(name=name):
                self.assertEqual(self.result[name]["count"], 0)

    def test_sampler_metadata_requires_a_regular_color_input(self) -> None:
        for name in ["invalidSamplerMode", "invalidDepthFormat", "depthSampler", "rgbMaskSampler",
                     "normalMapFormat", "stockNoiseDefault"]:
            with self.subTest(name=name):
                self.assertEqual(self.result[name]["count"], 0)

    def test_actual_asset_purpose_cannot_be_replaced_with_color(self) -> None:
        for name in ["stockNormalAsset", "stockNoiseAsset"]:
            with self.subTest(name=name):
                self.assertEqual(self.result[name]["count"], 0)

    def test_scalar_roles_are_distinct_before_expected_values_are_indexed(self) -> None:
        for name in ["sharedScrollUniform", "sharedFragmentScalarUniform"]:
            with self.subTest(name=name):
                self.assertEqual(self.result[name]["count"], 0)

    def test_unsupported_consumer_shape_and_untyped_color_key_are_rejected(self) -> None:
        for name in ["hidden", "perspective", "puppet", "multipleConsumers",
                     "effects", "wrongColorKey"]:
            with self.subTest(name=name):
                self.assertEqual(self.result[name]["count"], 0)


if __name__ == "__main__":
    unittest.main()
