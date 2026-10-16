#!/usr/bin/env python3
"""Real property/QuickJS/typed camera pipeline for camera-layer FOV."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests import scene_vector_vm_test_support as vm
from script.tests.test_scene_particle_camera_frame import SWIFT_SOURCES as CAMERA_SOURCES

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
FIXTURE = ROOT / "script/tests/fixtures/SceneCameraFOVScriptChecks.swift"
LIFECYCLE = SCENE / "Runtime/Session/SceneDesktopWallpaperSession+FrameDriverLifecycle.swift"
EXTRA_SOURCES = [*CAMERA_SOURCES,
    SCENE / "Rendering/Geometry/SceneLayerVisibility.swift",
    SCENE / "Systems/Properties/SceneUserPropertyDefinitionParser.swift",
    SCENE / "Systems/Properties/ScenePropertyBindingProgram.swift",
    SCENE / "Systems/Properties/ScenePropertyBindingCompiler+TargetMapping.swift",
    SCENE / "Systems/Properties/ScenePropertyBindingProgramValidator.swift",
    SCENE / "Systems/Properties/ScenePropertyLiveUpdateState.swift",
    SCENE / "Systems/Properties/ScenePuppetAnimationPropertyTarget.swift",
    SCENE / "Systems/Properties/SceneEvaluationTransaction.swift",
    SCENE / "Systems/Properties/SceneDynamicDefinitionMerger.swift",
    SCENE / "Runtime/Session/SceneDesktopWallpaperLaunchFrameSchema.swift",
]


def camera_preamble() -> str:
    # Replace the existing external camera carrier, never its algorithm.
    preamble = vm.SWIFT_PREAMBLE
    start = preamble.index("struct SceneParticleCameraFrame {")
    end = preamble.index("struct SceneFrameTiming {", start)
    preamble = preamble[:start] + preamble[end:]
    old = """    struct Camera {
        var parallaxEnabled = false
        var orthoWidth: Float? = nil
        var orthoHeight: Float? = nil
        var default2DInputLayerID: Int? = nil
        var default2DOriginInputLayerID: Int? = nil
        var nearZ: Float = 0.01
        var farZ: Float = 10000
    }"""
    new = """    struct Camera {
        var parallaxEnabled = false
        var orthoWidth: Float? = nil
        var orthoHeight: Float? = nil
        var default2DInputLayerID: Int? = nil
        var default2DOriginInputLayerID: Int? = nil
        var eye: [Float] = [0, 0, 10]
        var center: [Float] = [0, 0, 0]
        var up: [Float] = [0, 1, 0]
        var fovDegrees: Float? = 100
        var perspectiveOverrideFOVDegrees: Float? = nil
        var nearZ: Float = 0.01
        var farZ: Float = 10000
    }
    typealias CameraDescriptor = Camera"""
    if preamble.count(old) != 1:
        raise AssertionError("existing camera carrier changed")
    return preamble.replace(old, new) + """
extension SceneRenderDescriptor.Layer {
    var displayScriptOwnership: SceneLayerDisplayScriptOwnership? { nil }
}
struct SceneRuntimeInput {
    let propertyBindingProgram: ScenePropertyBindingProgram
    let renderDescriptor: SceneRenderDescriptor
    let scriptEffectVisibilityDefinitions: [SceneDynamicTargetDefinition] = []
}
struct SceneTimelineProgram {
    struct Binding { let definition: SceneDynamicTargetDefinition }
    let bindings: [Binding] = []
}
struct SceneTextScriptProgram {
    struct Binding { let definition: SceneDynamicTargetDefinition }
    let bindings: [Binding] = []
}
struct SceneSharedLayerAlphaProgram { let definitions: [SceneDynamicTargetDefinition] = [] }
struct SceneScriptMediaFrameCoordinator {
    init(vectorProgram: SceneScriptVectorProgram, stringProgram: SceneScriptStringProgram,
         scalarProgram: SceneScriptScalarProgram) {}
}
struct SceneDesktopWallpaperLaunchContext {
    let frameSchema: SceneDesktopWallpaperLaunchFrameSchema
    var sceneScriptStatefulTargets: Set<SceneDynamicTarget> {
        frameSchema.sceneScriptStatefulTargets
    }
    let sceneScriptScalarProgram: SceneScriptScalarProgram
    let sceneScriptStringProgram: SceneScriptStringProgram
    let sceneScriptCursorProgram: SceneScriptCursorProgram
    let propertyVectorScriptProgram: SceneScriptVectorProgram
    let liveState: ScenePropertyLiveUpdateState
    init(frameSchema: SceneDesktopWallpaperLaunchFrameSchema,
         sceneScriptScalarProgram: SceneScriptScalarProgram,
         sceneScriptStringProgram: SceneScriptStringProgram,
         sceneScriptCursorProgram: SceneScriptCursorProgram,
         propertyVectorScriptProgram: SceneScriptVectorProgram,
         liveState: ScenePropertyLiveUpdateState) {
        self.frameSchema = frameSchema
        self.sceneScriptScalarProgram = sceneScriptScalarProgram
        self.sceneScriptStringProgram = sceneScriptStringProgram
        self.sceneScriptCursorProgram = sceneScriptCursorProgram
        self.propertyVectorScriptProgram = propertyVectorScriptProgram
        self.liveState = liveState
    }
}
struct SceneDesktopWallpaperSession {}
"""


def retirement_hook() -> str:
    # Execute the original retirement declaration; only the session's unrelated
    # playback/surface leaves are outside this focused owner boundary.
    source = LIFECYCLE.read_text()
    start = source.index("    private func retireDestroyedSceneScriptOwners(")
    body = source.index("{", start)
    depth = 1
    end = body + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return "extension SceneDesktopWallpaperSession {\n" + source[start:end] + """
    func retireCommittedLayers(_ context: SceneDesktopWallpaperLaunchContext,
                               layerIDs: Set<Int>, frame: SceneScriptFrameInput) {
        retireDestroyedSceneScriptOwners(context, layerIDs: layerIDs, frame: frame)
    }
}
"""


def run_probe(directory: Path) -> dict:
    inputs = [*dict.fromkeys([*vm.SWIFT_SOURCES, *EXTRA_SOURCES]), *vm.C_SOURCES, FIXTURE,
              LIFECYCLE, Path(vm.__file__), Path(__file__)]
    before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    binary = vm.compile_vector_harness(directory, FIXTURE.read_text(),
        "camera-fov-script", extra_swift_sources=tuple(EXTRA_SOURCES),
        preamble=camera_preamble() + retirement_hook())
    run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=25)
    (directory / "stdout.json").write_text(run.stdout)
    (directory / "stderr.log").write_text(run.stderr)
    after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    (directory / "inputs.json").write_text(json.dumps({
        "before": before, "after": after, "exitCode": run.returncode,
    }, indent=2) + "\n")
    if before != after:
        raise AssertionError("source input changed during focused gate")
    if run.returncode != 0:
        raise AssertionError(run.stderr)
    return json.loads(run.stdout)


class SceneCameraFOVScriptTests(unittest.TestCase):
    def test_camera_fov_script_reaches_camera_and_preserves_boundaries(self) -> None:
        proof = os.environ.get("MWX_SCENE_PROPERTY_PROOF")
        if proof:
            directory = Path(proof)
            directory.mkdir(parents=True, exist_ok=True)
            facts = run_probe(directory)
        else:
            with tempfile.TemporaryDirectory(prefix="mwx-camera-fov-script-") as temporary:
                facts = run_probe(Path(temporary))
        self.assertTrue(facts)
        self.assertEqual([key for key, passed in facts.items() if passed is not True], [])


if __name__ == "__main__":
    unittest.main()
