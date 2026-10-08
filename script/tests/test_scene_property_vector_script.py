#!/usr/bin/env python3

"""Generic QuickJS Vec3 owner and previous-current boundary."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

try:
    from .scene_vector_vm_test_support import compile_vector_harness
except ImportError:
    from scene_vector_vm_test_support import compile_vector_harness


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
VM = SCENE / "Systems/Script"
QUICKJS = VM / "QuickJSNG"
SOURCES = [
    SCENE / "Systems/Particles/SceneParticlePlaybackModels.swift",
    SCENE / "Runtime/Frame/SceneStaticModelMaterialBindings.swift",
    SCENE / "Format/SceneJSONValue.swift",
    SCENE / "Format/SceneScriptBindingDefinition.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneDynamicSnapshot.swift",
    SCENE / "Systems/Properties/SceneDynamicLayerValues.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneScriptValueOwnership.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyBindingProgram.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyBindingCompiler+TargetMapping.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyBindingProgramValidator.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyLiveUpdateState.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePuppetAnimationPropertyTarget.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneScriptDynamicProviderHostContract.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserPropertyBindings.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptPropertyInput.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneNamedTextureReference.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneEffectTextureInput.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneNamedTextureDependencyReferenceAnalysis.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneAudioSpectrum.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Animation/SceneTextureAnimationControl.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneMatrix.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneLayerWorldFrameResolver.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneLayerDynamicWorldFrameResolver.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Puppet/ScenePuppetAttachmentFrameSnapshot.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptScalarRuntime.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLocalStorage.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptOwnerLifecycleBridge.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptAnimationHandleBridge.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptPuppetAnimationBridge.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Puppet/ScenePuppetAnimationControl.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Format/ScenePuppetAnimationLayer.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptAudioHost.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptEffectHandleBridge.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLayerMutation.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLayerHandleBridge.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLayerRuntimeDescriptorBridge.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLayerWorldTransformPublication.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLayerWorldTransformProjection.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptMediaEventBridge.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptMediaFrameCoordinator.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptProgramFrameLedger.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptScalarProgram.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptScalarProgram+Projection.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptParticleProjection.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptStringProgram.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptValueOwner+String.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorCandidateCatalog.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorCandidateModels.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorProgramModels.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorProgram.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorProgram+Registrations.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptBooleanVisibilityValidation.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptQuickJSProgramCandidateModels.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptValueRuntime.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptValueOwner+Cursor.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptValueOwner+PuppetBones.swift",
]

FIXTURES = ROOT / "script/tests/fixtures"
HARNESS = "\n".join((FIXTURES / name).read_text(encoding="utf-8") for name in (
    'ScenePropertyVectorSupport.swift',
    'ScenePropertyVectorBindings.swift',
    'ScenePropertyVectorHarness.swift',
    'ScenePropertyVectorPassCases.swift',
    'ScenePropertyVectorPropertyCases.swift',
    'ScenePropertyVectorParticleCases.swift',
    'ScenePropertyVectorLayerCases.swift',
    'ScenePropertyVectorMediaCases.swift',
    'ScenePropertyVectorMaterialCases.swift',
))


class ScenePropertyVectorScriptTests(unittest.TestCase):
    def test_mixed_material_user_input_and_inner_flag_share_the_existing_vm(self) -> None:
        value = self.result()["materialMixed"]
        self.assertEqual(value["ownerCount"], 1, value)
        self.assertEqual(value["publisherCount"], 2, value)
        for key in ("borrowedExactUserTarget", "foreignUserNotBorrowed", "nestedTargetActive",
                    "catalogExclusionKeepsPreparedFact", "validHotChanges", "layerStyleUntouched"):
            self.assertTrue(value[key], (key, value))
        self.assertEqual(value["currentFailures"], 0, value)
        for actual, expected in zip(value["enabledAnimated"], [.3645, .1725, .3645]):
            self.assertAlmostEqual(actual, expected, places=6)

    def test_mixed_material_undefined_uses_current_user_color_and_preserves_transactions(self) -> None:
        value = self.result()["materialMixed"]
        self.assertEqual(value["initialUndefined"], [.729, .345, .729], value)
        self.assertEqual(value["currentUndefined"], [.2, .6, .8], value)
        self.assertEqual(value["currentSource"], "sceneScript", value)
        self.assertTrue(value["invalidTransactionPreserved"], value)

    def test_mixed_material_bad_return_keeps_user_fallback_then_recovers(self) -> None:
        value = self.result()["materialMixed"]
        self.assertTrue(value["badReturnUnpublished"], value)
        self.assertEqual(value["badReturnFallback"], [.2, .6, .8], value)
        self.assertEqual(value["badReturnFallbackSource"], "userProperty", value)
        self.assertEqual(value["recoveredUndefined"], [.2, .6, .8], value)
        self.assertEqual(value["recoveredFailures"], 0, value)
        self.assertTrue(value["badAndRecoveryChangesAccepted"], value)

    @classmethod
    def setUpClass(cls) -> None:
        clang = shutil.which("clang")
        if clang is None:
            raise unittest.SkipTest("clang is required")
        cls.temp_dir = tempfile.TemporaryDirectory(prefix="mwx-scene-vec3-")
        temp = Path(cls.temp_dir.name)
        objects: list[Path] = []
        for source in [
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJS.c", ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSValueHost.c",
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSAnimationHost.c",
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSModuleHost.c",
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSAudioHost.c",
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSMediaEventHost.c",
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSHandleHost.c",
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSLayerHost.c",
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSParticleInstanceHost.c",
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSLayerSnapshotHost.c",
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSStorageHost.c",
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSJobHost.c",
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSTimerHost.c",
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/QuickJSNG/quickjs.c", ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/QuickJSNG/dtoa.c",
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/QuickJSNG/libregexp.c", ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/QuickJSNG/libunicode.c",
        ]:
            output = temp / f"{source.stem}.o"
            subprocess.run([
                clang, "-std=c11", "-O0", "-c", str(source), "-o", str(output),
                "-I", str(VM), "-I", str(QUICKJS),
            ], check=True, capture_output=True, text=True)
            objects.append(output)
        harness = temp / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = temp / "property-vector-script"
        compilation = subprocess.run([
            "xcrun", "swiftc", "-parse-as-library", "-O",
            "-import-objc-header", str(ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJS.h"),
            "-Xcc", f"-I{VM}",
            "-o", str(cls.binary), *map(str, SOURCES), str(harness),
            *map(str, objects), "-Xlinker", "-lm",
        ], capture_output=True, text=True)
        if compilation.returncode != 0:
            raise AssertionError(compilation.stdout + compilation.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp_dir.cleanup()

    def result(self) -> dict[str, object]:
        completed = subprocess.run(
            [str(self.binary)], check=True, capture_output=True, text=True
        )
        return json.loads(completed.stdout)

    def test_particle_normalized_color_uses_vector_owner_and_recovers(self) -> None:
        value = self.result()
        self.assertEqual(value["particleColor"], [0.5, 0.25, 0.75])
        self.assertEqual(value["particleColorRecovered"], [0.5, 0.25, 0.75])
        self.assertTrue(value["particleColorBadRejected"])
        self.assertEqual(value["particleColorCursorOwners"], 1)
        self.assertTrue(value["particleColorMarkerCleared"])
        self.assertEqual(value["particleColorNegativeAdmission"], [True] * 4)

    def test_generic_vec3_executes_script_properties_and_scalar_splat(self) -> None:
        value = self.result()
        self.assertEqual(value["bindings"], 3)
        self.assertEqual(value["origin"], [40, 2100, 0])
        self.assertEqual(value["scale"], [1.25, 1.25, 1.25])
        self.assertEqual(value["targetFilteredValueCount"], 1)
        self.assertFalse(value["targetFilteredOriginPublished"])
        self.assertEqual(value["failures"], 0)
        self.assertEqual(value["mutations"], [
            {"layerID": 10, "effectIndex": 0, "name": "clearHistory"},
        ])
        self.assertEqual(value["layerOrigin"], [4, 5, 6])
        self.assertEqual(value["layerFailures"], 0)

    def test_layer_angle_vm_boundary_uses_degrees_and_publishes_radians(self) -> None:
        value = self.result()
        self.assertEqual(value["angleFailure"], "", value)
        angles = value["angleValue"]
        self.assertAlmostEqual(angles[0], 0, delta=1e-6)
        self.assertAlmostEqual(
            angles[1], 0.15 * 3.141592653589793 / 180, delta=1e-6
        )
        self.assertAlmostEqual(
            angles[2], 3.141592653589793 / 2, delta=1e-6
        )

    def test_layer_angle_vm_publication_reaches_light_consumer_in_radians(self) -> None:
        value = self.result()
        self.assertEqual(value["angleFailure"], "", value)
        self.assertEqual(value["angleSnapshotSource"], "sceneScript", value)
        self.assertEqual(value["angleSnapshotValue"], value["angleValue"], value)
        for consumed, published in zip(value["angleLightValue"], value["angleValue"]):
            self.assertAlmostEqual(consumed, published, delta=1e-6, msg=str({
                key: value[key] for key in ("angleValue", "angleSnapshotValue", "angleLightValue")
            }))

    def test_spot_light_color_is_a_typed_model_light_consumer(self) -> None:
        value = self.result()
        self.assertEqual(value["spotColorBindings"], 1, value)
        self.assertAlmostEqual(value["spotColorValue"][0], 200 / 255)
        self.assertAlmostEqual(value["spotColorValue"][1], 200 / 255)
        self.assertEqual(value["spotColorValue"][2], 1, value)
        self.assertEqual(value["spotColorFailures"], 0, value)

    def test_static_model_material_tint_uses_shared_vec3_vm(self) -> None:
        value = self.result()
        self.assertEqual(value["modelTintBindings"], 1, value)
        self.assertAlmostEqual(value["modelTintValue"][0], 215 / 255)
        self.assertAlmostEqual(value["modelTintValue"][1], 235 / 255)
        self.assertEqual(value["modelTintValue"][2], 1, value)
        self.assertEqual(value["modelTintFailures"], 0, value)

    def test_generic_pass_vec2_uses_typed_scene_script_publication(self) -> None:
        value = self.result()
        self.assertEqual(value["passVectorBindings"], 1)
        self.assertEqual(value["passVectorValue"], [2, 2])
        self.assertEqual(value["passVectorFailures"], 0)
        self.assertTrue(value["passVectorWrongWrapperRejected"])
        self.assertTrue(value["passVectorUserProviderRejected"])

    def test_pass_color_user_input_reaches_one_script_owner_before_update(self) -> None:
        value = self.result()
        self.assertTrue(value["userColorExactInput"])
        self.assertFalse(value["userColorForeignInput"])
        self.assertFalse(value["userColorScalarInput"])
        self.assertEqual(value["userColorInputKey"], "palette")
        self.assertEqual(value["userColorMismatchedKeyCount"], 0)
        self.assertEqual(value["userColorMissingKeyCount"], 0)
        for key in ["userColorIRCount", "userColorOwnerCount", "userColorInputCount"]:
            self.assertEqual(value[key], 1, key)
        for actual, expected in zip(value["userColorFirst"], [0.4, 0.6, 0.8]):
            self.assertAlmostEqual(actual, expected)
        for actual, expected in zip(value["userColorChanged"], [0.2, 0.4, 0.6]):
            self.assertAlmostEqual(actual, expected)
        self.assertTrue(value["userColorInvalidUnpublished"])

    def test_direct_image_color_uses_shared_vec3_vm_and_current_fallback(self) -> None:
        value = self.result()
        self.assertEqual(value["layerColorBindings"], 1)
        self.assertTrue(value["layerColorMediaTargets"])
        self.assertEqual(value["layerColorValue"], [0.7, 0.5, 0.25])
        self.assertEqual(value["layerColorFailures"], 0)
        self.assertEqual(value["layerColorCurrent"], [0.6, 0.4, 0.2])
        self.assertEqual(value["layerColorUndefined"], [0.2, 0.3, 0.4])
        self.assertEqual(value["layerColorUndefinedFailures"], 0)
        self.assertEqual(value["layerColorFirst"], [0.4, 0.6, 0.8])
        self.assertEqual(value["layerColorSecondFailure"], "exception")
        self.assertFalse(value["layerColorSecondPublished"])
        self.assertEqual(value["layerColorThirdFailures"], 0)
        self.assertFalse(value["layerColorThirdPublished"])
        self.assertEqual(value["layerColorFallback"], [0.2, 0.3, 0.4])
        self.assertEqual(value["layerColorFallbackSource"], "authored")
        self.assertEqual(value["layerColorFailurePeer"], [10, 20, 30])
        self.assertEqual(value["layerColorFailurePeerFailures"], 1)

    def test_effectful_text_color_uses_static_script_properties_and_vec3_vm(self) -> None:
        value = self.result()
        self.assertEqual(value["textColorBindings"], 1)
        self.assertEqual(value["textColorValue"], [0.25, 0.5, 0.75])
        self.assertEqual(value["textColorFailures"], 0)

    def test_generic_pass_vec3_executes_wecolor_into_typed_publication(self) -> None:
        value = self.result()
        self.assertEqual(value["passColorBindings"], 1)
        self.assertEqual(value["passColorValue"], [0, 1, 1])
        self.assertEqual(value["passColorFailures"], 0)

    def test_callback_only_scalar_publishes_its_bound_current_property(self) -> None:
        value = self.result()
        self.assertEqual(value["currentPropertyFirst"], 1, value)
        self.assertTrue(value["currentPropertyStableSkipped"], value)
        self.assertEqual(value["currentPropertyChanged"], 3, value)
        self.assertEqual(value["currentPropertyTimer"], 9, value)
        self.assertTrue(value["currentPropertySettledSkipped"], value)
        self.assertTrue(value["currentPropertyLiveConsumer"], value)
        self.assertEqual(value["invalidCurrentPropertyFailure"], "bad-return", value)
        self.assertFalse(value["invalidCurrentPropertyPublished"], value)
        # Retry contract: a data-shaped bad-return fails the frame but keeps
        # the consumer's live-property target active for later frames.
        self.assertFalse(value["invalidCurrentPropertyConsumerDisabled"], value)

    def test_generic_pass_scalar_executes_static_properties_and_audio(self) -> None:
        value = self.result()
        self.assertEqual(value["passAudioBindings"], 1)
        self.assertTrue(value["passAudioDemand"])
        self.assertEqual(value["passAudioValue"], 1.5)
        self.assertEqual(value["passAudioFailures"], 0)
        self.assertTrue(value["passAudioWrongWrapperRejected"])
        self.assertTrue(value["passAudioUserProviderRejected"])

    def test_bad_return_is_local_and_duplicate_target_is_rejected(self) -> None:
        value = self.result()
        self.assertEqual(value["badReturn"], "bad-return")
        self.assertFalse(value["badPublished"])
        self.assertTrue(value["duplicateRejected"])
        self.assertTrue(value["wrongOwnerRejected"])
        self.assertEqual(value["animationBindings"], 1)
        self.assertEqual(value["animationCommands"], ["play"])
        self.assertTrue(value["animationWithoutTimelineRejected"])
        self.assertEqual(value["alphaAnimationBindings"], 1)
        self.assertEqual(value["alphaAnimationValue"], 0.75)
        self.assertEqual(value["alphaAnimationCommands"], ["play"])
        self.assertEqual(value["genericAlphaBindings"], 1)
        self.assertAlmostEqual(value["genericAlphaValue"], 0.75 + 1 / 60)
        self.assertEqual(value["genericPropertyAlphaBindings"], 1)
        self.assertEqual(value["genericPropertyAlphaValue"], 1.0)
        self.assertTrue(value["genericAlphaWrongWrapperRejected"])
        self.assertEqual(value["mediaAnimationCommands"], ["stop", "play"])
        self.assertTrue(value["mediaGenerationDeduplicated"])
        self.assertEqual(value["passTimelineBindings"], 1)
        self.assertTrue(value["passTimelineKeepsTimelineValueOwner"])
        self.assertEqual(value["passTimelineCommands"], ["stop", "play"])
        self.assertTrue(value["passTimelineGenerationDeduplicated"])
        retained = value["passTimelineAfterRejection"]
        self.assertEqual(retained["firstFailures"], 0, retained)
        self.assertEqual(retained["firstCommands"], ["stop", "play"], retained)
        self.assertEqual(retained["duplicateCommands"], [], retained)
        self.assertEqual(retained["nextFailures"], 0, retained)
        self.assertEqual(retained["nextCommands"], ["stop", "play"], retained)
        self.assertTrue(value["passTimelineThrowUnpublished"])
        self.assertTrue(value["passTimelineWithoutTargetRejected"])
        self.assertTrue(value["passTimelineWrongWrapperRejected"])
        self.assertTrue(value["passTimelinePropertiesRejected"])
        self.assertEqual(value["playbackBindings"], 1)
        self.assertEqual(value["playbackPlaying"], 0.5)
        self.assertEqual(value["playbackNextFrame"], 1.0)
        self.assertEqual(value["playbackStopped"], 0.5)
        self.assertEqual(value["playbackFailures"], 0)

    def test_layer_alpha_time_owner_republishes_each_frame_from_supplied_clocks(self) -> None:
        value = self.result()
        first = value["genericAlphaValue"]
        second = value["alphaTimeOwnerNextFrame"]
        # alpha owner 以 engine.frametime 步进的 update 每帧产出严格递增
        # scalar：第二轮把首轮发布值作为当前值喂回，输出仍继续上台阶。
        self.assertGreater(second, first, value)
        # 第二轮 evaluate 不复用首轮返回值（无 publication 缓存）：增量仍
        # 来自已供应时钟的一步，而不是记忆中的首轮结果。
        self.assertAlmostEqual(second, first + 1.0 / 60.0)

    def test_media_properties_event_updates_generic_string_owner(self) -> None:
        value = self.result()
        self.assertEqual(value["stringBindings"], 1)
        self.assertEqual(value["stringValue"], "春日歌 / Artist / Live / Album / Album Artist / Rock,Pop / music")
        self.assertEqual(value["stringFailures"], 0)
        self.assertTrue(value["stringGenerationDeduplicated"])

    def test_text_wrapper_admission_follows_the_shared_host_contract(self) -> None:
        admission = self.result()["textWrapperAdmission"]
        for admitted in (
            "script+value",
            "script+scriptproperties+value",
            "script+user+value",
            "script+scriptproperties+user+value",
        ):
            self.assertTrue(
                admission[admitted],
                f"text wrapper {admitted} must own a text content target",
            )
        for rejected in ("animation+script+value", "script+scriptproperties"):
            self.assertFalse(
                admission[rejected],
                f"text wrapper {rejected} must stay unowned",
            )

    def test_media_events_follow_authored_family_and_callback_order(self) -> None:
        value = self.result()
        first = "sIsPsRsHsLsUvIvPvRvHvLvUtItPtRtHtLtU"
        self.assertEqual(value["orderedMediaTrace"], first)
        self.assertEqual(value["orderedMediaDuplicateTrace"], first + "sUvUtU")
        self.assertEqual(value["orderedMediaFailures"], 0)
        self.assertEqual(value["orderedLayerMutationOrder"], [10, 42, 77])
        self.assertEqual(value["orderedLayerMutationFields"], [True, True, True])
        self.assertEqual(value["orderedDuplicateLayerMutations"], 0)

    def test_prepared_media_dispatch_keeps_generation_inputs_and_lifecycle_live(self) -> None:
        value = self.result()
        self.assertEqual(
            value["orderedNextGenerationTrace"],
            "sIsPsRsHsLsUvIvPvRvHvLvUtItPtRtHtLtU"
            + "sUvUtU" + "sPsHsLsUvPvHvLvUtPtHtLtU",
        )
        self.assertEqual(value["orderedNextGenerationVector"], [40, 50, 60])
        self.assertEqual(value["orderedNextGenerationScalar"], 0.3)
        self.assertEqual(value["orderedNextGenerationLayerMutations"], 0)
        self.assertEqual(value["orderedInvalidatedValues"], 0)
        self.assertEqual(value["orderedInvalidatedFailures"], 3)
        self.assertEqual(value["orderedInvalidatedLayerMutations"], 0)

    def test_audio_buffers_update_generic_vec3_owner(self) -> None:
        value = self.result()
        self.assertEqual(value["audioScaleBindings"], 1)
        self.assertTrue(value["audioScaleDemand"])
        self.assertEqual(value["audioScaleValue"], [2.25, 2.25, 2.25])
        self.assertEqual(value["audioScaleFailures"], 0)

    def test_all_particle_scalar_scripts_parse_and_publish_typed_values(self) -> None:
        value = self.result()
        self.assertEqual(value["particleScalarParsed"], 7)
        self.assertEqual(value["particleScalarBindings"], 7)
        self.assertEqual(value["particleScalarFailures"], 0)
        self.assertEqual(value["particleScalarValues"], {
            "alpha": 4, "size": 4, "lifetime": 4, "rate": 4,
            "speed": 4, "count": 500, "brightness": 4,
        })

    def test_particle_scalar_admission_is_field_exact_and_failure_local(self) -> None:
        value = self.result()
        self.assertEqual(value["particleScalarBadValues"], 6)
        self.assertEqual(value["particleScalarBadFailures"], 1)
        self.assertTrue(value["particleScalarBadSizeAbsent"])
        self.assertEqual(value["particleScalarRecovered"], 7)
        self.assertTrue(value["particleScalarMarkersCleared"])
        self.assertTrue(value["particleScalarHiddenPreserved"])
        self.assertTrue(value["particleScalarPartialExact"])
        self.assertEqual(value["particleScalarDuplicateCount"], 6)
        self.assertEqual(value["particleScalarConflictCount"], 5)

    def test_audio_buffers_update_generic_particle_rate_owner(self) -> None:
        value = self.result()
        self.assertEqual(value["particleAudioBindings"], 1)
        self.assertTrue(value["particleAudioDemand"])
        self.assertEqual(value["particleAudioValue"], 3.0)
        self.assertEqual(value["particleAudioFailures"], 0)
        self.assertEqual(value["particlePropertyFreeBindings"], 1)
        self.assertEqual(value["particleNullUserBindings"], 1)
        self.assertEqual(value["particleNullUserParseFailures"], 0)
        self.assertTrue(value["particleConflictingUserRejected"])
        self.assertTrue(value["particleUnknownWrapperRejected"])
        self.assertTrue(value["particleAdmittedVisible"])
        self.assertTrue(value["particleAdmittedRateScriptRemoved"])
        self.assertTrue(value["particleAdmittedSiblingPreserved"])
        self.assertTrue(value["particleStaticFallbackVisible"])
        self.assertTrue(value["particleStaticRatePreserved"])
        self.assertTrue(value["particleStaticSiblingPreserved"])

    def test_scalar_script_properties_follow_live_typed_user_input(self) -> None:
        value = self.result()
        self.assertEqual(value["dynamicScalarBindings"], 1)
        self.assertAlmostEqual(value["dynamicScalarFirst"], -0.2)
        self.assertAlmostEqual(value["dynamicScalarStable"], -0.2)
        self.assertAlmostEqual(value["dynamicScalarChanged"], -0.35)
        self.assertEqual(value["dynamicScalarWrongTypeFailure"], "invalid-argument")
        self.assertFalse(value["dynamicScalarWrongTypePublished"])
        self.assertAlmostEqual(value["dynamicScalarRecovered"], -0.4)
        self.assertEqual(value["dynamicScalarFallback"], -50)
        self.assertTrue(value["dynamicScalarMalformedRejected"])
        self.assertTrue(value["dynamicScalarLiveTarget"])
        self.assertTrue(value["dynamicVectorLiveTarget"])
        self.assertTrue(value["nullOuterUserScalarAdmitted"])
        self.assertTrue(value["failingDynamicScalarInitiallyActive"])
        self.assertTrue(value["failingDynamicScalarBecameUnavailable"])
        self.assertTrue(value["failingDynamicVectorInitiallyActive"])
        self.assertTrue(value["failingDynamicVectorBecameUnavailable"])
        self.assertTrue(value["disabledScalarLiveUpdateRejected"])
        self.assertTrue(value["disabledScalarLiveUpdateWasAtomic"])
        self.assertTrue(value["disabledVectorLiveUpdateRejected"])
        self.assertTrue(value["disabledVectorLiveUpdateWasAtomic"])
        self.assertTrue(value["activeVectorSiblingAccepted"])

    def test_apply_user_properties_uses_initial_full_then_changed_delta(self) -> None:
        value = self.result()
        self.assertEqual(value["propertyEventFirst"], [5, 2250, 0])
        self.assertEqual(value["propertyEventStable"], [5, 2250, 0])
        self.assertEqual(value["propertyEventChanged"], [7, 2250, 0])
        self.assertEqual(value["propertyEventFailures"], 0)
        self.assertTrue(value["propertyRevisionFirstDelta"])
        self.assertTrue(value["propertyRevisionStableSkipped"])
        self.assertTrue(value["propertyRevisionChangedDelta"])


SEED_HARNESS = (FIXTURES / "ScenePropertyVectorSeedHarness.swift").read_text(encoding="utf-8")


class SceneEffectVisibilitySeedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-effect-visibility-seed-"
        )
        try:
            cls.binary = compile_vector_harness(
                Path(cls.temporary_directory.name),
                SEED_HARNESS,
                "scene-effect-visibility-seed",
            )
        except Exception:
            cls.temporary_directory.cleanup()
            raise

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_prepared_snapshot_seed_reads_the_load_prepared_state(self) -> None:
        completed = subprocess.run(
            [str(self.binary)], check=True, capture_output=True, text=True
        )
        result = json.loads(completed.stdout)
        self.assertEqual(result["failures"], 0)
        self.assertTrue(result["baselineAdmitted"])
        self.assertTrue(result["preparedAdmitted"])
        self.assertTrue(result["preparedSeedHidden"])


if __name__ == "__main__":
    unittest.main()
