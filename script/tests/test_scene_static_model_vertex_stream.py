#!/usr/bin/env python3
"""Actual stream/transaction state with a CPU command-buffer protocol leaf.

No Metal device, command queue, shader, or GPU command is created by this gate.
The same Swift fixture also provides an opt-in real-Metal check for the caller's
existing pipeline/queue; this unittest never invokes that entry.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
PIPELINE = SCENE / "Rendering/Metal/SceneStaticModelPipeline.swift"
STREAM = PIPELINE.with_name("SceneStaticModelVertexStream.swift")
TRANSACTION = SCENE / "Rendering/Frame/SceneSourceUpdateTransaction.swift"
MODEL = SCENE / "Format/SceneMdlStaticModel.swift"
FIXTURE = Path(__file__).with_name("fixtures") / "SceneStaticModelVertexStreamHarness.swift"


class SceneStaticModelVertexStreamTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc unavailable")
        cls.scratch = tempfile.TemporaryDirectory(prefix="scene-model-stream-")
        root = Path(cls.scratch.name)
        inputs = (PIPELINE, STREAM, TRANSACTION, MODEL, FIXTURE, Path(__file__))
        before = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in inputs}
        pipeline = PIPELINE.read_text()
        # Extract the real immutable mesh/view and factory/ABI declarations.
        # The pipeline PSOs are outside this CPU storage-lifecycle gate.
        mesh = pipeline[pipeline.index("struct SceneStaticModelMesh {"):
                        pipeline.index("private struct SceneStaticModelShadowUniforms")]
        factory = pipeline[pipeline.index("    func makeVertexStream("):
                           pipeline.index("    /// Encodes into the caller's current render pass.")]
        abi = pipeline[pipeline.index("    private static let hasExpectedVertexABI ="):
                       pipeline.index("    /// Swift/MSL constant-buffer ABI.")]
        model = MODEL.read_text()
        vertex = model[model.index("    struct Vertex: Equatable {"):
                       model.index("    struct Bounds: Equatable {")]
        harness = (FIXTURE.read_text().replace("// PRODUCT_MESH", mesh)
                   .replace("// PRODUCT_FACTORY", factory).replace("// PRODUCT_ABI", abi)
                   .replace("// PRODUCT_VERTEX", vertex))
        (root / "Harness.swift").write_text(harness)
        sources = [root / "Harness.swift"]
        for path in (STREAM, TRANSACTION):
            target = root / path.name
            # Protocol leaf substitution only; state machine bodies unchanged.
            target.write_text(path.read_text().replace("import Metal\n", ""))
            sources.append(target)
        binary = root / "checks"
        command = ["swiftc", "-swift-version", "5", "-D", "STREAM_CPU_TEST",
                   "-module-cache-path", str(root / "modules"),
                   *map(str, sources), "-o", str(binary)]
        compiled = subprocess.run(command, capture_output=True, text=True, timeout=60)
        if compiled.returncode:
            raise AssertionError(compiled.stdout + compiled.stderr)
        ran = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
        if ran.returncode:
            raise AssertionError(ran.stdout + ran.stderr)
        cls.rows = json.loads(ran.stdout)
        after = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                 for path in inputs}
        drift = {path: [value, after[path]] for path, value in before.items() if value != after[path]}
        if drift:
            raise AssertionError(f"source changed during CPU gate: {drift}")
        destination = os.environ.get("MWX_MODEL_STREAM_EVIDENCE")
        if destination:
            out = Path(destination)
            out.mkdir(parents=True, exist_ok=True)
            (out / "checks.json").write_text(json.dumps(cls.rows, indent=2) + "\n")
            (out / "compile.log").write_text(compiled.stdout + compiled.stderr)
            (out / "run.log").write_text(ran.stdout + ran.stderr)
            (out / "inputs.json").write_text(json.dumps({
                "gpuCommands": False, "command": command,
                "sourceSHA256": before, "sourceDrift": drift,
                "substitution": "Metal protocol leaves only; production stream/transaction bodies unchanged",
            }, indent=2) + "\n")

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def check_group(self, name):
        self.assertTrue(self.rows[name], json.dumps(self.rows, indent=2))

    def test_fixed_capacity_and_pending_storage(self):
        self.check_group("pendingAndFull")

    def test_cancel_before_enqueue_and_after_arm(self):
        self.check_group("cancelBeforeSubmit")

    def test_submitted_cancel_waits_for_success_or_error_completion(self):
        self.check_group("submittedAndFailedCompletion")

    def test_old_generation_and_completion_do_not_release_current_binding(self):
        self.check_group("lateGeneration")

    def test_two_instances_and_retired_stream_lifetime(self):
        self.check_group("instancesAndLifetime")

    def test_uncommitted_arm_cancel_releases_command_buffer_and_transaction(self):
        self.check_group("uncommittedArmCancelLifetime")

    def test_mesh_channels_bounds_identity_and_input_rejections(self):
        self.check_group("validationAndMeshView")


if __name__ == "__main__":
    unittest.main()
