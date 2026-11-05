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

    def test_utility_capture_uses_prepared_program_and_retains_future_visibility(self) -> None:
        result = self.result["preparedUtility"]
        self.assertEqual(result["capture"], "capture")
        self.assertEqual(result["convenience"], "capture")
        # A prepared Program and source route own capture; the cold Plan does
        # not separately license it through a legacy singleton binding.
        self.assertEqual(result["missingBinding"], "capture")
        self.assertEqual(result["unadmitted"], "unsupportedDependencies")
        self.assertEqual(result["hidden"], "capture")
        self.assertEqual(result["captures"], [950])
        self.assertEqual(result["restrictedRoots"], "capture")
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

    def test_independent_named_sources_keep_exact_candidates_and_forward_supply(self) -> None:
        rows = self.result["independentNamedSources"]
        cases = (
            ("member", "member-read:0:1=120", 120, "resolvedMaterial", True, "skippedNoEffect"),
            ("solidBefore", "source-read:0:2=210", 210, "solidLayer", False, "none"),
            ("solidAfter", "source-read:0:2=210", 210, "solidLayer", True, "none"),
            ("renamed", "renamed-read:1:5=330", 330, "solidLayer", True, "none"),
        )
        for key, binding, provider, kind, forward, disposition in cases:
            with self.subTest(key=key):
                row = rows[key]
                self.assertEqual(row["candidates"], [binding])
                self.assertEqual(row["bindings"], [binding])
                self.assertEqual(row["kinds"], [kind])
                self.assertEqual(row["forward"], [forward])
                self.assertEqual(row["providers"], [provider])
                self.assertEqual(row["prepass"], [provider] if forward else [])
                self.assertEqual(row["graphProviders"], [])
                self.assertEqual(row["utilityCaptures"], [])
                self.assertEqual(row["providerDisposition"], disposition)

    def test_unused_named_sources_and_attachment_prefixes_do_not_gain_prepass(self) -> None:
        rows = self.result["independentNamedSources"]
        for key in ("member", "solidBefore", "solidAfter", "renamed"):
            with self.subTest(key=key):
                self.assertEqual(rows[key]["noDemand"], {
                    "providers": [], "prepass": [], "requiresEffect": False, "references": 0,
                })
        self.assertEqual(rows["negativeCandidates"], {
            "copyBackgroundPrefix": {"before": [410], "forward": []},
            "effectfulMainBackground": {"before": [410], "forward": []},
        })

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
        self.assertEqual(self.result["selectedMultiReferences"], {
            "slots": ["effect-431:0:1", "effect-432:0:1"],
            "providers": [420, 420], "requiredProviders": [420],
            "kinds": ["resolvedMaterial", "resolvedMaterial"],
            "requiresProgram": [True, True], "references": 2,
        })
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
                "potentialBindings": 3,
                "potentialSingletons": True,
                "expandedReferences": 3,
                "expandedSlots": [
                    "effect-964:0:1",
                    "effect-965:0:1",
                    "effect-966:0:1",
                ],
                "providers": [1325, 1325, 1325],
                "requiredProviders": [1325],
                "kinds": ["imageLayerBlend"] * 3,
                "forward": [True] * 3,
                "requiresProgram": [True] * 3,
                "issues": [],
            },
            self.result,
        )

    def test_hidden_forward_provider_keeps_two_slots_of_one_upstream(self) -> None:
        rows = self.result["forwardRepeatedProvider"]
        for name, upstream, middle, slots in [
            ("same", 1901, 1903, ["vector:0:2=1901", "vector:0:5=1901"]),
            ("renamed", 2901, 2903, ["omega:2:1=2901", "omega:2:6=2901"]),
        ]:
            with self.subTest(variant=name):
                row = rows[name]
                self.assertEqual(row["candidateCount"], 1)
                self.assertEqual(row["consumerProvider"], middle)
                self.assertEqual(row["middleBindings"], slots)
                self.assertEqual(row["middleProviders"], [upstream, upstream])
                self.assertEqual(row["requiredProviders"], [upstream, middle])
                self.assertEqual(row["forwardOrder"], [upstream, middle])
        for name in ["twoProviders", "secondary", "self", "background", "visible"]:
            with self.subTest(rejected=name):
                self.assertEqual(rows[name]["candidateCount"], 0)
                self.assertEqual(rows[name]["consumerProvider"], -1)
        self.assertFalse(rows["foreignConsumerAccepted"])

    def test_definition_material_candidates_keep_effective_pass_identity(self) -> None:
        # These are potential source carriers. Actual Program selection and
        # pixel contribution belong to the GraphExecutor/App gates.
        self.assertEqual(self.result["definitionMaterialProviders"]["passes"], [
            {"overridden": False, "passes": [0, 2], "slots": [2, 2],
             "providers": [1601, 1601], "effects": ["definition-shared"] * 2,
             "requiresProgram": [True] * 2},
            {"overridden": True, "passes": [0, 0, 1, 1], "slots": [2] * 4,
             "providers": [1601, 1602, 1601, 1602], "effects": ["instance-override"] * 4,
             "requiresProgram": [True] * 4},
        ])

    def test_definition_forward_provider_keeps_background_phase_boundary(self) -> None:
        self.assertEqual(self.result["definitionMaterialProviders"]["forward"], [
            {"readsBackground": False, "declaresDependency": True,
             "frontProviders": [1710], "frontForward": [True], "frontKinds": ["imageLayerBlend"],
             "hiddenProviders": [1720], "hiddenKinds": ["imageLayerBlend"]},
            {"readsBackground": False, "declaresDependency": False,
             "frontProviders": [1710], "frontForward": [True], "frontKinds": ["imageLayerBlend"],
             "hiddenProviders": [1720], "hiddenKinds": ["imageLayerBlend"]},
            {"readsBackground": True, "declaresDependency": True,
             "frontProviders": [], "frontForward": [], "frontKinds": [],
             "hiddenProviders": [1720], "hiddenKinds": ["imageLayerBlend"]},
            {"readsBackground": True, "declaresDependency": False,
             "frontProviders": [], "frontForward": [], "frontKinds": [],
             "hiddenProviders": [1720], "hiddenKinds": ["imageLayerBlend"]},
        ])

    def test_multi_provider_cold_plan_preserves_authored_binding_order(self) -> None:
        self.assertEqual(self.result["multiProviderCandidate"], {
            "candidate": True,
            "aggregate": {"providers": [601, 602], "slots": ["first:0:1", "second:0:1"]},
            "authoredSlots": ["z-authored-first:0:1", "a-authored-second:0:1"],
            "requiredProviders": [601, 602], "requiredEffect": True,
        })
        self.assertEqual(self.result["multiProviderRejects"], {
            "duplicateSlot": True,
            "missingProviderOrder": True, "missingConsumerOrder": True,
            "visibleEffectfulProvider": True,
            "forwardSafeProvider": True, "forwardUnsafeProvider": True,
            "forwardVisibleEffectfulGeometryProvider": True,
        })
        # Cold carriers still require a Program. Consumer dependency metadata
        # and provider visibility do not replace its actual resource interface.
        self.assertEqual(self.result["multiProviderColdCarriers"], {
            "rawParentProviderSlots": ["first:0:1", "second:0:1"],
            "declaredSubsetSlots": ["first:0:1", "second:0:1"],
            "declaredSubsetProviders": [601, 602],
            "declaredSubsetRequiresProgram": [True, True],
            "visibleProviderSlots": ["first:0:1", "second:0:1"],
            "visibleProviderKinds": ["imageLayerBlend", "imageLayerBlend"],
            "visibleProviderRequiresProgram": [True, True],
        })

    def test_raw_named_parent_is_its_own_source_without_transform_child_cycles(self) -> None:
        rows = self.result["rawNamedParents"]
        for mode, slots in (("ordinary", [2, 5]), ("renamed", [3, 6])):
            row = rows[mode]
            parent = row["parent"]
            self.assertEqual(row, {"parent": parent, "childCandidateCount": 1,
                "externalCandidateCount": 2, "childProviders": [parent],
                "externalProviders": [parent, parent], "externalSlots": slots,
                "kinds": ["imageLayerBlend"] * 3, "requiredProviders": [parent],
                "graphProviders": [], "cycles": []})
        for mode in ("secondary", "effectful", "utility", "shaderCycle"):
            row = rows[mode]
            self.assertEqual(row["childProviders"], [], row)
            self.assertEqual(row["externalProviders"], [], row)
        self.assertEqual(rows["shaderCycle"]["cycles"], [2310, 2311])

    def test_geometry_and_nested_providers_keep_actual_order_and_demand(self) -> None:
        self.assertEqual(self.result["multiProviderGeometry"], {
            "providers": [601, 602], "kinds": ["geometryLayer", "imageLayerBlend"],
            "slots": ["first:0:1", "second:0:1"],
        })
        self.assertEqual(self.result["nestedGeometryAggregate"], {
            "nestedBindingKind": "geometryLayer", "nestedRequiresProgram": True,
            "aggregateProviders": [702, 701], "aggregateKinds": ["imageLayerBlend", "geometryLayer"],
            "requiredProviders": [700, 701, 702], "graphProviders": [700, 701], "issues": [],
        })
        self.assertEqual(self.result["multiProviderInactiveSuperset"], {
            "candidate": True,
            "references": [{"provider": 601, "slot": "first:0:1"}, {"provider": 602, "slot": "second:0:1"}],
            "aggregate": {"providers": [601, 602], "slots": ["first:0:1", "second:0:1"]},
            "requiredProviders": [601, 602], "declaredProviders": [601, 602, 604],
        })

    def test_prepared_solid_and_image_vectors_use_exact_active_slots(self) -> None:
        # Typed preparation input only; Program compilation and per-input
        # contribution are exercised by the separate GPU/App gates.
        rows = self.result["preparedNamedInputs"]
        for kind in ("solid", "image"):
            for layout, expected in (
                ("SameEffect", ["z-first:0:2=901", "z-first:0:5=902"]),
                ("AcrossEffects", ["z-first:0:2=901", "a-second:1:5=902"]),
            ):
                with self.subTest(kind=kind, layout=layout):
                    row = rows[kind + layout]
                    self.assertEqual(row["bindings"], expected)
                    self.assertEqual(row["requiredProviders"], [901, 902])
                    self.assertEqual(row["referenceProviders"], [901, 902])
                    self.assertFalse(row["single"])
                    self.assertTrue(row["aggregate"] and row["requiresProgram"])
                    self.assertEqual(row["forward"], [False, False])
                    self.assertEqual(row["issues"], [])

    def test_same_provider_repeated_slots_and_renamed_inputs_keep_identity(self) -> None:
        rows = self.result["preparedNamedInputs"]
        same = rows["sameProvider"]
        self.assertEqual(same["bindings"], ["one:1:2=901", "one:1:5=901"])
        self.assertTrue(same["aggregate"])
        self.assertEqual(same["requiredProviders"], [901])
        self.assertEqual(same["referenceProviders"], [901])
        renamed = rows["renamed"]
        self.assertEqual(renamed["bindings"], ["sun:1:2=1701", "moon:0:5=1702"])
        self.assertEqual(renamed["requiredProviders"], [1701, 1702])
        self.assertTrue(renamed["requiresProgram"])
        self.assertEqual(renamed["issues"], [])

    def test_prepared_empty_and_partial_keys_do_not_revive_dead_descriptor_slots(self) -> None:
        rows = self.result["preparedNamedInputs"]
        empty = rows["emptyPrepared"]
        self.assertEqual(empty["bindings"], [])
        self.assertEqual(empty["requiredProviders"], [])
        self.assertEqual(empty["referenceProviders"], [])
        self.assertFalse(empty["requiresEffect"])
        self.assertEqual(empty["issues"], [])
        self_input = rows["emptyPreparedSelf"]
        self.assertEqual(self_input["bindings"], [])
        self.assertEqual(self_input["requiredProviders"], [])
        self.assertFalse(self_input["requiresEffect"])
        # Graph previous retains its self reference without external demand.
        self.assertEqual(self_input["referenceProviders"], [903])
        self.assertEqual(self_input["issues"], [])
        active = rows["oneActive"]
        self.assertEqual(active["bindings"], ["z-first:0:2=901"])
        self.assertTrue(active["single"])
        self.assertFalse(active["aggregate"])
        self.assertEqual(active["requiredProviders"], [901])
        self.assertEqual(active["referenceProviders"], [901])
        self.assertEqual(active["issues"], [])
        # An absent key remains the cold candidate path; an explicit empty
        # vector above is the prepared Program's zero-dependency fact.
        cold = rows["cold"]
        self.assertEqual(cold["bindings"], ["z-first:0:2=901", "z-first:0:5=902"])
        self.assertEqual(cold["requiredProviders"], [901, 902])
        self.assertTrue(cold["requiresProgram"])

    def test_prepared_visibility_and_existing_external_boundaries_remain_distinct(self) -> None:
        rows = self.result["preparedNamedInputs"]
        self.assertEqual(rows["hidden"]["execution"], [])
        self.assertEqual(rows["forward"]["forward"], [True, True])
        self.assertEqual(rows["forward"]["requiredProviders"], [901, 902])
        self.assertIn("missingProvider", rows["missingCold"]["issues"])
        self.assertEqual(rows["secondaryCold"]["bindings"], [])

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

    def test_prepared_forward_cycle_keeps_healthy_forward_provider(self) -> None:
        row = self.result["preparedForwardCycle"]
        self.assertEqual(row["candidateProviders"], [110, 120, 110, 210])
        self.assertEqual(row["candidateForward"], [True, True, False, True])
        self.assertEqual(row["cycles"], [110, 120])
        self.assertEqual(row["requiredProviders"], [210])
        self.assertEqual(row["graphProviders"], [])
        self.assertTrue(row["consumerBindingRetained"])
        self.assertEqual(row["activeExecution"], [100, 200])
        self.assertEqual(row["cycleOnlyForward"], [])
        self.assertEqual(row["withHealthyForward"], [210])

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

    def test_named_source_cuts_keep_early_misses_and_later_supply_separate(self) -> None:
        for suffix, base in (("", 1300), ("Renamed", 2300)):
            o, u, c, p, d = range(base, base + 5)
            expected = {
                "prefix": ([o, p, c], [], {str(c): [p]}, [p]),
                "earlyLate": ([c, p, d], [], {}, []),
                "visibleDeadline": ([p, d], [], {}, []),
                "independent": ([p, o, c], [u, p], {}, [p]),
                "inactive": ([p, c, d], [p], {}, [p]),
                "sameProviderActiveSlot": ([c, p, d], [], {}, []),
            }
            for mode, (preparation, prepass, before, scheduled) in expected.items():
                with self.subTest(mode=mode, renamed=bool(suffix)):
                    self.assertEqual(self.result["sourceTiming"][mode + suffix], {
                        "preparation": preparation, "prepass": prepass,
                        "before": before, "scheduled": scheduled, "providers": [u, p],
                    })

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
            "parentOwnSource": {"provider": 300, "slot": 1, "kind": "imageLayerBlend"},
            "dependenciesRejected": True,
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
                "prepared": [300, 301],
                "duplicateRejected": True,
            },
        )
        self.assertEqual(
            self.result["forwardStaticPreparationOrder"],
            {
                "authored": [800, 301, 850, 300, 900],
                "prepared": [301],
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
        self.assertEqual(self.result["forwardParentOwnSource"],
            {"provider": 300, "slot": 1, "kind": "imageLayerBlend", "forward": True})
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
                "prepared": [400, 401, 402],
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
