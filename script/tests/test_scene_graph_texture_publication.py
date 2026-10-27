#!/usr/bin/env python3

"""Generation-scoped graph publications and immutable snapshot overlays."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402


SWIFT_SOURCES = list(dict.fromkeys([
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift",
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    *scene_swift_sources("scene_resource_input"),
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneDynamicSnapshot.swift",
    *scene_swift_sources("authored_shader_frontend_support"),
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetPlan+Clear.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetPlan+Extent.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetFormat.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneLayerFullFramePairPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphExecutionState.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphExecutionState+Validation.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphExecutionState+Identity.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetTable.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetTable+Mapped.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetLease.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetLease+Publication.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneMaterialRenderState.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneMaterialRenderState+Compilation.swift",
    SCENE_ROOT / "Compilation/ShaderContract/SceneShaderCacheIdentity.swift",
    *scene_swift_sources("authored_shader_frontend_implementation"),
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Bindings/SceneAuthoredShaderFrameInputs.swift",
    SCENE_ROOT / "Rendering/Geometry/SceneMatrix.swift",
    SCENE_ROOT / "Rendering/Geometry/SceneDirectDrawOutputGeometry.swift",
    *scene_swift_sources("authored_shader_preparation_implementation"),
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader+Resample.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneCompressedTextureUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureMipUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureCandidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneStockTextureSemanticRegistry.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSlotBinding.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureProviderPublication.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneNamedTextureReference.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneFrameTextureRegistry.swift",
    *scene_swift_sources("resolved_material_frame_finalization"),
]))


SUPPORT = r'''
import Foundation
import Metal

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
        case shaderDirectiveUnsupported = "shader-directive-unsupported", shaderModuleResolutionRejected = "shader-module-resolution-rejected"
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
    case notApplicable
    case rejected(SceneEffectStageCompilerFailure)
    case accepted(Value)
}

nonisolated struct SceneResolvedMaterialNode {
    enum TextureProvenance: String, Hashable {
        case material, instance, userTexture, explicitBinding
    }
}

struct SceneXRayExecutionPlan {}

struct SceneEffectStageExecutionPlan {
    let layerID: Int
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole
    var xRay: SceneXRayExecutionPlan? { nil }

    var supportsUnifiedLogicalTargetStage: Bool { false }
    var supportsUnifiedHistoryTargetStage: Bool { false }
    var supportsUnifiedFullFrameComposeStage: Bool { false }
    var supportsUtilityCapture: Bool { true }
    var liveConsumerTargets: Set<SceneDynamicTarget> { [] }
}

struct SceneGraphCommandRuntime {
    init?(
        plan: SceneGraphRenderTargetPlan,
        texturesByIdentity: [
            SceneAuthoredEffectRenderPlan.TextureIdentity: MTLTexture
        ]
    ) {
        _ = plan
        _ = texturesByIdentity
    }
}

final class SceneGraphRenderTargetResidencyPin {
    func release() {}
}

final class SceneOffscreenTexturePool {
    struct Pair {}
    struct PinnedTexture {
        let texture: MTLTexture
        let pin: SceneGraphRenderTargetResidencyPin
    }

    // Publication-only gates never reserve terminal storage. The terminal
    // graph gate replaces this disabled adapter with the production pool.
    func reserveTerminalInput(
        layerID: Int, slot: Int, width: Int, height: Int,
        commandBuffer: MTLCommandBuffer
    ) -> PinnedTexture? { nil }
}
'''


HARNESS = (Path(__file__).parent / "fixtures/SceneGraphTexturePublicationHarness.swift").read_text(
    encoding="utf-8"
)


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneGraphTexturePublicationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-graph-texture-publication-"
        )
        root = Path(cls.temporary_directory.name)
        support = root / "Support.swift"
        harness = root / "Harness.swift"
        binary = root / "graph-texture-publication-test"
        support.write_text(SUPPORT, encoding="utf-8")
        harness.write_text(HARNESS, encoding="utf-8")
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        scene_cache = root / "scene-cache"
        scene_cache.mkdir()
        environment["MWX_SCENE_GENERIC_SHADER_CACHE"] = str(scene_cache)
        environment["MWX_SCENE_PIPELINE_BINARY_ARCHIVE"] = str(scene_cache)
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                "-parse-as-library",
                "-D",
                "SCENE_GRAPH_TESTING",
                str(support),
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework",
                "Metal",
                "-framework",
                "CoreGraphics",
                "-framework",
                "ImageIO",
                "-module-cache-path",
                str(root / "module-cache"),
                "-o",
                str(binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr or completed.stdout)
        cls.result = json.loads(completed.stdout)
        if not cls.result["metalAvailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_graph_publication_and_program_overlay(self) -> None:
        self.assertEqual(
            [name for name, passed in self.result["positive"].items() if not passed],
            [],
            self.result,
        )

    def test_invalid_graph_atoms_fail_closed(self) -> None:
        self.assertEqual(
            self.result["failures"],
            {
                "unresolved": "colorRepresentationUnresolved",
                "zeroGeneration": "invalidGeneration",
                "unknownToken": "unknownPhysicalToken",
                "wrongDescriptor": "descriptorMismatch",
                "pairToken": "unknownPhysicalToken",
                "r8Publication": "storageSemanticUnavailable",
                "rg88WrongStorage": "storageSemanticUnavailable",
                "r16WrongStorage": "storageSemanticUnavailable",
                "rg16WrongStorage": "storageSemanticUnavailable",
                "forgedR8AuthoredFormat": "rejected",
                "forgedR8WrongAuthoredFormat": "rejected",
                "forgedR8ColorPurpose": "rejected",
                "duplicateTokenAtLeaseCreation": "physicalAlias",
                "wrongTexture": "textureMismatch",
                "endpointViaFramebuffer": "invalidLogicalIdentity",
                "invalidFullFrameIdentity": "invalidLogicalIdentity",
                "zeroFullFrameGeneration": "invalidGeneration",
                "wrongPairMember": "pairMemberMismatch",
                "incompleteOverlay": "rejected",
                "wrongRequestOverlay": "rejected",
                "invalidGraphRewrap": "rejected",
            },
        )


if __name__ == "__main__":
    unittest.main()
