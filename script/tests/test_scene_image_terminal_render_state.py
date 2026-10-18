"""Finite ordinary-plane terminal depth/cull through production draw owners.

The pixel run is narrow; it does not run the advanced-blend matrix or prove
StaticModelFrame pool/admission/App behavior. Compile-only never invokes Metal.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_color_blend_capture_region as shared


class SceneImageTerminalRenderStateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("swiftc") or not shutil.which("xcrun"):
            raise unittest.SkipTest("Swift/Metal toolchain unavailable")
        cls.compile_only = os.environ.get("MWX_IMAGE_TERMINAL_COMPILE_ONLY") == "1"
        output = Path(os.environ.get("MWX_IMAGE_TERMINAL_EVIDENCE", "/private/tmp/mwx-image-terminal"))
        output.mkdir(parents=True, exist_ok=True)
        paths = [Path(__file__), shared.HARNESS, shared.PROJECTION_SOURCE, *shared.SOURCES,
                 shared.SHADER, shared.FOG, Path(shared.__file__),
                 Path(__file__).with_name("scene_color_blend_capture_test_support.py")]
        identity = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        with tempfile.TemporaryDirectory(prefix="terminal-", dir=output) as directory:
            root = Path(directory)
            support, binary = root / "Projection.swift", root / "probe"
            support.write_text(shared.projection_support())
            commands = [["swiftc", "-DDEBUG", *map(str, shared.SOURCES), str(support),
                         str(shared.HARNESS), "-module-cache-path", str(root / "cache"), "-o", str(binary)]]
            if cls.compile_only:
                commands.append([str(binary), "--compile-only"])
            else:
                air, library = root / "image.air", root / "image.metallib"
                commands += [["xcrun", "--sdk", "macosx", "metal", "-c", str(shared.SHADER), "-o", str(air)],
                             ["xcrun", "--sdk", "macosx", "metallib", str(air), "-o", str(library)],
                             [str(binary), str(library), "--terminal-finite-only"]]
            outputs = []
            for command in commands:
                ran = subprocess.run(command, capture_output=True, text=True, timeout=180)
                outputs.append(ran.stdout + ran.stderr)
                if ran.returncode:
                    (output / "first-failure.log").write_text("\n".join(outputs))
                    raise AssertionError(ran.stdout + ran.stderr)
            cls.result = json.loads(outputs[-1])
        assert identity == {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}, "source identity drift"
        (output / "source-identity.json").write_text(json.dumps(identity, indent=2))
        (output / "report.json").write_text(json.dumps(cls.result, indent=2))
        if cls.result.get("metalUnavailable"):
            raise unittest.SkipTest("Metal unavailable")

    def test_fixture_compiles_without_requiring_gpu_execution(self):
        if self.compile_only:
            self.assertEqual(self.result, {"compiled": True, "gpuExecuted": False})

    def test_finite_terminal_state_pixels_and_failure_boundaries(self):
        if self.compile_only:
            self.skipTest("compile-only: finite GPU semantics not executed")
        rows = self.result["finiteStates"]
        self.assertEqual(len(rows), 11)
        amber, blue, green, black = [0, 128, 255, 255], [255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 0, 255]
        for row in rows:
            name = row["name"]
            needs_depth = name not in ("neither", "normal-front-no-depth", "transparent-no-write")
            with self.subTest(name=name):
                self.assertTrue(row["completed"] and row["drawn"] and row["supports"], row)
                self.assertTrue(row["stateMismatchRejected"] and row["wrongPassRejected"] and row["unsupportedPoliciesRejected"], row)
                self.assertTrue(row["overlayDrawn"], row)
                self.assertEqual(row["overlay"], [192, 32, 192, 255], row)
                self.assertEqual(row["baseSupports"], not needs_depth, row)
                self.assertEqual(row["missingRejected"], needs_depth, row)
                self.assertEqual(row["left"], blue if name in ("write-only", "neither", "normal-front-no-depth") else amber, row)
                self.assertEqual(row["right"], black if name in ("normal-back", "transparent-write", "transparent-no-write") else blue, row)
                expected_far = blue if name in ("read-write", "write-only") else black if name == "transparent-write" else green
                self.assertEqual(row["farPeer"], expected_far, row)
        # The existing captured-main role retains read-only behavior, even when
        # a preceding color-only encoder detached the scene depth attachment.
        for row in self.result["terminalDepth"]:
            self.assertTrue(row["completed"] and row["drawn"] and row["missingRejected"], row)
            self.assertEqual(row["left"], amber if row["writer"] else blue, row)
            self.assertEqual(row["right"], blue, row)
            self.assertEqual(row["farPeer"], green, row)


if __name__ == "__main__":
    unittest.main()
