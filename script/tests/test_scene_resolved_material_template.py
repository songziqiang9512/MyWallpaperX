#!/usr/bin/env python3

"""R3 static material Template projection and fail-closed graph boundaries."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
PROGRAM_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialProgram.swift"
TEXTURE_CANDIDATE_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureCandidate.swift"
SWIFT_SOURCES = [
    SCENE_ROOT / "Compilation/Material/SceneRenderTargetVocabulary.swift",
    SCENE_ROOT / "Compilation/Material/SceneAuthoredMaterialResolver.swift",
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneScriptValueOwnership.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneNamedTextureReference.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderContract/SceneShaderSourceGraph.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneShaderMalformedMetadataAdmission.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderContract/SceneShaderLegacyAnnotationJSON.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderContract/SceneShaderContract.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneEffectTextureInput.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneMaterialRenderState.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialEffectIngress.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialScriptBindingClassifier.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialTemplateCompiler.swift",
]


SUPPORT = r'''
import Foundation

nonisolated enum SceneDynamicTarget: Hashable {
    case effectConstant(layerID: Int, effectIndex: Int, passIndex: Int, name: String)
    case materialConstant(layerID: Int, passIndex: Int, name: String, materialPath: String)
}

nonisolated enum SceneShaderCompatibilityTarget: String, Hashable {
    case unprofiledMetal = "unprofiled-metal"
    case windowsDX11ShaderModel4 = "windows-dx11-sm4"
}

enum SceneShaderUserValueKind {
    case null
    case number
    case string
}

enum SceneDocument {
    struct ShaderValue {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let userValueKind: SceneShaderUserValueKind?
        let components: [Double]?
        let timeline: Bool?
        let timelineDiagnostics: [String]
        let scriptSource: String?
        let bindingKeys: [String]

        init(
            rawValue: String,
            valueKind: String = "number",
            userBinding: String? = nil,
            userValueKind: SceneShaderUserValueKind? = nil,
            components: [Double]? = nil,
            timeline: Bool? = nil,
            timelineDiagnostics: [String] = [],
            scriptSource: String? = nil,
            bindingKeys: [String] = []
        ) {
            self.rawValue = rawValue
            self.valueKind = valueKind
            self.userBinding = userBinding
            self.userValueKind = userValueKind
                ?? userBinding.map { _ in .string }
            self.components = components
            self.timeline = timeline
            self.timelineDiagnostics = timelineDiagnostics
            self.scriptSource = scriptSource
            self.bindingKeys = bindingKeys
        }
    }
}

nonisolated struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }
        let id: String
        let passes: [PassDescriptor]
    }
    struct Layer {
        let id: Int
        let effects: [EffectDescriptor]
    }
    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let shaderPath: String?
        let textureSlots: [String?]
        let userTextureInputs: [SceneEffectTextureInput?]
        let combos: [String: Int]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        let userShaderValues: [String: String]
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String?
    }
    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
}
'''


HARNESS = (Path(__file__).parent / "fixtures/scene_resolved_material_template.swift").read_text(encoding="utf-8")


def source_prefix(path: Path, marker: str) -> str:
    source = path.read_text(encoding="utf-8")
    prefix, separator, _ = source.partition(marker)
    if not separator:
        raise RuntimeError(f"production source marker missing: {path.name}: {marker}")
    return prefix


class SceneResolvedMaterialTemplateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-resolved-material-template-"
        )
        temporary = Path(cls.temporary_directory.name)
        vfs_source = temporary / "SceneVFSAssetPath.swift"
        template_source = temporary / "SceneResolvedMaterialTemplate.swift"
        support = temporary / "Support.swift"
        harness = temporary / "Harness.swift"
        vfs_source.write_text(
            source_prefix(TEXTURE_CANDIDATE_SOURCE, "/// Purpose is part"),
            encoding="utf-8",
        )
        template_source.write_text(
            source_prefix(PROGRAM_SOURCE, "/// One fully resolved material pass"),
            encoding="utf-8",
        )
        support.write_text(SUPPORT, encoding="utf-8")
        harness.write_text(HARNESS, encoding="utf-8")
        binary = temporary / "resolved-material-template"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(temporary / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(temporary / "swift-cache")
        compilation = subprocess.run(
            [
                swiftc,
                *(str(source) for source in SWIFT_SOURCES),
                str(vfs_source),
                str(template_source),
                str(support),
                str(harness),
                "-o",
                str(binary),
            ],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            env=environment,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
            env=environment,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def assert_contracts(self, keys: list[str]) -> None:
        for key in keys:
            self.assertTrue(self.result[key], key)

    def test_template_preserves_typed_authored_structure(self) -> None:
        self.assert_contracts([
            "eightSlotsPreserved",
            "holesPreserved",
            "precedenceLowToHigh",
            "typedRequests",
            "namedLayerTargetIsProvider",
            "typedGraphRole",
            "priorEffectOutputIsTypedIngress",
            "combosDeterministic",
            "inheritedInactiveCombosTyped",
            "annotationDefaultStaysOutOfTemplate",
            "stateParsedOnly",
        ])

    def test_graph_and_texture_inputs_fail_closed(self) -> None:
        self.assert_contracts([
            "unknownFailsClosed",
            "slotShapeFailsClosed",
            "blockedGraphRejected",
            "invalidEffectIngressRejected",
            "duplicateNodeRejected",
            "orphanNodeRejected",
            "duplicatePartitionRejected",
            "ownerMismatchRejected",
            "graphUniverseRejected",
        ])

    def test_uniforms_separate_value_producers_from_script_attachments(self) -> None:
        self.assert_contracts([
            "staticExactBits",
            "exactScalarProjectionProven",
            "malformedScalarProjectionRejected",
            "constantFallbackMergedWithDynamic",
            "multipleValueContributorsPreserved",
            "timelineControlSeparated",
            "unknownScriptTypedUnproven",
            "boundedScriptNeedsExactProof",
            "boundedScriptExactProofBecomesSoleValue",
            "boundedPropertyScriptNeedsExactProof",
            "boundedPropertyScriptExactProofBecomesSoleValue",
            "boundedNullUserScriptNeedsExactProof",
            "boundedNullUserScriptExactProofBecomesSoleValue",
            "boundedNullUserProofDoesNotAuthorizeOtherProducers",
            "colorUserScriptOwnsSingleValue",
            "colorUserUnprovenRemainsAttached",
            "colorUserMalformedRejected",
        ])

    def test_vfs_and_shader_lexical_boundaries_match_production(self) -> None:
        self.assert_contracts([
            "assetVFSBoundaries",
            "shaderNormalizationMatchesLoader",
            "shaderEscapesRejected",
            "sourceGraphRequired",
            "malformedMetadataSkippedButPreserved",
            "malformedSamplerMetadataRejected",
            "otherShaderDiagnosticsRejected",
        ])

    def test_failures_are_bounded_and_finalizer_codes_are_stable(self) -> None:
        self.assert_contracts(["failureDetailsBounded", "finalizerFailuresStable"])

    def test_source_material_uses_real_pass_identity_and_shared_projection(self) -> None:
        self.assert_contracts([
            "sourceResolved", "sourceNoEffectIdentity", "sourceSharedTextureProjection",
            "sourceSharedUniformProjection", "sourceStateAuthorshipPreserved",
            "sourceScriptProofCannotBorrowAnotherLayerIdentity",
            "sourceGraphBindingRejected", "sourceIdentityRejected",
            "sourceResolverSlotOverflowRejected",
        ])


if __name__ == "__main__":
    unittest.main()
