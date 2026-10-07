#!/usr/bin/env python3

"""R4 resolved-material bridge, submission, and resource contracts."""

from __future__ import annotations

from script.tests.source_family import read_source_family
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.scene_dependency_binding_test_support import (
    SCENE_DEPENDENCY_BINDING_SUPPORT,
)


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
RUNTIME_CATALOG = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialRuntimeCatalog.swift"
)
RUNTIME_BRIDGE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialRuntimeBridge.swift"
)
ASSET_CATALOG = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneMaterialAssetTextureCatalog.swift"
)
LAUNCH = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Launch.swift"
TEXTURE_FRAME = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+TextureFrame.swift"
COMPOSITOR = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayerCompositor.swift"
CAPABILITY_STAGES = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+Stages.swift"
)
LAYER_SOURCE_PASSTHROUGH_PLAN = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneLayerSourcePassthroughPlan.swift"
)
GRAPH_COMPOSITION = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneResolvedMaterialGraphComposition.swift"
)
RENDERER_DIAGNOSTICS = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+Diagnostics.swift"
)
RENDERER_EXECUTION_EVIDENCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+ExecutionEvidence.swift"
)
FRAME_PREFLIGHT = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneResolvedMaterialFramePreflight.swift"
)
TARGET_ALLOCATOR = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/ScenePersistentGraphTargetAllocator.swift"
)
TARGET_CACHE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTextureAllocationCache.swift"
)
TARGET_SHARED_PAIR = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTextureAllocationCache+SharedPair.swift"
)
TARGET_BATCH = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTextureAllocationCache+Batch.swift"
)
TARGET_PREFLIGHT = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTexturePool+PersistentGraphTargets.swift"
)
OFFSCREEN_RESOLUTION_POLICY = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenResolutionPolicy.swift"
)
DRAW_REQUEST = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayerDrawRequest.swift"
UTILITY_FRAME_RENDERER = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityPlanFrameRenderer.swift"
)
METAL_RENDERER = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift"
METAL_RENDERER_DEPENDENCY_PROVIDERS = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+DependencyProviders.swift"
)
METAL_VIEW_FRAME_CONTEXT = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView+FrameContext.swift"
)
METAL_VIEW = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView.swift"
TEXT_TEXTURE_LOADER = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Text/SceneTextTextureLoader.swift"
HOST = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost.swift"
DEBUG_RUNNER = REPOSITORY_ROOT / "MyWallpaperX/App/Debug/DebugScenePlaybackRunner.swift"
DEBUG_SCENE_SWITCH_RUNNER = (
    REPOSITORY_ROOT
    / "MyWallpaperX/App/Debug/DebugScenePlaybackRunner+SceneSwitch.swift"
)
DEBUG_SURFACE_STOP_RELAUNCH_RUNNER = (
    REPOSITORY_ROOT
    / "MyWallpaperX/App/Debug/DebugScenePlaybackRunner+SurfaceStopRelaunch.swift"
)
DEBUG_PAUSE_RESUME_RUNNER = (
    REPOSITORY_ROOT
    / "MyWallpaperX/App/Debug/DebugScenePlaybackRunner+PauseResume.swift"
)
HOST_FRAME_DRIVER = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift"
)
HOST_SURFACE_TEARDOWN = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfaceTeardown.swift"
)
SUBMISSION_COORDINATOR = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator.swift"
)
SUBMISSION_COMPLETION = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator+Completion.swift"
)
SUBMISSION_LIFECYCLE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator+Lifecycle.swift"
)
SUBMISSION_FRAME_COMMIT = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator+FrameCommit.swift"
)
SUBMISSION_EXECUTION = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator+Execution.swift"
)
GRAPH_OBSERVATION = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneGraphExecutionObservation.swift"
GRAPH_TELEMETRY = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneGraphExecutionTelemetry.swift"
GRAPH_OBSERVATION_BUILDER = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphObservationBuilder.swift"
)
REAL_RESOURCE_PHASE_SWIFT_SOURCES = [
    SCENE_ROOT / "Rendering/Graph/SceneResolvedMaterialFrameResourceBundle.swift",
    SCENE_ROOT / "Rendering/Targets/SceneOffscreenTextureAllocationCache+PreparationAdmission.swift",
]
# The legacy one-phase fixture uses a nil-only, trap-on-new-phase adapter.
# Real pool/target fixtures add REAL_RESOURCE_PHASE_SWIFT_SOURCES instead.
RESOURCE_PHASE_UNAVAILABLE_SUPPORT = (
    Path(__file__).with_name("fixtures") / "SceneFrameResourcePhaseUnavailable.swift"
).read_text(encoding="utf-8")
RESOURCE_PHASE_UNAVAILABLE_HANDLE_SUPPORT = RESOURCE_PHASE_UNAVAILABLE_SUPPORT.split(
    "// COORDINATOR_RESOURCE_PHASE_UNAVAILABLE", 1
)[0]
SUBMISSION_SWIFT_SOURCES = [
    SCENE_ROOT / "Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator+SceneColor.swift",
    GRAPH_OBSERVATION,
    GRAPH_TELEMETRY,
    GRAPH_OBSERVATION_BUILDER,
    OFFSCREEN_RESOLUTION_POLICY,
    # Lighting is an opaque carried leaf in this coordinator-only fixture.
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/ScenePerformanceCounterHub.swift",
    RUNTIME_BRIDGE,
    SUBMISSION_COORDINATOR,
    SUBMISSION_LIFECYCLE,
    SUBMISSION_COMPLETION,
    SUBMISSION_FRAME_COMMIT,
    SUBMISSION_EXECUTION,
    SCENE_ROOT / "Rendering/Composition/SceneMainPassEncoder.swift",
]
COMPOSITOR_UNIFORMS = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayerCompositor+Uniforms.swift"
)
BASE_IMAGE_TEXTURE_CANDIDATE_SUPPORT = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneBaseImageTextureCandidateSupport.swift"
)
TEXTURE_CANDIDATE_TYPES = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureCandidate.swift"
)
TEXTURE_UV_TRANSFORM = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift"
)
TEXTURE_SAMPLING_TYPES = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift"
)
STATIC_SOURCE_DRAW_ONLY_SOURCES = [
    SCENE_ROOT / "Rendering/Composition/SceneFramebufferSnapshot.swift",
    SCENE_ROOT / "Resources/Textures/SceneResourceBudget.swift",
    SCENE_ROOT / "Diagnostics/ScenePerformanceCounterHub.swift",
    SCENE_ROOT / "Diagnostics/SceneGPUCensus.swift",
    LAYER_SOURCE_PASSTHROUGH_PLAN,
    DRAW_REQUEST,
    COMPOSITOR,
    COMPOSITOR_UNIFORMS,
    GRAPH_COMPOSITION,
    BASE_IMAGE_TEXTURE_CANDIDATE_SUPPORT,
    TEXTURE_CANDIDATE_TYPES,
    TEXTURE_UV_TRANSFORM,
    TEXTURE_SAMPLING_TYPES,
]


ASSET_HARNESS = (
    Path(__file__).with_name("fixtures") / "SceneAssetCatalogHarness.swift"
).read_text(encoding="utf-8")


VFS_SUPPORT = (
    Path(__file__).with_name("fixtures") / "SceneTextureVFSSupport.swift"
).read_text(encoding="utf-8")


SUBMISSION_COORDINATOR_FIXTURE = "\n".join(
    (Path(__file__).with_name("fixtures") / name).read_text(encoding="utf-8")
    for name in (
        "SceneSubmissionCoordinatorDependencies.swift",
        "SceneSubmissionTerminalReplayChecks.swift",
        "SceneSubmissionScenarioInputs.swift",
        "SceneSubmissionAdmissionChecks.swift",
        "SceneSubmissionPublicationChecks.swift",
        "SceneSubmissionAtomicPreparationChecks.swift",
        "SceneSubmissionRuntimeBridgeChecks.swift",
        "SceneSubmissionLifecycleChecks.swift",
        "SceneSubmissionCoordinatorMain.swift",
    )
) + SCENE_DEPENDENCY_BINDING_SUPPORT + RESOURCE_PHASE_UNAVAILABLE_SUPPORT


STATIC_SOURCE_DRAW_ONLY_HARNESS = (
    REPOSITORY_ROOT / "script/tests/fixtures/SceneStaticSourceDrawOnlyHarness.swift"
).read_text(encoding="utf-8") + RESOURCE_PHASE_UNAVAILABLE_HANDLE_SUPPORT


class SceneResolvedMaterialRuntimeBridgeTests(unittest.TestCase):
    def test_typed_data_attachment_preserves_target_format(self) -> None:
        from script.tests.test_scene_wallpaper_async_launch import function_body
        body = function_body(CAPABILITY_STAGES.read_text(), "private static func attachment(")
        harness = (
            Path(__file__).with_name("fixtures") / "SceneTypedDataAttachmentHarness.swift"
        ).read_text(encoding="utf-8").replace("__BODY__", body)
        with tempfile.TemporaryDirectory(prefix="mwx-data-attachment-") as directory:
            root = Path(directory)
            source = root / "main.swift"
            source.write_text(harness)
            built = subprocess.run(["xcrun", "swiftc", str(source), "-o", str(root / "run")],
                                   capture_output=True, text=True, timeout=60)
            self.assertEqual(built.returncode, 0, built.stderr)
            ran = subprocess.run([str(root / "run")], capture_output=True, text=True, timeout=10)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)

    def test_preview_and_inline_reporting_only_describe_typed_execution_owners(self) -> None:
        diagnostics = RENDERER_DIAGNOSTICS.read_text(encoding="utf-8")
        view = METAL_VIEW.read_text(encoding="utf-8")
        text_loader = TEXT_TEXTURE_LOADER.read_text(encoding="utf-8")

        self.assertIn("effect runtime resolved-material", diagnostics)
        self.assertIn("resolvedMaterialExecutionLayerIDs", diagnostics)
        self.assertNotIn("if executionStageCount > 1", diagnostics)
        self.assertNotIn("SceneEffectRuntimePlanner", diagnostics)
        self.assertIn("return nil", diagnostics)

        self.assertIn(
            "effectSummary: { [renderer] in renderer.effectRuntimeSummary(for: $0) }",
            view,
        )
        self.assertIn(
            "effectSummary: (SceneRenderDescriptor.Layer) -> String? = { _ in nil }",
            text_loader,
        )
        self.assertNotIn("SceneEffectRuntimePlanner.runtimeSummary", text_loader)
        self.assertNotIn("legacyEffectRuntimeExcludedLayerIDs", view + text_loader)

    def test_resource_demands_share_schema_and_never_guess_regular_assets(self) -> None:
        source = RUNTIME_CATALOG.read_text(encoding="utf-8")
        self.assertIn(
            "SceneResolvedMaterialShaderSchema.reachableSamplers",
            source,
        )
        self.assertIn("SceneResolvedMaterialTextureSlotPurpose", source)
        self.assertIn("userPropertyDemands", source)
        self.assertIn("systemProviderDemands", source)
        self.assertIn("sampler-schema-unavailable", source)
        self.assertIn("texture-purpose-unproven", source)
        self.assertIn("sampler=\\(samplerName)", source)
        self.assertIn("mode=\\(samplerMode)", source)
        self.assertIn("material=\\(materialKey)", source)
        self.assertIn("default=\\(defaultTexture)", source)
        self.assertNotIn("purpose: .premultipliedColor", source)
        self.assertIn("slot.candidates.indices.reversed()", source)
        self.assertIn("if case .graph = candidate.reference", source)
        self.assertIn("return (slot, candidates, false)", source)
        self.assertIn("guard projection.reachesDefault", source)

    def test_asset_catalog_is_eager_exact_and_fail_closed(self) -> None:
        source = ASSET_CATALOG.read_text(encoding="utf-8")
        self.assertIn("SceneTexturePathResolver", source)
        self.assertIn("resolveTextureFile(named: identity.path.value)", source)
        self.assertIn("purpose: identity.purpose", source)
        self.assertIn("requestIdentity: request", source)
        self.assertIn("loaded[identity] = .absent", source)
        self.assertIn("loaded[identity] = .unavailable", source)
        self.assertIn("private let staticStates:", source)
        self.assertIn("private let animatedDefinitions:", source)
        self.assertIn("func makeFrameProvider() -> FrameProvider", source)
        self.assertNotIn("sampleID", source)

    def test_claimed_route_is_current_and_all_post_claim_failures_close(self) -> None:
        composition = GRAPH_COMPOSITION.read_text(encoding="utf-8")
        diagnostics = RENDERER_DIAGNOSTICS.read_text(encoding="utf-8")
        frame_preflight = FRAME_PREFLIGHT.read_text(encoding="utf-8")
        compositor = COMPOSITOR.read_text(encoding="utf-8")
        passthrough_plan = LAYER_SOURCE_PASSTHROUGH_PLAN.read_text(
            encoding="utf-8"
        )
        bridge = RUNTIME_BRIDGE.read_text(encoding="utf-8")
        metal_renderer = read_source_family(METAL_RENDERER)
        execution_evidence = RENDERER_EXECUTION_EVIDENCE.read_text(
            encoding="utf-8"
        )
        metal_renderer_dependency_providers = (
            METAL_RENDERER_DEPENDENCY_PROVIDERS.read_text(encoding="utf-8")
        )

        self.assertIn("static func executeClaimed(", composition)
        # Target sizing/reservation moved into the single preflight walk
        # (FrameTargetRequest lane deleted); the pool wiring assertions follow
        # the walk in FRAME_PREFLIGHT.
        self.assertIn("func preflightResolvedMaterialFrameTargets(", frame_preflight)
        self.assertIn("admittedGraphs: claim.admittedGraphs", frame_preflight)
        self.assertIn("pairPlan: claim.pairPlan", frame_preflight)
        self.assertIn("preflightPersistentGraphTargets(", frame_preflight)
        self.assertIn("framePlan.token == claim.token", composition)
        self.assertIn(
            "for subject in runtime.executionEvidenceSubjects(for: claim)",
            composition,
        )
        self.assertNotIn("exactEffectSubjects", bridge)
        self.assertIn("runtime.executionEvidenceFamily(for: subject.key)", composition)
        self.assertIn(
            "?? subject.family",
            composition,
        )
        self.assertIn("let dispositionCatalog =", diagnostics)
        self.assertEqual(diagnostics.count("SceneEffectRuntimeDispositionCatalog("), 1)
        self.assertNotIn("installExecutionEvidence(", diagnostics)
        self.assertIn("resolvedMaterialSubjects:", diagnostics)
        self.assertIn("let dispositionCatalog =", execution_evidence)
        self.assertIn("installExecutionEvidence(", execution_evidence)
        self.assertIn("resolvedMaterialSubjects:", execution_evidence)
        self.assertIn("runtimeDispositionSubjects", diagnostics)
        self.assertIn(
            "dispositionCatalog.resolvedMaterialExecutionEvidenceSubjects",
            execution_evidence,
        )
        self.assertIn('backend: "resolved-material-graph"', composition)
        self.assertNotIn("authored-effect-graph", composition)
        self.assertIn(
            'runtime.recordClaimedFailure(\n'
            '                reasonCode: "frame-target-plan-consumption-failed"',
            composition,
        )
        self.assertNotIn("SceneEffectStageRenderer", composition)
        self.assertIn(
            "let resolvedMaterialRoute = resolvedMaterialClaim(for: request)",
            compositor,
        )
        self.assertIn(
            "guard !resolvedMaterialRoute.isRejected else { return .failed }",
            compositor,
        )
        self.assertIn(
            "request.resolvedMaterialFrameTargetPlan == nil",
            passthrough_plan,
        )
        self.assertIn("route.allowsLayerSourcePassthrough", passthrough_plan)
        self.assertIn(
            "SceneLayerColorBlendRenderer.supports(", passthrough_plan
        )
        self.assertNotIn("layerStyleNonneutral", passthrough_plan)
        self.assertNotIn("layerBlendNonneutral", passthrough_plan)
        self.assertNotIn("staticPuppet", passthrough_plan)
        self.assertNotIn("provider(.puppet", passthrough_plan)
        self.assertIn("request.dependencyEffects.isEmpty", passthrough_plan)
        self.assertIn("!request.requiresDependencyEffect", passthrough_plan)
        self.assertIn(
            "SceneLayerVisibility.hasCurrentSourceDisplayAuthority(",
            passthrough_plan,
        )
        self.assertNotIn(
            "request.layer.displayScriptOwnership?.isEmpty", passthrough_plan
        )
        self.assertNotIn("request.layer.visible != false", passthrough_plan)
        self.assertIn(
            "let passthroughResolution = SceneLayerSourcePassthroughPlan.resolve(",
            compositor,
        )
        self.assertIn(
            "if bypassReason != nil {\n"
            "            return ([], nil)",
            metal_renderer_dependency_providers,
        )
        self.assertIn("enum RejectionReason: String, Error", passthrough_plan)
        self.assertIn("unclaimed-visible-effects-\\(reason.rawValue)", compositor)
        fallback_start = compositor.index(
            "if case let .success(passthroughPlan) = passthroughResolution"
        )
        fallback_end = compositor.index(
            "guard !hasUnclaimedVisibleEffects else", fallback_start
        )
        source_passthrough = compositor[fallback_start:fallback_end]
        self.assertIn("route: resolvedMaterialRoute", compositor)
        self.assertIn(
            "return encoded ? .layerSourcePassthrough : .failed",
            source_passthrough,
        )
        self.assertIn("drawLayerSourcePassthrough(", source_passthrough)
        fallback_renderer = compositor[compositor.index(
            "private func drawLayerSourcePassthrough("
        ):compositor.index("func executeResolvedMaterialClaim(")]
        self.assertIn("sourceFragmentUniforms(", fallback_renderer)
        self.assertIn("textureFrame: plan.source.uvTransform", fallback_renderer)
        self.assertIn("sampling: plan.source.sampling", fallback_renderer)
        self.assertIn("SceneOffscreenEffectRenderer.captureSource(", fallback_renderer)
        self.assertIn("colorBlendPipelineSlot.resolve()", fallback_renderer)
        self.assertIn("alpha: 1", fallback_renderer)
        self.assertNotIn(
            ".normal(consumedDependency:",
            source_passthrough,
        )
        self.assertIn("case .notMigrated:\n            return .unclaimed", composition)
        self.assertIn("case rejected(reasonCode: String)", composition)
        self.assertIn("switch route {", frame_preflight)
        self.assertIn(
            "case let .rejected(reasonCode):\n"
            "                return .rejected(reasonCode: reasonCode)",
            frame_preflight,
        )
        self.assertNotIn(
            "guard let claim = route.execution else { continue }",
            frame_preflight,
        )
        self.assertIn(
            "resolvedMaterialRuntime.recordClaimedFailure(reasonCode: reasonCode)",
            composition,
        )
        self.assertIn("func rejectResolvedMaterialClaim(", composition)
        self.assertIn(
            "resolvedMaterialRuntime?.recordClaimedFailure(reasonCode: reasonCode)",
            composition,
        )
        self.assertGreaterEqual(
            compositor.count("rejectResolvedMaterialClaim(resolvedMaterialClaim"),
            7,
        )
        self.assertIn("case .failed:\n                    return .failed", compositor)
        self.assertIn("switch resolvedMaterialRuntime.markComposite(", composition)
        self.assertIn("case let .failed(reasonCode):", composition)
        self.assertIn('operation: "final-composite"', composition)
        self.assertIn("consumeResolvedMaterialComposite(", compositor)
        self.assertIn("return .failed", compositor)

        publication_failure_start = compositor.index(
            "switch publicationResult {"
        )
        data_provider_start = compositor.index(
            "if let graphExecutionTicket,\n"
            "               graphExecutionTicket.finalContent == .data {",
            publication_failure_start,
        )
        publication_failure = compositor[
            publication_failure_start:data_provider_start
        ]
        self.assertIn("case .published:", publication_failure)
        self.assertIn("graphOutputPublished = true", publication_failure)
        unavailable_start = publication_failure.index(
            "case let .unavailable(reasonCode):"
        )
        invalid_start = publication_failure.index(
            "case let .invalid(reasonCode):"
        )
        unavailable_branch = publication_failure[
            unavailable_start:invalid_start
        ]
        invalid_branch = publication_failure[invalid_start:]
        self.assertIn(
            "guard graphExecutionTicket.finalContent != .data else {",
            unavailable_branch,
        )
        self.assertIn("published: false", unavailable_branch)
        self.assertNotIn(
            "consumeResolvedMaterialComposite(",
            unavailable_branch,
        )
        self.assertIn("published: false", invalid_branch)
        self.assertIn("return .failed", invalid_branch)
        self.assertNotIn(
            "consumeResolvedMaterialComposite(",
            invalid_branch,
        )
        data_provider_path = compositor[
            data_provider_start:compositor.index(
                "let finalValues = SceneImageLayerUniformValues(",
                data_provider_start,
            )
        ]
        self.assertIn("graphOutputPublished,", data_provider_path)
        self.assertIn("return .failed", data_provider_path)
        visible_color_path = compositor[
            compositor.index(
                "let finalValues = SceneImageLayerUniformValues(",
                data_provider_start,
            ):compositor.index(
                "return request.geometryProduct == nil",
                data_provider_start,
            )
        ]
        self.assertIn("SceneImageLayerMainPassRenderer.draw(", visible_color_path)
        self.assertIn("consumeResolvedMaterialComposite(", visible_color_path)

    @unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
    def test_static_source_draw_only_degradation_rescues_only_graph_role(
        self,
    ) -> None:
        """Static-source draw-only degradation (docs/scene/capabilities/
        static-source-draw-only-degradation.md §3.4): the unpublished draw
        rescue applies only when the passthrough plan's sole failing guard is
        the static-source graph role, with the request-side texture atom
        resolvable; every other guard and the flag-off behavior stay verbatim.
        """
        with tempfile.TemporaryDirectory(
            prefix="mwx-static-source-draw-only-"
        ) as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            harness.write_text(
                STATIC_SOURCE_DRAW_ONLY_HARNESS, encoding="utf-8"
            )

            def compile_and_run(sources: list[Path], name: str) -> dict:
                binary = root / name
                compilation = subprocess.run(
                    [
                        "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                        *(str(source) for source in sources), str(harness),
                        "-framework", "Metal", "-module-cache-path",
                        str(root / "module-cache"), "-o", str(binary),
                    ],
                    capture_output=True, text=True, timeout=300,
                )
                self.assertEqual(compilation.returncode, 0, compilation.stderr)
                completed = subprocess.run(
                    [str(binary)], capture_output=True, text=True, timeout=60,
                )
                self.assertEqual(
                    completed.returncode, 0, completed.stdout + completed.stderr
                )
                return json.loads(completed.stdout)

            result = compile_and_run(STATIC_SOURCE_DRAW_ONLY_SOURCES, "production")
            if not result["metalAvailable"]:
                self.skipTest("Metal device unavailable")
            self.assertTrue(result["litCaptureFailureKeepsAuthoredUniforms"],
                "capture failure lost authored alpha/tint/sprite UV: " + str(result))
            self.assertEqual(
                result,
                {
                    "metalAvailable": True,
                    "snapshotCapacityCommitsAndRollsBack": True,
                    "litCaptureFailureKeepsAuthoredUniforms": True,
                    "litCaptureRecoveryUsesCapturedTexture": True,
                    "degradedPlanBuilt": True,
                    "degradedPlanDrawsRequestTexture": True,
                    "degradedPlanKeepsStaticFileAtom": True,
                    "degradedPlanCarriesLayerSourceIdentity": True,
                    "degradedPlanKeepsResolvedSample": True,
                    "degradedPlanContentMirrorsRequestCandidate": True,
                    "degradedPlanGeometryDrawable": True,
                    "graphPublicationActiveBuildsNormalPlan": True,
                    "flagOffKeepsGraphRoleRejection": True,
                    "flagOnBlendGuardUnaffected": True,
                    "flagOnTextureFrameGuardUnaffected": True,
                    "compositorDegradedEncoded": True,
                    "compositorDegradedDrewRequestBaseTexture": True,
                    "compositorDegradedTraceOperation": True,
                    "compositorFlagOffFails": True,
                    "compositorFlagOffTraceReason": True,
                },
            )

            # Mutate only an isolated product copy. The exact edit is a fault
            # injection precondition; the pass/fail oracle is actual texture
            # identity after completed Metal captures, not source shape.
            snapshot_source = SCENE_ROOT / "Rendering/Composition/SceneFramebufferSnapshot.swift"
            source_text = snapshot_source.read_text(encoding="utf-8")
            fault = "            texture = previous\n"
            if source_text.count(fault) != 1:
                self.fail("texture rollback fault injection must match exactly once")
            mutated_source = root / "SceneFramebufferSnapshotWithoutTextureRollback.swift"
            mutated_source.write_text(source_text.replace(fault, ""), encoding="utf-8")
            mutated_sources = [
                mutated_source if source == snapshot_source else source
                for source in STATIC_SOURCE_DRAW_ONLY_SOURCES
            ]
            faulty_result = compile_and_run(mutated_sources, "without-texture-rollback")
            self.assertEqual(faulty_result, {
                **result, "snapshotCapacityCommitsAndRollsBack": False,
            })
            print("snapshot rollback texture identity oracle: production=PASS; "
                  "temporary product without texture restore=REJECTED; "
                  "all other observations unchanged")

    def test_external_dependency_is_late_ready_and_composited_once(self) -> None:
        bridge = RUNTIME_BRIDGE.read_text(encoding="utf-8")
        coordinator = SUBMISSION_COORDINATOR.read_text(encoding="utf-8")
        frame_commit = SUBMISSION_FRAME_COMMIT.read_text(encoding="utf-8")
        execution = SUBMISSION_EXECUTION.read_text(encoding="utf-8")
        composition = GRAPH_COMPOSITION.read_text(encoding="utf-8")
        compositor = COMPOSITOR.read_text(encoding="utf-8")

        self.assertIn(
            "let dependencyOwnership: SceneResolvedMaterialDependencyOwnership",
            bridge,
        )
        self.assertIn(
            "let consumesExternalPrimaryDependency: Bool",
            bridge,
        )
        self.assertNotIn(
            "dependencyEffect: SceneDependencyEffectInput?",
            bridge,
        )
        self.assertNotIn("let preparedDependencyEffect:", coordinator)
        self.assertNotIn("let preparedDependencyEffect:", frame_commit)

        compact_coordinator = "".join(coordinator.split())
        self.assertIn(
            "dependencyReservationMatches("
            "request.frameInputs.dependencyEffects.first,"
            "unavailability:request.frameInputs.dependencyUnavailability,"
            "ownership:claim.dependencyOwnership)",
            compact_coordinator,
        )

        compact_execution = "".join(execution.split())
        self.assertIn(
            "dependenciesMatch(preparedEffects:ledger.preparedDependencyEffects,"
            "preparedUnavailability:ledger.preparedDependencyUnavailability,"
            "readyEffects:dependencyEffects,"
            "ownership:claim.dependencyOwnership)",
            compact_execution,
        )
        for contract in (
            "input.consumerLayerID==binding.consumerLayerID",
            "input.providerLayerID==binding.providerLayerID",
            "input.variant==.primary",
            "input.slot==binding.slot",
            "input.blendMode==binding.blendMode",
            "prepared.frameEpoch==ready.frameEpoch",
            "prepared.texture===ready.texture",
        ):
            self.assertIn(contract, compact_execution)
        self.assertIn("case.solidLayer:", compact_execution)
        self.assertIn("binding.slot.passIndex==0", compact_execution)
        self.assertIn("binding.slot.slotIndex==3", compact_execution)
        self.assertIn("binding.blendMode==0", compact_execution)
        self.assertIn(
            "SceneImageLayerBlendDependencyContract.supports("
            "blendMode:binding.blendMode)",
            compact_execution,
        )
        self.assertIn(
            "binding.blendMode==0||binding.requiresResolvedMaterialProgram",
            compact_execution,
        )
        self.assertIn(
            "ifcase.externalPrimary=claim.dependencyOwnership",
            compact_execution,
        )
        self.assertIn(
            "consumesExternalPrimaryDependency:"
            "consumesExternalPrimaryDependency",
            compact_execution,
        )

        compact_composition = "".join(composition.split())
        self.assertIn(
            "dependencyEffects:request.dependencyEffects,",
            compact_composition,
        )
        self.assertIn(
            "dependencyEffects:dependencyEffects,",
            compact_composition,
        )

        compact_compositor = "".join(compositor.split())
        self.assertIn(
            "letdependencyConsumed=graphExecutionTicket?"
            ".consumesExternalPrimaryDependency==true",
            compact_compositor,
        )
        self.assertIn(
            "letdependencyEffect=request.dependencyEffects.first",
            compact_compositor,
        )
        self.assertIn(
            "dependencyBlendMode:dependencyConsumed?nil:"
            "dependencyEffect?.blendMode",
            compact_compositor,
        )
        self.assertIn(
            "letfinalDependencyTexture=dependencyConsumed?nil:"
            "dependencyEffect?.texture",
            compact_compositor,
        )
        self.assertIn("dependencyTexture:finalDependencyTexture", compact_compositor)
        self.assertNotIn("requiresDependencyEffect", bridge)
        self.assertIn("func recordClaimedFailure(reasonCode: String)", bridge)
        self.assertNotIn("recordClaimedFailure()", bridge)

    def test_resolved_material_composition_provider_reserves_from_geometry(self) -> None:
        compact = "".join(FRAME_PREFLIGHT.read_text(encoding="utf-8").split())
        resolved_start = compact.index("ifbinding.kind==.resolvedMaterial{")
        exact_source_start = compact.index(
            "letproviderSelection=cachedBaseMaterialTextureSelectionImpl(",
            resolved_start,
        )
        resolved_route = compact[resolved_start:exact_source_start]

        self.assertIn("reserveDependencyInput(nil)", resolved_route)
        self.assertNotIn("baseMaterialTextureSelection", resolved_route)
        self.assertIn(
            "guardletproviderSource=providerSelection.sourceelse{",
            compact[exact_source_start:],
        )
        self.assertIn(
            "reserveDependencyInput(providerSource)",
            compact[exact_source_start:],
        )


    def test_frame_ordering_context_reaches_reserve_and_commit(self) -> None:
        frame_preflight = FRAME_PREFLIGHT.read_text(encoding="utf-8")
        composition = GRAPH_COMPOSITION.read_text(encoding="utf-8")
        target_preflight = TARGET_PREFLIGHT.read_text(encoding="utf-8")
        allocator = TARGET_ALLOCATOR.read_text(encoding="utf-8")
        cache = TARGET_CACHE.read_text(encoding="utf-8")
        batch = TARGET_BATCH.read_text(encoding="utf-8")
        coordinator = SUBMISSION_COORDINATOR.read_text(encoding="utf-8")
        execution = SUBMISSION_EXECUTION.read_text(encoding="utf-8")

        self.assertIn("commandBuffer: commandBuffer", frame_preflight)
        self.assertIn("commandBuffer: MTLCommandBuffer", frame_preflight)
        # The single preflight walk owns ordering-context construction and the
        # pool reservation call since the request-wrapper pass was collapsed.
        self.assertIn("func preflightResolvedMaterialFrameTargets(", frame_preflight)
        self.assertIn("let orderingContext", frame_preflight)
        self.assertIn("orderingContext: orderingContext", frame_preflight)
        self.assertIn("admittedGraphs: claim.admittedGraphs", frame_preflight)
        self.assertIn("pairPlan: claim.pairPlan", frame_preflight)
        self.assertIn("preflightPersistentGraphTargets(", frame_preflight)
        self.assertIn("orderingContext: contexts.first", target_preflight)
        self.assertIn("orderingContext: orderingContext", allocator)
        self.assertIn("reservation.orderingContext", batch)
        self.assertIn("submissionPins", cache + batch)
        self.assertNotIn("submissionPins = Set<UUID>()", allocator)
        commit = coordinator.index("pool.commitAndPinPersistentGraphTargets(")
        self.assertIn(
            "commandBuffer: commandBuffer",
            coordinator[commit:],
        )
        self.assertIn("executor.encodeResult(", execution)

    def test_normal_invalidation_is_not_a_graph_failure_diagnostic(self) -> None:
        lifecycle = SUBMISSION_LIFECYCLE.read_text(encoding="utf-8")
        frame_commit = SUBMISSION_FRAME_COMMIT.read_text(encoding="utf-8")
        completion = SUBMISSION_COMPLETION.read_text(encoding="utf-8")

        self.assertIn("case .surfaceStop, .sceneSwitch:", lifecycle)
        self.assertIn(
            'emission.diagnostics.append("runtime-invalidated-\\(reason.rawValue)")',
            lifecycle,
        )
        self.assertIn("failActiveFrameLocked(reason:", lifecycle)
        self.assertIn("case cancelled", completion)
        self.assertIn(
            "case SceneGraphExecutionResetReason.surfaceStop.rawValue,",
            completion,
        )
        self.assertIn(
            "SceneGraphExecutionResetReason.sceneSwitch.rawValue:",
            completion,
        )
        self.assertNotIn("SceneGraphExecutionResetReason(rawValue:", completion)
        self.assertIn("emission.diagnostics.append(reason)", frame_commit)
        self.assertIn("emission.diagnostics.append(headReason)", completion)

    def test_observer_precedes_encoding_and_frame_uses_one_buffer(self) -> None:
        coordinator = SUBMISSION_COORDINATOR.read_text(encoding="utf-8")
        execution = SUBMISSION_EXECUTION.read_text(encoding="utf-8")
        frame_commit = SUBMISSION_FRAME_COMMIT.read_text(encoding="utf-8")
        completion = SUBMISSION_COMPLETION.read_text(encoding="utf-8")

        observer = coordinator.index("observeCommandBufferLocked(commandBuffer)")
        prepared = coordinator.index("guard case let .success(prepared)", observer)
        allocation_commit = coordinator.index(
            "pool.commitAndPinPersistentGraphTargets(", prepared
        )
        ledger = coordinator.index("activeByID[identity] = .init(", allocation_commit)
        self.assertLess(observer, prepared)
        self.assertLess(prepared, allocation_commit)
        self.assertLess(allocation_commit, ledger)
        self.assertIn("commandBuffer: commandBuffer", coordinator)
        admission = execution.index("switch admitClaimedExecutionLocked(")
        encode = execution.index("executor.encodeResult(")
        self.assertLess(admission, encode)
        self.assertIn("guard ledger.commandBuffer === commandBuffer", execution)
        self.assertIn("ledger.phase == .allocationCommitted", execution)
        self.assertIn('"prepared-frame-consumption-rejected"', execution)
        self.assertIn(
            "guard commandBuffer.status == .notEnqueued",
            frame_commit,
        )
        self.assertIn("func completeCommandBuffer(", completion)
        self.assertIn("commandBufferIdentities", completion)

    def test_terminal_seal_rejection_keeps_real_buffer_unsubmitted(self) -> None:
        # Compile the actual terminal helper and submission owner; the carrier
        # supplies app dependencies. This does not execute the full renderer.
        from script.tests.test_scene_persistent_color_output import _compile_and_run
        result = _compile_and_run("SceneTerminalSealHarness.swift")
        self.assertEqual(result["accepted"], [True, False, True])
        self.assertEqual(result["beforeSubmit"], [True, True, True])
        self.assertEqual(result["marker"], [11, 0, 33])
        self.assertEqual(result["completed"], [True, False, True])
        self.assertEqual(result["rejection"], "resolved-material-frame-seal-rejected")


    @unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
    def test_current_submission_coordinator_lifecycle_behaviors(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-r4-submission-coordinator-"
        ) as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "submission-coordinator"
            harness.write_text(SUBMISSION_COORDINATOR_FIXTURE, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-parse-as-library",
                    *(str(source) for source in SUBMISSION_SWIFT_SOURCES),
                    str(harness),
                    "-framework",
                    "Metal",
                    "-module-cache-path",
                    str(root / "module-cache"),
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                check=True,
                capture_output=True,
                text=True,
            )
            result = json.loads(completed.stdout)
            if not result["metalAvailable"]:
                self.skipTest("Metal device unavailable")
            expected = {
                "externalDependencyExactReadyMatchIssuesTicket",
                "externalDependencyMissingReadyRejected",
                "externalDependencyWrongProviderRejected",
                "externalDependencyWrongSlotRejected",
                "externalDependencyWrongBlendRejected",
                "externalDependencyWrongEpochRejected",
                "externalDependencyWrongObjectRejected",
                "geometryDependencyExactReadyMatchIssuesTicket",
                "geometryDependencyWrongSlotRejected",
                "solidDependencyExactReadyMatchIssuesTicket",
                "solidProgramDependencySlotOneIssuesTicket",
                "solidProgramDependencyContentDriftRejected",
                "solidDependencyMissingReadyRejected",
                "solidDependencySecondaryRejected",
                "solidDependencyWrongEffectRejected",
                "solidDependencyWrongPassRejected",
                "normalInvalidateHasNoGraphDiagnostic",
                "stableHistoryAllocationClassifiesCopyOnWrite",
                "descriptorChangeClassifiesAllocationReprepare",
                "historyFreeFreshIdentityClassifiesAllocationRebind",
                "unknownHistoryTransitionRejected",
                "deviceLossInvalidateHasGraphDiagnostic",
                "executorInvalidateHasGraphDiagnostic",
                "pendingSurfaceStopCancelsSilently",
                "pendingSceneSwitchCancelsSilently",
                "allocationReprepareRemainsFailure",
                "effectReparseRemainsFailure",
                "deviceLossRemainsFailure",
                "executorInvalidationRemainsFailure",
                "unknownCancellationRemainsFailure",
                "surfaceStopGPUFailureRemainsFailure",
                "invalidSurfaceStopLedgerRemainsFailure",
                "productionObservationBuilderSuccess",
                "productionObservationBuilderFailure",
                "claimUsesCentralCapabilityAdmission",
                "claimCarriesGraphIdentityOnly",
                "systemProviderExplicitAbsenceSoftBlocks",
                "systemProviderInitialPreparationIsPurposeQualifiedPending",
                "systemProviderUnknownIdentityRemainsUnavailable",
                "systemProviderPurposesRemainPerConsumer",
            "systemProviderPreparedNoiseNotOverwrittenByMissingMedia",
                "uninstalledDispositionEvidenceIsNotInvoked",
                "bridgeProjectsOnlyInstalledDispositionEvidence",
                "executionEvidenceOverridesFallbackFamily",
                "missingExecutionEvidenceKeepsFallbackIsolated",
                "visualFailurePassthroughKeepsFailedTelemetry",
                "dynamicRendererPassthroughKeepsFailedTelemetry",
                "malformedExecutionEvidenceDropsOnlyInvalidKey",
                "emptyExecutionFamilyDropsOnlyInvalidKey",
                "invalidCapabilityTokenRejectsWithoutLegacyFallback",
                "typedTargetDescriptorFallbackRemainsLayerLocal",
                "pendingSourceFallbackRemainsLayerLocal",
                "preflightFailureReasonReachesCoordinatorEvidence",
                "claimWaitsForAtomicFramePreparation",
                "typedHistoryDiscardReachesPoolExactly",
                "forgedHistoryDiscardRejectedBeforePoolCommit",
                "secondPreparationFailureRollsBackWholeFrame",
                "externalDependencyCaptureFailureRejectsOnlyItsSubgraph",
                "cascadingDependencyCaptureFailureRejectsTransitiveSubgraph",
                "repeatTerminalPublicationRejectsBeforeLedgerAndPreservesPreviousCurrent",
                "preparedProviderOutputKeepsNamedReservationWithoutCompositorOwnership",
                "namedPublicationMissKeepsSuffixAndFrameLocal",
                "aggregatePublicationMissRejectsOnlyConsumer",
                "aggregateSourceUnavailableSkipsClaimAndKeepsSuffix",
                "sourceUnavailableFallbackRequiresDependencyContract",
                "twoCandidatesPublishConsumeAndCommitAtomically",
                "postClaimFailureDropsWholeFrame",
                "foreignBufferRejectedBeforePrepare",
                "ticketIsSingleConsumption",
                "invalidateDefersPinReleaseUntilTerminal",
                "aggregateBarrierWaitsForAllBuffers",
                "historyPendingDefersDescendantBeforeFramePrepare",
                "preparedFrameDeferralCancelsWithoutFailure",
                "twoPendingSubmissionsUseBoundedCapacity",
                "reverseGPUCompletionCommitsOnlyFromQueueHead",
                "historyFreeFailureDoesNotCancelIndependentSuccess",
                "sameFrameTransactionsSealAsOneSubmission",
                "aSuccessBFailureCReusesAWithoutReset",
                "freshAndInvalidatedInitialStatesKeepDistinctReasons",
            }
            self.assertEqual(set(result["results"]), expected)
            self.assertTrue(all(result["results"].values()), result)

    @unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
    def test_texture_vfs_preserves_package_loose_stock_precedence(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-r3-vfs-") as directory:
            root = Path(directory)
            package, loose, stock = root / "package", root / "loose", root / "stock"
            for path in (package, loose, stock):
                path.mkdir()
            for base in (package, loose, stock):
                (base / "materials").mkdir()
                (base / "materials/shared.png").write_bytes(b"x")
            (package / "materials/bare.png").write_bytes(b"x")
            (stock / "stock-only.png").write_bytes(b"x")
            harness = root / "Harness.swift"
            binary = root / "vfs"
            harness.write_text(VFS_SUPPORT, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc",
                    str(REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceIndex.swift"),
                    str(REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceView.swift"),
                    str(REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTexturePathResolver.swift"),
                    str(harness), "-module-cache-path", str(root / "module-cache"),
                    "-o", str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary), str(package), str(loose), str(stock)],
                check=True,
                capture_output=True,
                text=True,
            )
            result = json.loads(completed.stdout)
            self.assertTrue(Path(result["shared"]).resolve().is_relative_to(package.resolve()))
            self.assertTrue(Path(result["bare"]).resolve().is_relative_to(package.resolve()))
            self.assertTrue(Path(result["stock"]).resolve().is_relative_to(stock.resolve()))
            self.assertEqual(result["missing"], "")


if __name__ == "__main__":
    unittest.main()
