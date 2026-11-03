#!/usr/bin/env python3
"""Real Puppet playback publishes complete pose/coverage frames to Metal."""

from __future__ import annotations

import json
import hashlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.test_scene_puppet_playback import SCENE_ROOT, SWIFT_SOURCES
from script.tests.test_scene_puppet_direct_playback import EXTRA_SOURCES

PIPELINE = SCENE_ROOT / "Rendering/Metal/SceneStaticModelPipeline.swift"
FOG_HEADER = SCENE_ROOT / "Rendering/Composition/SceneDistanceFog.metalh"


PLAYBACK_SOURCES = [
    "Runtime/Frame/SceneMaterialRenderState.swift",
    "Format/SceneMdlPuppetAttachmentReader.swift",
    "Systems/Puppet/ScenePuppetAttachmentPoseProjection.swift",
    "Systems/Puppet/ScenePuppetTranslationMotion.swift",
    "Systems/Puppet/ScenePuppetAnimationPlaybackRuntime.swift",
    "Systems/Puppet/ScenePuppetAnimationControl.swift",
    "Rendering/Geometry/ScenePuppetClipping.swift",
    "Rendering/Geometry/ScenePuppetMeshGeometry.swift",
    "Systems/Puppet/ScenePuppetPlaybackState.swift",
    "Systems/Properties/ScenePuppetAnimationPropertyTarget.swift",
    "Rendering/Geometry/SceneGeometryProduct.swift",
    "Rendering/Frame/SceneSourceUpdateTransaction.swift",
    "Rendering/Metal/SceneStaticModelVertexStream.swift",
    "Rendering/Metal/SceneMetalPipeline.swift",
    "Rendering/Composition/SceneBlendModeShaderSource.swift",
    "Rendering/Targets/SceneOffscreenResolutionPolicy.swift",
    "Diagnostics/ScenePerformanceCounterHub.swift",
]

PLAYBACK_SOURCES += [item for item in EXTRA_SOURCES if item not in PLAYBACK_SOURCES and SCENE_ROOT / item not in SWIFT_SOURCES]


def static_model_carrier_source() -> str:
    """Real mesh/factory/ABI; this direct publication probe needs no model PSO."""
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


FIXTURE = Path(__file__).with_name("fixtures") / "ScenePuppetBufferPublicationHarness.swift"
HARNESS = FIXTURE.read_text()


class PuppetBufferPublicationTests(unittest.TestCase):
    def test_frozen_image_frame_controls_gpu_pixels_coverage_and_clipping_roi(self):
        facts = self.result["frozenImage"]
        for key in ("frozenVertices", "frozenCoverage", "frozenPixels", "frozenPixelCoverage", "frozenROI",
                    "gpuDoesNotPrepareCPU"):
            with self.subTest(check=key):
                self.assertTrue(facts[key], facts)

    def test_direct_publication_uses_frozen_cpu_bytes_bounds_and_independent_surfaces(self):
        facts = self.result["directPublication"]
        for key in ("frozenGPUBytes", "repeatDoesNotPrepareCPU", "frozenBounds",
                    "surfaceIsolation", "frozenBindFallback", "fallbackRecovery", "factoryCount",
                    "noFrameAllocation"):
            with self.subTest(check=key):
                self.assertTrue(facts[key], facts)

    def test_direct_publication_rejects_foreign_command_and_recycles_resolved_storage(self):
        facts = self.result["directPublication"]
        for key in ("wrongCommandAndTransaction", "busyRejectsFourth", "cancelRecoversSlot",
                    "submittedCancelKeepsSlot", "completionRecoversSlot"):
            with self.subTest(check=key):
                self.assertTrue(facts[key], facts)

    def test_translation_query_overlay_expires_once_per_cadence_while_render_rebounds(self):
        facts = self.result["queryRenderTranslation"]
        first, next_pose, later = (facts[key] for key in ("firstPose", "nextPose", "laterPose"))
        self.assertAlmostEqual(first["queryX"], 0.35, places=6)
        self.assertAlmostEqual(first["renderX"], 0.35, places=6)
        self.assertEqual(facts["samePose"], first)
        self.assertEqual(facts["nextAgainPose"], next_pose)
        self.assertEqual(facts["samePositions"], facts["firstPositions"])
        self.assertEqual(facts["same"]["imageSHA256"], facts["first"]["imageSHA256"])
        self.assertAlmostEqual(next_pose["queryX"], 0.1, places=6)
        self.assertAlmostEqual(later["queryX"], 0.1, places=6)
        self.assertGreater(next_pose["renderX"], next_pose["queryX"])
        self.assertLess(next_pose["renderX"], first["renderX"])
        self.assertNotEqual(later["renderX"], next_pose["renderX"])
        for pose_name in ("firstPose", "nextPose", "laterPose"):
            pose = facts[pose_name]
            with self.subTest(pose=pose_name):
                self.assertEqual(pose["queryBasis"], first["queryBasis"])
                self.assertEqual(pose["renderBasis"], first["renderBasis"])
                self.assertEqual(pose["queryBasis"], pose["renderBasis"])
                self.assertAlmostEqual(pose["worldX"], pose["renderX"], places=6)
                self.assertAlmostEqual(pose["attachmentX"], pose["renderX"], places=6)
        self.assertGreater(facts["kickedPose"]["renderX"],later["renderX"])
        self.assertNotEqual(facts["kicked"]["imageSHA256"],facts["later"]["imageSHA256"])
        self.assertNotEqual(facts["firstPositions"], facts["nextPositions"])
        self.assertNotEqual(facts["nextPositions"], facts["laterPositions"])
        # Every vertex moves by the physical root's displacement, while local
        # query translation has already returned to the nonzero animation base.
        delta = next_pose["renderX"] - first["renderX"]
        for before, after in zip(facts["firstPositions"], facts["nextPositions"]):
            self.assertAlmostEqual(after[0] - before[0], delta, places=6)
            self.assertAlmostEqual(after[1], before[1], places=6)
        self.assertNotEqual(facts["first"]["imageSHA256"], facts["later"]["imageSHA256"])
        for name in ("first", "same", "next", "later"):
            frame = facts[name]
            with self.subTest(gpu_frame=name):
                self.assertTrue(frame["readyAfter"] and frame["drew"])
                self.assertEqual(frame["draws"], 1)
                self.assertGreater(frame["litPixels"], 0)

    def test_nonphysical_bone_keeps_prior_setter_translation_across_cadences(self):
        facts = self.result["queryRenderTranslation"]
        self.assertEqual(facts["ordinaryFirstPose"], facts["ordinaryNextPose"])
        self.assertAlmostEqual(facts["ordinaryNextPose"]["queryX"], 0.35, places=6)
        self.assertAlmostEqual(facts["ordinaryNextPose"]["renderX"], 0.35, places=6)
        self.assertEqual(facts["ordinaryFirst"]["imageSHA256"], facts["ordinaryNext"]["imageSHA256"])

    def test_paused_control_blend_reaches_actual_gpu_coverage(self):
        self.assertTrue(self.result["dynamicBlendSamplesEqual"])
        self.assertTrue(self.result["dynamicBlendBuffersChanged"])
        half = self.result["dynamicHalfBlend"]
        full = self.result["dynamicFullBlend"]
        self.assertTrue(half["drew"] and full["drew"])
        self.assertNotEqual(half["imageSHA256"], full["imageSHA256"])
        # Atlas alpha .5 × layer .5 × coverage (.75 versus .5).
        self.assertAlmostEqual(half["centerBGRA"][3], 48, delta=1)
        self.assertAlmostEqual(full["centerBGRA"][3], 32, delta=1)

    @classmethod
    def setUpClass(cls) -> None:
        if not shutil.which("swiftc") or not shutil.which("xcrun"):
            raise unittest.SkipTest("Swift/Metal toolchain unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-puppet-publication-") as directory:
            root = Path(directory)
            identity_paths = [Path(__file__), FIXTURE, PIPELINE, Path(static_model_carrier_source.__code__.co_filename), *SWIFT_SOURCES,
                *(SCENE_ROOT / path for path in PLAYBACK_SOURCES), FOG_HEADER,
                SCENE_ROOT / "Rendering/Composition/SceneLayerColorBlendPipeline.swift",
                SCENE_ROOT / "Rendering/Composition/SceneImageLayer.metal"]
            identity = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in identity_paths}
            source = root / "publication.swift"
            source.write_text(HARNESS + static_model_carrier_source(), encoding="utf-8")
            # Compile the exact production shader/state prefix. The subsequent
            # broad renderer owns framebuffer routing, which this focused GPU
            # test does not need to replace with stub scene/graph contracts.
            color_blend = root / "color_blend.swift"
            color_blend_prefix, _ = (
                SCENE_ROOT / "Rendering/Composition/SceneLayerColorBlendPipeline.swift"
            ).read_text(encoding="utf-8").split("final class SceneLayerColorBlendPipeline {", 1)
            color_blend.write_text(color_blend_prefix, encoding="utf-8")
            air, library, binary = root / "image.air", root / "image.metallib", root / "publication"
            commands = [
                ["xcrun", "--sdk", "macosx", "metal", "-c",
                 str(SCENE_ROOT / "Rendering/Composition/SceneImageLayer.metal"), "-o", str(air)],
                ["xcrun", "--sdk", "macosx", "metallib", str(air), "-o", str(library)],
                ["swiftc", "-D", "DEBUG", *map(str, SWIFT_SOURCES),
                 *(str(SCENE_ROOT / path) for path in PLAYBACK_SOURCES),
                 str(color_blend), str(source), "-o", str(binary)],
            ]
            for command in commands:
                run = subprocess.run(command, capture_output=True, text=True, timeout=120)
                if run.returncode:
                    raise RuntimeError(run.stdout + run.stderr)
            run = subprocess.run([str(binary), str(library), str(FOG_HEADER)], capture_output=True,
                                 text=True, timeout=30)
            if run.returncode:
                raise RuntimeError(f"Puppet publication GPU harness exit {run.returncode}:\n"
                                   + run.stdout + run.stderr)
            if identity != {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in identity_paths}:
                raise RuntimeError("product source or Fog header changed during GPU gate")
            cls.result = json.loads(run.stdout)
        print(json.dumps(cls.result, sort_keys=True))

    def assert_center_bgra(self, frame: dict, expected: list[int]) -> None:
        self.assertTrue(frame["drew"])
        self.assertEqual(len(frame["centerBGRA"]), 4)
        for channel, (actual, wanted) in enumerate(zip(frame["centerBGRA"], expected)):
            with self.subTest(channel=channel):
                self.assertAlmostEqual(actual, wanted, delta=1)

    def test_first_failed_pose_has_no_publication_or_direct_draw(self) -> None:
        failed = self.result["firstFailure"]
        self.assertFalse(failed["readyBefore"])
        self.assertFalse(failed["readyAfter"])
        self.assertFalse(failed["drew"])
        self.assertEqual(failed["draws"], 0)
        self.assertEqual(failed["litPixels"], 0)
        self.assertTrue(self.result["firstFailureBuffersUntouched"])
        self.assertTrue(self.result["firstFailureHasNoEvidence"])
        recovery = self.result["firstRecovery"]
        self.assertTrue(recovery["readyAfter"])
        self.assertTrue(recovery["drew"])
        self.assertGreater(recovery["litPixels"], 0)

    def test_finite_collapsed_pose_is_published_and_restores_opaque_geometry(self):
        for name in ("collapsed", "collapseRecovery"):
            frame = self.result[name]
            self.assertTrue(frame["readyAfter"] and frame["drew"])
            self.assertEqual(frame["draws"], 1)
        self.assertEqual(self.result["collapsed"]["litPixels"], 0)
        self.assertEqual(self.result["collapseRecovery"]["imageSHA256"],
                         self.result["firstRecovery"]["imageSHA256"])

    def test_later_partial_evaluation_retains_last_complete_pose(self) -> None:
        self.assertTrue(self.result["verifiedPartialWrite"])
        self.assertGreater(self.result["good"]["litPixels"], 0)
        failed = self.result["partialFailure"]
        self.assertTrue(failed["readyAfter"])
        self.assertTrue(failed["drew"])
        self.assertEqual(failed["draws"], 1)
        for field in ("Buffers", "Pixels", "Attachments", "Evidence"):
            with self.subTest(field=field):
                self.assertTrue(self.result[f"partialFailure{field}Unchanged"])

    def test_valid_frame_after_failure_replaces_the_retained_pose(self) -> None:
        recovered = self.result["recovered"]
        self.assertTrue(recovered["readyAfter"])
        self.assertTrue(recovered["drew"])
        self.assertEqual(recovered["draws"], 1)
        self.assertGreater(recovered["litPixels"], 0)
        for field in ("Buffers", "Pixels", "Attachments", "Evidence"):
            with self.subTest(field=field):
                self.assertTrue(self.result[f"recovery{field}Changed"])

    def test_new_command_buffer_requires_its_own_publication(self) -> None:
        for name in ("firstRecovery", "good", "partialFailure", "recovered"):
            with self.subTest(frame=name):
                self.assertFalse(self.result[name]["readyBefore"])
                self.assertTrue(self.result[name]["readyAfter"])
                self.assertFalse(self.result[name]["differentLiveCommandReady"])
                self.assertTrue(self.result[name]["previousCommandReleased"])

    def test_shared_vertex_abi_and_ordinary_quad_keep_opaque_coverage(self) -> None:
        self.assertEqual(self.result["quadVertexStride"], 24)
        self.assertEqual(self.result["quadVertexDefaultCoverage"], 1)
        for name in ("ordinaryQuad", "absentAlpha", "absentAlphaLater"):
            with self.subTest(frame=name):
                self.assert_center_bgra(self.result[name], [16, 32, 48, 64])
        self.assertTrue(self.result["staticBuffersUnchanged"])

    def test_alpha_only_animation_samples_coverage_and_changes_color_once(self) -> None:
        # Color atlas [32,64,96,128] × layer alpha .5 × interpolated bone alpha.
        for name, expected in (
            ("fullAlpha", [16, 32, 48, 64]),
            ("halfAlpha", [8, 16, 24, 32]),
            ("zeroAlpha", [0, 0, 0, 0]),
        ):
            with self.subTest(frame=name):
                self.assert_center_bgra(self.result[name], expected)
                self.assertTrue(self.result[name]["readyAfter"])
        self.assertTrue(self.result["alphaOnlyBuffersChanged"])
        self.assertTrue(self.result["alphaOnlyPositionsUnchanged"])
        self.assertTrue(self.result["alphaOnlyAttachmentsUnchanged"])
        self.assertEqual(self.result["zeroAlpha"]["litPixels"], 0)

    def test_repeated_or_constant_alpha_does_not_republish_vertex_bytes(self) -> None:
        self.assertTrue(self.result["repeatedAlphaBuffersUnchanged"])
        self.assertEqual(self.result["halfAlphaAgain"]["imageSHA256"],
                         self.result["halfAlpha"]["imageSHA256"])
        self.assertTrue(self.result["constantAlphaBuffersUnchanged"])
        self.assert_center_bgra(self.result["inheritedAlphaLater"], [8, 16, 24, 32])

    def test_hidden_clip_restores_default_coverage_and_reactivation_resamples(self) -> None:
        self.assert_center_bgra(self.result["hiddenAlpha"], [16, 32, 48, 64])
        self.assert_center_bgra(self.result["visibleAgain"], [0, 0, 0, 0])
        self.assertEqual(self.result["hiddenAlpha"]["imageSHA256"],
                         self.result["fullAlpha"]["imageSHA256"])
        self.assertEqual(self.result["visibleAgain"]["imageSHA256"],
                         self.result["zeroAlpha"]["imageSHA256"])

    def test_normalized_four_bone_weights_mix_exported_alpha_without_parent_product(self) -> None:
        # Non-unit authored weights [2,2,2,2] normalize to quarters; only bone 1 is opaque.
        self.assert_center_bgra(self.result["mixedWeights"], [4, 8, 12, 16])
        # A full-weight fourth-level child keeps exported .5, not .5 to the fourth power.
        self.assert_center_bgra(self.result["inheritedAlpha"], [8, 16, 24, 32])

    def test_static_clip_blend_weights_alpha_from_opaque_and_clamps_coverage(self) -> None:
        for weight, expected in (
            ("0.0", [16, 32, 48, 64]),
            ("0.5", [8, 16, 24, 32]),
            ("2.0", [0, 0, 0, 0]),
        ):
            with self.subTest(weight=weight):
                self.assert_center_bgra(self.result["blendedAlpha"][weight], expected)

    def test_color_blend_fragment_consumes_puppet_coverage_before_unpremultiplying(self) -> None:
        # Additive mode31 adds premultiplied source RGB to [16,32,48],
        # while preserving the framebuffer alpha of 255.
        for name, expected in (
            ("full", [48, 96, 144, 255]),
            ("half", [32, 64, 96, 255]),
            ("zero", [16, 32, 48, 255]),
        ):
            with self.subTest(frame=name):
                self.assert_center_bgra(self.result["colorBlendFrames"][name], expected)
        self.assert_center_bgra(self.result["ordinaryColorBlend"], [48, 96, 144, 255])
        # Multiply mode2 distinguishes scaling only RGB or only alpha from
        # scaling both before unpremultiplication: base × (1 - alpha + premultRGB).
        for name, expected in (
            ("full", [10, 24, 42, 255]),
            ("half", [13, 28, 45, 255]),
            ("zero", [16, 32, 48, 255]),
        ):
            with self.subTest(multiply_frame=name):
                self.assert_center_bgra(self.result["colorBlendMultiplyFrames"][name], expected)

    def test_one_alpha_contributor_preserves_neutral_peers_and_actual_gpu_coverage(self):
        facts = self.result["multiAlpha"]
        for family, expected in (("allowed", [12, 24, 36, 48]), ("opaque", [16, 32, 48, 64])):
            for row in facts[family]:
                with self.subTest(family=family, order=row["authoredOrder"]):
                    self.assertEqual(row["selection"], {"state": "allowed", "clips": 2})
                    self.assertEqual(row["clipOrder"], row["authoredOrder"])
                    self.assert_center_bgra(row["frame"], expected)
        for row in facts["allowed"]:
            self.assertAlmostEqual(row["attachmentX"], 0.125, places=6)
        self.assertEqual(facts["optional"]["selection"], {"state": "allowed", "clips": 1})
        self.assert_center_bgra(facts["optional"]["frame"], [12, 24, 36, 48])
        self.assert_center_bgra(facts["hidden"], [16, 32, 48, 64])
        self.assert_center_bgra(facts["restored"], [12, 24, 36, 48])

    def test_two_alpha_contributors_and_near_one_peer_remain_rejected(self):
        facts = self.result["multiAlpha"]
        for name in ("twoContributors", "nearOne", "bound"):
            self.assertEqual(facts[name], {"state": "unsupported"})
        self.assertFalse(facts["manual"]["readyAfter"])
        self.assertFalse(facts["manual"]["drew"])
        self.assertEqual(facts["manual"]["draws"], 0)
        self.assertEqual(facts["manual"]["litPixels"], 0)

    def test_shared_hidden_resume_keeps_pose_alpha_and_two_surfaces_on_one_sample(self) -> None:
        self.assert_center_bgra(self.result["sharedHidden"], [16, 32, 48, 64])
        for name in ("sharedResumedA", "sharedResumedB"):
            with self.subTest(surface=name):
                self.assert_center_bgra(self.result[name], [8, 16, 24, 32])
        self.assertAlmostEqual(self.result["sharedResumedPoseX"], 0.125)
        self.assertAlmostEqual(self.result["sharedResumedAttachmentX"], 0.125)
        self.assertTrue(self.result["sharedSurfacePixelsMatch"])
        self.assertTrue(self.result["sharedSurfaceAttachmentsMatch"])


if __name__ == "__main__":
    unittest.main()
