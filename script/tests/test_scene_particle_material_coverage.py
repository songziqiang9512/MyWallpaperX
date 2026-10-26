#!/usr/bin/env python3
"""Real preparation gates for the bounded Sprite alpha-to-coverage profile.

This compiles production parsers, material compiler, Runtime and child expansion.
Runtime creates shared texture/buffer resources; no GPU commands are submitted.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

if __package__:
    from .test_scene_particle_assets import SWIFT_SOURCES as ASSET_SOURCES
    from .test_scene_particle_runtime import SWIFT_SOURCES as RUNTIME_SOURCES
    from .scene_particle_runtime_configuration_cases import NO_TIMESTAMP_OBSERVATION_SUPPORT
else:
    from test_scene_particle_assets import SWIFT_SOURCES as ASSET_SOURCES
    from test_scene_particle_runtime import SWIFT_SOURCES as RUNTIME_SOURCES
    from scene_particle_runtime_configuration_cases import NO_TIMESTAMP_OBSERVATION_SUPPORT

FIXTURES = Path(__file__).resolve().parent / "fixtures"
BASE_HARNESS = FIXTURES / "SceneParticleRuntimeHarness.swift"
COVERAGE_HARNESS = FIXTURES / "SceneParticleMaterialCoverageHarness.swift"
# Imported groups can spell the same file through Scene/../Storage or Storage.
# Resolve full paths before de-duplication; distinct files never collapse by name.
SWIFT_SOURCES = list(dict.fromkeys(path.resolve() for path in [*RUNTIME_SOURCES, *ASSET_SOURCES]))
HARNESS_MAIN = '''    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw HarnessError.missingMode }
        switch CommandLine.arguments[1] {
        case "profiles": try printJSON(SceneParticleMaterialCoverageHarness.profiles())
        case "demand": try printJSON(SceneParticleMaterialCoverageHarness.demand())
        default: throw HarnessError.missingMode
        }
    }

'''


class SceneParticleMaterialCoverageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if not swiftc:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-particle-coverage-")
        cls.addClassCleanup(cls.temporary_directory.cleanup)
        directory = Path(cls.temporary_directory.name)
        source = BASE_HARNESS.read_text()
        start = source.index("    static func main() throws {")
        end = source.index("    static func renderDescriptor(", start)
        harness = directory / BASE_HARNESS.name
        harness.write_text(NO_TIMESTAMP_OBSERVATION_SUPPORT + source[:start] + HARNESS_MAIN + source[end:])
        cls.binary = directory / "particle-coverage"
        cls.compilation = subprocess.run([
            swiftc, "-D", "DEBUG", *(str(path) for path in SWIFT_SOURCES), str(harness),
            str(COVERAGE_HARNESS), "-framework", "Metal", "-framework", "CoreGraphics",
            "-framework", "ImageIO", "-module-cache-path", str(directory / "module-cache"),
            "-o", str(cls.binary),
        ], capture_output=True, text=True)
        if cls.compilation.returncode:
            raise RuntimeError(cls.compilation.stderr)
        cls.outputs = {}
        for mode in ("profiles", "demand"):
            completed = subprocess.run([str(cls.binary), mode], capture_output=True, text=True)
            if completed.returncode:
                raise RuntimeError(f"{mode}: {completed.stderr}")
            cls.outputs[mode] = json.loads(completed.stdout)

    def test_only_plain_static_screen_sprite_profile_is_admitted(self) -> None:
        rows = self.outputs["profiles"]
        positives = {
            "sprite", "renamed", "screen", "rendererFlagOne", "normalizedBlend",
            "defaultAlpha", "knownZeroCombos", "overbrightZero", "overbrightFraction",
            "overbrightLimit",
        }
        old = {"oldAdditiveRope", "oldTranslucentTrail", "oldFixedTranslucent", "oldSpriteDepthCull"}
        rejected = {
            "spritetrail", "rope", "ropetrail", "fixed", "upright", "axis", "rendererFlags",
            "malformedRenderer", "unknownRendererField", "twoRenderers", "passOne", "passNegative",
            "normalCull", "depthTest", "depthWrite", "bothDepth", "refract", "cutout", "lighting",
            "unknownComboZero", "unknownComboOne", "userTexture", "userValue", "alphaEnabled",
            "alphaUnknown", "negativeOverbright", "largeOverbright", "nonfiniteOverbright",
            "emptyOverbright", "vectorOverbright", "dynamicOverbright", "unknownConstant",
            "customShader", "unknownBlend", "normalBlend",
        }
        self.assertEqual(set(rows), positives | old | rejected)
        self.assertEqual({name for name, row in rows.items() if row["executable"]}, positives | old)
        for name in positives:
            with self.subTest(name=name):
                self.assertEqual(rows[name]["sharedBlend"], "alphatocoverage")
                self.assertEqual(rows[name]["pipelineBlend"], "alphatocoverage")
                self.assertTrue(rows[name]["hasRenderState"])
                self.assertTrue(rows[name]["sceneCamera"])
                self.assertFalse(rows[name]["depthAttachment"])
                self.assertEqual(rows[name]["cull"], "none")
        self.assertAlmostEqual(rows["overbrightFraction"]["overbright"], 1.19, places=5)
        self.assertEqual(rows["overbrightZero"]["overbright"], 0)
        self.assertEqual(rows["overbrightLimit"]["overbright"], 64)
        self.assertFalse(rows["customShader"]["shaderSupported"])
        self.assertEqual(rows["unknownBlend"]["sharedBlend"], "unavailable")

    def test_ordinary_blend_state_capabilities_are_preserved(self) -> None:
        rows = self.outputs["profiles"]
        for name, blend in (("oldAdditiveRope", "additive"),
                            ("oldTranslucentTrail", "translucent"),
                            ("oldFixedTranslucent", "translucent"),
                            ("oldSpriteDepthCull", "translucent")):
            with self.subTest(name=name):
                self.assertEqual(rows[name]["pipelineBlend"], blend)
                self.assertTrue(rows[name]["hasRenderState"])
        self.assertTrue(rows["oldSpriteDepthCull"]["depthAttachment"])
        self.assertEqual(rows["oldSpriteDepthCull"]["cull"], "back")
        self.assertFalse(rows["normalBlend"]["executable"])

    def test_prepared_root_and_child_demand_precedes_particle_birth(self) -> None:
        rows = self.outputs["demand"]
        for name in ("rootNoBirth", "preparedHidden", "childNoBirth"):
            with self.subTest(name=name):
                self.assertTrue(rows[name]["required"])
                self.assertEqual(rows[name]["rootParticles"], 0)
                self.assertEqual(rows[name]["childParticles"], 0)
                self.assertEqual(rows[name]["childSystems"], 0)
                self.assertEqual(rows[name]["rootSystems"], 1)
        self.assertEqual(rows["childNoBirth"]["activeLayerIDs"], [5])
        self.assertEqual(rows["hidden"]["activeLayerIDs"], [])
        self.assertEqual(rows["preparedHidden"]["activeLayerIDs"], [4])
        for name in ("empty", "ordinary", "hidden", "rejectedChild", "customShader",
                     "ordinaryWithRejectedPeer"):
            with self.subTest(name=name):
                self.assertFalse(rows[name]["required"])
        self.assertEqual(rows["ordinaryWithRejectedPeer"]["activeLayerIDs"], [7])
        self.assertEqual(rows["ordinaryWithRejectedPeer"]["rootSystems"], 1)

    def test_runtime_provenance_rejects_dynamic_and_unknown_constant_wrappers(self) -> None:
        rows = self.outputs["demand"]
        for name, row in rows.items():
            with self.subTest(noGPUUpload=name):
                self.assertEqual(row["uploadQueueCreations"], 0)
        for name in ("primitive", "primitiveString", "valueOnly", "nullUser"):
            with self.subTest(name=name):
                self.assertTrue(rows[name]["required"])
                self.assertEqual(rows[name]["rootSystems"], 1)
        for name in ("scriptWrapper", "emptyScript", "objectUser", "boundUser", "animation",
                     "unparsedAnimation", "timelineDiagnostic", "unknownWrapper", "emptyBinding",
                     "primitiveWithBinding", "unknownKind", "emptyStringUser", "nullUserAnimation"):
            with self.subTest(name=name):
                self.assertFalse(rows[name]["required"])
                self.assertEqual(rows[name]["rootSystems"], 0)
                self.assertIn("unsupportedRenderState", rows[name]["diagnostics"])
        self.assertFalse(rows["ordinaryNullUser"]["required"])
        self.assertEqual(rows["ordinaryNullUser"]["rootSystems"], 1)
        self.assertEqual(rows["ordinaryNullUser"]["diagnostics"], [])


if __name__ == "__main__":
    unittest.main()
