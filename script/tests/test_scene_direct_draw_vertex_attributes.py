#!/usr/bin/env python3
"""Actual host ABI -> both shader backends -> transparent offscreen RTT.

The owned U/E/N points match the geometry experiment inputs, but native float
outputs below are an independently defined contract, not official RGB parity.
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

from script.tests.test_scene_resolved_material_program_finalizer import (
    SWIFT_SOURCES, SUPPORT_SOURCE,
)
from script.tests.scene_compiler_fixture import compiler_bundle, fixture_sources


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = Path(__file__).with_name("fixtures") / "SceneDirectDrawVertexAttributesHarness.swift"
GRAPH = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph"
SOURCES = list(dict.fromkeys([
    *SWIFT_SOURCES, SUPPORT_SOURCE,
    GRAPH / "SceneResolvedMaterialAttachmentKind.swift",
    GRAPH / "SceneResolvedMaterialAttachmentStorage.swift",
]))


def hashes(paths):
    return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


@unittest.skipUnless(shutil.which("swiftc"), "Swift compiler required")
class SceneDirectDrawVertexAttributesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-direct-draw-attributes-")
        cls.addClassCleanup(cls.temporary.cleanup)
        root = Path(cls.temporary.name)
        evidence = os.environ.get("MWX_DIRECT_DRAW_EVIDENCE")
        cls.evidence = Path(evidence) if evidence else None
        if cls.evidence:
            cls.evidence.mkdir(parents=True, exist_ok=True)
        ref = os.environ.get("MWX_DIRECT_DRAW_PRODUCT_REF")
        before = hashes(SOURCES)
        frozen = []
        for source in SOURCES:
            destination = root / "frozen" / source.relative_to(ROOT)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(subprocess.check_output(
                ["git", "show", f"{ref}:{source.relative_to(ROOT)}"], cwd=ROOT)
                if ref else source.read_bytes())
            frozen.append(destination)
        if not ref and hashes(SOURCES) != before:
            raise RuntimeError("Product inputs changed while freezing the standalone gate")
        bundle = compiler_bundle(root)
        sources = fixture_sources(root, bundle, frozen)
        harness = root / FIXTURE.name
        harness.write_bytes(FIXTURE.read_bytes())
        inputs = [*sources, harness, *(p for p in bundle.rglob("*") if p.is_file())]
        frozen_before = hashes(inputs)
        binary = root / "vertex-attributes"
        command = ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library", "-D", "SCENE_GRAPH_TESTING",
                   "-whole-module-optimization", "-Onone", *map(str, sources), str(harness),
                   "-framework", "Metal", "-framework", "CoreGraphics", "-framework", "ImageIO",
                   "-framework", "Security", "-module-cache-path", str(root / "modules"),
                   "-o", str(binary)]
        if os.environ.get("MWX_DIRECT_DRAW_LEGACY_HOST") == "1":
            command[5:5] = ["-D", "MWX_DIRECT_DRAW_LEGACY_HOST"]
        env = os.environ.copy()
        env["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        env["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        env["MWX_SCENE_GENERIC_SHADER_CACHE"] = str(root / "isolated-cache")
        compiled = subprocess.run(command, cwd=ROOT, env=env,
                                  capture_output=True, text=True, timeout=240)
        if cls.evidence:
            (cls.evidence / "compile.json").write_text(json.dumps({
                "command": command, "productRef": ref, "returncode": compiled.returncode,
                "stderr": compiled.stderr, "frozenInputs": frozen_before,
                "fixtureTrust": json.loads((root / "fixture-trust.json").read_text()),
            }, indent=2) + "\n")
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        run_command = [str(binary), str(bundle), str(root / "artifacts")]
        if os.environ.get("MWX_DIRECT_DRAW_CPU_ONLY") == "1":
            run_command.append("--cpu-only")
        completed = subprocess.run(run_command, cwd=root, env=env,
                                   capture_output=True, text=True, timeout=180)
        if cls.evidence:
            (cls.evidence / "result.json").write_text(completed.stdout)
            (cls.evidence / "run.log").write_text(completed.stderr)
            (cls.evidence / "identity.json").write_text(json.dumps({
                "frozenBefore": frozen_before, "frozenAfter": hashes(inputs),
                "productRef": ref, "runReturncode": completed.returncode,
                "appOrVMRun": False, "officialRGBParity": "not-claimed",
            }, indent=2) + "\n")
        if frozen_before != hashes(inputs):
            raise RuntimeError("Frozen gate inputs changed during compilation or GPU run")
        if completed.returncode:
            raise RuntimeError(completed.stderr or completed.stdout)
        cls.result = json.loads(completed.stdout)

    def gpu_frames(self):
        if not self.result["metalAvailable"]:
            self.skipTest("No offscreen GPU run; CPU ABI only")
        return self.result["frames"]

    def close(self, observed, expected, *, delta=0.0001):
        self.assertEqual(len(observed), len(expected))
        for actual, wanted in zip(observed, expected, strict=True):
            self.assertAlmostEqual(actual, wanted, delta=delta)

    def test_host_defaults_and_authored_points_use_real_packed_bindings(self):
        cpu = self.result["cpu"]
        self.assertIsNotNone(cpu["default01"], "host did not expose the quad ABI")
        self.close(cpu["default01"], [0, 1, 1, 1])
        self.close(cpu["default23"], [0, 0, 1, 0])
        self.close(cpu["authored01"], [0.05, 0.95, 1.15, 1.2])
        self.close(cpu["authored23"], [-0.25, -0.2, 1.3, -0.35])
        self.assertTrue(cpu["wrongTypeRejected"])

    def test_logical_H_size_is_independent_of_physical_RTT(self):
        self.close(self.result["cpu"]["logicalSize"], [100, 100])
        self.close(self.result["cpu"]["ordinarySize"], [96, 96])
        for frame in self.gpu_frames():
            with self.subTest(frame={k: frame[k] for k in ("domain", "backend", "mode", "physicalSize")}):
                self.close(frame["encodedInputSize"], [100, 100])

    def test_partial_coverage_storage_is_derived_by_the_real_attachment_owner(self):
        for name, passed in self.result["cpu"]["partialCoverageStorage"].items():
            with self.subTest(contract=name):
                self.assertTrue(passed)

    def test_two_real_backends_keep_authored_UV_and_position_at_sentinels(self):
        frames = self.gpu_frames()
        self.assertEqual({f["backend"] for f in frames}, {"boundedSwift", "genericCompilerArtifact"})
        self.assertEqual(len(frames), 84)
        for frame in frames:
            if frame["domain"] == "default-unit-in-E-capture":
                continue
            for name in ("interior", "outsideUnit"):
                if name not in frame["probes"]:
                    continue
                probe = frame["probes"][name]
                u, v = probe["actualUV"]
                expected = ([u, v, 0.25, 1] if frame["mode"] == "uv" else
                            [100 * (u - 0.5), 100 * (0.5 - v), 0.25, 1]
                            if frame["mode"] == "position" else [0.21875, 0.225, 0.25, 1])
                with self.subTest(domain=frame["domain"], backend=frame["backend"],
                                  mode=frame["mode"], renamed=frame["renamed"], sentinel=name,
                                  size=frame["physicalSize"]):
                    self.assertTrue(frame["completed"])
                    # One authored-coordinate tolerance serves UV and local
                    # position. The latter is expressed in H-scaled units;
                    # using an unscaled UV epsilon there rejects the same
                    # interpolation error after merely changing its units.
                    tolerance = 0.00002 * (100 if frame["mode"] == "position" else 1)
                    self.close(probe["pixel"], expected, delta=tolerance)

    def test_renamed_equivalent_sources_and_both_backends_agree_on_gpu(self):
        frames = self.gpu_frames()
        ordinary = {(f["domain"], f["mode"], f["physicalSize"]): f["probes"]
                    for f in frames if f["backend"] == "boundedSwift" and not f["renamed"]}
        for frame in frames:
            key = frame["domain"], frame["mode"], frame["physicalSize"]
            with self.subTest(backend=frame["backend"], renamed=frame["renamed"], key=key):
                self.assertEqual(frame["probes"], ordinary[key])

    def test_true_polygon_leaves_AABB_minus_polygon_transparent(self):
        for frame in self.gpu_frames():
            if frame["domain"] not in ("E", "N"):
                continue
            with self.subTest(backend=frame["backend"], mode=frame["mode"],
                              domain=frame["domain"], size=frame["physicalSize"],
                              renamed=frame["renamed"]):
                pixel = frame["probes"]["aabbMinusPolygon"]["pixel"]
                if frame["domain"] == "N":
                    self.close(pixel, [0, 0, 0, 0], delta=0)
                else:
                    self.assertAlmostEqual(pixel[3], 1, delta=0)

    def test_default_unit_counterexample_does_not_inherit_authored_domain(self):
        for frame in self.gpu_frames():
            if frame["domain"] == "default-unit-in-E-capture":
                with self.subTest(backend=frame["backend"], mode=frame["mode"], renamed=frame["renamed"]):
                    self.close(frame["probes"]["outsideUnit"]["pixel"], [0, 0, 0, 0], delta=0)
                    self.assertEqual(frame["probes"]["interior"]["pixel"][3], 1)


if __name__ == "__main__":
    unittest.main()
