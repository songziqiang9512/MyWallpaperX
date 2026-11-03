#!/usr/bin/env python3

from __future__ import annotations

from script.tests.source_family import read_source_family
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
ADMISSION_CATALOG_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneEffectAdmissionCatalog.swift"
)
DEPENDENCY_RUNTIME_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneDependencyFrameRuntime.swift"
)
STATIC_MODEL_DEPENDENCY_RUNTIME_SOURCE = DEPENDENCY_RUNTIME_SOURCE.with_name(
    "SceneDependencyFrameRuntime+StaticModel.swift"
)
METAL_RENDERER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift"
DEPENDENCY_PROVIDER_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+DependencyProviders.swift"
)
UTILITY_RUNTIME_PLAN_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityLayerRuntimePlan.swift"
)
LAUNCH_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Launch.swift"
SWIFT_SOURCES = [
    UTILITY_RUNTIME_PLAN_SOURCE,
    SOURCE_ROOT / "Rendering/Targets/SceneOffscreenResolutionPolicy.swift",
    Path(__file__).with_name("fixtures")
    / "SceneDependencyRenderPlanTestSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneNamedTextureReference.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneImageLayerBlendDependencyContract.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneNamedTextureDependencyReferenceAnalysis.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneDependencyGraphAnalysis.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneDependencyRenderPlan+ImageProgramReference.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneDependencyRenderPlan+ForwardPreparation.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneDependencyRenderPlan+StaticModel.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneDependencyRenderPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneDependencyRenderPlan+Aggregate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneDependencyRenderPlan+BindingCompilation.swift",
]

HARNESS_FIXTURE_DIRECTORY = Path(__file__).with_name("fixtures")
HARNESS_SOURCE = "\n".join(
    (HARNESS_FIXTURE_DIRECTORY / name).read_text(encoding="utf-8")
    for name in (
        'SceneDependencyRenderPlanFixtureInputs.swift',
        'SceneDependencyRenderPlanHarness.swift',
        'SceneDependencyRenderPlanNamedUtilityCases.swift',
        'SceneDependencyRenderPlanProgramProviderCases.swift',
        'SceneDependencyRenderPlanMultiProviderCases.swift',
        'SceneDependencyRenderPlanXRayCases.swift',
        'SceneDependencyRenderPlanImageBlendCases.swift',
    )
)


class SceneDependencyRenderPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-dependency-plan-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-dependency-plan"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness), "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        default_environment = os.environ.copy()
        default_environment.pop("MWX_SCENE_NAMED_PROVIDER_ROUTE", None)
        completed = subprocess.run(
            [str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
            env=default_environment,
        )
        cls.result = json.loads(completed.stdout)
        disabled_environment = default_environment.copy()
        disabled_environment["MWX_SCENE_NAMED_PROVIDER_ROUTE"] = "disable-generic"
        disabled = subprocess.run(
            [str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
            env=disabled_environment,
        )
        cls.route_disabled_result = json.loads(disabled.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_utility_capture_retains_prepared_binding_for_future_visibility(self) -> None:
        result = self.result["preparedUtility"]
        self.assertEqual(result["capture"], "capture")
        self.assertEqual(result["convenience"], "capture")
        self.assertEqual(result["missingBinding"], "unsupportedDependencies")
        self.assertEqual(result["unadmitted"], "unsupportedDependencies")
        self.assertEqual(result["hidden"], "capture")
        self.assertEqual(result["captures"], [950])
        self.assertEqual(result["restrictedRoots"], "unsupportedDependencies")
        self.assertEqual(result["expandedRoots"], "capture")
        self.assertEqual(result["hiddenExpandedRoots"], "capture")
        self.assertFalse(result["restrictedFramebuffer"])
        self.assertTrue(result["expandedFramebuffer"])

    def test_framebuffer_consumes_prepared_requirements_without_re_admission(self) -> None:
        result = self.result["preparedUtility"]
        self.assertFalse(result["framebufferEmpty"])
        self.assertFalse(result["framebufferNoPreparedProvider"])
        for key in ("framebufferPreparedProvider", "framebufferCapture", "framebufferBackground",
                    "framebufferRefraction", "framebufferBlend"):
            self.assertTrue(result[key], key)

    def test_utility_selection_preserves_single_and_multiple_dependencies(self) -> None:
        # Hidden, unadmitted, child-owning, non-composition and inactive-effect
        # consumers must not gain a route while sharing the reference index.
        # Prepared hidden consumer 903 stays eligible for future activation.
        self.assertEqual(self.result["utilitySelection"], [901, 902, 903])

    def test_named_reference_variants_are_typed(self) -> None:
        self.assertEqual(self.result["parsedVariants"], ["unspecified", "a", "b"])
        self.assertTrue(self.result["invalidReference"])
        self.assertFalse(self.result["secondaryBinding"])
        self.assertEqual(
            self.result["secondaryIssues"],
            ["33:unsupportedVariant:1"],
        )

    def test_named_consumers_share_path_independent_backward_binding(self) -> None:
        self.assertEqual(self.result["referenceCount"], 19)
        self.assertEqual(
            # Layer 3 is the hidden conditional consumer; it joins the named
            # consumer set since the conditional provider chain slice.
            self.result["namedConsumers"],
            [2, 3, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 31, 32, 35, 37],
        )
        self.assertEqual(
            self.result["requiredEffectConsumers"],
            [2, 3, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 31, 32, 35, 37],
        )
        self.assertEqual(self.result["executableUtilityConsumers"], [15, 31])
        self.assertEqual(
            # Layer 3 joins as the hidden conditional consumer's binding
            # since the conditional provider chain slice.
            self.result["bindingConsumers"],
            [2, 3, 8, 9, 10, 11, 12, 13, 14, 15, 16, 31, 35],
        )
        self.assertFalse(self.result["defaultUtilityBinding"])
        self.assertEqual(self.result["requiredProviders"], [1, 30, 34])
        # A plain dependency-free text provider carries the same composite
        # route as a hidden image provider; a text provider with authored
        # effects has no plain-raster composite contract yet.
        self.assertEqual(
            self.result["textMaskRoute"],
            {
                "kind": "imageLayerBlend",
                "provider": 34,
                "slot": 1,
                "requiresProgram": True,
            },
        )
        self.assertFalse(self.result["effectfulTextMaskBinding"])

    def test_named_provider_route_rollback_is_generic_only_and_fail_closed(self) -> None:
        self.assertEqual(
            self.result["resolvedMaterialRoute"],
            {
                "binding": True,
                "resolvedMaterial": True,
                "requiredEffect": True,
                "requiredProviders": [400],
                "issues": [],
            },
        )
        self.assertEqual(
            self.route_disabled_result["resolvedMaterialRoute"],
            {
                "binding": False,
                "resolvedMaterial": False,
                "requiredEffect": True,
                "requiredProviders": [],
                "issues": ["401:namedProviderRouteDisabled:400"],
            },
        )
        self.assertEqual(
            self.result["resolvedMaterialUtilityRoute"],
            {
                "binding": False,
                "requiredEffect": False,
                "requiredProviders": [],
                "issues": ["411:unsupportedConsumer:-1"],
            },
        )
        self.assertEqual(
            self.route_disabled_result["resolvedMaterialUtilityRoute"],
            {
                "binding": False,
                "requiredEffect": True,
                "requiredProviders": [],
                "issues": ["411:namedProviderRouteDisabled:410"],
            },
        )
        self.assertEqual(
            self.result["solidCarrierRoute"],
            {
                "binding": True,
                "solid": True,
                "requiredEffect": True,
                "requiredProvider": True,
                "issues": [],
            },
        )
        self.assertEqual(
            self.route_disabled_result["solidCarrierRoute"],
            {
                "binding": False,
                "solid": False,
                "requiredEffect": True,
                "requiredProvider": False,
                "issues": ["31:namedProviderRouteDisabled:30"],
            },
        )

        self.assertEqual(
            self.result["solidCarrierWithoutExecutableID"],
            {
                "binding": False,
                "requiredEffect": False,
                "requiredProvider": False,
                "issues": ["31:unsupportedConsumer:-1"],
            },
        )

        self.assertEqual(
            self.route_disabled_result["solidCarrierWithoutExecutableID"],
            {
                "binding": False,
                "requiredEffect": True,
                "requiredProvider": False,
                "issues": ["31:namedProviderRouteDisabled:30"],
            },
        )
        self.assertEqual(
            self.route_disabled_result["imageBlendBinding"],
            {
                "consumer": -1,
                "provider": -1,
                "effect": "",
                "pass": -1,
                "slot": -1,
                "blend": -1,
                "imageBlend": False,
                "forwardCapture": False,
            },
        )
        self.assertEqual(
            self.route_disabled_result["nestedImageBlend"],
            {
                "bindings": [],
                "providers": [],
                "graphProviders": [],
                "effectConsumers": [401, 402],
                # Route rollback keeps both provider identities blocked, but
                # the terminal unbound consumer may retain its base source.
                "passthroughBlocked": [400, 401],
                "issues": [
                    "401:namedProviderRouteDisabled:400",
                    "402:namedProviderRouteDisabled:401",
                ],
            },
        )

    def test_only_exact_optional_user_texture_retains_lower_named_dependency(
        self,
    ) -> None:
        self.assertEqual(
            self.result["shadowedNamedReferences"],
            {
                "referenceCount": 1,
                "binding": True,
                "provider": 420,
                "issues": [],
            },
        )

    def test_mixed_system_named_provider_builds_forward_program_binding(
        self,
    ) -> None:
        self.assertEqual(
            self.result["mixedSystemNamedProvider"],
            {
                "potentialCount": 2,
                "references": 1,
                "bindingKind": "imageLayerBlend",
                "requiresForwardCapture": True,
                "requiresProgram": True,
                "provider": 1321,
                "issues": [],
            },
            self.result,
        )
        self.assertEqual(
            self.result["mixedSystemNamedUnadmitted"],
            {
                "references": 0,
                "binding": False,
                "requiresEffect": False,
                "consumerBlocked": False,
                "providerBlocked": False,
            },
            self.result,
        )
        self.assertTrue(self.result["selectedMultiReferenceAccepted"])
        self.assertEqual(
            self.result["potentialCycleIsolation"],
            {
                "broadCycles": [1332, 1510],
                "isolatedCycles": [],
                "isolatedConsumerEdges": [1331],
                "unadmittedProviderEdges": [],
            },
            self.result,
        )

    def test_mixed_property_named_provider_requires_exact_program_admission(
        self,
    ) -> None:
        self.assertEqual(
            self.result["mixedPropertyNamedProvider"],
            {
                "potentialCount": 1,
                "unadmittedReferences": 0,
                "unadmittedBinding": False,
                "unadmittedConsumerBlocked": False,
                "unadmittedProviderBlocked": False,
                "admittedReferences": 1,
                "admittedBinding": True,
                "admittedProvider": 1331,
            },
        )

    def test_one_provider_program_vector_preserves_authored_slot_order(self) -> None:
        self.assertEqual(
            self.result["singleProviderProgramVector"],
            {
                "directReferences": 1,
                "directSlots": ["effect-964:0:1"],
                "potentialBindings": 2,
                "potentialSingletons": True,
                "expandedReferences": 3,
                "expandedSlots": [
                    "effect-964:0:1",
                    "effect-965:0:1",
                    "effect-966:0:1",
                ],
                "provider": 1325,
                "kind": "imageLayerBlend",
                "forward": True,
                "requiresProgram": True,
                "issues": [],
            },
            self.result,
        )

    def test_multi_provider_composition_candidate_is_fail_closed(
        self,
    ) -> None:
        self.assertEqual(
            self.result["multiProviderCandidate"],
            {
                "candidate": True,
                "aggregate": {
                    "providers": [601, 602],
                    "slots": ["first:0:1", "second:0:1"],
                    "strict": True,
                    "reversedStrict": False,
                    "wrongBlendStrict": False,
                },
                "authoredOrder": {
                    "slots": [
                        "z-authored-first:0:1",
                        "a-authored-second:0:1",
                    ],
                    "bindingSlots": [
                        "z-authored-first:0:1",
                        "a-authored-second:0:1",
                    ],
                    "strict": True,
                    "admitted": True,
                },
                "aggregateAdmission": {
                    "positive": True,
                    "reversed": False,
                    "missing": False,
                    "duplicate": False,
                    "wrongProvider": False,
                },
                "binding": True,
                "requiredProviders": [601, 602],
                "requiredEffect": True,
            },
        )
        self.assertEqual(
            self.result["multiProviderRejects"],
            {
                "dependencyMismatch": True,
                "duplicateSlot": True,
                "unsafeProvider": True,
                "unsafeAggregate": True,
                "wrongPass": True,
                "wrongSlot": True,
                "userTexture": True,
                "extraPass": True,
                "extraSlots": True,
                "unknownCombo": True,
                "missingProviderOrder": True,
                "missingConsumerOrder": True,
                "visibleProvider": True,
                "visibleEffectfulProvider": True,
                "forwardSafeProvider": True,
                "forwardUnsafeProvider": True,
                "forwardVisibleEffectfulGeometryProvider": True,
            },
        )
        self.assertEqual(
            self.result["multiProviderGeometry"],
            {
                "providers": [601, 602],
                "kinds": ["geometryLayer", "imageLayerBlend"],
                "slots": ["first:0:1", "second:0:1"],
                "strict": True,
                "admitted": True,
            },
        )
        self.assertEqual(
            self.result["nestedGeometryAggregate"],
            {
                "nestedBindingKind": "geometryLayer",
                "nestedRequiresProgram": True,
                "aggregateProviders": [702, 701],
                "aggregateKinds": ["imageLayerBlend", "geometryLayer"],
                "requiredProviders": [700, 701, 702],
                "graphProviders": [700, 701],
                "issues": [],
            },
        )

    def test_multi_provider_inactive_effect_keeps_declaration_superset_strict(
        self,
    ) -> None:
        self.assertEqual(
            self.result["multiProviderInactiveSuperset"],
            {
                "candidate": True,
                "references": [
                    {"provider": 601, "slot": "first:0:1"},
                    {"provider": 602, "slot": "second:0:1"},
                ],
                "aggregate": {
                    "providers": [601, 602],
                    "strict": True,
                    "admitted": True,
                },
                "requiredProviders": [601, 602],
                "declaredProviders": [601, 602, 604],
            },
        )

    def test_cycle_forward_and_invalid_external_primary_contracts_fail_closed(self) -> None:
        self.assertEqual(self.result["cycles"], [4, 5])
        self.assertIn("2:dependencyMismatch:1", self.result["issues"])
        self.assertIn("6:forwardUtilityProvider:7", self.result["issues"])
        self.assertIn("32:missingProvider:999", self.result["issues"])
        # Non-neutral authored constants no longer gate the structural
        # carrier; the MaterialProgram owns shader semantics. A path-kind
        # user-texture override keeps the slot out of dependency references
        # entirely: no binding and no dependency issue is produced.
        self.assertNotIn("10:unsupportedConsumer:-1", self.result["issues"])
        self.assertNotIn("33:unsupportedConsumer:-1", self.result["issues"])
        self.assertNotIn(33, self.result["bindingConsumers"])
        self.assertNotIn("15:unsupportedConsumer:-1", self.result["issues"])
        self.assertNotIn("16:unsupportedConsumer:-1", self.result["issues"])
        for layer_id in (17, 18, 19):
            self.assertIn(
                f"{layer_id}:unsupportedConsumer:-1",
                self.result["issues"],
            )

    def test_matrix_shape_keeps_hidden_consumer_out_of_runtime_liveness(self) -> None:
        # Conditional-content consumers (hidden layers declaring dependency
        # references) are reachable provider roots since the batch-B
        # conditional provider chain slice: the hidden consumer pair gains
        # one binding (7 -> 8).
        self.assertEqual(self.result["matrixBindingCount"], 8)
        self.assertEqual(self.result["matrixRequiredProviders"], [10, 11, 12, 13, 14, 15])

    def test_unbound_consumer_preserves_base_while_provider_stays_blocked(self) -> None:
        self.assertEqual(
            self.result["staticPassthroughBlocks"],
            {
                "namedProvider": True,
                "namedConsumer": False,
                # The hidden consumer (111) declares its reference, so its
                # provider (110) must be ready when the conditional content
                # shows: the provider joins the blocked set (was False before
                # conditional provider chains).
                "hiddenNamedProvider": True,
                "hiddenNamedConsumer": False,
                "selfReference": False,
                "unreferenced": False,
                "explicitProvider": True,
                "explicitConsumer": False,
                "requiredProvidersEmpty": True,
            },
        )

    def test_unbound_xray_shapes_keep_provider_sided_safety(
        self,
    ) -> None:
        self.assertEqual(
            self.result["staticPassthroughXRayBlocks"],
            {
                "exemptConsumer": False,
                "xRayProvider": True,
                "extraDependency": False,
                "opacityMaskCombo": False,
                "blendModeCombo": False,
                "nonStockDefinition": False,
                "secondNamedSlot": False,
                "mismatchedProvider": False,
                "secondNamedReference": False,
                "multiplePasses": False,
                "exemptThenProvider": True,
                "upperConsumer": False,
            },
        )

    def test_xray_provider_safety_does_not_block_unbound_consumer_fallback(
        self,
    ) -> None:
        self.assertEqual(
            self.result["isolatedXRayPassthroughBlocks"],
            {
                "exactProvider": True,
                "exactConsumer": False,
                "missingProviderConsumer": False,
                "unverifiedStockPathProvider": True,
                "unverifiedStockPathConsumer": False,
                "multiEffectProvider": True,
                "multiEffectConsumer": False,
            },
        )

    def test_hidden_image_provider_is_a_program_gated_external_primary(self) -> None:
        self.assertEqual(
            self.result["hiddenVideoXRayProgramBinding"],
            {
                "provisional": True,
                "provider": 260,
                "slot": 1,
                "requiresProgram": True,
                "forward": True,
                "runtimeAdmitted": True,
                "runtimeRejected": True,
                "providerRequired": True,
                "consumerRequiresEffect": True,
                "activeExecution": [261],
                "inactiveExecution": [],
            },
        )

    def test_verified_xray_authority_flows_from_stock_identity_to_dependency_plan(
        self,
    ) -> None:
        launch = LAUNCH_SOURCE.read_text(encoding="utf-8")
        catalog = ADMISSION_CATALOG_SOURCE.read_text(encoding="utf-8")
        renderer = read_source_family(METAL_RENDERER_SOURCE)
        dependency_provider = DEPENDENCY_PROVIDER_SOURCE.read_text(encoding="utf-8")
        dependency_runtime = DEPENDENCY_RUNTIME_SOURCE.read_text(encoding="utf-8")
        static_model_dependency_runtime = (
            STATIC_MODEL_DEPENDENCY_RUNTIME_SOURCE.read_text(encoding="utf-8")
        )

        self.assertIn(
            "SceneXRayStockIdentityVerifier.verifiedStockIdentityEffectKeys(",
            launch,
        )
        self.assertIn(
            "descriptor: runtimeInput.renderDescriptor",
            launch,
        )
        self.assertIn(
            "shaderContracts: runtimeInput.shaderContracts",
            launch,
        )
        self.assertIn(
            "verifiedXRayStageKeys: verifiedXRayStockIdentityKeys",
            launch,
        )
        self.assertIn(
            "self.verifiedXRayStageKeys = verifiedXRayStageKeys.intersection(",
            catalog,
        )
        self.assertIn(
            "verifiedXRayStageKeys: verifiedXRayStageKeys",
            dependency_runtime,
        )

    def test_parent_aware_visibility_precedes_layer_draw_request(self) -> None:
        renderer = read_source_family(METAL_RENDERER_SOURCE)
        visibility_guard = renderer.index(
            "guard frameVisibleLayerIDs.contains(layer.id) else { continue }"
        )
        draw_outcome = renderer.index("let drawOutcome = imageCompositor.drawOutcome(")
        self.assertLess(visibility_guard, draw_outcome)

    def test_static_model_named_albedo_uses_typed_forward_provider(self) -> None:
        self.assertEqual(
            self.result["staticModelNamedProvider"],
            {
                "binding": True,
                "provider": 611,
                "pass": 0,
                "slot": 0,
                "forward": True,
                "required": True,
                "activeOrder": [611],
                "inactiveOrder": [],
            },
        )
        disabled = self.route_disabled_result["staticModelNamedProvider"]
        self.assertFalse(disabled["binding"])
        self.assertFalse(disabled["required"])
        self.assertEqual(disabled["activeOrder"], [])

        utility_plan = UTILITY_RUNTIME_PLAN_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "dependencyPlan.bindingsByConsumerLayerID.values.map(\\.providerLayerID)",
            utility_plan,
        )
        report_start = utility_plan.index("static func reportLines(")
        report_end = utility_plan.index("extension SceneRenderDescriptor")
        self.assertNotIn(
            "dependencyPlan.requiredProviderLayerIDs",
            utility_plan[report_start:report_end],
        )

    def test_mixed_consumer_preserves_existing_effect_provider_route(self) -> None:
        self.assertEqual(
            self.result["mixedModelNamedProvider"],
            {
                "modelBinding": False,
                "effectBinding": True,
                "required": True,
            },
        )

    def test_forward_image_provider_preparation_precedes_authored_layer_loop(self) -> None:
        renderer = read_source_family(METAL_RENDERER_SOURCE)
        dependency_provider = DEPENDENCY_PROVIDER_SOURCE.read_text(
            encoding="utf-8"
        )
        dependency_runtime = DEPENDENCY_RUNTIME_SOURCE.read_text(encoding="utf-8")
        static_model_dependency_runtime = (
            STATIC_MODEL_DEPENDENCY_RUNTIME_SOURCE.read_text(encoding="utf-8")
        )
        main_pass = renderer.index("let (mainPass, groups) = makeScenePass(")
        forward_preparation = renderer.index(
            "prepareForwardDependencyProviders(", main_pass
        )
        authored_loop = renderer.index("frameLayers: for layer in orderedLayers")
        self.assertLess(main_pass, forward_preparation)
        self.assertLess(forward_preparation, authored_loop)
        prepass = renderer[forward_preparation:authored_loop]
        self.assertIn("framePlans: resolvedMaterialFrameTargetPlans", prepass)
        self.assertIn("layersByID: frameLayersByID", prepass)
        self.assertIn(
            ".forwardDependencyPreparationOrder(\n"
            "                    authoredLayerIDs: orderedLayerIDs,\n"
            "                    activeExecutionLayerIDs: activeExecutionLayerIDs,\n"
            "                    activeStaticModelConsumerLayerIDs:",
            dependency_provider,
        )
        self.assertIn(
            "resolvedMaterialExecutionLayerIDs(",
            dependency_runtime,
        )
        self.assertIn(
            "executeDependencyGraphProviderIfRequired(",
            dependency_provider,
        )
        self.assertIn(
            "forwardGraphProviderLayerIDs.contains(layer.id)",
            renderer,
        )
        self.assertIn(
            "forwardCaptureProviderLayerIDs.contains(providerLayerID)",
            static_model_dependency_runtime,
        )

    def test_puppet_atlas_cannot_publish_as_flat_image_provider(self) -> None:
        self.assertTrue(self.result["puppetImageBlendRejected"])

    def test_structural_slot3_hidden_solid_dependency_is_generic_and_fail_closed(
        self,
    ) -> None:
        self.assertEqual(
            self.result["solidCarrierBinding"],
            {
                "consumer": 31,
                "provider": 30,
                "effect": "31#effect#slot3-solid",
                "pass": 0,
                "slot": 3,
                "blend": 0,
                "solid": True,
            },
        )
        self.assertTrue(self.result["solidCarrierGeneralizesAuthoredShaderShape"])
        self.assertTrue(all(self.result["solidCarrierRejects"].values()))

    def test_visible_effectful_solid_data_provider_requires_admitted_program(
        self,
    ) -> None:
        self.assertEqual(
            self.result["materialProgramSolidCarrier"],
            {
                "provider": 94,
                "slot": 1,
                "solid": True,
                "requiresProgram": True,
                "forward": False,
            },
        )
        self.assertTrue(
            all(self.result["materialProgramSolidCarrierRejects"].values())
        )
        self.assertTrue(self.result["materialProgramSolidCarrierExtraAsset"])

    def test_visible_effectless_image_uses_same_named_source_owner(self) -> None:
        self.assertEqual(self.result["visibleStaticImageBindings"], {
            "backward": True, "forward": True, "implicitVisible": True,
            "effectfulNeverRaw": True, "puppetRejected": True,
            "childrenRejected": True, "dependenciesRejected": True,
        })

    def test_exact_plain_image_blend_dependency_is_typed_and_fail_closed(self) -> None:
        self.assertEqual(
            self.result["imageBlendBinding"],
            {
                "consumer": 301,
                "provider": 300,
                "effect": "image-blend",
                "pass": 0,
                "slot": 1,
                "blend": 0,
                "imageBlend": True,
                "forwardCapture": False,
            },
        )
        self.assertEqual(
            self.result["forwardImageBlendBinding"],
            {
                "consumer": 301,
                "provider": 300,
                "imageBlend": True,
                "forwardCapture": True,
            },
        )
        self.assertEqual(
            self.result["forwardEffectfulImageBlendBinding"],
            {
                "consumer": 301,
                "provider": 300,
                "imageBlend": True,
                "forwardCapture": True,
            },
        )
        self.assertEqual(
            self.result["forwardEffectfulPreparationOrder"],
            {
                "authored": [800, 301, 850, 300, 900],
                "prepared": [300, 800, 301, 850, 900],
                "duplicateRejected": True,
            },
        )
        self.assertEqual(
            self.result["forwardStaticPreparationOrder"],
            {
                "authored": [800, 301, 850, 300, 900],
                "prepared": [800, 301, 850, 300, 900],
            },
        )
        self.assertEqual(
            self.result["transformedImageBlendBinding"],
            {"provider": 300, "imageBlend": True, "requiresProgram": True},
        )
        self.assertEqual(
            self.result["imageBlendWithGraphInternalPrevious"],
            {"provider": 300, "requiresProgram": True},
        )
        self.assertEqual(
            self.result["nonNormalTransformedImageBlend"],
            {"provider": 300, "blend": 6, "requiresProgram": True},
        )
        self.assertTrue(all(self.result["programRequiredRuntimeRejects"].values()))
        self.assertTrue(self.result["partialStrengthRequiresProgram"])
        self.assertTrue(all(self.result["imageBlendRejects"].values()))
        self.assertTrue(self.result["imageBlendEffectfulProvider"])
        self.assertTrue(
            self.result["forwardImageBlendOrderIndependentAssetProvider"]
        )
        self.assertTrue(all(self.result["forwardImageBlendRejects"].values()))
        self.assertEqual(
            self.result["nestedImageBlend"],
            {
                "bindings": [401, 402],
                "providers": [400, 401],
                "graphProviders": [400, 401],
                "effectConsumers": [401, 402],
                "passthroughBlocked": [400, 401, 402],
                "issues": [],
            },
        )
        self.assertEqual(
            self.result["nestedProgramReference"],
            {
                "bindings": [501, 502],
                "providers": [500, 501],
                "graphProviders": [500, 501],
                "effectConsumers": [501, 502],
                "issues": [],
            },
        )
        self.assertTrue(
            self.result["unexplainedProgramDependencyRejected"]
        )
        self.assertEqual(
            self.result["forwardNestedImageBlend"],
            {
                "bindings": [401, 402],
                "providers": [400, 401],
                "graphProviders": [400, 401],
                "forwardProviders": [400, 401],
                "prepared": [400, 401, 399, 402],
                "issues": [],
            },
        )
        self.assertEqual(
            self.result["brokenNestedImageBlend"],
            {"bindings": [], "providers": [], "graphProviders": []},
        )

    def test_retired_provider_is_unavailable_without_aborting_healthy_layers(self) -> None:
        self.assertEqual(self.result["retiredForwardProviders"], {
            "direct": [], "upstream": [401], "middle": [], "model": [],
            "duplicateRejected": True,
        })

if __name__ == "__main__":
    unittest.main()
