#!/usr/bin/env python3
"""Actual stream/transaction state with CPU leaves and a separate real Metal gate.

The CPU methods create no device, command queue, shader, or GPU command.
Finite channels belong to Reader/Skinning; the direct-playback gate exercises
late invalid output and complete bind fallback through the actual producer.
The Metal method decodes its own MDL through Reader, submits a GPU blit and
checks actual bytes, bounds, pending cancellation and completed slot reuse.
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

    def test_mesh_channels_bounds_identity_and_storage_input_rejections(self):
        self.check_group("validationAndMeshView")

    def test_real_metal_reads_verified_vertices_and_resolves_submitted_lease(self):
        from script.tests.test_scene_static_model_reader import SWIFT_SOURCES, build_model

        with tempfile.TemporaryDirectory(prefix="scene-model-stream-metal-") as temporary:
            folder = Path(temporary)
            destination = os.environ.get("MWX_MODEL_STREAM_EVIDENCE")
            evidence = Path(destination) / "metal" if destination else None
            if evidence:
                evidence.mkdir(parents=True, exist_ok=True)
            inputs = [*SWIFT_SOURCES, STREAM, TRANSACTION, PIPELINE, FIXTURE, Path(__file__)]
            before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
            pipeline = PIPELINE.read_text()
            mesh = pipeline[pipeline.index("struct SceneStaticModelMesh {"):
                            pipeline.index("private struct SceneStaticModelShadowUniforms")]
            factory = pipeline[pipeline.index("    func makeVertexStream("):
                               pipeline.index("    /// Encodes into the caller's current render pass.")]
            abi = pipeline[pipeline.index("    private static let hasExpectedVertexABI ="):
                           pipeline.index("    /// Swift/MSL constant-buffer ABI.")]
            harness = folder / "Harness.swift"
            harness.write_text(FIXTURE.read_text().replace("// PRODUCT_MESH", mesh)
                               .replace("// PRODUCT_FACTORY", factory).replace("// PRODUCT_ABI", abi))
            model = folder / "verified.mdl"
            model.write_bytes(build_model(bounds=(-10, -10, -10, 10, 10, 10), vertices=[
                ((-2, 3, -4), (2, -3, 4), (-5, 6, -7, -1), (.125, .875)),
                ((5, -6, 7), (0, 0, 0), (0, 0, 0, 0), (.625, .25)),
                ((1, 2, 3), (0, 0, 1), (1, 0, 0, 1), (.5, .5))]))
            sources = [*SWIFT_SOURCES, STREAM, TRANSACTION, harness]
            binary = folder / "metal-checks"
            command = ["swiftc", "-O", "-swift-version", "5", "-module-cache-path", str(folder / "modules"),
                       *map(str, sources), "-o", str(binary)]
            compiled = subprocess.run(command, capture_output=True, text=True, timeout=120)
            if evidence:
                (evidence / "Harness.swift").write_text(harness.read_text())
                (evidence / "compile.stdout").write_text(compiled.stdout)
                (evidence / "compile.stderr").write_text(compiled.stderr)
                (evidence / "inputs.json").write_text(json.dumps({"gpuCommands": True,
                    "command": command, "sources": before, "timeoutSeconds": 30,
                    "scope": "actual GPU buffer readback/storage lease; no draw or visual claim"}, indent=2) + "\n")
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            ran = subprocess.run([str(binary), str(model)], capture_output=True, text=True, timeout=30)
            if evidence:
                (evidence / "run.stdout").write_text(ran.stdout)
                (evidence / "run.stderr").write_text(ran.stderr)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            after = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
            self.assertEqual(after, before, "source changed during actual Metal gate")
            rows = json.loads(ran.stdout)
            if "skipped" in rows:
                self.skipTest(rows["skipped"])
            for key in ("gpuCompleted", "allBufferBytes", "currentBounds", "pendingLease",
                        "completionRevokedLease", "slotReused", "cancelledNext"):
                with self.subTest(check=key):
                    self.assertTrue(rows[key], rows)
            if evidence:
                (evidence / "checks.json").write_text(json.dumps(rows, indent=2) + "\n")


if __name__ == "__main__":
    unittest.main()
