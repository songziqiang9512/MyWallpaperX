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

HOST_SOURCE = RUNTIME / "SceneDesktopWallpaperHost.swift"
FRAME_DRIVER_SOURCE = RUNTIME / "SceneDesktopWallpaperHost+FrameDriver.swift"
FRAME_DRIVER_LIFECYCLE_SOURCE = (
    RUNTIME / "SceneDesktopWallpaperHost+FrameDriverLifecycle.swift"
)
POINTER_EVENTS_SOURCE = RUNTIME / "SceneDesktopWallpaperHost+PointerEvents.swift"
VIEW_SOURCE = RENDERING / "SceneMetalView.swift"
MEDIA_COORDINATOR_SOURCE = RENDERING / "SceneMediaThumbnailCoordinator.swift"
CURSOR_INTERACTION_SOURCE = (
    RENDERING / "SceneMetalView+SceneScriptCursorInteraction.swift"
)
SCALAR_RUNTIME_SOURCE = SCRIPT / "SceneScriptScalarRuntime.swift"
CURSOR_PROGRAM_SOURCE = SCRIPT / "SceneScriptCursorProgram.swift"
MEDIA_EVENT_BRIDGE_SOURCE = SCRIPT / "SceneScriptMediaEventBridge.swift"
MEDIA_FRAME_COORDINATOR_SOURCE = SCRIPT / "SceneScriptMediaFrameCoordinator.swift"
OWNER_EFFECTS_VALIDATION_SOURCE = (
    SCRIPT / "SceneScriptOwnerEffectsRuntimeValidation.swift"
)
LAUNCH_SOURCE = RUNTIME / "SceneDesktopWallpaperHost+Launch.swift"
LAUNCH_SCHEMA_SOURCE = RUNTIME / "SceneDesktopWallpaperLaunchFrameSchema.swift"
STARTUP_REPORT_SOURCE = (
    RUNTIME / "SceneDesktopWallpaperLaunchContext+StartupReport.swift"
)
MODEL_SOURCE = RUNTIME / "SceneRuntimeModel.swift"
CANDIDATE_SOURCE = SCRIPT / "SceneScriptQuickJSProgramCandidate.swift"
ROUTE_CANDIDATE_SOURCE = SCRIPT / "SceneScriptVectorMediaRouteCandidate.swift"
FALLBACK_CATALOG_SOURCE = SCRIPT / "SceneScriptFallbackCatalog.swift"
VECTOR_PROGRAM_SOURCE = SCRIPT / "SceneScriptVectorProgram.swift"
LAYER_HANDLE_SOURCE = SCRIPT / "SceneScriptLayerHandleBridge.swift"
LAYER_RUNTIME_DESCRIPTOR_SOURCE = (
    SCRIPT / "SceneScriptLayerRuntimeDescriptorBridge.swift"
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


class SceneFrameVMRoutingTests(unittest.TestCase):
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

    def test_shared_candidate_family_order_retries_in_a_fresh_domain(self) -> None:
        candidate = CANDIDATE_SOURCE.read_text(encoding="utf-8")
        loop = candidate.index("for _ in 0...maximumAttempts")
        fresh_domain = candidate.index(
            "domain = try SceneScriptQuickJSDomain(budget: budget)", loop
        )
        vector = candidate.index("compileNonPassCandidate(", fresh_domain)
        cursor = candidate.index("SceneScriptCursorProgram.compileCandidate(", vector)
        scalar = candidate.index("SceneScriptScalarProgram.compileCandidate(", cursor)
        string = candidate.index("SceneScriptStringProgram.compileCandidate(", scalar)
        vector_pass = candidate.index(".instantiatePassOwners(", string)
        self.assertLess(fresh_domain, vector)
        self.assertLess(vector, cursor)
        self.assertLess(cursor, scalar)
        self.assertLess(scalar, string)
        self.assertLess(string, vector_pass)
        self.assertIn("next iteration reconstructs every surviving owner", candidate)
        self.assertIn("scalarProgram: .unavailable(generation: generation)", candidate)
        self.assertIn("ownerConstruction=failed", candidate)
        self.assertIn("fallback=current-frame-lower-priority", candidate)

    def test_layer_snapshot_precedes_every_shared_domain_callback(self) -> None:
        frame = FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        frame_driver_cursor = (
            RUNTIME / "SceneDesktopWallpaperHost+FrameDriverCursor.swift"
        ).read_text(encoding="utf-8")
        lifecycle = FRAME_DRIVER_LIFECYCLE_SOURCE.read_text(encoding="utf-8")
        vector = VECTOR_PROGRAM_SOURCE.read_text(encoding="utf-8")
        media_frame = MEDIA_FRAME_COORDINATOR_SOURCE.read_text(encoding="utf-8")
        owner_validation = OWNER_EFFECTS_VALIDATION_SOURCE.read_text(
            encoding="utf-8"
        )
        render = swift_body(frame, "private func renderFrame()")
        commit_frame = swift_body(lifecycle, "func commitSubmittedSceneFrame(")
        publication = render.index(".publishLayerSnapshot(")
        cursor_batch = render.index("let cursorBatch = cursorPreparation.batch")
        cursor = render.index("sceneScriptCursorProgram.dispatch(")
        media_callback = render.index("launchContext.frameSchema.mediaFrameCoordinator.evaluate(")
        owner_preflight = render.index(
            ".preflightOwnerEffectsToFixedPoint(ownerEffects)"
        )
        surface_render = render.index("surface.metalView.renderFrame(")
        layer_commit = render.index("commitSubmittedSceneFrame(")
        self.assertLess(publication, cursor_batch)
        self.assertLess(publication, cursor)
        self.assertLess(publication, media_callback)
        self.assertLess(media_callback, owner_preflight)
        self.assertLess(owner_preflight, surface_render)
        self.assertLess(surface_render, layer_commit)
        surface_commit = commit_frame.index("evaluationTransaction.commit")
        alpha_commit = commit_frame.index("sharedLayerAlphaRuntime.commitValues(")
        timeline_commit = commit_frame.index("timelinePlaybackRuntime.apply(")
        video_commit = commit_frame.index("videoTextureSourceRegistry?.apply(")
        plan_call = commit_frame.index("commitSceneScriptLayerPlan(")
        plan_helper_start = lifecycle.index("func commitSceneScriptLayerPlan(")
        plan_commit = lifecycle.index(
            "context.sceneScriptDynamicLayerRuntime.commit(plan)",
            plan_helper_start,
        )
        self.assertLess(surface_commit, alpha_commit)
        self.assertLess(alpha_commit, timeline_commit)
        self.assertLess(timeline_commit, video_commit)
        self.assertLess(video_commit, plan_call)
        self.assertGreater(plan_commit, plan_helper_start)
        self.assertIn("rejectedOwnerTargets.contains($0.key)", render)
        self.assertIn("admittedOwnerEffects.flatMap(", render)
        self.assertEqual(
            render.count(".preflightOwnerEffectsToFixedPoint(ownerEffects)"),
            1,
        )
        self.assertNotIn(".preflightOwnerEffects(admittedOwnerEffects)", render)
        self.assertIn("timelineRuntime.validate(", owner_validation)
        self.assertIn("videoRegistry.validate(", owner_validation)
        self.assertNotIn(".applyIsolatingOwners(layerMutations)", render)
        self.assertIn("if layerSnapshotFailure != nil", frame_driver_cursor)
        self.assertIn(
            "cursorBatch = .init(samples: [], overflowed: false)",
            frame_driver_cursor,
        )
        self.assertEqual(render.count("if let failure = sceneScriptLayerSnapshotFailure"), 3)
        self.assertNotIn("publishLayerSnapshot", vector)
        self.assertNotIn("layerSnapshot:", vector)
        self.assertIn("vectorProgram.evaluate(", media_frame)
        self.assertIn("stringProgram.evaluate(", media_frame)
        self.assertIn("scalarProgram.evaluate(", media_frame)
        # The host encodes user properties once per frame; the coordinator
        # must pass that string through instead of letting each program
        # re-encode the full dictionary.
        self.assertGreaterEqual(
            media_frame.count("userPropertiesJSON: userPropertiesJSON"), 2
        )

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
        mutations = swift_body(handle, "static func mutations(")

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
        self.assertIn("case (.destroy, 1, 0), (.upsert, 1, 0):", mutations)
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

        # A malformed DTO must remain a local owner failure; callers discard
        # the owner-local C journal before the candidate reaches frame commit.
        scalar = SCALAR_RUNTIME_SOURCE.read_text(encoding="utf-8")
        string = (SCRIPT / "SceneScriptStringRuntime.swift").read_text(
            encoding="utf-8"
        )
        self.assertIn("SceneScriptLayerMutationBridge.discard(owner: handle)", scalar)
        self.assertIn("SceneScriptLayerMutationBridge.discard(owner: handle)", string)

    def test_one_media_snapshot_feeds_vm_before_every_surface(self) -> None:
        frame_driver = FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        view = VIEW_SOURCE.read_text(encoding="utf-8")
        coordinator = MEDIA_COORDINATOR_SOURCE.read_text(encoding="utf-8")
        host_render = swift_body(frame_driver, "private func renderFrame()")
        view_prepare = swift_body(view, "func prepareMediaThumbnail(")
        view_render = swift_body(view, "func renderFrame(")
        coordinator_update = swift_body(coordinator, "func update(")

        snapshot_declaration = (
            "let mediaInput = SceneMediaThumbnailInbox.shared.latest()"
        )
        self.assertEqual(host_render.count(snapshot_declaration), 1)
        self.assertEqual(
            host_render.count("SceneMediaThumbnailInbox.shared.latest()"),
            1,
        )
        snapshot_position = host_render.index(snapshot_declaration)
        preparation_position = host_render.index(
            "surface.metalView.prepareMediaThumbnail(from: mediaInput)"
        )
        event_position = host_render.index(
            "SceneScriptMediaThumbnailEventInput(snapshot: mediaInput)"
        )
        media_vm_position = host_render.index(
            "launchContext.frameSchema.mediaFrameCoordinator.evaluate("
        )
        surface_loop_position = host_render.index(
            "for (displayID, surface) in surfaces",
            media_vm_position,
        )
        surface_render_position = host_render.index(
            "surface.metalView.renderFrame(",
            surface_loop_position,
        )
        self.assertLess(snapshot_position, preparation_position)
        self.assertLess(preparation_position, event_position)
        self.assertLess(event_position, media_vm_position)
        self.assertLess(media_vm_position, surface_loop_position)
        self.assertNotIn("mediaColorTransitionRuntime", host_render)

        surface_loop = host_render[surface_loop_position:]
        self.assertNotIn("SceneMediaThumbnailInbox.shared.latest()", surface_loop)
        self.assertEqual(
            host_render.count(
                "surface.metalView.prepareMediaThumbnail(from: mediaInput)"
            ),
            1,
        )
        self.assertIn("$0.generation == mediaInput.generation", host_render)
        self.assertIn("$0.pendingGeneration == nil", host_render)
        self.assertEqual(
            surface_loop.count("mediaThumbnail: mediaThumbnailSnapshot"), 1
        )
        self.assertGreater(
            host_render.index(
                "mediaThumbnail: mediaThumbnailSnapshot", surface_render_position
            ),
            surface_render_position,
        )

        self.assertIn("mediaThumbnail: SceneMediaThumbnailTextureStore.Snapshot", view)
        self.assertEqual(
            view_prepare.count("mediaThumbnailCoordinator.update(from: input)"),
            1,
        )
        self.assertNotIn("mediaThumbnailCoordinator.update", view_render)
        self.assertNotIn("SceneMediaThumbnailInbox.shared", view)
        self.assertIn(
            "from input: SceneMediaThumbnailInbox.Snapshot",
            coordinator,
        )
        self.assertEqual(
            coordinator_update.count("textureStore.update(from: input)"),
            1,
        )
        self.assertNotIn("SceneMediaThumbnailInbox.shared", coordinator)
        self.assertNotIn("func update()", coordinator)

    def test_cursor_exports_gate_the_single_surface_dispatch_route(self) -> None:
        host = HOST_SOURCE.read_text(encoding="utf-8")
        frame_driver = FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        frame_driver_cursor = (
            RUNTIME / "SceneDesktopWallpaperHost+FrameDriverCursor.swift"
        ).read_text(encoding="utf-8")
        pointer_events = POINTER_EVENTS_SOURCE.read_text(encoding="utf-8")
        pointer_state = (
            RUNTIME / "SceneSurfacePointerState.swift"
        ).read_text(encoding="utf-8")
        interaction = CURSOR_INTERACTION_SOURCE.read_text(encoding="utf-8")
        scalar_runtime = SCALAR_RUNTIME_SOURCE.read_text(encoding="utf-8")
        cursor_program = CURSOR_PROGRAM_SOURCE.read_text(encoding="utf-8")
        event_bridge = MEDIA_EVENT_BRIDGE_SOURCE.read_text(encoding="utf-8")

        self.assertIn("installPointerEventMonitorsIfNeeded()", host)
        self.assertIn("removePointerEventMonitors()", host)
        self.assertIn("removePointerEventMonitors()", frame_driver)
        self.assertIn("NSEvent.addLocalMonitorForEvents", pointer_events)
        self.assertIn("NSEvent.addGlobalMonitorForEvents", pointer_events)
        self.assertEqual(pointer_events.count("NSEvent.removeMonitor("), 2)
        self.assertIn("guard debugPointerOverride == nil", pointer_events)
        self.assertIn("recordSceneScriptPointerEvent(", pointer_events)
        self.assertIn("else if surfaces.count == 1,", frame_driver_cursor)
        self.assertIn("let (displayID, surface) = surfaces.first", frame_driver_cursor)
        self.assertIn("sceneScriptCursorFrameBatch(", frame_driver_cursor)
        self.assertIn("capturedOwnerLayerIDs:", frame_driver_cursor)
        self.assertIn("drainSceneScriptPointerEvents()", frame_driver_cursor)
        self.assertIn("drainedEvents: drained", frame_driver_cursor)
        # A deferred/dropped frame must re-insert drained pointer events and
        # restore the pre-dispatch cursor edge state instead of consuming
        # press/release/click edges for a frame that was never displayed.
        self.assertIn("restoreSceneScriptPointerEvents(batch)", frame_driver)
        self.assertIn("edgeStateSnapshot()", frame_driver)
        self.assertIn("restoreEdgeState(cursorEdgeState)", frame_driver)
        self.assertIn("drainedPointerBatches[displayID] = drained", frame_driver_cursor)
        self.assertIn(
            "mutating func restore(", pointer_state
        )
        self.assertIn(
            "events.insert(contentsOf: batch.events, at: 0)", pointer_state
        )
        self.assertIn("surface: sceneScriptSurfaceInput(", interaction)
        self.assertIn("cursorLeftDown: pointer.primaryButtonIsDown", interaction)
        self.assertIn("init(replacingSurfaceOf frame:", scalar_runtime)
        self.assertIn("with: sample.surface", cursor_program)
        self.assertIn("pointerPosition: pointer.normalizedPosition", interaction)
        self.assertIn("ownerProjections: projections", interaction)
        self.assertIn("? ownerLayerIDs : captureCandidates", interaction)
        self.assertIn("originInteractionProjections(", interaction)
        self.assertIn(
            "sample.pointerPosition != previousPointerPosition",
            cursor_program,
        )
        self.assertIn("sample.ownerProjections.filter", cursor_program)
        self.assertIn(
            "? admittedProjections[binding.layerID]",
            cursor_program,
        )
        self.assertIn("Self.mergingAuthoredMutation(", cursor_program)
        self.assertIn("authoredLayerBaselines:", cursor_program)
        self.assertIn("discardCandidates(ownerLayerID:", cursor_program)
        self.assertIn("owner.exportedCursorEvents", cursor_program)
        self.assertIn('case .move: "cursorMove"', event_bridge)
        self.assertIn("let scale = layer.scaleXYZ ?? [1, 1, 1]", cursor_program)


if __name__ == "__main__":
    unittest.main()
