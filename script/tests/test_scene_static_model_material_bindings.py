#!/usr/bin/env python3

"""Exact authored static-model material keys through schema and properties.

The shader stages in the Swift fixture are self-authored declarations and a
constant output. This CPU harness uses the production schema,
binding compiler, property program, and dynamic snapshot resolver. It does
not create a Metal device or evaluate a real Workshop shader body.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import test_scene_sampler_default_purpose as schema_fixture
import test_scene_static_model_material_properties as property_fixture


ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
FIXTURE = Path(__file__).with_name("fixtures") / "SceneStaticModelMaterialBindingsHarness.swift"
SOURCES = list(dict.fromkeys([
    *schema_fixture.SWIFT_SOURCES,
    *property_fixture.SOURCES,
    SCENE_ROOT / "Compilation/Material/SceneResolvedMaterialShaderSchema+StaticModelInterface.swift",
    SCENE_ROOT / "Compilation/Material/SceneStaticModelMaterialBindingCompiler.swift",
    SCENE_ROOT / "Resources/Providers/SceneStockNoiseTextureStore.swift",
]))

# Only the descriptor/ShaderValue leaves are doubled. Schema and
# property evaluation remain real. These unrelated compiler failure DTOs are
# the same linkage boundary used by the existing shader schema fixture.
SUPPORT = r'''
import Foundation

nonisolated enum SceneEffectStageCompilerBackend { case authoredShader }
nonisolated struct SceneEffectStageCompilerFailure {
    enum Phase: String { case shaderPreprocessor = "shader-preprocessor"; case invariant }
    enum Code: String {
        case shaderStageMissing = "shader-stage-missing"
        case shaderSourceGraphMissing = "shader-source-graph-missing"
        case shaderSourceIdentityMismatch = "shader-source-identity-mismatch"
        case shaderVariantInvalid = "shader-variant-invalid"
        case shaderIncludeMissing = "shader-include-missing"
        case shaderIncludeAmbiguous = "shader-include-ambiguous"
        case shaderIncludeCycle = "shader-include-cycle"
        case shaderDirectiveUnsupported = "shader-directive-unsupported"
        case shaderModuleResolutionRejected = "shader-module-resolution-rejected"
        case shaderConditionInvalid = "shader-condition-invalid"
        case shaderPreprocessorBudgetExceeded = "shader-preprocessor-budget-exceeded"
        case shaderPreprocessorDiagnostic = "shader-preprocessor-diagnostic"
        case shaderPreparationInvariant = "shader-preparation-invariant"
    }
    let backend: SceneEffectStageCompilerBackend
    let phase: Phase
    let code: Code
    let details: [String]
}
nonisolated enum SceneEffectStageBackendCompileResult<Value> {
    case notApplicable, rejected(SceneEffectStageCompilerFailure), accepted(Value)
}
nonisolated struct SceneResolvedMaterialNode {
    enum TextureProvenance: String, Hashable { case material, instance, userTexture, explicitBinding }
}
'''


class SceneStaticModelMaterialBindingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-model-material-bindings-")
        root = Path(cls.temporary.name)
        cls.addClassCleanup(cls.temporary.cleanup)
        support = root / "Support.swift"
        support.write_text(SUPPORT + property_fixture.STUBS, encoding="utf-8")
        cls.binary = root / "model-material-bindings"
        cls.environment = os.environ.copy()
        cls.environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-modules")
        cls.environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-modules")
        cls.environment["MWX_SCENE_GENERIC_SHADER_CACHE"] = str(root / "preparation-cache")
        compiled = subprocess.run(
            [swiftc, "-parse-as-library", *map(str, SOURCES), str(support), str(FIXTURE),
             "-framework", "Metal", "-framework", "CoreGraphics", "-framework", "ImageIO",
             "-module-cache-path", str(root / "swift-modules"), "-o", str(cls.binary)],
            capture_output=True, text=True, env=cls.environment,
        )
        if compiled.returncode != 0:
            raise AssertionError(compiled.stderr)

    def result(self, group: str) -> dict:
        completed = subprocess.run(
            [str(self.binary), group], capture_output=True, text=True, env=self.environment,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return json.loads(completed.stdout)

    def test_same_uniforms_preserve_annotation_keys_and_ignore_stale_aliases(self) -> None:
        result = self.result("identities")
        self.assertEqual(result["uppercase"]["state"], "authored")
        self.assertEqual(result["lowercase"]["state"], "authored")
        self.assertEqual(result["uppercase"]["keys"], ["Alpha", "Color", "Brigtness"])
        self.assertEqual(result["lowercase"]["keys"], ["alpha", "color", "brightness"])
        self.assertEqual(result["uppercase"]["components"], [[0.02], [0.2, 0.4, 0.6], [1.25]])
        self.assertEqual(result["lowercase"]["components"], [[0.8], [0.6, 0.4, 0.2], [3.0]])
        self.assertEqual(result["renamed"]["keys"], ["opacityGain", "surfaceTint", "lightGain"])
        self.assertEqual(result["renamed"]["components"], [[0.35], [0.1, 0.3, 0.9], [2.0]])

    def test_unproven_schema_preserves_legacy_and_proven_input_conflict_rejects(self) -> None:
        result = self.result("invalidSchema")
        self.assertGreaterEqual(len(result), 10)
        for name, value in result.items():
            with self.subTest(name=name):
                expected = "rejected" if name == "bothUniformAndAnnotationAuthored" else "unavailable"
                self.assertEqual(value["state"], expected)
                self.assertEqual(value["keys"], [])
                self.assertTrue(value["reason"])

    def test_defaults_require_exact_finite_components(self) -> None:
        result = self.result("defaults")
        self.assertEqual(result["annotation"]["state"], "authored")
        self.assertEqual(result["annotation"]["keys"], [None, None, None])
        self.assertEqual(result["annotation"]["components"], [[0.125], [0.25, 0.5, 0.75], [1.75]])
        self.assertEqual(result["directUniform"]["keys"], ["g_TintAlpha", "g_TintColor", "g_Brightness"])
        self.assertEqual(result["directUniform"]["components"], [[0.4], [0.9, 0.2, 0.1], [2.5]])
        for name, value in result.items():
            if name in {"annotation", "directUniform"}:
                continue
            with self.subTest(name=name):
                expected = "unavailable" if name in {"emptyDefault", "nonFiniteDefault"} else "rejected"
                self.assertEqual(value["state"], expected)

    def test_exact_property_wrappers_publish_the_prepared_key_without_peer_leaks(self) -> None:
        result = self.result("properties")
        self.assertEqual(result["bindingCount"], 8)
        self.assertEqual(result["definitionCount"], 8)
        self.assertEqual(result["instructionCount"], 8)
        self.assertEqual(result["diagnostics"], 0)
        self.assertEqual(result["layer7"], [[0.3], [0.1, 0.5, 0.9], [2.0]])
        self.assertEqual(result["layer8"], [[0.7], [0.9, 0.5, 0.1], [3.0]])
        self.assertEqual(result["emission7"], [[0.7, 0.3, 0.2], [4.0]])
        self.assertEqual(result["claimedEmissionBindingCount"], 2)
        self.assertEqual(result["claimedEmissionTargetCount"], 2)
        self.assertTrue(result["exactTargets"])
        self.assertTrue(result["staleAliasesAbsent"])
        self.assertTrue(result["peerMaterialsAbsent"])
        self.assertTrue(result["independentNextFrame"])
        self.assertEqual(result["invalidWrapperBindings"], 0)
        self.assertEqual(result["rejectedMaterialBindings"], 0)
        self.assertEqual(result["unavailableState"], "unavailable")
        self.assertEqual(result["unavailableBindingCount"], 5)
        self.assertEqual(result["unavailableDiagnostics"], 0)
        self.assertEqual(result["unavailableLegacyValues"], [[0.3], [0.1, 0.5, 0.9], [2.0], [0.7, 0.3, 0.2], [4.0]])

    def test_host_builtin_and_source_failure_have_explicit_states(self) -> None:
        result = self.result("sources")
        self.assertEqual(result["hostBuiltin"]["state"], "hostBuiltin")
        self.assertEqual(result["missing"]["state"], "unavailable")
        self.assertEqual(result["ambiguous"]["state"], "unavailable")
        self.assertEqual(result["noPassZero"]["state"], "unavailable")

    def test_unconditional_interface_does_not_need_runtime_texture_facts(self) -> None:
        result = self.result("proofBoundaries")
        for name in ["noReadinessFacts", "noFormatFacts", "requireDirectiveAdmitted"]:
            with self.subTest(name=name):
                self.assertEqual(result[name]["state"], "authored")
                self.assertEqual(result[name]["keys"], ["Alpha", None, None])
                self.assertEqual(result[name]["components"][0], [0.02])
        for name in ["conditionalInterface", "conditionalDuplicate", "conditionalKeyCollision",
                     "macroRewrite", "unresolvedInclude", "vertexFragmentConflict",
                     "sameLineHiddenDeclaration", "bareMacroPrefix", "explicitUniformCombo",
                     "explicitTypeCombo", "authoredUniformCombo", "samplerUniformCombo",
                     "malformedRequireRejected"]:
            with self.subTest(name=name):
                self.assertEqual(result[name]["state"], "unavailable")
                self.assertEqual(result[name]["keys"], [])
                self.assertTrue(result[name]["reason"])

    def test_selected_numeric_input_must_match_the_preserved_raw_value(self) -> None:
        result = self.result("numericInput")
        for name in ["malformedScalar", "malformedVector", "malformedWrapper", "projectionMismatch"]:
            with self.subTest(name=name):
                self.assertEqual(result[name]["state"], "rejected")
                self.assertEqual(result[name]["keys"], [])
                self.assertTrue(result[name]["reason"])
        self.assertEqual(result["unknownKind"]["state"], "unavailable")
        self.assertEqual(result["whitespacePropertyKey"]["state"], "unavailable")
        self.assertEqual(result["whitespaceStaticKey"]["state"], "authored")
        self.assertEqual(result["whitespaceStaticKey"]["keys"], [" Alpha ", None, None])
        self.assertEqual(result["whitespaceStaticKey"]["components"][0], [0.02])
        for name in ["commaVector", "tabVector", "commaWrapper"]:
            with self.subTest(name=name):
                self.assertEqual(result[name]["state"], "authored")
                self.assertEqual(result[name]["keys"], [None, "Color", None])
                self.assertEqual(result[name]["components"][1], [0.2, 0.4, 0.6])

    def test_prepared_default_albedo_preserves_presence_and_independent_uniform_failure(self) -> None:
        result = self.result("albedoDefaults")
        for name in ["omitted", "null", "normalOnly", "unconditionalInclude", "tailReadiness"]:
            with self.subTest(name=name):
                self.assertEqual(result[name], "util/white")
        self.assertEqual(result["colored"], "fixtures/colored")
        self.assertEqual(result["unavailableUniformState"], "unavailable")
        self.assertEqual(result["unavailableUniformDefault"], "util/white")
        self.assertEqual(result["unrelatedFormatVariantFailure"], "texture-format-unavailable")
        self.assertEqual(result["unrelatedFormatDefault"], "util/white")
        self.assertEqual(result["explicitStillAuthored"], "fixtures/authored-blue")
        self.assertEqual(result["badPathStillAuthored"], "fixtures/missing-explicit")
        for name in ["explicit", "badPath", "user", "userPath", "passOne", "missingContract", "duplicateContract"]:
            with self.subTest(name=name):
                self.assertIsNone(result[name])

    def test_default_albedo_rejects_ambiguous_conditional_or_noncolor_metadata(self) -> None:
        result = self.result("albedoDefaults")
        for name in ["conditionalSameName", "conditionalOnly", "conditionalInclude", "readiness",
                     "macroRename", "conditionalMacroAlias", "noDefault", "opacityMode", "format", "internal", "conflict",
                     "malformedDefault", "invalidAssetPath", "samplerArray", "graphDigestMismatch",
                     "graphRawMismatch", "annotationComboSampler", "annotationComboType",
                     "tokenPasteOtherVertex", "tokenPasteOtherFragment", "emptyPrefixHiddenConditional",
                     "materialNormal", "materialNoise", "graphMaterialAlias", "registeredDataDefault",
                     "registeredNoiseDefault"]:
            with self.subTest(name=name):
                self.assertIsNone(result[name])


if __name__ == "__main__":
    unittest.main()
