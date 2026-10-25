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

from script.tests.scene_framebuffer_source_test_support import _declaration


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
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialFrameResourceBundle.swift",
    *(
        path
        for path in RUNTIME_FIXTURE["SUBMISSION_SWIFT_SOURCES"]
        if path.name != "SceneResolvedMaterialRuntimeBridge.swift"
    ),
]))
SUPPORT = (
    EXECUTOR_FIXTURE["SUPPORT"]
    .replace(
        EXECUTOR_FIXTURE["PUBLICATION_FIXTURE"]["SUPPORT"],
        EXECUTOR_FIXTURE["PUBLICATION_FIXTURE"]["SUPPORT"].rsplit(
            "final class SceneOffscreenTexturePool {", 1
        )[0],
    )
    .replace("final class SceneGraphRenderTargetResidencyPin {\n    func release() {}\n}\n", "")
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
    + r'''
extension SceneResolvedMaterialRuntimeBridge {
    typealias LogSink = @Sendable (String) -> Void

    struct ClaimedExecution {
        let layerID: Int
        let dependencyOwnership: SceneResolvedMaterialDependencyOwnership
        let sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute
        let token: SceneResolvedMaterialExecutionCapabilityCatalog.Token
        let sceneBackgroundRequirement:
            SceneResolvedMaterialExecutionCapabilityCatalog.SceneBackgroundRequirement? = nil
        let supportsTerminalMaterialReplay: Bool = false
    }
    enum Claim {
        case notMigrated
        case rejected(reasonCode: String)
        case claimed(ClaimedExecution)
    }

'''
    + _declaration((REPOSITORY_ROOT /
        'MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialRuntimeBridge.swift'
      ).read_text(encoding='utf-8'), 'FramePreparationRequest')
    + r'''
    enum FramePreparationResult {
        case ready
        case rejected(reasonCode: String)
    }
'''
    + _declaration((REPOSITORY_ROOT /
        'MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialRuntimeBridge.swift'
      ).read_text(encoding='utf-8'), 'ExecutionTicket',
      marker='    struct ExecutionTicket: Hashable {')
    + r'''
    enum ExecutionResult {
        case encoded(texture: MTLTexture, ticket: ExecutionTicket)
        case failed(reasonCode: String)
    }
    enum CompositeOutcome {
        case consumed
        case failed(reasonCode: String)
    }
    enum TerminalMaterialReplayOutcome {
        case notApplicable
        case consumed
        case failed(reasonCode: String)
    }
}

struct SceneResolvedMaterialFrameTargetPlan {
    let token: SceneResolvedMaterialExecutionCapabilityCatalog.Token
    let allocation: ScenePersistentGraphTargetFramePlan
}

extension SceneResolvedMaterialRuntimeBridge.FrameInputs {
    func withDependencyEffects(_ dependencyEffects: [SceneDependencyEffectInput]) -> Self {
        .init(dependencyEffects: dependencyEffects,
            dependencyUnavailability: dependencyUnavailability,
            dynamicValues: dynamicValues, pointerIsInside: pointerIsInside)
    }
}
'''


)


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
                    str(HARNESS_PATH.with_name("SceneMaterialFrameResourceBundleChecks.swift")),
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
        def assert_checks(value):
            if isinstance(value, dict):
                for child in value.values():
                    assert_checks(child)
            elif isinstance(value, bool):
                self.assertTrue(value, payload)
        for section in ("resourceBundleIdentity", "resourceBundleCapacity", "environmentOverlay"):
            assert_checks(payload[section])
        self.assertEqual(payload["quarterFailure"], "success", payload)
        self.assertEqual(payload["threeQuarterFailure"], "success", payload)
        for key in (
            "resourcePhasePreservesOriginalPixels",
            "serialQuarterConverges",
            "inFlightQuarterConverges",
            "serialThreeQuarterConverges",
            "inFlightThreeQuarterConverges",
            "pendingHistoryDefersNextFrame",
            "authoredWeightsProduceDistinctPixels",
            "sourceCaptureIsExact",
            "colorHistoryPublishesColor",
            "dataHistoryPublishesTypedData",
        ):
            self.assertTrue(payload[key], payload)


if __name__ == "__main__":
    unittest.main()
