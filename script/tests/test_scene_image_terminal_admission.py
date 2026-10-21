"""Execute the production terminal-entry predicate with typed boundary leaves.

This CPU seam checks target selection, including the older solid/text entries.
It does not compile shader capability facts, execute graph/GPU commands, or
replace the companion real-App placement/representation gate.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / (
    "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/"
    "SceneResolvedMaterialFramePreflight+Admission.swift"
)
STATE_SOURCES = [ROOT / "MyWallpaperX/Core/SteamWorkshopScene" / path for path in (
    "Runtime/Frame/SceneMaterialRenderState.swift",
    "Compilation/Material/SceneMaterialRenderState+Compilation.swift",
)]

LEAVES = r'''
protocol MTLTexture: AnyObject {}
final class Texture: MTLTexture {}
enum DependencyOwnership: Equatable { case none, external, aggregate }
enum SceneResolvedMaterialRuntimeBridge {
    struct ClaimedExecution {
        var supportsTerminalMaterialReplay = true
        var supportsPlacementSpaceTerminalReplay = true
        var admittedGraphs = [1, 2]
        var dependencyOwnership = DependencyOwnership.none
    }
}
enum SceneRenderDescriptor {
    struct Layer {
        var id = 17
        var contentKind = "image"
        var colorBlendMode: Int? = nil
        var perspective = false
        var imageMaterialRenderState: SceneMaterialRenderState? = nil
        var utilityLayer: String? = nil
    }
}
struct SceneParticleCameraFrame {
    var defaultsToPerspective = false
    func resolvesPerspective(for layer: SceneRenderDescriptor.Layer) -> Bool {
        layer.perspective
    }
}
struct SceneBaseImageTextureSnapshot { var geometryProducts: [Int: Int] = [:] }
final class Dependencies {
    var required: Set<Int> = []
    func requiresGraphOutputCapture(for id: Int) -> Bool { required.contains(id) }
}
final class SceneMetalRenderer { let dependencyRuntime = Dependencies() }
'''

MAIN = r'''
@main enum AdmissionChecks {
    static func main() throws {
        let renderer = SceneMetalRenderer()
        let target = Texture()
        let other = Texture()
        var base = SceneResolvedMaterialRuntimeBridge.ClaimedExecution()
        var image = SceneRenderDescriptor.Layer()
        let camera = SceneParticleCameraFrame()
        let textures = SceneBaseImageTextureSnapshot()
        func selects(_ claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution = .init(),
                     _ layer: SceneRenderDescriptor.Layer = .init(),
                     _ frame: SceneParticleCameraFrame = .init(),
                     _ source: SceneBaseImageTextureSnapshot = .init(),
                     visible: Bool = true, target: MTLTexture) -> Bool {
            renderer.initialResolvedTerminalReplayTarget(claim: claim, layer: layer,
                cameraFrame: frame, imageTextures: source, isVisible: visible,
                mainSource: target) === target
        }
        var results: [String: Bool] = [:]
        results["twoImageStages"] = selects(base, image, camera, textures, target: target)
        image.id = 91011
        results["renamedIdentity"] = selects(base, image, target: other)
        base.admittedGraphs = [1, 2, 3]
        results["imageThreeStages"] = selects(base, image, target: target)
        base.supportsPlacementSpaceTerminalReplay = false
        results["missingPlacementQualification"] = !selects(base, image, target: target)
        base.supportsPlacementSpaceTerminalReplay = true
        base.supportsTerminalMaterialReplay = false
        results["missingChainQualification"] = !selects(base, image, target: target)
        base.supportsTerminalMaterialReplay = true
        for dependency in [DependencyOwnership.external, .aggregate] {
            base.dependencyOwnership = dependency
            results["dependency-\(dependency)"] = !selects(base, image, target: target)
        }
        base.dependencyOwnership = .none
        results["hiddenImage"] = !selects(base, image, visible: false, target: target)
        for mode in [1, 30, 31] {
            image.colorBlendMode = mode
            results["advanced-\(mode)"] = !selects(base, image, target: target)
        }
        image.colorBlendMode = 0
        image.perspective = true
        results["perspective"] = !selects(base, image, target: target)
        image.perspective = false
        results["nativeCameraOrthoOverride"] = selects(base, image,
            .init(defaultsToPerspective: true), target: target)
        image.imageMaterialRenderState = SceneMaterialRenderState.compile(blending: "translucent",
            depthTest: "disabled", depthWrite: "disabled", cullMode: "nocull", alphaWriting: nil)
        results["outerMaterialState"] = !selects(base, image, target: target)
        for alpha: String? in [nil, "default"] {
            image.imageMaterialRenderState = SceneMaterialRenderState.compile(blending: "additive",
                depthTest: "disabled", depthWrite: "disabled", cullMode: "nocull", alphaWriting: alpha)!
            results["outerAdditive-\(alpha ?? "omitted")"] = !selects(base, image, target: target)
        }
        image.imageMaterialRenderState = nil
        image.utilityLayer = "composition"
        results["utilityImage"] = !selects(base, image, target: target)
        image.utilityLayer = nil
        results["geometry"] = !selects(base, image, camera,
            .init(geometryProducts: [image.id: 1]), target: target)
        renderer.dependencyRuntime.required = [image.id]
        results["providerOutput"] = !selects(base, image, target: target)
        renderer.dependencyRuntime.required = []
        image.contentKind = "unknown"
        results["unknownKind"] = !selects(base, image, target: target)
        image.contentKind = "text"
        base.admittedGraphs = [1]
        base.supportsPlacementSpaceTerminalReplay = false
        results["oldTextQualificationUnchanged"] = selects(base, image, target: target)
        base.admittedGraphs = [1, 2]
        results["textTwoStagesStillOrdinary"] = !selects(base, image, target: target)
        image.contentKind = "solid"
        image.perspective = true
        base.admittedGraphs = [1]
        results["oldNativeSolid"] = selects(base, image,
            .init(defaultsToPerspective: true), target: target)
        results["oldOrthoSolidSeparateOwner"] = !selects(base, image, target: target)
        print(String(decoding: try JSONSerialization.data(withJSONObject: results,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc required")
class SceneImageTerminalAdmissionTests(unittest.TestCase):
    def test_actual_entry_preserves_qualified_images_and_adjacent_routes(self):
        source = SOURCE.read_text()
        # Compile the exact complete entry method; unrelated frame allocation
        # leaves are outside this seam, not replaced implementations.
        begin = source.index("extension SceneMetalRenderer {")
        end = source.index("    func admitResolvedMaterialFrameTargets(", begin)
        predicate = source[begin:end] + "}\n"
        sources = [SOURCE, *STATE_SOURCES]
        before = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
        with tempfile.TemporaryDirectory(prefix="mwx-image-terminal-admission-") as directory:
            root = Path(directory)
            harness = root / "Admission.swift"
            harness.write_text("import Foundation\n" + LEAVES + predicate + MAIN)
            binary = root / "admission"
            compiled = subprocess.run([
                "xcrun", "swiftc", "-parse-as-library", *map(str, STATE_SOURCES), str(harness),
                "-module-cache-path", str(root / "module-cache"), "-o", str(binary),
            ], capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            completed = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            results = json.loads(completed.stdout)
        self.assertEqual({path: hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}, before)
        self.assertEqual(len(results), 24)
        for name, passed in results.items():
            with self.subTest(case=name):
                self.assertTrue(passed)


if __name__ == "__main__":
    unittest.main()
