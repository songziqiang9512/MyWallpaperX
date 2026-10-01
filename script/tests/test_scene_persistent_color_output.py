#!/usr/bin/env python3
"""RF07 direct product-owner checks and the pre-change terminal-output red case.

GPU: python3.12 -m unittest script.tests.test_scene_persistent_color_output.ScenePersistentColorOutputTests

The pre-change terminal primitive red is frozen in /private/tmp/mwx-rf07.
This gate now compiles the real target pool and submission coordinator together.
The fixture never implements its own history or completion state machine.
The GPU-failure case injects the existing completion seam after real commands
complete; it is not a hardware GPU-failure reproduction.
"""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_scene_material_copy_history_rendering import (
    SWIFT_SOURCES as OWNER_SOURCES, SUPPORT as OWNER_SUPPORT,
)

from script.tests.test_scene_bloom_post_process import FAULT_HEADER, FAULT_SOURCE

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
FIXTURES = Path(__file__).parent / "fixtures"
MAPPING = SCENE / "Rendering/Composition/SceneDisplayMappingPostProcess.swift"
RESOURCE_BUDGET = SCENE / "Resources/Textures/SceneResourceBudget.swift"


# Stored dependencies only. All color flow, outcome, pool and history logic is
# compiled from production files; this carrier avoids unrelated app systems.
TERMINAL_SUPPORT = r'''
struct TerminalRenderDescriptor {
    struct Camera { let clearColor: [Float]; let bloom: SceneBloomConfiguration }
    let hdrEnabled: Bool
    let camera: Camera
}
struct TerminalCompositor {
    let resolvedMaterialRuntime: SceneResolvedMaterialSubmissionCoordinator?
    func endResolvedMaterialFrame(on buffer: MTLCommandBuffer) -> Bool {
        guard let runtime = resolvedMaterialRuntime else { return false }
        let sealed = runtime.sealFrame(on: buffer)
        _ = runtime.endFrame()
        return sealed
    }
}
struct SceneMetalRenderer {
    let renderDescriptor: TerminalRenderDescriptor
    let imageCompositor: TerminalCompositor
    let bloomPostProcess: SceneBloomPostProcess?
    let displayMappingPostProcess: SceneDisplayMappingPostProcess?
}
'''
BLIT_FAULT_HEADER = "void MWXArmBlitFault(id<MTLCommandBuffer> buffer, NSUInteger mask);"
BLIT_FAULT_SOURCE = r'''
static id blitBuffer;
static NSUInteger blitMask, blitAttempts;
static IMP blitOriginal;
static id faultBlit(id receiver, SEL selector) {
    if (receiver == blitBuffer && (blitMask & (1UL << blitAttempts++))) return nil;
    return ((id (*)(id, SEL))blitOriginal)(receiver, selector);
}
void MWXArmBlitFault(id<MTLCommandBuffer> buffer, NSUInteger mask) {
    if (!blitOriginal) {
        Method method = class_getInstanceMethod(object_getClass(buffer), @selector(blitCommandEncoder));
        blitOriginal = method_setImplementation(method, (IMP)faultBlit);
    }
    blitBuffer = buffer;
    blitMask = mask;
    blitAttempts = 0;
}
'''


def _run(command: list[str], *, cwd: Path, timeout: int = 120) -> str:
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True,
                            timeout=timeout, check=False)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result.stdout


def _compile_and_run(name: str) -> dict:
    with tempfile.TemporaryDirectory(prefix="mwx-persistent-color-") as directory:
        folder = Path(directory)
        _run(["xcrun", "-sdk", "macosx", "metal", "-c",
              str(MAPPING.with_suffix(".metal")), "-o", str(folder / "mapping.air")],
             cwd=folder)
        _run(["xcrun", "-sdk", "macosx", "metal", "-c",
              str(MAPPING.with_name("SceneBloomPostProcess.metal")), "-o", str(folder / "bloom.air")], cwd=folder)
        (folder / "Fault.h").write_text(FAULT_HEADER + BLIT_FAULT_HEADER)
        (folder / "Fault.m").write_text(FAULT_SOURCE + BLIT_FAULT_SOURCE)
        _run(["xcrun", "clang", "-fobjc-arc", "-c", str(folder / "Fault.m"),
              "-o", str(folder / "fault.o")], cwd=folder)
        _run(["xcrun", "-sdk", "macosx", "metallib", str(folder / "mapping.air"), str(folder / "bloom.air"),
              "-o", str(folder / "default.metallib")], cwd=folder)
        support = folder / "Support.swift"
        support.write_text(OWNER_SUPPORT + TERMINAL_SUPPORT, encoding="utf-8")
        sources = list(dict.fromkeys([*OWNER_SOURCES, MAPPING, MAPPING.with_name("SceneBloomPostProcess.swift"), RESOURCE_BUDGET,
                   SCENE / "Rendering/Composition/SceneMainPassEncoder.swift",
                   SCENE / "Rendering/Frame/SceneMetalRenderer+ClearColor.swift",
                   SCENE / "Rendering/Frame/SceneMetalRenderer+FrameOutcome.swift", support, FIXTURES / name]))
        binary = folder / "persistent-color"
        _run(["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library", "-whole-module-optimization", "-D", "SCENE_GRAPH_TESTING",
              "-import-objc-header", str(folder / "Fault.h"), str(folder / "fault.o"),
              *map(str, sources), "-module-cache-path", str(folder / "module-cache"),
              "-o", str(binary)], cwd=folder, timeout=300)
        output = _run([str(binary)], cwd=folder, timeout=30)
        return json.loads(output.strip().splitlines()[-1])


class ScenePersistentColorOutputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.result = _compile_and_run("ScenePersistentColorOutputHarness.swift")

    def test_accumulating_hdr_is_bounded_on_every_terminal_export(self):
        # Hardcoded independent shoulder golden; this fails before RF07.
        self.assertEqual(len(self.result["accumulatingFrames"]), 8)
        for frame in self.result["accumulatingFrames"]:
            self.assertTrue(frame["gpuCompleted"])
            self.assertAlmostEqual(frame["rgb"][0], 11 / 12, delta=1 / 1024)
            self.assertAlmostEqual(frame["rgb"][1], 0.25, delta=1 / 1024)
            self.assertAlmostEqual(frame["rgb"][2], 0.5, delta=1 / 1024)
            self.assertEqual(frame["alpha"], 1)

    def test_real_target_and_submission_owner_lifecycle(self):
        for name, passed in self.result["ownerChecks"].items():
            with self.subTest(name=name):
                self.assertTrue(passed, name)

    def test_half_alpha_authored_draw_accumulates_only_in_raw(self):
        expected = [[1.5, .625, .25, 1, 5/6, .6, .25, 1],
                    [.75, .8125, .125, 1, 2/3, 9/13, .125, 1]]
        for actual, golden in zip(self.result["alphaFrames"], expected, strict=True):
            for value, target in zip(actual, golden, strict=True):
                self.assertAlmostEqual(value, target, delta=1/1024)

    def test_existing_clear_true_and_non_hdr_routes_are_unchanged(self):
        self.assertTrue(self.result["clearedHDR"]["gpuCompleted"])
        self.assertAlmostEqual(self.result["clearedHDR"]["rgb"][0], 11 / 12, delta=1 / 1024)
        self.assertEqual(self.result["nonHDR"]["rgb"], [3, 0.25, 0.5])
        self.assertEqual(self.result["nonHDR"]["alpha"], 1)


if __name__ == "__main__":
    unittest.main()
