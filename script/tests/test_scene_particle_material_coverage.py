#!/usr/bin/env python3
"""Real material preparation and pipeline demand for particle alpha-to-coverage.

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

    def test_a2c_material_preparation_is_independent_of_geometry_profile(self) -> None:
        rows = self.outputs["profiles"]
        positives = {
            "sprite", "renamed", "renamedRope", "screen", "rendererFlagOne", "normalizedBlend",
            "defaultAlpha", "knownZeroCombos", "overbrightZero", "overbrightFraction",
            "overbrightSixtyFour", "overbrightSixtyFive", "overbrightLarge",
            "spritetrail", "rope", "ropetrail", "fixed", "upright", "axis", "rendererFlags",
            "malformedRenderer", "unknownRendererField", "twoRenderers", "normalCull",
            "depthTest", "depthWrite", "bothDepth", "ropeDepthCull", "trailReadOnlyDepth",
            "ropeTrailDepthWrite",
        }
        ordinary = {
            "oldAdditiveRope", "oldTranslucentTrail", "oldFixedTranslucent", "oldSpriteDepthCull",
            "translucentRopeDepthCull", "additiveTrailReadOnlyDepth", "refractionTrailReadOnlyDepth",
        }
        resource_failures = {"customShader", "missingTexture"}
        rejected = {
            "passOne", "passNegative", "refract", "cutout", "lighting",
            "unknownComboZero", "unknownComboOne", "userTexture", "userValue", "alphaEnabled",
            "alphaUnknown", "negativeOverbright", "nonfiniteOverbright", "nanOverbright",
            "floatOverflowOverbright",
            "emptyOverbright", "vectorOverbright", "dynamicOverbright", "unknownConstant",
            "unknownBlend", "normalBlend", "refractionDepthWrite", "depthUnknownCombo",
            "depthUserTexture",
        }
        self.assertEqual(set(rows), positives | ordinary | resource_failures | rejected)
        self.assertEqual({name for name, row in rows.items() if row["hasPipelineState"]},
                         positives | ordinary | resource_failures)
        for name in positives:
            with self.subTest(name=name):
                self.assertEqual(rows[name]["sharedBlend"], "alphatocoverage")
                self.assertEqual(rows[name]["pipelineBlend"], "alphatocoverage")
                self.assertTrue(rows[name]["shaderSupported"])
                self.assertTrue(rows[name]["textureAvailable"])
        self.assertEqual(rows["unknownBlend"]["sharedBlend"], "unavailable")

    def test_overbright_is_a_nonnegative_finite_backend_float(self) -> None:
        rows = self.outputs["profiles"]
        self.assertAlmostEqual(rows["overbrightFraction"]["overbright"], 1.19, places=5)
        for name, value in (("overbrightZero", 0), ("overbrightSixtyFour", 64),
                            ("overbrightSixtyFive", 65), ("overbrightLarge", 1024)):
            with self.subTest(name=name):
                self.assertEqual(rows[name]["overbright"], value)
        for name in ("negativeOverbright", "nonfiniteOverbright", "nanOverbright",
                     "floatOverflowOverbright", "emptyOverbright", "vectorOverbright",
                     "dynamicOverbright"):
            with self.subTest(name=name):
                self.assertFalse(rows[name]["hasPipelineState"])
                self.assertIn("unsupportedRenderState", rows[name]["diagnostics"])

    def test_shader_and_texture_availability_are_separate_preparation_facts(self) -> None:
        rows = self.outputs["profiles"]
        self.assertTrue(rows["customShader"]["hasPipelineState"])
        self.assertFalse(rows["customShader"]["shaderSupported"])
        self.assertIn("unsupportedShader", rows["customShader"]["diagnostics"])
        self.assertTrue(rows["missingTexture"]["hasPipelineState"])
        self.assertFalse(rows["missingTexture"]["textureAvailable"])
        self.assertIn("missingTextureFile", rows["missingTexture"]["diagnostics"])

    def test_material_preparation_preserves_the_original_camera_selection(self) -> None:
        rows = self.outputs["profiles"]
        camera_selected = {
            "sprite", "renamed", "screen", "rendererFlagOne", "normalizedBlend",
            "defaultAlpha", "knownZeroCombos", "overbrightZero", "overbrightFraction",
            "overbrightSixtyFour", "overbrightSixtyFive", "overbrightLarge", "normalCull",
            "depthTest", "depthWrite", "bothDepth", "oldSpriteDepthCull", "customShader",
            "missingTexture",
        }
        self.assertEqual({name for name, row in rows.items() if row["sceneCamera"]}, camera_selected)

    def test_cull_and_depth_follow_the_authored_material_state(self) -> None:
        rows = self.outputs["profiles"]
        depth_states = {
            "depthTest": (True, False), "depthWrite": (False, True), "bothDepth": (True, True),
            "ropeDepthCull": (True, True), "trailReadOnlyDepth": (True, False),
            "ropeTrailDepthWrite": (False, True), "oldSpriteDepthCull": (True, True),
            "translucentRopeDepthCull": (True, True), "additiveTrailReadOnlyDepth": (True, False),
            "refractionTrailReadOnlyDepth": (True, False),
        }
        back_cull = {"normalCull", "ropeDepthCull", "oldSpriteDepthCull", "translucentRopeDepthCull"}
        for name, row in rows.items():
            if not row["hasPipelineState"]:
                continue
            with self.subTest(name=name):
                self.assertEqual((row["depthTest"], row["depthWrite"]),
                                 depth_states.get(name, (False, False)))
                self.assertEqual(row["depthAttachment"], name in depth_states)
                self.assertEqual(row["cull"], "back" if name in back_cull else "none")
        self.assertTrue(rows["refractionTrailReadOnlyDepth"]["refractionPrepared"])
        self.assertFalse(rows["refractionDepthWrite"]["refractionPrepared"])

    def test_ordinary_blend_state_capabilities_are_preserved(self) -> None:
        rows = self.outputs["profiles"]
        for name, blend in (("oldAdditiveRope", "additive"),
                            ("oldTranslucentTrail", "translucent"),
                            ("oldFixedTranslucent", "translucent"),
                            ("oldSpriteDepthCull", "translucent"),
                            ("translucentRopeDepthCull", "translucent"),
                            ("additiveTrailReadOnlyDepth", "additive"),
                            ("refractionTrailReadOnlyDepth", "translucent")):
            with self.subTest(name=name):
                self.assertEqual(rows[name]["pipelineBlend"], blend)
                self.assertTrue(rows[name]["hasPipelineState"])
        self.assertFalse(rows["normalBlend"]["hasPipelineState"])

    def test_prepared_root_and_child_demand_precedes_particle_birth(self) -> None:
        rows = self.outputs["demand"]
        for name in ("rootNoBirth", "ropeNoBirth", "trailNoBirth", "preparedHidden",
                     "childNoBirth", "trailChildNoBirth"):
            with self.subTest(name=name):
                self.assertTrue(rows[name]["required"])
                self.assertEqual(rows[name]["rootParticles"], 0)
                self.assertEqual(rows[name]["childParticles"], 0)
                self.assertEqual(rows[name]["childSystems"], 0)
                self.assertEqual(rows[name]["rootSystems"], 1)
        self.assertEqual(rows["childNoBirth"]["activeLayerIDs"], [5])
        self.assertEqual(rows["ropeNoBirth"]["activeLayerIDs"], [10])
        self.assertEqual(rows["trailNoBirth"]["activeLayerIDs"], [11])
        self.assertEqual(rows["trailChildNoBirth"]["activeLayerIDs"], [12])
        self.assertEqual(rows["hidden"]["activeLayerIDs"], [])
        self.assertEqual(rows["preparedHidden"]["activeLayerIDs"], [4])
        for name in ("empty", "ordinary", "hidden", "rejectedChild", "customShader",
                     "missingTexture", "ordinaryWithRejectedPeer", "ordinaryWithCustomShaderPeer",
                     "ordinaryWithMissingTexturePeer"):
            with self.subTest(name=name):
                self.assertFalse(rows[name]["required"])
        for name in ("ordinaryWithRejectedPeer", "ordinaryWithCustomShaderPeer",
                     "ordinaryWithMissingTexturePeer"):
            with self.subTest(healthyPeer=name):
                self.assertEqual(rows[name]["activeLayerIDs"], [7])
                self.assertEqual(rows[name]["rootSystems"], 1)
        self.assertIn("unsupportedRenderState", rows["rejectedChild"]["diagnostics"])
        self.assertEqual(rows["rejectedChild"]["activeLayerIDs"], [6])
        self.assertEqual(rows["rejectedChild"]["rootSystems"], 1)
        self.assertIn("unsupportedShader", rows["ordinaryWithCustomShaderPeer"]["diagnostics"])
        self.assertIn("missingTextureFile", rows["ordinaryWithMissingTexturePeer"]["diagnostics"])
        for name in ("customShader", "missingTexture"):
            with self.subTest(unavailableRoot=name):
                self.assertEqual(rows[name]["rootSystems"], 0)

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
                     "primitiveWithBinding", "unknownKind", "emptyStringUser", "nullUserAnimation",
                     "unknownConstant"):
            with self.subTest(name=name):
                self.assertFalse(rows[name]["required"])
                self.assertEqual(rows[name]["rootSystems"], 0)
                self.assertIn("unsupportedRenderState", rows[name]["diagnostics"])
        self.assertFalse(rows["ordinaryNullUser"]["required"])
        self.assertEqual(rows["ordinaryNullUser"]["rootSystems"], 1)
        self.assertEqual(rows["ordinaryNullUser"]["diagnostics"], [])


if __name__ == "__main__":
    unittest.main()
