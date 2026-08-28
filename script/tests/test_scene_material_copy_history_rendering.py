#!/usr/bin/env python3

"""GPU pixel gate for generic material-copy-history execution."""

from __future__ import annotations

import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
EXECUTOR_GATE = Path(__file__).with_name(
    "test_scene_resolved_material_graph_executor.py"
)
EXECUTOR_FIXTURE = runpy.run_path(str(EXECUTOR_GATE))
POOL_FIXTURE = runpy.run_path(
    str(Path(__file__).with_name("test_scene_offscreen_texture_pool.py"))
)
RUNTIME_FIXTURE = runpy.run_path(
    str(Path(__file__).with_name("test_scene_resolved_material_runtime_bridge.py"))
)
SWIFT_SOURCES = list(dict.fromkeys([
    *EXECUTOR_FIXTURE["CONTRACT_FIXTURE"]["SWIFT_SOURCES"],
    *POOL_FIXTURE["SWIFT_SOURCES"],
    *(
        path
        for path in RUNTIME_FIXTURE["SUBMISSION_SWIFT_SOURCES"]
        if path.name != "SceneResolvedMaterialRuntimeBridge.swift"
    ),
]))
SUPPORT = (
    EXECUTOR_FIXTURE["SUPPORT"]
    .replace(
        """struct SceneGraphCommandRuntime {
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
""",
        "",
    )
    .replace(
        "final class SceneOffscreenTexturePool {\n    struct Pair {}\n}\n",
        "",
    )
    .replace(
        """final class ScenePreparedPersistentGraphTargets {
    struct HistoryRehydrateCopy {
        let sourceToken: SceneGraphExecutionState.PhysicalToken
        let sourceTexture: MTLTexture
        let targetToken: SceneGraphExecutionState.PhysicalToken
        let targetTexture: MTLTexture
    }
}
""",
        "",
    )
    .replace(
        """struct SceneDependencyEffectInput {
    let frameEpoch: UInt64
    let namedReference: SceneNamedTextureReference
    let reservedMaterialResource: SceneFrameTextureResource?
}
""",
        """struct SceneDependencyEffectInput {
    let consumerLayerID: Int
    let providerLayerID: Int
    let variant: SceneNamedTextureReference.Variant
    let slot: SceneEffectPassSlot
    let blendMode: Int
    let frameEpoch: UInt64
    let texture: MTLTexture

    var namedReference: SceneNamedTextureReference {
        .init(providerLayerID: providerLayerID, variant: variant)
    }

    var reservedMaterialResource: SceneFrameTextureResource? {
        SceneFrameTextureResource.reservedNamedLayerTarget(
            reference: namedReference,
            frameEpoch: frameEpoch,
            texture: texture
        )
    }
}
""",
    )
    .replace(
        """final class SceneResolvedMaterialRuntimeBridge {
    struct FrameInputs {
        let time: Float
        let dynamicValues: SceneDynamicSnapshot
        let pointerIsInside: Bool
        let layerModelMatrix: simd_float4x4
        let effectTextureProjectionMatrixInverse: simd_float4x4
        let dependencyEffect: SceneDependencyEffectInput?

        init(
            dependencyEffect: SceneDependencyEffectInput? = nil,
            dynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0),
            pointerIsInside: Bool = true
        ) {
            time = 0
            self.dynamicValues = dynamicValues
            self.pointerIsInside = pointerIsInside
            layerModelMatrix = matrix_identity_float4x4
            effectTextureProjectionMatrixInverse = matrix_identity_float4x4
            self.dependencyEffect = dependencyEffect
        }
    }
}
""",
        """final class SceneResolvedMaterialRuntimeBridge {
    typealias LogSink = @Sendable (String) -> Void

    struct ClaimedExecution {
        let layerID: Int
        let dependencyOwnership: SceneResolvedMaterialDependencyOwnership
        let sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute
        let token: SceneResolvedMaterialExecutionCapabilityCatalog.Token
        let sceneBackgroundRequirement:
            SceneResolvedMaterialExecutionCapabilityCatalog.SceneBackgroundRequirement? = nil
    }
    enum Claim {
        case notMigrated
        case rejected(reasonCode: String)
        case claimed(ClaimedExecution)
    }
    struct FrameInputs {
        let time: Float = 0
        let dynamicValues: SceneDynamicSnapshot
        let pointerIsInside: Bool
        let layerModelMatrix = matrix_identity_float4x4
        let effectTextureProjectionMatrixInverse = matrix_identity_float4x4
        let dependencyEffect: SceneDependencyEffectInput?

        init(
            dependencyEffect: SceneDependencyEffectInput? = nil,
            dynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0),
            pointerIsInside: Bool = true
        ) {
            self.dynamicValues = dynamicValues
            self.pointerIsInside = pointerIsInside
            self.dependencyEffect = dependencyEffect
        }

        func withDependencyEffect(
            _ dependencyEffect: SceneDependencyEffectInput?
        ) -> Self {
            .init(
                dependencyEffect: dependencyEffect,
                dynamicValues: dynamicValues,
                pointerIsInside: pointerIsInside
            )
        }
    }
    struct FramePreparationRequest {
        let claim: ClaimedExecution
        let targetPlan: SceneResolvedMaterialFrameTargetPlan
        let materialFunctionInvocations:
            [SceneGraphMaterialFunctionInvocationRequest] = []
        let sceneBackgroundResource: SceneFrameTextureResource? = nil
        let sourceTexture: MTLTexture?
        let sourceUniforms: SceneLayerFragmentUniforms?
        let sourcePipeline: SceneImageLayerPipeline
        let frameInputs: FrameInputs
    }
    enum FramePreparationResult {
        case ready
        case rejected(reasonCode: String)
    }
    struct ExecutionTicket: Hashable {
        struct EffectFailure: Hashable {
            let layerID: Int
            let effectIndex: Int
            let descriptorID: String
            let reasonCode: String
        }
        let identity, epoch: UInt64
        let finalTextureIdentity: ObjectIdentifier
        let consumesExternalPrimaryDependency: Bool
        let effectFailures: [EffectFailure]
    }
    enum ExecutionResult {
        case encoded(texture: MTLTexture, ticket: ExecutionTicket)
        case failed(reasonCode: String)
    }
    enum CompositeOutcome {
        case consumed
        case failed(reasonCode: String)
    }
}

struct SceneResolvedMaterialFrameTargetPlan {
    let token: SceneResolvedMaterialExecutionCapabilityCatalog.Token
    let allocation: ScenePersistentGraphTargetFramePlan
}
""",
    )
)
if "typealias LogSink = @Sendable (String) -> Void" not in SUPPORT:
    raise AssertionError("runtime bridge support replacement did not match")
if "let consumerLayerID: Int" not in SUPPORT:
    raise AssertionError("dependency effect support replacement did not match")


HARNESS_PATH = (
    Path(__file__).with_name("fixtures")
    / "SceneMaterialCopyHistoryRenderingHarness.swift"
)
HARNESS = HARNESS_PATH.read_text(encoding="utf-8")
MAIN = HARNESS_PATH.with_name(
    "SceneMaterialCopyHistoryRenderingMain.swift"
).read_text(encoding="utf-8")


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneMaterialCopyHistoryRenderingTests(unittest.TestCase):
    def test_material_copy_history_pixels_converge_across_frames(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-material-copy-history-"
        ) as directory:
            root = Path(directory)
            support = root / "Support.swift"
            harness = root / "Harness.swift"
            main = root / "Main.swift"
            binary = root / "material-copy-history-test"
            support.write_text(SUPPORT, encoding="utf-8")
            harness.write_text(HARNESS, encoding="utf-8")
            main.write_text(MAIN, encoding="utf-8")
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
            environment["MWX_SCENE_GENERIC_SHADER_ROUTE"] = "disable-generic"
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
                    str(main),
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
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)

        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertEqual(payload["quarterFailure"], "success", payload)
        self.assertEqual(payload["threeQuarterFailure"], "success", payload)
        for key in (
            "serialQuarterConverges",
            "inFlightQuarterConverges",
            "serialThreeQuarterConverges",
            "inFlightThreeQuarterConverges",
            "pendingHistoryDefersNextFrame",
            "authoredWeightsProduceDistinctPixels",
            "sourceCaptureIsExact",
        ):
            self.assertTrue(payload[key], payload)


if __name__ == "__main__":
    unittest.main()
