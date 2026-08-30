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
POINTER_EVENTS_SOURCE = RUNTIME / "SceneDesktopWallpaperHost+PointerEvents.swift"
VIEW_SOURCE = RENDERING / "SceneMetalView.swift"
MEDIA_COORDINATOR_SOURCE = RENDERING / "SceneMediaThumbnailCoordinator.swift"
CURSOR_INTERACTION_SOURCE = (
    RENDERING / "SceneMetalView+SceneScriptCursorInteraction.swift"
)
SCALAR_RUNTIME_SOURCE = SCRIPT / "SceneScriptScalarRuntime.swift"
CURSOR_PROGRAM_SOURCE = SCRIPT / "SceneScriptCursorProgram.swift"
MEDIA_EVENT_BRIDGE_SOURCE = SCRIPT / "SceneScriptMediaEventBridge.swift"
LAUNCH_SOURCE = RUNTIME / "SceneDesktopWallpaperHost+Launch.swift"
MODEL_SOURCE = RUNTIME / "SceneRuntimeModel.swift"
CANDIDATE_SOURCE = SCRIPT / "SceneScriptQuickJSProgramCandidate.swift"
ROUTE_CANDIDATE_SOURCE = SCRIPT / "SceneScriptVectorMediaRouteCandidate.swift"
FALLBACK_CATALOG_SOURCE = SCRIPT / "SceneScriptFallbackCatalog.swift"
VECTOR_PROGRAM_SOURCE = SCRIPT / "SceneScriptVectorProgram.swift"


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
        self.assertIn("candidate.vectorProgram.mediaThumbnailTargets", route)
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
        self.assertIn("+ launchContext.sceneScriptFallbackDefinitions", frame)
        self.assertIn("fallbackCatalog.targets.isDisjoint(", launch)
        self.assertIn("activeBindings=", launch)
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
        vector = VECTOR_PROGRAM_SOURCE.read_text(encoding="utf-8")
        render = swift_body(frame, "private func renderFrame()")
        publication = render.index(".publishLayerSnapshot(")
        cursor_batch = render.index("let cursorBatch:")
        cursor = render.index("sceneScriptCursorProgram.dispatch(")
        vector_callback = render.index("propertyVectorScriptProgram.evaluate(")
        string_callback = render.index("sceneScriptStringProgram.evaluate(")
        scalar_callback = render.index("sceneScriptScalarProgram.evaluate(")
        self.assertLess(publication, cursor_batch)
        self.assertLess(publication, cursor)
        self.assertLess(publication, vector_callback)
        self.assertLess(publication, string_callback)
        self.assertLess(publication, scalar_callback)
        self.assertIn("if sceneScriptLayerSnapshotFailure != nil", render)
        self.assertEqual(render.count("if let failure = sceneScriptLayerSnapshotFailure"), 5)
        self.assertIn("cursorBatch = .init(samples: [], overflowed: false)", render)
        self.assertNotIn("publishLayerSnapshot", vector)
        self.assertNotIn("layerSnapshot:", vector)

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
        vector_vm_position = host_render.index(
            "launchContext.propertyVectorScriptProgram.evaluate("
        )
        surface_loop_position = host_render.index(
            "for (displayID, surface) in surfaces"
        )
        surface_render_position = host_render.index(
            "surface.metalView.renderFrame(",
            surface_loop_position,
        )
        self.assertLess(snapshot_position, preparation_position)
        self.assertLess(preparation_position, event_position)
        self.assertLess(event_position, vector_vm_position)
        self.assertLess(vector_vm_position, surface_loop_position)
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
        pointer_events = POINTER_EVENTS_SOURCE.read_text(encoding="utf-8")
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
        self.assertIn("else if surfaces.count == 1,", frame_driver)
        self.assertIn("let metalView = surfaces.values.first?.metalView", frame_driver)
        self.assertIn("sceneScriptCursorFrameBatch(", frame_driver)
        self.assertIn("capturedOwnerLayerIDs:", frame_driver)
        self.assertIn("drainSceneScriptPointerEvents()", frame_driver)
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
        self.assertIn("authoredTransformBaseline:", cursor_program)
        self.assertIn("discardCandidates(ownerLayerID:", cursor_program)
        self.assertIn("owner.exportedCursorEvents", cursor_program)
        self.assertIn('case .move: "cursorMove"', event_bridge)
        self.assertIn("let scale = layer.scaleXYZ ?? [1, 1, 1]", cursor_program)


if __name__ == "__main__":
    unittest.main()
