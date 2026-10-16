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
RENDER_STATE = SCENE / "Compilation/Material/SceneMaterialRenderState.swift"
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
            ["xcrun", "swiftc", "-swift-version", "5", str(source), str(SOURCE_MATERIALS), str(RESOLVER),
             str(BUILTIN), str(RENDER_STATE), str(SCENE / "Format/SceneJSONValue.swift"),
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
        self.assertTrue(ready["cancelRejectsRequest"])

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


if __name__ == "__main__":
    unittest.main()
