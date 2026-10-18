#!/usr/bin/env python3

"""End-to-end R3 finalization from authored contract to immutable Program."""

from __future__ import annotations

from script.tests.source_family import read_source_family
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
STOCK_MATERIAL_ROOT = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/materials"
)
VISUAL_PASSTHROUGH_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough.swift"
)
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import (  # noqa: E402
    scene_swift_sources,
    scene_swift_sources_by_basename,
)


MATERIAL_PROGRAM_SOURCES = scene_swift_sources_by_basename(
    "resolved_material_program_all"
)


FINALIZER_SOURCE = next(
    source
    for source in scene_swift_sources("resolved_material_frame_finalization")
    if source.name == "SceneResolvedMaterialProgramFinalizer.swift"
)
VARIANT_CACHE_SOURCE = next(
    source
    for source in scene_swift_sources("resolved_material_frame_finalization")
    if source.name == "SceneResolvedMaterialExecutionCapabilityVariant.swift"
)
RUNTIME_CATALOG_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialRuntimeCatalog.swift"
)
TEMPLATE_COMPILER_SOURCE = MATERIAL_PROGRAM_SOURCES[
    "SceneResolvedMaterialTemplateCompiler.swift"
]
SHADER_SCHEMA_SOURCE = MATERIAL_PROGRAM_SOURCES[
    "SceneResolvedMaterialShaderSchema.swift"
]
SHADER_REACHABILITY_SOURCE = MATERIAL_PROGRAM_SOURCES[
    "SceneResolvedMaterialShaderSchema+Reachability.swift"
]
VARIANT_COMPILATION_SOURCE = MATERIAL_PROGRAM_SOURCES[
    "SceneResolvedMaterialExecutionCapabilityVariant+Compilation.swift"
]


SWIFT_SOURCES = [
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift",
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "Compilation/ShaderContract/SceneShaderContractLoader.swift",
    SCENE_ROOT / "Compilation/ShaderContract/SceneBuiltinShaderIdentity.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneDynamicSnapshot.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderContract/SceneShaderSourceGraph.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderContract/SceneShaderLegacyAnnotationJSON.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderContract/SceneShaderContract.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneMaterialRenderState.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneMaterialRenderState+Compilation.swift",
    *scene_swift_sources("authored_shader_frontend_implementation"),
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Bindings/SceneAuthoredShaderFrameInputs.swift",
    *scene_swift_sources("authored_shader_preparation_implementation"),
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader+Resample.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneCompressedTextureUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureMipUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureCandidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneStockTextureSemanticRegistry.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSlotBinding.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureProviderPublication.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneNamedTextureReference.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneFrameTextureRegistry.swift",
    *scene_swift_sources("resolved_material_frame_finalization"),
]

# Preparation/frame source groups overlap; each Swift file is one compiler input.
SWIFT_SOURCES = list(dict.fromkeys(SWIFT_SOURCES))

FIXTURE_ROOT = REPOSITORY_ROOT / "script/tests/fixtures"
SUPPORT_SOURCE = FIXTURE_ROOT / "SceneResolvedMaterialFinalizerSupport.swift"
SHARED_FIXTURE_SOURCES = [
    SUPPORT_SOURCE,
    FIXTURE_ROOT / "SceneResolvedMaterialFinalizerShaderFixtures.swift",
    FIXTURE_ROOT / "SceneResolvedMaterialFinalizerFrameFixtures.swift",
    FIXTURE_ROOT / "SceneResolvedMaterialFinalizerColorEligibilityCases.swift",
    FIXTURE_ROOT / "SceneResolvedMaterialFinalizerTextureResolutionCases.swift",
    FIXTURE_ROOT / "SceneResolvedMaterialFinalizerGraphInputCases.swift",
    FIXTURE_ROOT / "SceneResolvedMaterialFinalizerPreparationCases.swift",
    FIXTURE_ROOT / "SceneResolvedMaterialFinalizerFramebufferCases.swift",
    FIXTURE_ROOT / "SceneResolvedMaterialFinalizerDynamicUniformCases.swift",
    FIXTURE_ROOT / "SceneResolvedMaterialFinalizerProviderResourceCases.swift",
    FIXTURE_ROOT / "SceneResolvedMaterialFinalizerFailureCases.swift",
    FIXTURE_ROOT / "SceneResolvedMaterialPreparedVariantCases.swift",
    FIXTURE_ROOT / "SceneResolvedMaterialFinalizerSharedState.swift",
]
FIXTURE_SOURCES = [
    *SHARED_FIXTURE_SOURCES,
    FIXTURE_ROOT / "SceneResolvedMaterialFinalizerHarness.swift",
]


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneResolvedMaterialProgramFinalizerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-resolved-material-finalizer-"
        )
        root = Path(cls.temporary_directory.name)
        binary = root / "resolved-material-finalizer-test"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        shader_cache = root / "shader-cache"
        shader_cache.mkdir()
        environment["MWX_SCENE_GENERIC_SHADER_CACHE"] = str(shader_cache)
        # This standalone harness owns Finalizer/resource provenance and has no
        # signed compiler bundle. Exercise the explicit bounded rollback; the
        # generic owner and its failure boundary have separate product gates.
        environment["MWX_SCENE_GENERIC_SHADER_ROUTE"] = "disable-generic"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES),
                *(str(path) for path in FIXTURE_SOURCES),
                "-framework",
                "Metal",
                "-framework",
                "CoreGraphics",
                "-framework",
                "ImageIO",
                "-module-cache-path",
                str(root / "module-cache"),
                "-o",
                str(binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr or completed.stdout)
        cls.result = json.loads(completed.stdout)
        cls.variant_cache_record_count = sum(
            1 for _ in shader_cache.glob("SceneVariantAnalysis-*/*.json")
        )
        warmed = subprocess.run(
            [str(binary)], cwd=REPOSITORY_ROOT, env=environment,
            capture_output=True, text=True, check=True,
        )
        cls.warmed_result = json.loads(warmed.stdout)
        if not cls.result["metalAvailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    def test_rt_shader_defaults_share_typed_same_layer_ingress(self) -> None:
        results = self.result["rtDefaultAdmission"]
        for suffix in ("", "_a", "_b"):
            self.assertEqual(results["_rt_imageLayerComposite_42" + suffix], "ready:1:fact:true", results)
            self.assertEqual(results["_rt_imageLayerComposite_42" + suffix + ":binding"], "graph-ingress", results)
        for token in ("_rt_imageLayerComposite_43_a", "_rt_imagelayercomposite_42_a", "_rt_unknown", "_rt_imageLayerComposite_42_c", "_rt_imageLayerComposite_-1", "_RT_imageLayerComposite_42_a"):
            self.assertTrue(results[token].startswith("rejected:"), results)
        for token in ("_rt_imageLayerComposite_42", "_rt_imageLayerComposite_42_a", "_rt_imageLayerComposite_42_b"):
            self.assertEqual(results[token + ":spelling"], token)
            self.assertEqual(results[token + ":persistent"], "same")
            self.assertEqual(results[token + ":override"], "success", results)
            self.assertEqual(results[token + ":straight"], "success", results)
            self.assertEqual(results[token + ":straightPurpose"], "straight-albedo", results)
            self.assertEqual(results[token + ":straightIngress"], "true", results)
            for failure in ("missing", "stale", "purpose"):
                self.assertNotEqual(results[token + ":" + failure], "success", results)

    def test_absent_authored_asset_reaches_same_layer_default(self) -> None:
        results = self.result["rtDefaultAdmission"]
        self.assertEqual(results["absent-candidate"], "success", results)
        self.assertEqual(results["absent-candidate:identity"], "graph", results)
        self.assertEqual(results["absent-candidate:purpose"], "premultiplied-color", results)
        self.assertEqual(results["ready-candidate"], "success", results)
        self.assertEqual(results["ready-candidate:identity"], "asset", results)
        self.assertEqual(results["ready-candidate:purpose"], "straight-albedo", results)
        for label in ("pending-candidate", "unavailable-candidate"):
            self.assertNotEqual(results[label], "success", results)

    def test_rt_defaults_do_not_manufacture_authored_presence_or_reject_dead_sampler(self) -> None:
        results = self.result["rtDefaultAdmission"]
        self.assertEqual(results["dead-unknown"], "success", results)
        self.assertNotEqual(results["active-presence"], "success", results)

    def test_full_frame_default_keeps_case_insensitive_provider_identity(self) -> None:
        results = self.result["rtDefaultAdmission"]
        for token in ("_rt_FullFrameBuffer", "_RT_FULLFRAMEBUFFER", "_rt_fullframebuffer"):
            self.assertEqual(results[token], "success", results)
            self.assertEqual(results[token + ":identity"], "background", results)

    def test_persistent_cache_preserves_cold_run_results(self) -> None:
        self.assertGreater(self.variant_cache_record_count, 0)
        self.assertEqual(self.warmed_result, self.result)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_real_preparation_frontend_uniforms_and_derivation_produce_program(self) -> None:
        self.assertEqual(
            [name for name, passed in self.result["positive"].items() if not passed],
            [],
            self.result,
        )
        self.assertEqual(
            self.result["activeDefaultCache"],
            {
                "launchMasks": [1],
                "failure": "success",
                "cached": 1,
                "prepared": 1,
                "frontend": 1,
                "capacity": 0,
            },
            self.result,
        )

    def test_only_texture_projection_consumers_require_an_invertible_matrix(
        self,
    ) -> None:
        self.assertEqual(
            self.result["effectProjectionRequirements"],
            {
                "modelOnly": "unrequired",
                "textureForward": "required",
                "textureInverse": "required",
            },
            self.result,
        )

    def test_mapped_texture_resolution_is_independent_of_candidate_translation(
        self,
    ) -> None:
        self.assertEqual(
            [
                name
                for name, passed in self.result[
                    "mappedTextureResolution"
                ].items()
                if not passed
            ],
            [],
            self.result["mappedTextureResolution"],
        )
    def test_neutral_missing_texture_resolution_is_structural_and_fail_closed(
        self,
    ) -> None:
        self.assertEqual(
            [
                name
                for name, passed in self.result[
                    "neutralTextureResolutionAnalyzer"
                ].items()
                if not passed
            ],
            [],
            self.result["neutralTextureResolutionAnalyzer"],
        )
        self.assertEqual(
            self.result["neutralTextureResolutionFailures"],
            {
                "resolutionCandidate": "uniform/staticUniformBindingInvalid",
                "mappedNotIdentity": "success",
                "uvNotIdentity": "success",
                "coordinatePending": "texture/resourceSnapshotUnresolved",
                "coordinateWrongPurpose": "texture/textureMetadataIncomplete",
                "wrongComponent": "uniform/staticUniformBindingInvalid",
                "downstreamComputation": "success",
                "unsampledDefaultResolution": "success",
            },
        )

    def test_alpha_attenuation_eligibility_cross_checks_schema_and_graph_identity(
        self,
    ) -> None:
        self.assertEqual(
            self.result["attenuationEligibilityCases"],
            {
                "maskOffPreparedVariant": True,
                "maskOnPreparedVariant": True,
                "wrongSamplerModeRejected": True,
                "auxiliaryGraphInputRejected": True,
                "extraActiveSamplerRejected": True,
                "priorEffectOutputAccepted": True,
                "internalFramebufferRejected": True,
                "differentEffectOutputRejected": True,
                "fallbackCandidateRejected": True,
            },
            self.result,
        )

    def test_color_blend_eligibility_uses_prepared_source_schema_and_graph_identity(
        self,
    ) -> None:
        self.assertEqual(
            self.result["colorBlendEligibilityCases"],
            {
                "unmaskedSourceFact": True,
                "unmaskedTransferProven": True,
                "unmaskedSamplerSetExact": True,
                "modeZeroSourceFact": True,
                "modeZeroTransferProven": True,
                "modeZeroSamplerSetExact": True,
                "unmaskedPreparedVariant": True,
                "stockMaskMultiplyPreparedVariant": True,
                "legacyMaskOverridePreparedVariant": True,
                "modeZeroOpaquePreparedVariant": True,
                "wrongSamplerModeRejected": True,
                "auxiliaryGraphInputRejected": True,
                "extraActiveSamplerRejected": True,
                "priorEffectOutputAccepted": True,
                "internalFramebufferRejected": True,
                "differentEffectOutputRejected": True,
                "fallbackCandidateRejected": True,
            },
            self.result,
        )

    def test_shader_preparation_requires_typed_source_graph(self) -> None:
        self.assertEqual(
            self.result["shaderPreparationBoundary"]["missingSourceGraph"],
            "shader-preprocessor/shader-source-graph-missing/0",
        )
        product_sources = {
            path: path.read_text(encoding="utf-8")
            for path in SCENE_ROOT.rglob("*.swift")
        }
        for retired_token in (
            "fallbackGraph(",
            ".legacyContract",
            "case legacyContract",
        ):
            offenders = [
                str(path.relative_to(REPOSITORY_ROOT))
                for path, source in product_sources.items()
                if retired_token in source
            ]
            self.assertEqual(offenders, [], retired_token)

    def test_semantic_and_exact_identity_boundaries(self) -> None:
        self.assertEqual(
            [name for name, passed in self.result["identity"].items() if not passed],
            [],
            self.result,
        )

    def test_prepared_variant_preserves_current_serial_frame_facts(self) -> None:
        cases = self.result["preparedVariantFrames"]
        self.assertEqual([name for name, passed in cases.items() if not passed], [], cases)

    def test_dormant_unresolved_material_alias_is_a_typed_graph_input_fact(
        self,
    ) -> None:
        self.assertEqual(
            self.result["dormantGraphInputFacts"],
            {
                "defaultBoundaryPreservesGraphFact": "preserved",
                "arbitraryHiddenKeySlot0": "proven",
                "unseenArbitraryHiddenKeySlot3": "proven",
            },
            self.result,
        )

    def test_captured_main_internal_program_can_terminate_its_exact_effect(
        self,
    ) -> None:
        self.assertEqual(
            self.result["capturedMainInternalTerminal"],
            {
                "exactEffectOutputAccepted": True,
                "terminalRemainsInternalOnly": True,
                "foreignEffectOutputRejected": True,
                "foreignFramebufferBindingRejected": True,
                "forgedEffectOutputRejected": True,
                "missingTargetRejected": True,
            },
            self.result,
        )

    def test_graph_input_alias_uses_the_validated_active_effect_ingress(self) -> None:
        self.assertEqual(
            self.result["admittedEffectIngress"],
            {
                "layerSourceAfterDisabledRawEffects": "success",
                "priorActiveOutputWithRawOrdinalGap": "success",
                "contextIdentityMismatch": "texture/textureReferenceInvalid",
                "wrongLayer": "texture/textureReferenceInvalid",
                "namedLayerSource": "texture/textureReferenceInvalid",
                "selfOutput": "texture/textureReferenceInvalid",
            },
            self.result,
        )

    def test_purpose_selection_and_binding_fail_closed(self) -> None:
        expected = {
            "nonFramebufferDoesNotInject": "texture/textureBindingInvalid",
            "framebufferWithoutIdentity": "texture/textureReferenceInvalid",
            "previousWithoutIdentity": "texture/textureReferenceInvalid",
            "historicalFramebufferWithoutHidden":
                "texture/textureBindingInvalid",
            "historicalFramebufferLabelOnly": "texture/textureBindingInvalid",
            "unknownEditorMaterialAlias": "texture/textureBindingInvalid",
            "regularGraphSampler": "success",
            "customPurposeIgnored": "success",
            "unknownMode": "texture/authoredSamplerSchemaInvalid",
            "multipleCandidates": "success",
            "unreachableGraphCandidate": "success",
            "providerUnavailableDoesNotUseEarlierCandidate": (
                "texture/resourceSnapshotUnresolved"
            ),
            "providerAbsentUsesEarlierCandidate": "success",
            "providerMissingDoesNotUseEarlierCandidate": (
                "texture/resourceSnapshotUnresolved"
            ),
            "providerPendingDoesNotUseEarlierCandidate": (
                "texture/resourceSnapshotUnresolved"
            ),
            "systemProviderPendingVisualFallback": (
                "material-finalizer-system-provider-pending"
            ),
            "providerUnavailableDoesNotUseShaderDefault": (
                "texture/resourceSnapshotUnresolved"
            ),
            "providerAbsentUsesShaderDefault": "success",
            "slotSchemaMismatch": "texture/textureBindingInvalid",
            "optionalUntypedMask": "texture/texturePurposeUnproven",
            "authoredOverridesShaderDefault": "success",
            "authoredFailureDoesNotUseShaderDefault": (
                "texture/resourceSnapshotUnresolved"
            ),
            "optionalMaskPendingDoesNotUseDefault": (
                "texture/resourceSnapshotUnresolved"
            ),
            "optionalMaskWrongPurposeDoesNotUseDefault": (
                "texture/textureMetadataIncomplete"
            ),
            "activeDefaultMaskMissing": "texture/textureBindingInvalid",
        }
        self.assertEqual(
            {name: self.result["failures"][name] for name in expected},
            expected,
        )

    def test_mixed_system_and_named_provider_selects_precompiled_typed_abi(
        self,
    ) -> None:
        self.assertEqual(
            self.result["mixedSystemNamedProvider"],
            {
                "variantCount": 2,
                "allReady": True,
                "abiSlots": [[], [1]],
                "profiles": [
                    "source-proven-graph-input-overlay-alpha-blend",
                ],
                "ready": "system:preserved-channels",
                "absent": "named:premultiplied-color",
                "readyAgain": "system:preserved-channels",
                "pending": "named:premultiplied-color",
                "pendingVisualFallback": "success",
                "unavailable": "named:premultiplied-color",
                "missing": "texture/resourceSnapshotUnresolved",
                "incomplete": "texture/textureMetadataIncomplete",
                "cacheStable": True,
            },
            self.result,
        )

    def test_named_provider_runtime_content_selects_exact_purpose(self) -> None:
        self.assertEqual(
            self.result["namedProviderRuntimePurpose"],
            {
                "color": "premultiplied-color",
                "data": "preserved-channels",
                "dataMaskRejected": "unproven",
            },
            self.result,
        )

    def test_official_sampler_modes_are_typed_without_custom_purpose(self) -> None:
        self.assertEqual(
            self.result["samplerSchema"],
            {
                "regularGraph": "premultiplied-color",
                "regularAsset": "unproven",
                "albedoAsset": "straight-albedo",
                "noiseAsset": "noise",
                "normalAsset": "normal",
                "normalAssetCaseInsensitive": "normal",
                "registeredStockNoise": "noise",
                "registeredStockWaterFlowPhase": "phase",
                "registeredStockWaterRippleNormal": "normal",
                "registeredStockWaterRippleNormalConflict": "unproven",
                "neighboringWaterRippleNormalUnproven": "unproven",
                "customWaterRippleNormalUnproven": "unproven",
                "registeredStockShimmerGradient": "preserved-channels",
                "registeredStockLightShaftsGradient": "preserved-channels",
                "registeredStockFireGradient": "preserved-channels",
                "registeredStockFireGradientConflict": "unproven",
                "unregisteredGradient": "unproven",
                "registeredStockCloudNoise": "noise",
                "registeredStockPerlinNoise": "noise",
                "registeredStockVoronoiNoise": "noise",
                "registeredStockLocalVoronoiNoise": "noise",
                "registeredStockUniformNoise": "noise",
                "registeredStockPerlinPurposeConflict": "unproven",
                "registeredStockVoronoiPurposeConflict": "unproven",
                "neighboringCustomPerlinUnproven": "unproven",
                "neighboringPerlin512Unproven": "unproven",
                "neighboringPerlinSuffixUnproven": "unproven",
                "neighboringVoronoiSuffixUnproven": "unproven",
                "neighboringLocalVoronoiSuffixUnproven": "unproven",
                "neighboringUniformSuffixUnproven": "unproven",
                "registeredStockPurposeConflict": "unproven",
                "unknownMaterialAsset": "unproven",
                "conflictingMaterial": "schema-invalid",
                "reachableConditionalAlbedo": "straight-albedo",
                "customPurposeIgnored": "premultiplied-color",
                "opacityMask": "mask",
                "rgbMask": "preserved-channels",
                "rgbMaskNamedTarget": "premultiplied-color",
                "flowMask": "flow",
                "normal": "schema-invalid",
                "depth": "depth",
                "depthR8": "depth",
                "depthWrongFormat": "schema-invalid",
                "normalFormat": "premultiplied-color",
                "genericFormat": "premultiplied-color",
                "unknownMode": "schema-invalid",
            },
        )

    def test_stock_perlin_semantic_fact_is_bound_to_fixed_resource_hashes(
        self,
    ) -> None:
        expected = {
            "util/perlin_256.tex": (
                "3a9e76025b07080babb4097c08a01ff9fcbae56ad4c122f6b070aaaae94bdd11"
            ),
            "util/perlin_256.tex-json": (
                "2f9cfef09edf3ecff1b6a6d9773cf55a1b12c2fa194a525bbe2c58cf1d70c315"
            ),
        }
        actual = {
            relative: hashlib.sha256(
                (STOCK_MATERIAL_ROOT / relative).read_bytes()
            ).hexdigest()
            for relative in expected
        }
        self.assertEqual(actual, expected)

    def test_stock_caustics_data_semantics_are_bound_to_fixed_resource_hashes(
        self,
    ) -> None:
        expected = {
            "pattern/voronoi.tex": (
                "0c05190a0c05250fb90414cbcc63cceb87e07e7eb6e2eebd368fa93867327885"
            ),
            "pattern/voronoi.tex-json": (
                "2f9cfef09edf3ecff1b6a6d9773cf55a1b12c2fa194a525bbe2c58cf1d70c315"
            ),
            "pattern/voronoi_local.tex": (
                "67a99eda6e1200b89450b4324111efa8969e745490c887a80d9fd29054d2e1e7"
            ),
            "pattern/voronoi_local.tex-json": (
                "2f9cfef09edf3ecff1b6a6d9773cf55a1b12c2fa194a525bbe2c58cf1d70c315"
            ),
            "util/uniform_256.tex": (
                "0717c990a2b2c8e333df2650237825a1b61dc6f6f3a981c67250d1fbed7b333e"
            ),
            "util/uniform_256.tex-json": (
                "2f9cfef09edf3ecff1b6a6d9773cf55a1b12c2fa194a525bbe2c58cf1d70c315"
            ),
        }
        actual = {
            relative: hashlib.sha256(
                (STOCK_MATERIAL_ROOT / relative).read_bytes()
            ).hexdigest()
            for relative in expected
        }
        self.assertEqual(actual, expected)

    def test_registered_stock_default_unblocks_only_typed_implicit_input(self) -> None:
        self.assertEqual(
            self.result["implicitFramebufferSchema"],
            {
                "registeredStockDefault": "0",
                "registeredAuthoredCandidate": "0",
                "unprovenAuthoredCandidate": "0",
                "graphAuthoredCandidate": "",
                "unknownDefault": "",
            },
        )

    def test_only_unmarked_sampler_combo_becomes_readiness_schema(self) -> None:
        self.assertEqual(
            self.result["samplerSchemaOrigin"],
            {
                "unmarkedReadiness": "MASK|asset",
                "authoredMarker": "none|none",
            },
        )

    def test_only_exact_single_branch_sampler_may_seed_its_readiness_combo(
        self,
    ) -> None:
        ambiguous = (
            "shader-preprocessor/shader-variant-invalid:"
            "active-schema-ambiguous"
        )
        self.assertEqual(
            self.result["shaderPreparationBoundary"]["selfGatedReadiness"],
            {
                "ready": "accepted:1",
                "unready": "accepted:",
                "nonUnitGuard": ambiguous,
                "elseBranch": ambiguous,
                "nestedGuard": ambiguous,
            },
        )

    def test_snapshot_identity_and_metadata_states_remain_distinct(self) -> None:
        self.assertEqual(self.result["failures"]["straightGraphColor"], "success")
        expected = {
            "missingGraphIdentity": "texture/resourceSnapshotUnresolved",
            "pending": "texture/resourceSnapshotUnresolved",
            "unavailable": "texture/resourceSnapshotUnresolved",
            "incompletePublication": "texture/textureMetadataIncomplete",
            "purposeMismatch": "texture/textureMetadataIncomplete",
            "unresolvedPublication": "texture/textureMetadataIncomplete",
            "unsupportedSampler": "texture/textureMetadataIncomplete",
            "textureDynamicFrameMismatch": "invariant/frameSnapshotMismatch",
            "dynamicInputsFrameMismatch": "invariant/frameSnapshotMismatch",
            "maskedMissing": "texture/textureBindingInvalid",
            "maskedPending": "texture/resourceSnapshotUnresolved",
            "maskedWrongPurpose": "texture/textureMetadataIncomplete",
        }
        self.assertEqual(
            {name: self.result["failures"][name] for name in expected},
            expected,
        )

    def test_shader_defaults_and_dynamic_contributors_are_fail_closed(self) -> None:
        expected = {
            "missingUniformDefault": "uniform/staticUniformBindingInvalid",
            "malformedUniformDefault": "uniform/uniformBindingInvalid",
            "exactWhitespaceUniformBindingKey": "success",
            "malformedStaticDeclaration": "uniform/staticUniformBindingInvalid",
            "uniformDeclarationConflict": "uniform/uniformDeclarationConflict",
            "hostUniformDeclarationConflict":
                "uniform/hostUniformDeclarationConflict",
            "hostUniformBindingInvalid": "uniform/hostUniformBindingInvalid",
            "provenTimelineScriptValue": "success",
            "unknownTimelineScriptAttachment": "uniform/uniformScriptAttachmentUnproven",
            "authoredDynamicFallback": "success",
            "dynamicSourceMismatch": "uniform/dynamicUniformBindingInvalid",
            "timelineVectorTypeMismatch": "uniform/dynamicUniformBindingInvalid",
            "unequalScalarSplatFallback":
                "uniform/dynamicUniformBindingInvalid",
            "nonUserScalarSplatContributor":
                "uniform/dynamicUniformBindingInvalid",
            "extraKeyScalarSplat": "success",
            "scriptKeyScalarSplat": "uniform/dynamicUniformBindingInvalid",
            "unequalDefaultStaticScalarSplat":
                "uniform/staticUniformBindingInvalid",
            "missingDefaultStaticScalarSplat":
                "uniform/staticUniformBindingInvalid",
            "nonFiniteDefaultStaticScalarSplat":
                "uniform/uniformBindingInvalid",
            "wrongABIStaticScalarSplat":
                "uniform/staticUniformBindingInvalid",
            "arrayStaticScalarSplat":
                "frontend/shaderFrontendFailed",
            "nonFiniteStaticScalarSplat":
                "uniform/staticUniformBindingInvalid",
            "unprovenStaticScalarSplat":
                "uniform/staticUniformBindingInvalid",
            "scalarShaderDefaultOnly":
                "uniform/staticUniformBindingInvalid",
            "multipleValueContributors": "uniform/uniformContributorPolicyUnproven",
            "runtimeLoopMetadataOnly": "frontend/shaderFrontendFailed",
            "runtimeLoopDynamicProducer": "frontend/shaderFrontendFailed",
            "runtimeLoopOverBudget": "frontend/shaderFrontendFailed",
            "runtimeLoopNegativeExact": "frontend/shaderFrontendFailed",
            "runtimeLoopNonIntegralExact": "frontend/shaderFrontendFailed",
            "runtimeLoopNonFiniteExact": "frontend/shaderFrontendFailed",
            "runtimeLoopMultipleProducer": "frontend/shaderFrontendFailed",
            "runtimeLoopCrossTemplateCache": (
                "invariant/variantSelectionTemplateIdentityInvariant"
            ),
        }
        self.assertEqual(
            {name: self.result["failures"][name] for name in expected},
            expected,
        )

    def test_material_cache_rejects_different_templates(self) -> None:
        self.assertEqual(self.result["materialCrossTemplateCache"], {
            "equivalent": "success",
            "combos": "invariant/variantSelectionTemplateIdentityInvariant",
            "textures": "invariant/variantSelectionTemplateIdentityInvariant",
            "graphRole": "invariant/variantSelectionTemplateIdentityInvariant",
            "renderState": "invariant/variantSelectionTemplateIdentityInvariant",
            "inactiveCombos": "invariant/variantSelectionTemplateIdentityInvariant",
            "ownerEligibility": "invariant/variantSelectionTemplateIdentityInvariant",
            "shaderContent": "invariant/variantSelectionTemplateIdentityInvariant",
            "sourceGraph": "invariant/variantSelectionTemplateIdentityInvariant",
            "equivalentAfterRejection": "success",
        })

    def test_visual_passthrough_reasons_remain_bounded(self) -> None:
        finalizer_text = FINALIZER_SOURCE.read_text(encoding="utf-8")
        visual_text = VISUAL_PASSTHROUGH_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            ".hostUniformBindingInvalid",
            finalizer_text,
        )
        self.assertIn(".activeUniformSchemaMissing", finalizer_text)
        for reason in (
            '"material-finalizer-host-uniform-declaration-conflict"',
            '"material-finalizer-uniform-declaration-conflict"',
        ):
            self.assertIn(reason, visual_text)
        self.assertNotIn(
            "material-finalizer-host-uniform-binding",
            visual_text,
        )
        self.assertNotIn("material-finalizer-active-uniform-schema", visual_text)
        self.assertIn('reasonCode == "material-variant-envelope-invariant"', visual_text)
        self.assertIn("&& !graph.renderTargets.isEmpty", visual_text)

    def test_frame_selection_consumes_only_precompiled_sampler_reachability(self) -> None:
        variant_text = VARIANT_CACHE_SOURCE.read_text(encoding="utf-8")
        self.assertNotIn(
            "SceneResolvedMaterialShaderSchema.reachableSamplers(",
            variant_text,
        )
        self.assertNotIn("reachable-sampler-schema", variant_text)

    def test_one_material_program_target_drives_resource_and_program_preparation(
        self,
    ) -> None:
        self.assertEqual(
            self.result["compatibilityTargetTextureCandidate"],
            {
                "unprofiledReachabilityRejected": True,
                "bootstrapSlots": [0],
                "reachableSlots": [0],
                "programVariantCount": 1,
                "targets": ["windows-dx11-sm4"],
                "dependencies": ["HLSL"],
                "branchInsensitiveDependencies": [],
            },
            self.result,
        )

        runtime_catalog = RUNTIME_CATALOG_SOURCE.read_text(encoding="utf-8")
        template_compiler = TEMPLATE_COMPILER_SOURCE.read_text(encoding="utf-8")
        schema = SHADER_SCHEMA_SOURCE.read_text(encoding="utf-8")
        reachability = SHADER_REACHABILITY_SOURCE.read_text(encoding="utf-8")
        variant_compilation = read_source_family(VARIANT_COMPILATION_SOURCE)
        target_token = "compatibilityTarget: .windowsDX11ShaderModel4"
        self.assertEqual(runtime_catalog.count(target_token), 1)
        self.assertNotIn(target_token, schema)
        self.assertNotIn(target_token, reachability)
        self.assertNotIn(target_token, variant_compilation)
        self.assertIn(
            "compatibilityTarget: compatibilityTarget",
            template_compiler,
        )
        for consumer in (schema, reachability, variant_compilation):
            self.assertIn(
                "compatibilityTarget: template.compatibilityTarget",
                consumer,
            )

    def test_finalizer_and_variant_selection_invariants_remain_typed(self) -> None:
        expected = {
            "variantSelectionReachabilityIdentity": (
                "invariant/variantSelectionReachabilityIdentityInvariant"
            ),
            "variantSelectionKey": "invariant/variantSelectionKeyInvariant",
            "terminalGraphOverrideUnavailable": (
                "texture/resourceSnapshotUnresolved"
            ),
            "textureVariantKeyIdentityInvariant": (
                "invariant/textureVariantKeyIdentityInvariant"
            ),
            "graphRoleIdentityInvariant": "invariant/graphRoleIdentityInvariant",
            "programAssemblyIdentityInvariant": (
                "invariant/programAssemblyIdentityInvariant"
            ),
        }
        self.assertEqual(
            {name: self.result["failures"][name] for name in expected},
            expected,
        )
        self.assertEqual(
            self.result["failures"]["variantSelectionKeyDetails"],
            "admitted-1,resolved-1,matches-0,key-e1-r1-a1-fs0-0-7",
        )
        finalizer_text = FINALIZER_SOURCE.read_text(encoding="utf-8")
        variant_text = VARIANT_CACHE_SOURCE.read_text(encoding="utf-8")
        self.assertIn(".finalizerUnexpectedFailure", finalizer_text)
        self.assertIn(".variantSelectionUnexpectedFailure", variant_text)

    def test_render_state_and_color_contracts_fail_closed(self) -> None:
        expected = {
            "unsupportedState": "state/renderStateInvalid",
            "dataGraphInput": "texture/textureMetadataIncomplete",
            "arithmeticOutput": "color/colorContractUnproven",
            "arithmeticScalarOutput": "success",
            "scalarRedConsumer": "success",
            "scalarRedForgedTEXFormat": "texture/textureMetadataIncomplete",
            "scalarRedWrongFormat": "texture/textureMetadataIncomplete",
            "maskedColorAuxiliary": "texture/textureMetadataIncomplete",
            "overlayColorAuxiliary": "texture/textureMetadataIncomplete",
        }
        self.assertEqual(
            {name: self.result["failures"][name] for name in expected},
            expected,
        )


if __name__ == "__main__":
    unittest.main()
