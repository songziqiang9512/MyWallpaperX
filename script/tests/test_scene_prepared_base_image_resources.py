#!/usr/bin/env python3
"""Whole preparation owners with controlled loader/compiler/encoder boundaries.

These checks allocate native texture identities but do not compile shaders,
submit draw commands, or qualify rendered output.
"""

from __future__ import annotations

import json
import os
import platform
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
PREPARATION = SCENE / "Runtime/Session/ScenePreparedDeviceResources.swift"
SOURCE_MATERIALS = SCENE / "Runtime/Session/ScenePreparedDeviceResources+SourceMaterials.swift"
RESOLVER = SCENE / "Resources/Textures/SceneTexturePathResolver.swift"
BUILTIN = SCENE / "Compilation/ShaderContract/SceneBuiltinShaderIdentity.swift"
RENDER_STATE = SCENE / "Runtime/Frame/SceneMaterialRenderState.swift"
RENDER_STATE_COMPILATION = SCENE / "Compilation/Material/SceneMaterialRenderState+Compilation.swift"
FIXTURE = Path(__file__).with_name("fixtures") / "ScenePreparedBaseImageResourcesHarness.swift"


@unittest.skipUnless(platform.system() == "Darwin", "requires native Metal textures")
class ScenePreparedBaseImageResourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workspace = tempfile.TemporaryDirectory(prefix="mwx-prepared-base-images-")
        workspace = Path(cls.workspace.name)
        cls.addClassCleanup(cls.workspace.cleanup)
        binary = workspace / "checks"
        source = Path(os.environ.get("MWX_PREPARED_BASE_IMAGE_SOURCE", PREPARATION))
        compile_result = subprocess.run(
            ["xcrun", "swiftc", "-swift-version", "5",
             str(SCENE / "Resources/Assets/SceneResourceIndex.swift"),
             str(SCENE / "../SteamWorkshopStorage/ScenePlaybackSource.swift"), str(SCENE / "Format/ScenePkgReader.swift"),
             str(SCENE / "Resources/Assets/SceneResourceIdentity.swift"), str(SCENE / "Resources/Assets/SceneResourceView+Backing.swift"),
             str(SCENE / "Resources/Assets/SceneResourceView.swift"), str(source), str(SOURCE_MATERIALS), str(RESOLVER),
             str(BUILTIN), str(RENDER_STATE), str(RENDER_STATE_COMPILATION),
             str(SCENE / "Format/SceneJSONValue.swift"),
             str(SCENE / "Resources/Assets/SceneModelResourceIdentity.swift"),
             str(SCENE / "Compilation/Material/ScenePreparedImageMaterialCatalog.swift"),
             str(FIXTURE), "-framework", "Metal", "-module-cache-path",
             str(workspace / "modules"), "-o", str(binary)],
            capture_output=True, text=True, timeout=120,
        )
        if compile_result.returncode:
            raise AssertionError(compile_result.stdout + compile_result.stderr)
        run = subprocess.run([str(binary), str(workspace / "assets")],
                             capture_output=True, text=True, timeout=30)
        if run.returncode:
            raise AssertionError(run.stdout + run.stderr)
        cls.facts = json.loads(run.stdout)
        if cls.facts.get("skip"):
            raise unittest.SkipTest(cls.facts["skip"])
        if output := os.environ.get("MWX_PREPARED_BASE_IMAGE_RESULT"):
            Path(output).write_text(json.dumps(cls.facts, indent=2, sort_keys=True) + "\n")

    def test_static_geometry_uses_natural_metadata_independent_of_dynamic_alias_admission(self) -> None:
        for name in ("staticAuto", "staticAutoMissing", "staticBroad", "staticDeclaredAuto", "staticDeclaredExplicitAuto"):
            self.assertEqual(self.facts[name]["geometry"]["1"], [20, 10])
            self.assertTrue(self.facts[name]["geometryPublished"])
        self.assertEqual(self.facts["staticAuto"]["geometry"]["2"], [20, 10])
        self.assertEqual(self.facts["staticBroad"]["dynamicCount"], 0)

    def test_missing_size_defaults_without_conflating_explicit_zero_or_model_size(self) -> None:
        for name in ("staticDefault", "staticDefaultOmittedPolicy"):
            self.assertEqual(self.facts[name]["geometry"], {"1": [1, 1]})
        for name in ("staticManual", "staticOmittedPolicy", "staticExplicitZero", "staticDeclared",
                     "staticSpecial", "staticSolid", "staticPuppet", "staticMissing", "staticPartialDeclaration",
                     "staticRawNull", "staticRawArray", "staticRawValueNumber", "staticVideoAuto", "staticVideoManualDefault",
                     "staticText", "staticNamedOutput", "staticSolidTexture"):
            self.assertEqual(self.facts[name]["geometry"], {}, name)

    def test_deferred_metadata_does_not_upload_or_mask_later_ready_outcome(self) -> None:
        case = self.facts["staticDeferred"]
        self.assertEqual(case["geometry"], {"1": [20, 10]})
        self.assertEqual(case["loads"], 0)
        self.assertEqual(case["loadedCount"], 0)
        self.assertFalse(case["hasOutcome"])
        self.assertTrue(case["pending"])
        ready = self.facts["deferredReady"]
        self.assertEqual(ready["beforeLoads"], 0)
        self.assertTrue(ready["ready"])
        self.assertTrue(ready["hasOutcome"])
        self.assertTrue(ready["foreignInputRejected"])
        self.assertTrue(ready["cancelRejectsRequest"])

    def test_cancel_and_drain_joins_actual_deferred_worker(self) -> None:
        for name, passed in self.facts["deferredDrain"].items():
            self.assertTrue(passed, name)

    def test_existing_task_metadata_stage_preserves_deferred_cancel_and_early_failure(self) -> None:
        case = self.facts["taskStages"]
        self.assertEqual(case["geometry"], [20, 10])
        self.assertEqual(case["loads"], 0)
        for key in ("deferredStillPending", "cancelledGeometry", "earlyFailure", "pausedBeforeMetadata", "pendingCancellation", "returnedBeforeWorkerRelease"):
            self.assertTrue(case[key], key)

    def test_successful_entries_reuse_the_same_loaded_reference_without_loading(self) -> None:
        case = self.facts["shared"]
        self.assertEqual(case["loads"], 2)
        self.assertEqual(case["loadedCount"], 2)
        self.assertEqual(case["dynamicCount"], 1)
        self.assertTrue(case["sameTexture"])
        self.assertTrue(case["sameCandidate"])
        self.assertEqual(case["size"], [2, 1])
        self.assertEqual(case["naturalSize"], [20, 10])

    def test_layer_override_cannot_publish_as_the_model_default(self) -> None:
        case = self.facts["overrideWithCanonicalPeer"]
        self.assertEqual(case["loads"], 2)
        self.assertEqual(case["dynamicCount"], 1)
        self.assertTrue(case["sameCanonicalTexture"])
        self.assertTrue(case["differentOverrideTexture"])
        self.assertEqual(case["naturalSize"], [20, 10])
        for name in ("overrideOnly", "missingCanonical"):
            with self.subTest(name=name):
                self.assertEqual(self.facts[name]["loads"], 1)
                self.assertEqual(self.facts[name]["dynamicCount"], 0)

    def test_deferred_missing_and_special_providers_are_not_opened(self) -> None:
        for name in ("deferred", "missing", "composition", "solid", "animated"):
            with self.subTest(name=name):
                self.assertEqual(self.facts[name]["loads"], 0)
                self.assertEqual(self.facts[name]["dynamicCount"], 0)
        self.assertTrue(self.facts["deferred"]["pending"])
        # A static Puppet atlas can now be prepared once, but the controlled
        # unavailable mesh backend cannot qualify a new geometry instance.
        self.assertEqual(self.facts["puppet"]["loads"], 1)
        self.assertTrue(self.facts["puppet"]["hasOutcome"])
        self.assertEqual(self.facts["puppet"]["dynamicCount"], 0)

    def test_failed_or_untyped_publication_cannot_escape_into_dynamic_resources(self) -> None:
        for name in ("decodeFailure", "uploadFailure", "noCandidate", "mismatchedCandidate", "loadedAnimation"):
            with self.subTest(name=name):
                self.assertEqual(self.facts[name]["loads"], 1)
                self.assertEqual(self.facts[name]["dynamicCount"], 0)
        case = self.facts["uploadFailure"]
        self.assertFalse(case["hasOutcome"])
        self.assertEqual(case["loadedCount"], 0)
        self.assertEqual(case["failedCount"], 1)
        self.assertEqual(case["evicted"], 1)

    def test_video_products_keep_native_extent_without_static_texture_upload(self) -> None:
        for name in ("staticVideoAuto", "staticVideoManualDefault", "videoExplicit", "videoRenamed"):
            with self.subTest(name=name):
                case = self.facts[name]
                self.assertEqual(case["loads"], 0)
                self.assertFalse(case["hasOutcome"])
                self.assertEqual(case["dynamicCount"], 1)
                self.assertTrue(case["videoProduct"])
                self.assertTrue(case["videoSourceMatchesModel"])
                self.assertTrue(case["hasMaterialRecipe"])
                self.assertEqual(case["size"], [3750, 2250])
                self.assertEqual(case["naturalSize"], [3750, 2250])
                self.assertEqual(case["videoPreparations"], 1)
        self.assertEqual(self.facts["videoRenamed"]["videoPayload"], "renamed-video.tex")
        overridden = self.facts["videoOverrideOnly"]
        self.assertEqual(overridden["loads"], 1)
        self.assertEqual(overridden["dynamicCount"], 0)
        self.assertEqual(overridden["videoPreparations"], 0)
        for name in ("videoOverrideKeepsUnusedStaticDefaultCold", "videoOverrideKeepsUnusedVideoDefaultCold"):
            with self.subTest(unused_default=name):
                self.assertEqual(self.facts[name]["loads"], 0)
                self.assertEqual(self.facts[name]["dynamicCount"], 0)
                self.assertEqual(self.facts[name]["videoPreparations"], 0)
        peer = self.facts["videoOverrideWithCanonicalPeer"]
        self.assertEqual(peer["loads"], 1)
        self.assertTrue(peer["videoProduct"])
        self.assertTrue(peer["videoSourceMatchesModel"])
        self.assertEqual(peer["videoPayload"], "video.tex")
        webm = self.facts["videoWebM"]
        self.assertEqual(webm["loads"], 0)
        self.assertEqual(webm["dynamicCount"], 0)
        self.assertEqual(webm["videoPreparations"], 0)

    def test_models_with_the_same_video_source_share_one_prepared_file(self) -> None:
        case = self.facts["videoSharedModels"]
        self.assertEqual(case["loads"], 0)
        self.assertEqual(case["dynamicCount"], 2)
        self.assertEqual(case["videoProducts"], 2)
        self.assertEqual(case["videoPreparations"], 1)
        self.assertTrue(case["sameSource"])
        self.assertTrue(case["sameFile"])
        self.assertTrue(case["leasesReleased"])
        distinct = self.facts["videoDistinctSources"]
        self.assertEqual(distinct["dynamicCount"], 2)
        self.assertEqual(distinct["videoProducts"], 2)
        self.assertEqual(distinct["videoPreparations"], 2)
        self.assertFalse(distinct["sameSource"])
        self.assertFalse(distinct["sameFile"])
        self.assertTrue(distinct["leasesReleased"])

    def test_video_write_failure_and_cancellation_do_not_publish_failed_templates(self) -> None:
        repeated = self.facts["videoRepeatedFailure"]
        self.assertEqual(repeated["videoPreparations"], 1)
        self.assertEqual(repeated["dynamicCount"], 0)
        self.assertEqual(repeated["failedCount"], 2)
        failed = self.facts["videoWriteFailure"]
        self.assertEqual(failed["loads"], 0)
        self.assertEqual(failed["dynamicCount"], 0)
        self.assertEqual(failed["failedCount"], 1)
        self.assertEqual(failed["videoPreparations"], 1)
        peer = self.facts["videoFailedPeer"]
        self.assertEqual(peer["loads"], 0)
        self.assertEqual(peer["dynamicCount"], 1)
        self.assertEqual(peer["videoProducts"], 1)
        self.assertEqual(peer["videoPreparations"], 2)
        self.assertEqual(peer["failedCount"], 1)
        for key in ("healthyPeer", "failedPeerAbsent", "leasesReleased"):
            self.assertTrue(peer[key], key)
        cancelled = self.facts["videoCancelled"]
        self.assertTrue(cancelled["cancelled"])
        self.assertFalse(cancelled["returnedPreparation"])
        self.assertEqual(cancelled["videoPreparations"], 1)
        self.assertTrue(cancelled["leasesReleased"])
        upload = self.facts["videoSurvivesStaticUploadFailure"]
        self.assertEqual(upload["loads"], 1)
        self.assertEqual(upload["dynamicCount"], 1)
        self.assertEqual(upload["videoProducts"], 1)
        self.assertEqual(upload["videoPreparations"], 1)
        self.assertEqual(upload["evicted"], 1)
        self.assertTrue(upload["healthyPeer"])

    def test_explicit_dynamic_preparation_retains_priority_and_existing_behavior(self) -> None:
        case = self.facts["explicitWithEntry"]
        self.assertEqual(case["loads"], 2)
        self.assertEqual(case["loadedCount"], 2)
        self.assertEqual(case["dynamicCount"], 1)
        self.assertEqual(case["dynamicLoadOrdinal"], 2)
        self.assertEqual(case["entryLoadOrdinal"], 1)
        self.assertEqual(case["naturalSize"], [20, 10])
        self.assertEqual(self.facts["explicitOnly"]["loads"], 1)
        self.assertEqual(self.facts["explicitOnly"]["dynamicCount"], 1)
        self.assertEqual(self.facts["explicitOnly"]["naturalSize"], [20, 10])

    def test_plain_texture_success_cannot_admit_unknown_material_semantics(self) -> None:
        for name in ("customShader", "multiplePasses", "duplicateModelLinks", "secondSlot",
                     "provider", "constant", "userShaderValue", "unknownCombo", "wrongVersion",
                     "additive", "depthEnabled", "alphaWriting"):
            with self.subTest(name=name):
                self.assertEqual(self.facts[name]["loads"], 1)
                self.assertTrue(self.facts[name]["hasOutcome"])
                self.assertEqual(self.facts[name]["dynamicCount"], 0)

    def test_builtin_literal_and_indirect_share_a_published_default_recipe(self) -> None:
        for name in ("litIndirect", "litExplicit"):
            with self.subTest(name=name):
                self.assertEqual(self.facts[name]["dynamicCount"], 1)
                self.assertTrue(self.facts[name]["hasMaterialRecipe"])
                self.assertTrue(self.facts[name]["litRecipe"])
        self.assertTrue(self.facts["shared"]["hasMaterialRecipe"])
        self.assertFalse(self.facts["shared"]["litRecipe"])
        self.assertEqual(self.facts["litPuppet"]["dynamicCount"], 0)
        self.assertEqual(self.facts["unknownBuiltinExplicit"]["dynamicCount"], 0)
        self.assertEqual(self.facts["unknownBuiltinExplicit"]["loads"], 1)
        self.assertEqual(self.facts["sourceExplicit"]["dynamicCount"], 1)
        self.assertFalse(self.facts["sourceExplicit"]["hasMaterialRecipe"])

    def test_complete_variants_without_sampler_zero_use_only_base_image_domain(self) -> None:
        for name in ("sourceInactive", "sourceInactiveNoCandidate", "sourceOtherSamplerOnly"):
            with self.subTest(name=name):
                case = self.facts[name]
                self.assertEqual(case["preparedCount"], 1)
                self.assertEqual(case["outputDomain"], "baseImage")
                self.assertEqual(case["sampledPath"], "")
                self.assertEqual(case["sampledPurpose"], "")
                self.assertEqual(case["warmupCalls"], 1)
                self.assertEqual(case["warmupPlanCount"], 2)
                self.assertEqual(case["reasons"], [])

    def test_active_sampler_zero_requires_one_exact_purpose_across_all_variants(self) -> None:
        case = self.facts["sourceActiveSamePurpose"]
        self.assertEqual(case["preparedCount"], 1)
        self.assertEqual(case["outputDomain"], "sampledAsset")
        self.assertEqual(case["sampledPath"], "materials/renamed-color.png")
        self.assertEqual(case["sampledPurpose"], "straightAlbedo")
        self.assertEqual(case["sharedModelPath"], "models/renamed-source.json")
        self.assertEqual(case["warmupCalls"], 1)
        self.assertEqual(case["warmupPlanCount"], 2)
        self.assertEqual(case["reasons"], [])
        for name in ("sourceActiveUnknownPurpose", "sourceActiveConflictingPurposes",
                     "sourceMixedActiveInactive"):
            with self.subTest(name=name):
                rejected = self.facts[name]
                self.assertEqual(rejected["preparedCount"], 0)
                self.assertEqual(rejected["warmupCalls"], 0)
                self.assertEqual(rejected["reasons"], ["source-domain-variant-dependent"])

    def test_source_domain_selection_preserves_envelope_and_pipeline_rejections(self) -> None:
        reasons = {
            "sourceIncompleteEnvelope": "variant-envelope-incomplete",
            "sourceEmptyEnvelope": "variant-envelope-incomplete",
            "sourceSchemaFailure": "variant-schema",
            "sourcePrecompileFailure": "controlledPrecompileFailure",
            "sourceActiveMissingCandidate": "source-domain-unavailable",
            "sourcePlanFailure": "pipeline-plan-incomplete",
            "sourceWarmupFailure": "pipeline-warmup",
            "sourceWarmupNoReady": "pipeline-warmup",
        }
        for name, reason in reasons.items():
            with self.subTest(name=name):
                case = self.facts[name]
                self.assertEqual(case["preparedCount"], 0)
                self.assertEqual(case["reasons"], [reason])
                self.assertEqual(case["warmupCalls"], int(name in {
                    "sourceWarmupFailure", "sourceWarmupNoReady"}))

    def test_captured_main_requires_exact_live_consumer_and_all_variant_samplers(self) -> None:
        case = self.facts["sourceCapturedMain"]
        self.assertEqual(case["preparedCount"], 1)
        self.assertEqual(case["outputDomain"], "capturedMain")
        self.assertEqual(case["sampledPath"], "")
        self.assertEqual(case["warmupPlanCount"], 2)
        self.assertEqual(case["reasons"], [])
        for name in ("sourceCapturedInactive", "sourceCapturedWrongPurpose", "sourceCapturedOtherSampler",
                     "sourceCapturedWrongConsumer", "sourceCapturedAsset", "sourceCapturedMissing"):
            with self.subTest(name=name):
                rejected = self.facts[name]
                self.assertEqual(rejected["preparedCount"], 0)
                self.assertEqual(rejected["warmupCalls"], 0)
                self.assertEqual(rejected["reasons"], ["framebuffer-source-domain-unproven"])
        failed = self.facts["sourceCapturedWarmupFailure"]
        self.assertEqual(failed["preparedCount"], 0)
        self.assertEqual(failed["reasons"], ["pipeline-warmup"])


if __name__ == "__main__":
    unittest.main()
