#!/usr/bin/env python3

"""Frame-driver routing assertions for generic media and cursor VM owners."""

from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
RUNTIME = SCENE / "Runtime"
SCRIPT = RUNTIME / "SceneScript"
RENDERING = SCENE / "Rendering"

HOST_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost.swift"
FRAME_DRIVER_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift"
FRAME_DRIVER_LIFECYCLE_SOURCE = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriverLifecycle.swift"
)
SURFACE_TEARDOWN_SOURCE = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfaceTeardown.swift"
)
POINTER_EVENTS_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+PointerEvents.swift"
VIEW_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView.swift"
MEDIA_COORDINATOR_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneMediaThumbnailCoordinator.swift"
CURSOR_INTERACTION_SOURCE = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView+SceneScriptCursorInteraction.swift"
)
SCALAR_RUNTIME_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptScalarRuntime.swift"
CURSOR_PROGRAM_SOURCES = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptCursorProgram.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptCursorProgram+Construction.swift",
)
CURSOR_HIT_ADMISSION_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptCursorHitAdmission.swift"
MEDIA_EVENT_BRIDGE_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptMediaEventBridge.swift"
MEDIA_FRAME_COORDINATOR_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptMediaFrameCoordinator.swift"
PROGRAM_FRAME_LEDGER_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptProgramFrameLedger.swift"
PROPERTY_INPUT_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptPropertyInput.swift"
OWNER_EFFECTS_VALIDATION_SOURCE = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptOwnerEffectsRuntimeValidation.swift"
)
LAUNCH_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Launch.swift"
LAUNCH_SCHEMA_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperLaunchFrameSchema.swift"
STARTUP_REPORT_SOURCE = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperLaunchContext+StartupReport.swift"
)
MODEL_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRuntimeModel.swift"
CANDIDATE_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptQuickJSProgramCandidate.swift"
ROUTE_CANDIDATE_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorMediaRouteCandidate.swift"
FALLBACK_CATALOG_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptFallbackCatalog.swift"
VECTOR_PROGRAM_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorProgram.swift"
LAYER_HANDLE_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLayerHandleBridge.swift"
LAYER_RUNTIME_DESCRIPTOR_SOURCE = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLayerRuntimeDescriptorBridge.swift"
)


def swift_body(source: str, signature: str) -> str:
    signature_start = source.index(signature)
    body_start = source.index("{", signature_start)
    depth = 0
    for position in range(body_start, len(source)):
        character = source[position]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[body_start + 1:position]
    raise AssertionError(f"unterminated Swift body: {signature}")


# Host all-surface rollback source checks retired with D10.
# Actual presentation/VM behavior: test_scene_frame_presentation_integration.
# GPU source ownership: test_scene_surface_submission and the FIFO harness below.
class SceneFrameVMRoutingTests(unittest.TestCase):
    def test_alpha_display_fallback_wiring_in_runtime_model(self) -> None:
        """Checkpoint wiring pin for the second-tier alpha display fallback:
        the claimed set is the union of every alpha publication path, the
        fallback runs after scalar projection, and downstream projections
        consume its output rather than the pre-fallback descriptor."""
        model = MODEL_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "let alphaClaimedTargets = sharedAlphaTargets\n"
            "            .union(projectedScalarTargets)\n"
            "            .union(timelineTargets)",
            model,
        )
        # The call site wraps across lines in the source; assert the call
        # name and the claimed-set argument as separate fragments.
        self.assertIn("applyUnclaimedFallback(", model)
        self.assertIn("claimedTargets: alphaClaimedTargets", model)
        fallback_at = model.index("fallbackProjectedDescriptor =")
        scalar_at = model.index("SceneScriptScalarDisplayProjection.apply(")
        particle_at = model.index("SceneScriptParticleProjection.apply(")
        self.assertLess(scalar_at, fallback_at)
        self.assertLess(fallback_at, particle_at)
        self.assertIn(
            "to: fallbackProjectedDescriptor\n",
            model,
        )

    def test_user_property_revision_ack_is_shared_and_restored_with_frame_state(self) -> None:
        property_input = PROPERTY_INPUT_SOURCE.read_text(encoding="utf-8")
        bridge = MEDIA_EVENT_BRIDGE_SOURCE.read_text(encoding="utf-8")
        frame = FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        self.assertIn("struct SceneScriptAppliedUserPropertyState", property_input)
        self.assertIn("revisionsByTarget", property_input)
        self.assertIn("revisionsByTarget[target] == revision", property_input)
        self.assertIn("func changedJSON(", property_input)
        self.assertIn("mutating func record(", property_input)
        self.assertIn("let appliedUserProperties: SceneScriptAppliedUserPropertyState", bridge)
        ledger = PROGRAM_FRAME_LEDGER_SOURCE.read_text(encoding="utf-8")
        # The applied-property state lives in the shared frame ledger; the
        # restore assignment is asserted there once instead of per family.
        self.assertIn("appliedUserProperties = state.appliedUserProperties", ledger)
        for source_path in (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorProgram.swift",
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptScalarProgram.swift",
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptStringProgram.swift",
        ):
            source = source_path.read_text(encoding="utf-8")
            self.assertIn("appliedUserProperties.changedJSON(", source)
            self.assertIn("appliedUserProperties.record(", source)
            self.assertIn("frameLedger", source)
            self.assertNotIn("changedUserPropertiesJSON(\n                previous:", source)
        render = swift_body(frame, "private func renderFrame()")
        self.assertIn("propertyRevision: launchContext.liveState.revision", render)

    def test_media_route_rebuilds_to_a_fresh_fixed_point_and_keeps_authored_fallbacks(
        self,
    ) -> None:
        launch = LAUNCH_SOURCE.read_text(encoding="utf-8")
        launch_schema = LAUNCH_SCHEMA_SOURCE.read_text(encoding="utf-8")
        startup_report = STARTUP_REPORT_SOURCE.read_text(encoding="utf-8")
        frame = FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        model = MODEL_SOURCE.read_text(encoding="utf-8")
        candidate = CANDIDATE_SOURCE.read_text(encoding="utf-8")
        route = ROUTE_CANDIDATE_SOURCE.read_text(encoding="utf-8")
        fallback = FALLBACK_CATALOG_SOURCE.read_text(encoding="utf-8")
        media_bridge = MEDIA_EVENT_BRIDGE_SOURCE.read_text(encoding="utf-8")

        self.assertIn(
            'static let environmentKey = "MWX_SCENE_SCRIPT_VECTOR_MEDIA_ROUTE"',
            media_bridge,
        )
        self.assertIn('case genericOnly = "generic-only"', media_bridge)
        self.assertIn('case disableGeneric = "disable-generic"', media_bridge)
        self.assertIn("guard let rawValue else { return .genericOnly }", media_bridge)
        self.assertNotIn('case observeOnly = "observe-only"', media_bridge)
        self.assertIn("targets.subtracting(mediaOwnerTargets)", media_bridge)

        self.assertIn("while let candidate = programs", route)
        self.assertIn("mediaTargets.formUnion(", route)
        self.assertIn("candidate.vectorProgram.mediaOwnerTargets", route)
        self.assertIn("initialPassTargets, mediaOwnerTargets: mediaTargets", route)
        self.assertIn("route.excludedVectorOwnerTargets(", route)
        self.assertIn("nextExcluded.isSuperset(of: excludedVectorTargets)", route)
        discard = route.index("programs = nil")
        cancellation = route.index("try cancellationCheck()")
        rebuild = route.index(
            "programs = try builder(admitted, excludedVectorTargets)", discard
        )
        self.assertLess(discard, cancellation)
        self.assertLess(cancellation, rebuild)
        self.assertIn("SceneScriptVectorMediaRouteCandidate.compile(", launch)
        self.assertIn("let committedPrograms = routedPrograms.programs", launch)
        self.assertIn("routedPrograms.mediaOwnerTargets", launch)
        self.assertIn("model.propertyVectorProjection.excludingTargets(", launch)
        self.assertEqual(launch.count("SceneScriptVectorMediaRouteState.resolve("), 1)

        for failure_family in (
            "constructionReport.vectorFailures.keys",
            "constructionReport.scalarFailures.keys",
            "constructionReport.stringFailures.keys",
        ):
            self.assertIn(failure_family, fallback)
        self.assertIn(".union(routeDisabledTargets)", fallback)
        self.assertIn("vectorProjection.uniqueCandidates.map(\\.definition)", fallback)
        self.assertIn("SceneScriptScalarProgram.projectedDefinitions(", fallback)
        self.assertIn("SceneScriptStringProgram.projectedDefinitions(", fallback)
        self.assertIn("Set(definitions.map(\\.target)) == targets", fallback)
        self.assertIn("SceneScriptFallbackCatalog(", launch)
        self.assertIn(
            "sceneScriptFallbackDefinitions: sceneScriptFallbackDefinitions",
            launch,
        )
        self.assertIn("+ sceneScriptFallbackDefinitions", launch_schema)
        # Launch-frozen catalog token: the schema verifies once at launch that
        # the runtime descriptor matches the domain-configured catalog and
        # freezes the token; the frame driver must pass it per snapshot.
        self.assertIn("sceneScriptLayerCatalogToken", launch_schema)
        self.assertIn(
            "SceneScriptQuickJSDomain\n"
            "               .catalogSignature(for: runtimeInput.renderDescriptor)",
            launch_schema,
        )
        self.assertIn("catalogToken: launchContext.frameSchema", frame)
        self.assertIn("fallbackCatalog.targets.isDisjoint(", launch)
        self.assertIn("activeBindings=", startup_report)
        self.assertIn("mediaThumbnailTargets.count", startup_report)
        self.assertIn("mediaOwnerTargets.intersection", startup_report)
        self.assertNotIn("MWX_SCENE_SCRIPT_VECTOR_MEDIA_ROUTE", frame)
        self.assertNotIn("SceneScriptVectorMediaRouteState.resolve(", frame)
        self.assertNotIn("retainAdmittedPassTargets", model + launch + candidate)


    def test_layer_catalog_is_configured_once_per_snapshot(self) -> None:
        handle = LAYER_HANDLE_SOURCE.read_text(encoding="utf-8")
        runtime_fields = LAYER_RUNTIME_DESCRIPTOR_SOURCE.read_text(
            encoding="utf-8"
        )
        snapshot = swift_body(handle, "func publishLayerSnapshot(")
        runtime = swift_body(runtime_fields, "func publishLayerRuntimeFields(")
        self.assertEqual(snapshot.count("configureLayerCatalog(descriptor)"), 1)
        self.assertNotIn("configureLayerCatalog(descriptor)", runtime)
        # The per-frame snapshot path must not rescan the layer catalog: a
        # launch-frozen token is compared instead, and configure only runs
        # for the token-less bootstrap path.
        self.assertIn(
            "videoSnapshots: [Int: SceneScriptVideoPlaybackSnapshot] = [:]",
            handle[handle.index("func publishLayerSnapshot("):],
        )
        self.assertIn("catalogToken: String? = nil", handle)
        self.assertIn(
            "guard configured == catalogToken else", snapshot
        )
        self.assertIn(
            '"SceneScript layer catalog identity changed"', snapshot
        )

    def test_layer_mutation_bridge_rejects_malformed_dto_before_owner_plan(self) -> None:
        handle = LAYER_HANDLE_SOURCE.read_text(encoding="utf-8")
        mutations = swift_body(handle, "static func mutations(\n        owner: OpaquePointer,\n        ownerTarget: SceneDynamicTarget\n    )")

        # The C DTO is a safety boundary: enum values and bit fields must be
        # exact, rather than being coerced into the nearest Swift case.
        self.assertIn(
            "case UInt32(MWX_SCENE_QUICKJS_LAYER_MUTATION_UPSERT.rawValue):",
            mutations,
        )
        self.assertIn(
            "case UInt32(MWX_SCENE_QUICKJS_LAYER_MUTATION_DESTROY.rawValue):",
            mutations,
        )
        self.assertIn("raw.dynamic <= 1", mutations)
        self.assertIn("raw.visible <= 1", mutations)
        self.assertIn("raw.order_index >= 0", mutations)
        self.assertIn("raw.layer_id >= -maximumLayerIdentity", mutations)
        self.assertIn("raw.fields & ~SceneScriptLayerMutation.Fields.authoredFields.rawValue == 0", mutations)
        self.assertIn("switch (kind, raw.dynamic, raw.fields)", mutations)
        self.assertIn(
            "case (.destroy, 0, 0), (.destroy, 1, 0), (.upsert, 1, 0):",
            mutations,
        )
        self.assertIn(
            "case (.upsert, 0, _)\n                where !fields.isEmpty && fields.isSubset(of: .authoredFields):",
            mutations,
        )
        self.assertIn("if raw.dynamic == 1", mutations)
        self.assertIn("(0...1).contains(raw.alpha)", mutations)
        self.assertIn("(1...1024).contains(raw.point_size)", mutations)
        self.assertIn("(0...1).contains(raw.color.0)", mutations)
        self.assertIn("unknown layer mutation kind", mutations)
        self.assertNotIn(
            "raw.kind == UInt32(MWX_SCENE_QUICKJS_LAYER_MUTATION_DESTROY.rawValue)\n                    ? .destroy : .upsert",
            mutations,
        )


    def test_media_coordinator_observes_each_program_event_once_per_frame(self) -> None:
        coordinator = MEDIA_FRAME_COORDINATOR_SOURCE.read_text(encoding="utf-8")
        bridge = MEDIA_EVENT_BRIDGE_SOURCE.read_text(encoding="utf-8")
        self.assertIn("SceneScriptObservedMediaFrameEvents", bridge)
        self.assertIn(
            "let observedVectorEvents = vectorProgram.observeMediaEvents(events)",
            coordinator,
        )
        self.assertIn(
            "let observedStringEvents = stringProgram.observeMediaEvents(events)",
            coordinator,
        )
        self.assertIn(
            "let observedScalarEvents = scalarProgram.observeMediaEvents(events)",
            coordinator,
        )
        for observed in (
            "observedMediaEvents: observedVectorEvents",
            "observedMediaEvents: observedStringEvents",
            "observedMediaEvents: observedScalarEvents",
        ):
            self.assertEqual(coordinator.count(observed), 2)
        ledger = PROGRAM_FRAME_LEDGER_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "func observeMediaEvents(_ events: SceneScriptMediaFrameEvents)",
            ledger,
        )
        for program in (
            VECTOR_PROGRAM_SOURCE,
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptStringProgram.swift",
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptScalarProgram.swift",
        ):
            source = program.read_text(encoding="utf-8")
            self.assertIn("frameLedger.observeMediaEvents(events)", source)
            self.assertIn("observedMediaEvents?.", source)



if __name__ == "__main__":
    unittest.main()
