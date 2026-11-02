#!/usr/bin/env python3
"""Real CPU Puppet state produces immutable direct geometry frames.

The shared vertex ABI is the exact production value declaration. This gate
compiles no Metal imports, protocol substitutes, stream or GPU publication owner.
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
]


class ScenePuppetDirectPlaybackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        destination = os.environ.get("MWX_DIRECT_PLAYBACK_OUTPUT")
        cls.scratch = None if destination else tempfile.TemporaryDirectory(prefix="direct-playback-")
        folder = Path(destination or cls.scratch.name)
        folder.mkdir(parents=True, exist_ok=True)
        sources = list(dict.fromkeys([*SWIFT_SOURCES, *(SCENE_ROOT / p for p in EXTRA_SOURCES)]))
        identities = [*sources, FIXTURE, METAL_PIPELINE, Path(__file__)]
        before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in identities}
        vertex_source = METAL_PIPELINE.read_text()
        quad = vertex_source[vertex_source.index("struct SceneQuadVertex {"):
                             vertex_source.index("enum SceneLayerBlendMode")]
        harness = folder / "Harness.swift"
        harness.write_text(FIXTURE.read_text().replace("// PRODUCT_QUAD", quad))
        binary = folder / "direct-playback"
        command = ["swiftc", "-swift-version", "5", *map(str, sources),
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

    def test_shared_pose_signature_bone_override_and_revision(self):
        self.check("poseAndSignature")
        self.check("unpreparedHasNoFrame")
        self.check("renamed")

    def test_noncontiguous_physical_bones_keep_their_configuration_and_nonphysical_edits(self):
        self.check("multiplePhysicsBones")

    def test_late_vertex_and_active_unconsumed_channels_choose_complete_bind(self):
        self.check("lateVertexFallback")
        self.check("channelVisibility")
        self.check("invalidFrame")

    def test_late_nonfinite_skin_output_returns_complete_bind_frame_then_recovers(self):
        for key in ("latePositionOverflowFallback", "lateNormalOverflowFallback",
                    "lateTangentOverflowFallback"):
            with self.subTest(case=key):
                self.check(key)
        self.check("finiteAffineOutput")

    def test_frozen_frame_and_independent_cpu_instances_keep_their_values(self):
        self.check("frozenFrameValueSurvivesLaterPrepare")
        self.check("cpuInstanceIsolation")
        self.check("factoryCount")


if __name__ == "__main__":
    unittest.main()
