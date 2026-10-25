#!/usr/bin/env python3
"""One production Puppet state publishes direct geometry through real CPU leases.

Metal protocol leaves are deterministic CPU objects; no device, shader or GPU
command is created. Production playback/evaluator/stream/transaction stay intact.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_scene_puppet_playback import SCENE_ROOT, SWIFT_SOURCES

FIXTURE = Path(__file__).with_name("fixtures") / "ScenePuppetDirectPlaybackHarness.swift"
PIPELINE = SCENE_ROOT / "Rendering/Metal/SceneStaticModelPipeline.swift"
METAL_PIPELINE = SCENE_ROOT / "Rendering/Metal/SceneMetalPipeline.swift"
EXTRA_SOURCES = [
    "Format/SceneMdlStaticModel.swift", "Format/SceneMdlPuppetAttachmentReader.swift",
    "Systems/Puppet/ScenePuppetAnimationEvaluator+Skinning.swift",
    "Systems/Puppet/ScenePuppetAttachmentPoseProjection.swift",
    "Systems/Puppet/ScenePuppetTranslationMotion.swift",
    "Systems/Puppet/ScenePuppetAnimationControl.swift",
    "Systems/Puppet/ScenePuppetAnimationPlaybackRuntime.swift",
    "Systems/Puppet/ScenePuppetPlaybackState.swift",
    "Systems/Puppet/ScenePuppetPlaybackState+DirectModel.swift",
    "Systems/Properties/ScenePuppetAnimationPropertyTarget.swift",
    "Rendering/Geometry/SceneGeometryProduct.swift",
    "Rendering/Metal/SceneStaticModelVertexStream.swift",
    "Rendering/Frame/SceneSourceUpdateTransaction.swift",
]


def static_model_carrier_source() -> str:
    """Real mesh/factory/ABI; PSO creation is outside CPU publication tests."""
    source = PIPELINE.read_text()
    mesh = source[source.index("struct SceneStaticModelMesh {"):
                  source.index("private struct SceneStaticModelShadowUniforms")]
    factory = source[source.index("    func makeVertexStream("):
                     source.index("    /// Encodes into the caller's current render pass.")]
    abi = source[source.index("    private static let hasExpectedVertexABI ="):
                 source.index("    /// Swift/MSL constant-buffer ABI.")]
    return ("import Metal\nimport simd\n" + mesh
            + "final class SceneStaticModelPipeline {\n let device: MTLDevice\n"
            + " init(device: MTLDevice) { self.device = device }\n" + factory + abi + "}\n")


def puppet_bone_evidence_leaf_source() -> str:
    """Observe old image publication; optional direct diagnostics are outside that GPU gate."""
    return r'''
final class ScenePuppetBoneEvidence {
    static func isEnabled(for layerID: Int) -> Bool { true }
    func record(layerID: Int, revision: UInt64, frame: UInt64, sceneTime: Double,
                scriptWritten: Bool, displacement: Float,
                positions: [SIMD2<Float>], commandBuffer: MTLCommandBuffer) {
        Observation.evidence.append(positions)
    }
    func recordDirect(layerID: Int, revision: UInt64, frame: UInt64, sceneTime: Double,
                      poseStatus: String, selection: ScenePuppetAnimationSelection,
                      animationFrame: ScenePuppetAnimationPlaybackRuntime.LayerFrame,
                      vertices: [SceneMdlStaticModel.Vertex],
                      bindVertices: [SceneMdlStaticModel.Vertex], commandBuffer: MTLCommandBuffer) {}
}
'''


class ScenePuppetDirectPlaybackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        destination = os.environ.get("MWX_DIRECT_PLAYBACK_OUTPUT")
        cls.scratch = None if destination else tempfile.TemporaryDirectory(prefix="direct-playback-")
        folder = Path(destination or cls.scratch.name)
        folder.mkdir(parents=True, exist_ok=True)
        sources = list(dict.fromkeys([*SWIFT_SOURCES, *(SCENE_ROOT / p for p in EXTRA_SOURCES)]))
        identities = [*sources, FIXTURE, PIPELINE, METAL_PIPELINE, Path(__file__)]
        before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in identities}
        compiled_paths = []
        for source in sources:
            target = folder / source.name
            target.write_text(source.read_text().replace("import Metal\n", ""))
            compiled_paths.append(target)
        carrier = folder / "StaticModelCarrier.swift"
        carrier.write_text(static_model_carrier_source().replace("import Metal\n", ""))
        vertex_source = METAL_PIPELINE.read_text()
        quad = vertex_source[vertex_source.index("struct SceneQuadVertex {"):
                             vertex_source.index("enum SceneLayerBlendMode")]
        harness = folder / "Harness.swift"
        harness.write_text(carrier.read_text() + FIXTURE.read_text().replace("// PRODUCT_QUAD", quad))
        binary = folder / "direct-playback"
        command = ["swiftc", "-swift-version", "5", *map(str, compiled_paths),
                   str(harness), "-o", str(binary)]
        compiled = subprocess.run(command, capture_output=True, text=True, timeout=120)
        (folder / "compile.stdout").write_text(compiled.stdout)
        (folder / "compile.stderr").write_text(compiled.stderr)
        if compiled.returncode:
            raise AssertionError(compiled.stdout + compiled.stderr)
        ran = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
        (folder / "raw.stdout").write_text(ran.stdout)
        (folder / "raw.stderr").write_text(ran.stderr)
        if ran.returncode:
            raise AssertionError(ran.stdout + ran.stderr)
        cls.rows = json.loads(ran.stdout)
        after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in identities}
        drift = {p: [v, after[p]] for p, v in before.items() if v != after[p]}
        (folder / "inputs.json").write_text(json.dumps({"command": command, "sources": before,
            "sourceDrift": drift, "GPU": False}, indent=2) + "\n")
        if drift:
            raise AssertionError(f"source drift: {drift}")

    @classmethod
    def tearDownClass(cls):
        if cls.scratch:
            cls.scratch.cleanup()

    def check(self, key):
        self.assertTrue(self.rows[key], json.dumps(self.rows, sort_keys=True))

    def test_shared_pose_signature_bone_override_and_command_identity(self):
        self.check("poseAndSignature")
        self.check("wrongCommandAndTransaction")
        self.check("renamed")

    def test_noncontiguous_physical_bones_keep_their_configuration_and_nonphysical_edits(self):
        self.check("multiplePhysicsBones")

    def test_late_vertex_and_active_unconsumed_channels_choose_complete_bind(self):
        self.check("lateVertexFallback")
        self.check("channelVisibility")
        self.check("invalidFrame")

    def test_busy_cancel_failed_completion_and_surface_ownership(self):
        self.check("busyAndResolution")
        self.check("surfaceIsolation")
        self.check("factoryCount")


if __name__ == "__main__":
    unittest.main()
