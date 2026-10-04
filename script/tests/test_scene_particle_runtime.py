#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

if __package__:
    from .scene_particle_runtime_author_sample_cases import SceneParticleAuthorSampleCases
    from .scene_particle_runtime_world_space_cases import SceneParticleWorldSpaceCases
else:
    from scene_particle_runtime_author_sample_cases import SceneParticleAuthorSampleCases
    from scene_particle_runtime_world_space_cases import SceneParticleWorldSpaceCases


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift",
    SOURCE_ROOT / "Systems/Properties/SceneDynamicLayerValues.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/ScenePerformanceCounterHub.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneGPUCensus.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneAudioSpectrum.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneMaterialRenderState.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceIndex.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceView.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneStockTextureResolver.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinition.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleInitializer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleAudioResponsePlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleVortex.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRemapValue.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleReduceMovement.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCollisionPlane.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePositionAroundControlPoint.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinitionParser.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinitionParser+Operator.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinitionParser+InstanceOverride.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleWorldSpacePlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleTextureSource.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRefractionPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRefractionBinding.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRefractionTextureLoader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleBuiltInTextureRegistry.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleAssetGraph.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticlePipelineRenderStateCompiler.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleBoids.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulationSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulationDiagnostic.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleControlPointForce.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+ControlPointForce.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+ReduceMovement.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+CollisionPlane.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+PositionAroundControlPoint.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+Boids.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+AudioResponse.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+Vortex.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCapVelocity.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+CapVelocity.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleUnaryOperatorPlans.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePeriodicEmission.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleLayerImageEmissionMap.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleOscillationCache.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleStepSnapshotRecorder.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePlaybackModels.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+ExplicitEmission.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRuntime+PlaybackTransaction.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleTrailPositionHistory.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+Initializer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+Random.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator+InstanceOverride.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleInstanceOverride+Dynamic.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleChildLifecycle.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleChildTemplateSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleTrailRenderPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRopePlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRopeTrailPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleRenderSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleMetalInstanceBuffer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleShaderSource.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleSamplerStateSet.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleMetalPipeline.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleDepthTargetPool.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneFramebufferSnapshot.swift",
    SOURCE_ROOT / "Format/SceneTexDataReader.swift",
    SOURCE_ROOT / "Format/SceneTexContainer.swift",
    SOURCE_ROOT / "Format/SceneBCTextureDecoder.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader+Resample.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneCompressedTextureUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureMipUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureCandidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader+Candidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneSourceUpdateTransaction.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Animation/SceneSpriteAnimation.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneLayerVisibility.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleChildGraphExpansion.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleChildRuntimeModels.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleChildInstanceBuilder.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleChildRuntime.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRuntimeModels.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleLayerRuntime.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRuntime.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRuntime+Support.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePlaybackState.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneDynamicSnapshot.swift",
]


HARNESS_SOURCES = [
    Path(__file__).resolve().parent / "fixtures/SceneParticleRuntimeHarness.swift",
    Path(__file__).resolve().parent / "fixtures/SceneParticleRuntimeLifecycleHarness.swift",
    Path(__file__).resolve().parent / "fixtures/SceneParticleRuntimeChildrenHarness.swift",
    Path(__file__).resolve().parent / "fixtures/SceneParticleRuntimeEventsHarness.swift",
    Path(__file__).resolve().parent / "fixtures/SceneParticleRuntimeControlPointsHarness.swift",
    Path(__file__).resolve().parent / "fixtures/SceneParticleRuntimeWorldFramesHarness.swift",
    Path(__file__).resolve().parent / "fixtures/SceneParticleRuntimeWorldPointerHarness.swift",
    Path(__file__).resolve().parent / "fixtures/SceneParticleRuntimeRopeHarness.swift",
    Path(__file__).resolve().parent / "fixtures/SceneParticleRuntimeRenderingHarness.swift",
    Path(__file__).resolve().parent / "fixtures/SceneParticleRuntimeAuthorSamplesHarness.swift",
]


class SceneParticleRuntimeTests(
    SceneParticleAuthorSampleCases, SceneParticleWorldSpaceCases, unittest.TestCase
):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-particle-runtime-")
        directory = Path(cls.temporary_directory.name)
        cls.binary = directory / "scene-particle-runtime"
        compilation = subprocess.run(
            [
                swiftc,
                *(str(path) for path in SWIFT_SOURCES),
                *(str(path) for path in HARNESS_SOURCES),
                "-framework", "Metal",
                "-framework", "CoreGraphics",
                "-framework", "ImageIO",
                "-module-cache-path", str(directory / "module-cache"),
                "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def run_harness(self, *arguments: str) -> dict[str, object]:
        completed = subprocess.run(
            [str(self.binary), *arguments],
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(completed.stdout)

    def test_playback_control_preserves_runtime_and_clears_history(self) -> None:
        result = self.run_harness("playback-control")
        for name, value in result.items():
            with self.subTest(name=name):
                self.assertTrue(value, name)

    def test_generic_layer_alpha_preserves_root_and_child_instance_alpha(self) -> None:
        result = self.run_harness("layer-alpha-synthetic")
        for field in ["initial", "changed", "hidden", "recovered", "fallback",
                      "startup", "rejected", "restored", "retry"]:
            self.assertEqual(len(result[field]), 2)
            for value in result[field]:
                self.assertAlmostEqual(value, 0.5, places=6)
        self.assertTrue(result["positionsUnchanged"])
        self.assertEqual(result["rootParticles"], 1)
        self.assertEqual(result["childParticles"], 1)


    def test_static_sprite_geometry_uses_mapped_color_extent_in_root_and_child(self) -> None:
        result = self.run_harness("sprite-geometry-synthetic")
        self.assertEqual(result["active"], [1, 2, 3, 4])
        for name in ["raw", "embedded", "atlas", "refract", "child", "child-refract"]:
            with self.subTest(name=name):
                self.assertEqual(result[name]["aspect"], [0.25, 0.25])
                self.assertEqual(result[name]["pixels"], [4, 16, 63, 63])
        self.assertEqual(result["raw"]["textureSize"], [8, 8])
        self.assertEqual(result["raw"]["uvScale"], [0.25, 1])
        self.assertEqual(result["atlas"]["textureSize"], [8, 8])
        self.assertEqual(result["atlas"]["uvScale"], [1, 1])
        for name in ["embedded", "refract", "child", "child-refract"]:
            self.assertEqual(result[name]["textureSize"], [8, 8])
            self.assertEqual(result[name]["uvScale"], [0.25, 1])

    def test_synthetic_rejects_unsupported_roots_and_keeps_diagnostics(self) -> None:
        result = self.run_harness("synthetic")
        self.assertEqual(
            result["activeLayerIDs"], [2, 3, 4, 6, 7, 9, 11, 13, 14, 16, 17, 18, 19]
        )
        self.assertEqual(
            result["batchLayerIDs"],
            [2, 3, 4, 4, 4, 6, 7, 9, 9, 9, 9, 9, 11, 13, 14, 16, 17, 17, 18, 19],
        )
        self.assertGreater(result["activeParticleCount"], 0)
        self.assertGreater(result["childInstanceCount"], 0)
        self.assertTrue(result["childCullStates"])
        self.assertEqual(set(result["childCullStates"]), {"back"})
        self.assertEqual(result["staticChildInstanceCount"], 4)
        self.assertEqual(result["staticChildOrigins"][:3], [[0, 0, 0], [0, 0, 0], [1, 2, 3]])
        self.assertEqual(result["scaledStaticInstance"]["size"], [8])
        self.assertEqual(result["scaledStaticInstance"]["velocity"], [8, 0, 0])
        self.assertTrue(result["staticChildScaleBounded"])
        # 内置纹理尺寸已对齐官方 .tex 的 imageWidth/imageHeight，非方形纹理不再按方形近似。
        self.assertEqual(result["batchTextureSizes"]["6"], [32, 128])
        self.assertEqual(result["batchTextureSizes"]["7"], [64, 64])
        self.assertAlmostEqual(result["trailStretch"], 5)
        self.assertEqual(result["trailVelocity"], [100, 0, 0])
        self.assertEqual(result["defaultTrailStretch"], 2)
        self.assertEqual(result["childTrailStretch"], 2)
        self.assertTrue(result["rendererWorldOrientation"])
        self.assertTrue(result["movementWorldLayerLoaded"])
        self.assertEqual(result["normalCullState"], "back")
        self.assertEqual(result["rawControlPointCopyPositions"], [[22, 0, 0]])
        self.assertFalse(result["adjustedControlPointCopyLoaded"])
        self.assertTrue(result["rawControlPointCopyBounded"])
        self.assertEqual(result["rawControlPointCopyLayerIDs"], [17])
        self.assertFalse(result["hiddenMentioned"])
        self.assertNotIn(10, result["activeLayerIDs"])
        self.assertIn(11, result["activeLayerIDs"])
        diagnostics = result["diagnostics"]
        kinds = {value["kind"] for value in diagnostics}
        self.assertIn("missingTextureReference", kinds)
        self.assertIn("worldSpaceUnsupported", kinds)
        self.assertFalse(any(
            value["kind"] == "trailRendererUnsupported" and value["layer"] in (3, 4, 19)
            for value in diagnostics
        ))
        self.assertNotIn("missingSpriteRenderer", kinds)
        self.assertIn("childSystemsUnsupported", kinds)
        self.assertIn("unsupportedShader", kinds)
        self.assertNotIn(15, result["activeLayerIDs"])
        self.assertNotIn(15, result["batchLayerIDs"])
        self.assertNotIn(20, result["activeLayerIDs"])
        self.assertIn(
            "spritetrail:invalidLength",
            [value["detail"] for value in diagnostics if value["layer"] == 20],
        )
        for path in [
            "particles/angles-child.json",
            "particles/zero-scale-child.json",
            "particles/negative-scale-child.json",
            "particles/nonuniform-scale-child.json",
            "particles/huge-scale-child.json",
            "particles/malformed-scale-child.json",
            "particles/event-origin-child.json",
            "particles/nan-origin-child.json",
        ]:
            self.assertIn(
                f"{path}:unsupportedTransformOrControlPoint",
                result["staticChildUnsupportedDetails"],
            )
        self.assertIn(
            "particles/probability-child.json:unsupportedStaticProbability",
            result["staticChildUnsupportedDetails"],
        )
        self.assertIn(
            "particles/custom-shader.json:unsupportedShader",
            result["staticChildUnsupportedDetails"],
        )
        self.assertIn(
            "particles/adjusted-copy-child.json:rawParentControlPointCopyMalformed",
            [value["detail"] for value in diagnostics if value["detail"] is not None],
        )
        details = [value["detail"] for value in diagnostics if value["detail"] is not None]
        self.assertIn(
            "particles/malformed-copy-child.json:rawParentControlPointCopyMalformed",
            details,
        )
        self.assertIn(
            "particles/raw-copy-child.json:rawParentControlPointCopyOutsideStaticDepthOne",
            details,
        )
        self.assertIn(
            "particles/raw-copy-child.json:rawParentControlPointSourceDynamic",
            details,
        )
        self.assertIn("builtInTextureUnavailable", kinds)

    def test_playback_teardown_terminates_the_same_root_and_child_instance_once(self) -> None:
        result = self.run_harness("lifecycle-synthetic")
        self.assertEqual(result["identity"], result["observationIdentity"])
        self.assertEqual(result["reason"], "scene-switch")
        self.assertEqual(result["active"], result["observed"])
        self.assertEqual(result["active"]["layers"], 1)
        self.assertEqual(result["active"]["rootSystems"], 1)
        self.assertGreater(result["active"]["childSystems"], 0)
        self.assertGreater(result["active"]["rootParticles"], 0)
        self.assertGreater(result["active"]["childParticles"], 0)
        self.assertGreater(result["batchCountBeforeTeardown"], 0)
        self.assertEqual(result["terminated"], {
            "layers": 0,
            "rootSystems": 0,
            "childSystems": 0,
            "rootParticles": 0,
            "childParticles": 0,
        })
        self.assertEqual(result["postTeardownBatchCount"], 0)
        self.assertFalse(result["repeatedObservation"])

    def test_product_playback_discards_unbounded_fixed_step_debt(self) -> None:
        result = self.run_harness("playback-delta-synthetic")
        self.assertAlmostEqual(result["sixtyFPS"], 1 / 60)
        self.assertAlmostEqual(result["thirtyFPS"], 1 / 30)
        self.assertAlmostEqual(result["slowFrame"], 1 / 30)
        self.assertEqual(result["negative"], 0)
        self.assertEqual(result["nonFinite"], 0)

    def test_particle_frame_transaction_restores_simulation_and_random_state(self) -> None:
        result = self.run_harness("frame-transaction-synthetic")
        self.assertTrue(result["sameParticles"])
        self.assertTrue(result["sameTime"])
        self.assertTrue(result["sameRandom"])
        self.assertEqual(result["transientPersistentCount"], 0)
        self.assertGreater(result["transientBeforeConsume"], 0)
        self.assertEqual(
            result["transientAfterConsume"], result["transientBeforeConsume"]
        )
        self.assertEqual(result["transientAfterNextAdvance"], 0)
        self.assertEqual(
            result["transientRestored"], result["transientBeforeConsume"]
        )
        self.assertEqual(result["steadyPersistentCount"], 1)
        self.assertEqual(result["steadyTransientCount"], 0)

    def test_subframe_lifetime_renders_root_and_child_sprite_once_without_resurrection(self) -> None:
        result = self.run_harness("subframe-lifetime-synthetic")
        self.assertGreater(result["rootInstanceCount"], 0)
        self.assertGreater(result["childInstanceCount"], 0)
        self.assertEqual(result["rootPersistentCount"], 0)
        self.assertEqual(result["childPersistentCount"], 0)
        self.assertEqual(result["secondAdvanceInstanceCount"], 0)
        for position in result["rootPositions"]:
            self.assertAlmostEqual(position[0], 32, places=5)
            self.assertAlmostEqual(position[1], 48, places=5)
            self.assertAlmostEqual(position[2], 0, places=5)

    def test_subframe_child_final_sample_survives_retirement_then_never_repeats(self) -> None:
        result = self.run_harness("subframe-child-lifecycle-synthetic")
        self.assertEqual(result["staticCount"], 1)
        self.assertEqual(result["staticPosition"], [7, 9, 0])
        self.assertEqual(result["staticLifecycleSystems"], 0)
        self.assertEqual(result["staticLifecycleParticles"], 0)
        self.assertEqual(result["staticNextCount"], 0)

        self.assertEqual(result["spawnCount"], 1)
        self.assertEqual(result["spawnLifecycleSystems"], 0)
        self.assertEqual(result["spawnLifecycleParticles"], 0)
        self.assertEqual(result["spawnNextCount"], 0)

        self.assertEqual(result["deathCount"], 1)
        self.assertEqual(result["deathLifecycleSystems"], 0)
        self.assertEqual(result["deathLifecycleParticles"], 0)
        self.assertEqual(result["deathNextCount"], 0)

        self.assertEqual(result["depthOneCount"], 1)
        # The depth-one system retired; only the newly queued depth-two owner remains.
        self.assertEqual(result["depthOneRemainingSystems"], 1)
        self.assertEqual(result["depthTwoCount"], 1)
        self.assertEqual(result["depthTwoLifecycleSystems"], 0)
        self.assertEqual(result["depthTwoLifecycleParticles"], 0)
        self.assertEqual(result["depthTwoNextCount"], 0)

        # A retiring maxcount=1 owner must leave admission before the same
        # callback's next event is reconciled. The retired sample still draws
        # once, while lifecycle contains only the newly queued replacement.
        self.assertEqual(result["replacementSecondCount"], 1)
        self.assertEqual(result["replacementSecondSystems"], 1)
        self.assertEqual(result["replacementThirdCount"], 1)
        self.assertEqual(result["replacementThirdSystems"], 1)

        # The same contract applies to nested event children. One live depth-one
        # replacement plus one live depth-two replacement remain after each frame.
        self.assertEqual(result["nestedReplacementThirdCount"], 1)
        self.assertEqual(result["nestedReplacementThirdSystems"], 2)
        self.assertEqual(result["nestedReplacementFourthCount"], 1)
        self.assertEqual(result["nestedReplacementFourthSystems"], 2)

    def test_velocity_random_uses_official_zero_for_each_omitted_endpoint(self) -> None:
        result = self.run_harness("velocity-defaults-synthetic")
        maximum_only = result["maximumOnly"]
        minimum_only = result["minimumOnly"]
        self.assertEqual([maximum_only[0], maximum_only[2]], [0, 0])
        self.assertGreaterEqual(maximum_only[1], 0)
        self.assertLessEqual(maximum_only[1], 100)
        self.assertEqual([minimum_only[0], minimum_only[2]], [0, 0])
        self.assertGreaterEqual(minimum_only[1], -100)
        self.assertLessEqual(minimum_only[1], 0)
        self.assertEqual(result["omitted"], [0, 0, 0])

    def test_child_pointer_control_point_uses_child_local_scale_and_fails_closed_outside(self) -> None:
        result = self.run_harness("child-pointer-control-point-synthetic")
        self.assertEqual(result["outside"], [0, 0, 0])
        self.assertAlmostEqual(result["insideScaled"][0], 2.5, places=5)
        self.assertEqual(result["insideScaled"][1:], [0, 0])
        self.assertEqual(result["dynamicInsideScaled"], [0, 0, 0])
        self.assertEqual(result["emitterMissing"], [])
        self.assertEqual(result["emitterDynamicOnly"], [])
        self.assertEqual(len(result["emitterRecovered"]), 1)
        self.assertAlmostEqual(result["emitterRecovered"][0][0], 10, places=5)
        self.assertAlmostEqual(result["emitterRecovered"][0][1], 0, places=5)
        self.assertAlmostEqual(result["emitterRecovered"][0][2], 0, places=5)
        self.assertEqual(result["rootPointerChildStaticPosition"], [25, 0, 0])
        self.assertEqual(result["pointerDemandLayerIDs"], [18])

    def test_dynamic_control_point_angles_reach_root_and_child_emitters(self) -> None:
        result = self.run_harness("dynamic-control-point-angle-synthetic")
        for velocity in result["dynamic"]:
            self.assertAlmostEqual(velocity[0], 0, places=5)
            self.assertAlmostEqual(velocity[1], 1, places=5)
        for velocity in result["fallback"]:
            self.assertAlmostEqual(velocity[0], 1, places=5)
            self.assertAlmostEqual(velocity[1], 0, places=5)
        self.assertEqual(result["malformed"], result["fallback"])

    def test_runtime_consumes_each_surface_snapshot_then_restores_authored_fallback(self) -> None:
        result = self.run_harness("dynamic-control-point-synthetic")
        self.assertEqual(result["activeLayerIDs"], [90])
        self.assertEqual(
            result["positions"],
            [[11, 21, 31], [-4, 7, 8], [3, 4, 5]],
        )

    def test_child_scaled_float_overflow_keeps_safe_peer_and_recovers(self) -> None:
        result = self.run_harness("child-float-safety")
        self.assertGreater(result["unsafeAssembled"], 0)
        self.assertEqual(result["uploadedCount"], 1)
        self.assertTrue(result["uploadedFinite"])
        self.assertEqual(result["rootCount"], 2)
        self.assertEqual(result["recoveredCount"], 2)
        self.assertEqual(result["rejectedLanes"], 40)
        self.assertTrue(result["emptyDraw"])
        self.assertEqual(result["recoveredBuffer"], 1)

    def test_child_tree_inherits_layer_modifiers_with_flags_prewarm_and_rollback(self) -> None:
        result = self.run_harness("child-instance-override-synthetic")
        for name in ("static", "staticFallback"):
            self.assertEqual(result[name]["count"], 2)
            self.assertAlmostEqual(result[name]["alpha"], 0.4)
            self.assertAlmostEqual(result[name]["size"], 8)
            self.assertEqual(result[name]["color"], [1, 0.25, 1])
            self.assertAlmostEqual(result[name]["lifetime"], 15)
        for name in ("disabled", "disabledFallback"):
            self.assertAlmostEqual(result[name]["size"], 4)
            self.assertEqual(result[name]["color"], [1, 1, 1])
            self.assertAlmostEqual(result[name]["lifetime"], 10)
        for name in ("staticDynamic", "prewarm", "container", "eventspawn", "eventfollow",
                     "eventdeath", "eventspawnNested", "eventfollowNested", "eventdeathNested"):
            with self.subTest(name=name):
                self.assertGreater(result[name]["count"], 0)
                self.assertAlmostEqual(result[name]["alpha"], 0.25)
                self.assertAlmostEqual(result[name]["size"], 12)
                self.assertEqual(result[name]["color"], [0.125, 0.5, 0.03125])
                self.assertAlmostEqual(result[name]["lifetime"], 20)
                self.assertAlmostEqual(result[name]["velocity"], 6)
        self.assertEqual(result["staticDynamic"]["count"], 2)
        self.assertEqual(result["continuous0"]["count"], 6)
        self.assertEqual(result["continuous248"]["count"], 3)
        self.assertAlmostEqual(result["staticDynamic"]["simulationTime"], 0.05)
        self.assertAlmostEqual(result["prewarm"]["simulationTime"], 0.05)
        for name in ("eventspawn", "eventfollow", "eventspawnNested", "eventfollowNested"):
            self.assertAlmostEqual(result[name]["simulationTime"], 0.05 + 5 / 120)
        self.assertAlmostEqual(result["eventdeath"]["simulationTime"], 0.05 + 4 / 120)
        self.assertAlmostEqual(result["eventdeathNested"]["simulationTime"], 0.05 + 2 / 120)
        self.assertEqual(result["disabledDynamic"]["count"], 2)
        self.assertAlmostEqual(result["disabledDynamic"]["alpha"], 0.25)
        self.assertAlmostEqual(result["disabledDynamic"]["size"], 4)
        self.assertAlmostEqual(result["disabledDynamic"]["velocity"], 2)
        self.assertEqual(result["disabledDynamic"]["color"], [0.5, 0.5, 0.5])
        self.assertTrue(result["staticRetryEqual"])
        self.assertTrue(result["disabledRetryEqual"])

    def test_runtime_consumes_dynamic_instance_override_then_restores_authored_values(self) -> None:
        result = self.run_harness("dynamic-instance-override-synthetic")
        self.assertEqual(result["zeroCount"], 0)
        self.assertEqual(result["dynamicCount"], 2)
        self.assertAlmostEqual(result["dynamicAlpha"], 0.25)
        self.assertAlmostEqual(result["dynamicSize"], 12)
        self.assertEqual(result["dynamicColor"], [0.25, 1, 0.0625])
        self.assertEqual(result["fallbackCount"], 3)
        self.assertAlmostEqual(result["fallbackAlpha"], 0)
        self.assertAlmostEqual(result["fallbackSize"], 4)
        self.assertEqual(result["fallbackColor"], [1, 1, 1])

    def test_rope_trail_runtime_builds_multisegment_batches_and_fails_closed(self) -> None:
        result = self.run_harness("rope-trail-synthetic")
        self.assertEqual(result["activeLayerIDs"], [31])
        self.assertGreaterEqual(result["prewarmedInstanceCount"], 4)
        self.assertTrue(result["prewarmedAllSegmentsMoveForward"])
        coarse = result["coarseSignature"]
        fine = result["fineSignature"]
        self.assertEqual(len(coarse), len(fine))
        self.assertGreaterEqual(len(coarse), 4 * 8)
        for coarse_value, fine_value in zip(coarse, fine):
            self.assertAlmostEqual(coarse_value, fine_value, places=5)
        self.assertTrue(result["bufferMatches"])
        self.assertTrue(result["usesPerspective"])
        self.assertTrue(result["sizeIsWorldSpace"])
        self.assertTrue(result["orientationScreen"])
        self.assertFalse(result["mixedRendererLoaded"])
        self.assertFalse(result["malformedRendererLoaded"])
        self.assertFalse(result["objectRendererLoaded"])
        self.assertFalse(result["onlyMalformedRendererLoaded"])
        self.assertTrue(result["missingSpriteRenderer"])
        self.assertIn(
            "trailRendererUnsupported:32:ropetrail:unsupportedProfile",
            result["diagnosticDetails"],
        )
        self.assertIn(
            "trailRendererUnsupported:33:ropetrail:animatedTexture",
            result["diagnosticDetails"],
        )
        self.assertIn(
            "trailRendererUnsupported:34:ropetrail:unsupportedProfile",
            result["diagnosticDetails"],
        )
        self.assertIn(
            "trailRendererUnsupported:35:ropetrail:unsupportedProfile",
            result["diagnosticDetails"],
        )
        self.assertIn(
            "missingSpriteRenderer:36:",
            result["diagnosticDetails"],
        )
        self.assertIn(
            "missingSpriteRenderer:37:",
            result["diagnosticDetails"],
        )
        self.assertFalse(result["emptyRendererLoaded"])
        self.assertIn(
            "missingSpriteRenderer:38:",
            result["diagnosticDetails"],
        )

    def test_rope_runtime_connects_live_particles_and_fails_closed(self) -> None:
        result = self.run_harness("rope-synthetic")
        # Layer 44 carries the renderer world flag (bit0): admitted since the
        # pointer-trail family batch — the spline is affine-invariant, so the
        # local construction renders identically through the layer matrix.
        self.assertEqual(result["activeLayerIDs"], [41, 44, 45, 46, 48])
        self.assertGreaterEqual(result["instanceCount"], 2)
        self.assertTrue(result["bufferMatches"])
        self.assertTrue(result["orientationScreen"])
        self.assertFalse(result["usesPerspective"])
        self.assertTrue(result["allSegmentsNonzero"])
        self.assertTrue(result["uvStartsAtZero"])
        self.assertTrue(result["uvEndsAtOne"])
        self.assertTrue(result["uvContinuous"])
        self.assertTrue(result["usesDisplacement"])
        self.assertTrue(result["subdivisionHalvesDefaultDensity"])
        self.assertAlmostEqual(result["scrollUVStart"], 0.5, places=5)
        self.assertAlmostEqual(result["scrollUVEnd"], 2.5, places=5)
        self.assertGreater(result["childRopeCount"], 0)
        self.assertTrue(result["childRopeUsesSubdivision"])
        self.assertTrue(result["childRopeTranslated"])
        self.assertTrue(result["childRopeUVStartsWithPhase"])
        self.assertIn(
            "ropeRendererUnsupported:42:rope:animatedTexture",
            result["diagnosticDetails"],
        )
        self.assertIn(
            "ropeRendererUnsupported:43:rope:unsupportedProfile",
            result["diagnosticDetails"],
        )
        # Layer 44 (renderer world flag) no longer reports unsupported; its
        # admission is covered by the activeLayerIDs assertion above.
        self.assertIn(
            "ropeRendererUnsupported:47:rope:unsupportedProfile",
            result["diagnosticDetails"],
        )
        self.assertFalse(any(
            "rope-child.json:outsideStrictStaticProfile" in detail
            for detail in result["diagnosticDetails"]
        ))
        self.assertIn(
            "simulationLimitation:48:particles/rope-child.json:"
            "unusedParentControlPointMappings:mappings=2",
            result["diagnosticDetails"],
        )

    def test_stock_tex_reference_loads_through_particle_runtime(self) -> None:
        bundle = REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneStockAssets.bundle"
        result = self.run_harness("stock-synthetic", str(bundle))
        self.assertEqual(result["activeLayerIDs"], [21, 22])
        # debris1.tex 是官方 8 帧 128×128 spritesheet，整张上传为 1024×128 纹理。
        self.assertEqual(result["textureWidth"], 1024)
        self.assertEqual(result["textureHeight"], 128)
        self.assertEqual(result["rootSampling"], {
            "filter": "linear",
            "address": "clampToEdge",
            "clampBorderFallback": False,
        })
        self.assertEqual(result["childTextureWidth"], 512)
        for aspect in result["childFrameAspects"]:
            self.assertAlmostEqual(aspect, 85.334 / 102.4, places=5)
        self.assertEqual(result["wideFrameAspects"], [2, 2])
        self.assertEqual(result["childSampling"], {
            "filter": "linear",
            "address": "repeatWrap",
            "clampBorderFallback": False,
        })
        self.assertEqual(result["refractionSampling"], {
            "color": {
                "filter": "linear",
                "address": "repeatWrap",
                "clampBorderFallback": False,
            },
            "normal": {
                "filter": "linear",
                "address": "clampToEdge",
                "clampBorderFallback": False,
            },
        })
        self.assertEqual(result["diagnosticKinds"], [])

    def test_child_bursts_preserve_authored_density_with_bounded_depth_capacity(self) -> None:
        result = self.run_harness("child-capacity-synthetic")
        self.assertEqual(result["single"], 8500)
        self.assertEqual(result["prewarm"], 8500)
        self.assertEqual(result["smallPeer"], 5536)
        self.assertTrue(result["identityReplay"])
        self.assertEqual(result["static"], 65536)
        self.assertEqual(result["staticCapacity"], [65536, 0])
        for trigger in ["eventspawn", "eventdeath", "eventfollow"]:
            self.assertEqual(result[trigger], 60000, trigger)
            self.assertEqual(result[trigger + "Capacity"], [60000, 0], trigger)
        self.assertEqual(result["nested"], 120000)
        self.assertEqual(result["nestedCapacity"], [60004, 60000])
        for name in ["static", "eventspawn", "eventdeath", "eventfollow"]:
            self.assertIn("aggregateSystemBudget:systems=64:particleCapacity=65536",
                          result[name + "Diagnostics"], name)
        self.assertIn("nestedAggregateSystemBudget:depth=2:systems=64:particleCapacity=65536",
                      result["nestedDiagnostics"])
        for systems, capacity in result["recycleAllocations"]:
            self.assertLessEqual(systems, 64)
            self.assertLessEqual(capacity, 65536)
        self.assertEqual(result["recycle"], result["replay"])
        self.assertGreater(max(result["recycle"]), 8500)
        self.assertGreater(result["recycle"][-1], 0)

    def test_continuous_children_follow_finish_and_obey_aggregate_budget(self) -> None:
        result = self.run_harness("eventfollow-synthetic")
        self.assertEqual(result["childCounts"], [0, 1, 2, 0, 0, 0])
        self.assertEqual(result["childPositions"], [2, 2])
        self.assertEqual(result["childSizes"], [10, 10])
        self.assertEqual(result["boundedCounts"], [0, 1, 1, 1, 0, 0])
        self.assertEqual(len(result["boundedSizes"]), 3)
        for size in result["boundedSizes"]:
            self.assertAlmostEqual(size, 0.8, places=5)
        self.assertEqual(result["budgetCounts"], [0, 64, 128, 192, 256, 320])
        self.assertEqual(result["childUnsupportedLayers"], [])
        self.assertIn(
            "aggregateSystemBudget:systems=64:particleCapacity=65536",
            result["budgetDetails"],
        )
        self.assertIn(
            "particles/audio-child.json:outsideStrictEventProfile",
            result["audioChildDetails"],
        )
        self.assertEqual(set(result["childScaleDetails"]), {
            "particles/follow-child.json:childScaleBounded:scale=2.5,2.5,1.0",
            "particles/bounded-child.json:childScaleBounded:scale=0.2,0.2,0.2",
        })
        self.assertTrue(result["inheritedFollowMatches"])
        self.assertTrue(all(result["inheritedFollowMatches"]))
        self.assertTrue(result["inheritedDeathColors"])
        for color in result["inheritedDeathColors"]:
            for actual, expected in zip(color, [0.2, 0.4, 0.6]):
                self.assertAlmostEqual(actual, expected, places=6)
        self.assertEqual(set(result["eventColorMarkers"]), {
            "particles/inherit-follow-child.json:eventColorOperatorBounded:setcolor",
            "particles/inherit-death-child.json:eventColorInitializerBounded:setcolor",
        })
        self.assertEqual(set(result["invalidEventColorDetails"]), {
            "particles/invalid-inherit-static.json:eventColorInitializerOutsideEventChild",
            "particles/invalid-inherit-death.json:eventColorOperatorOutsideFollowChild",
            "particles/invalid-inherit-follow.json:eventColorOperatorUnsupported",
        })

    def test_simulation_evidence_advances_without_drawables_and_survives_dormancy(self) -> None:
        result = self.run_harness("batch-evidence-synthetic")
        self.assertIn("particle loaded: 2 / 2", result["initial"])
        self.assertIn("particle current nonempty: layers=[]", result["initial"])
        self.assertIn("particle committed nonempty: layers=[]", result["initial"])
        self.assertGreater(result["rejectedCount"], 0)
        self.assertEqual(result["retriedCount"], 0)
        self.assertEqual(result["beforeCommit"], [200])
        self.assertEqual(result["afterDiscard"], [200])
        self.assertIn("particle current nonempty: layers=[200]", result["discarded"])
        self.assertEqual(result["committed"], [200])
        self.assertIn("particle loaded: 2 / 2", result["dormant"])
        self.assertIn("particle current nonempty: layers=[]", result["dormant"])
        self.assertIn("particle committed nonempty: layers=[200]", result["dormant"])

    def test_child_audio_consumer_receives_the_shared_typed_input(self) -> None:
        result = self.run_harness("eventfollow-synthetic")
        self.assertTrue(result["hasAudioConsumer"])
        self.assertEqual(result["activeChildAudioInput"], 1)

    def test_child_audio_observation_is_transactional_and_template_sticky(self) -> None:
        result = self.run_harness("eventfollow-synthetic")
        self.assertEqual(result["rejectedChurnObservationCount"], 1)
        self.assertEqual(result["churnObservationsAfterRestore"], 0)
        self.assertEqual(result["retryChurnObservationCount"], 1)
        self.assertEqual(result["retryChurnObservationPaths"], [
            "particles/audio-churn-child.json",
        ])
        self.assertEqual(result["laterChurnObservationCount"], 0)

    def test_rate_only_event_children_stop_after_bounded_window(self) -> None:
        result = self.run_harness("eventfollow-synthetic")
        counts = result["windowCounts"]
        # rate-only eventspawn child(无 duration)只允许一个有界 burst:
        # 发射窗口 = 自身粒子最大寿命,粒子清空后系统回收,计数必须归零并保持。
        self.assertGreaterEqual(max(counts), 1)
        self.assertEqual(counts[-2:], [0, 0])
        self.assertLess(counts.index(max(counts)), len(counts) - 2)


    def test_instance_buffer_capacity_growth_is_bounded(self) -> None:
        result = self.run_harness("instance-buffer-budget")
        # A system emission within the frozen whole-layer segment-instance
        # budget keeps uploading; an emission beyond it fails closed through
        # the allocation path instead of growing the buffer without bound.
        self.assertTrue(result["withinBudgetAccepted"])
        self.assertTrue(result["overBudgetRejected"])


    def test_synthetic_nested_children_follow_depth_limit_and_budget(self) -> None:
        result = self.run_harness("nested-synthetic")
        self.assertEqual(result["trailCounts"], [0, 1, 2, 3, 0, 0])
        heads = result["headPositions"]
        origins = result["trailOrigins"]
        self.assertEqual(len(heads), 4)
        self.assertEqual(len(origins), 3)
        for index, origin in enumerate(origins):
            self.assertAlmostEqual(origin, heads[index + 1], delta=0.01)
        for index in range(1, len(heads)):
            self.assertAlmostEqual(heads[index] - heads[index - 1], 1.0, delta=0.01)
        self.assertGreater(heads[0], 40)
        self.assertIn(
            "particles/depth-three.json:nestedDepthUnsupported", result["depthDetails"]
        )
        self.assertIn(
            "particles/static-leaf.json:nestedStaticChildUnsupported",
            result["staticDetails"],
        )
        self.assertIn(
            "nestedAggregateSystemBudget:depth=2:systems=64:particleCapacity=65536",
            result["budgetDetails"],
        )
        self.assertEqual(result["budgetTrailCounts"][0], 0)
        self.assertEqual(result["budgetTrailCounts"][1], 64)
        self.assertEqual(result["nestedUnsupportedLayers"], [])


    def test_delayed_child_emitters_survive_until_their_actual_emission_finishes(self) -> None:
        results = self.run_harness("delayed-children")
        for name, value in results.items():
            with self.subTest(profile=name):
                self.assertTrue(value["nonemptyFrames"], "delayed child never reached a draw batch")
                self.assertTrue(value["retryEqual"])
                self.assertEqual(value["systems"][-1], 0)
                if name not in ("multipleBurst", "prewarmBurst"):
                    self.assertGreaterEqual(value["nonemptyFrames"][0], 13)
                    self.assertLessEqual(value["nonemptyFrames"][0], 18)
                if name.startswith("static") or name == "pausedBurst":
                    self.assertEqual(value["systems"][5], 1)
        self.assertGreaterEqual(results["spawnLongFinite"]["nonemptyFrames"][-1], 40)
        self.assertEqual(results["staticBurst"]["nonemptyFrames"][0], 13)
        self.assertEqual(results["multipleBurst"]["nonemptyFrames"][0], 1)
        self.assertIn(13, results["multipleBurst"]["nonemptyFrames"])
        self.assertEqual(results["prewarmBurst"]["nonemptyFrames"][0], 1)
        self.assertEqual(results["pausedBurst"]["nonemptyFrames"], results["staticBurst"]["nonemptyFrames"])

    def test_child_emission_invalid_delay_and_tiny_duration_retire_safely(self) -> None:
        results = self.run_harness("delayed-child-edges")
        for name, value in results.items():
            with self.subTest(profile=name):
                self.assertTrue(value["retryEqual"], "replaying retirement must restore systems and allocator identity")
                self.assertEqual(value["systems"][-1], 0)
                if name in ("negativeDelay", "excessiveDelay", "malformedDelay", "invalidFinite"):
                    self.assertFalse(value["nonemptyFrames"])
                else:
                    self.assertTrue(value["nonemptyFrames"])
        self.assertEqual(results["safePeer"]["nonemptyFrames"][0], 1)
        self.assertEqual(results["tinyBurst"]["nonemptyFrames"][0], 1)
        self.assertEqual(results["tinyDelayedBurst"]["nonemptyFrames"][0], 13)
        self.assertEqual(results["tinyDelayedRate"]["nonemptyFrames"][0], 13)
        self.assertEqual(max(results["tinyDelayedRate"]["counts"]), 10)


if __name__ == "__main__":
    unittest.main()
