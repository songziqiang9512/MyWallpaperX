"""Run production frozen-frame scheduling with controlled transport completion.

The existing method-extraction scaffold executes the driver, Session text/media
notifications, invalidation, surface submission, cohort and PreparedFrame owners.
The ordinary simulation branch uses a counting probe only in playing scenarios.
Timer, dispatch, raster readiness and Metal completion are controlled boundaries;
no scheduler or publication policy is reproduced.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.steam.test_steam_library_interactions import method
from script.tests.scene.test_scene_prepared_script_resource_catalog import swift_declaration

ROOT = Path(__file__).resolve().parents[3]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SESSION = SCENE / "Runtime/Session"


FIXTURE = (Path(__file__).resolve().parents[1] / "fixtures") / "ScenePausedFrameRecoveryHarness.swift"

DISPLAY_OUTPUT_SCENARIO = r'''
    static func displayOutputChanges() {
        let (owner, hdr, before) = fixture()
        let sdr = owner.attach(2)
        hdr.window.screen = Screen(maximumPotentialExtendedDynamicRangeColorComponentValue: 4)
        sdr.window.screen = Screen()
        owner.startFrameDriver()
        complete(hdr.metalView, 0, true)
        complete(sdr.metalView, 0, true)
        owner.applyScenePostProcessing(.enabled)
        precondition(owner.scenePostProcessing == .ultra && hdr.metalView.draws == 1)
        owner.applyScenePostProcessing(.ultraDisplayHDR)
        precondition(hdr.metalView.draws == 2 && hdr.metalView.metalLayer.wantsExtendedDynamicRangeContent)
        precondition(sdr.metalView.draws == 1 && !sdr.metalView.metalLayer.wantsExtendedDynamicRangeContent)
        complete(hdr.metalView, 1, true)
        hdr.window.screen!.maximumExtendedDynamicRangeColorComponentValue = 3
        hdr.metalView.refreshDisplayOutputForScreenChange()
        DispatchQueue.main.drain()
        precondition(hdr.metalView.draws == 3 && hdr.metalView.displayOutput.uniform == 3)
        complete(hdr.metalView, 2, true)
        owner.applyScenePostProcessing(.ultra)
        precondition(hdr.metalView.draws == 4 && !hdr.metalView.metalLayer.wantsExtendedDynamicRangeContent)
        precondition(hdr.metalView.displayOutput.uniform == 1 && sdr.metalView.draws == 1)
        complete(hdr.metalView, 3, true)
        frozen(owner, before)
        stopped(owner)

        let (pending, surfaces, pendingBefore) = candidate()
        let pendingSurface = surfaces[0], view = pendingSurface.metalView
        pendingSurface.window.screen = hdr.window.screen
        var deliveries: [Bool] = []
        pending.onFirstFrameCompletion = { _, succeeded in deliveries.append(succeeded) }
        pending.startFrameDriver()
        complete(view, 0, true)
        precondition(pending.initialPresentationCohort.hasDelivered && deliveries == [true])
        pending.applyScenePostProcessing(.disabled)
        precondition(pending.scenePostProcessing == .ultra && view.draws == 1)
        pending.applyScenePostProcessing(.ultraDisplayHDR)
        pendingSurface.window.screen!.maximumExtendedDynamicRangeColorComponentValue = 2
        view.refreshDisplayOutputForScreenChange()
        DispatchQueue.main.drain()
        precondition(pending.initialPresentationCohort.isHeld && deliveries == [true] && view.draws == 1)
        precondition(view.displayOutput.uniform == 2 && view.metalLayer.wantsExtendedDynamicRangeContent)
        frozen(pending, pendingBefore)
        stopped(pending)

        let (ordinary, surface, _) = fixture()
        ordinary.scenePostProcessing = .enabled
        ordinary.applyScenePostProcessing(.disabled)
        precondition(ordinary.scenePostProcessing == .enabled && surface.metalView.draws == 0)
    }
'''


def production_harness(sources=None):
    """Accept frozen source bytes for causal old/new checks; normal tests use live owners."""
    def read(relative):
        return sources[relative] if sources is not None else (SCENE / relative).read_text()

    driver = read("Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift")
    session = read("Runtime/Session/SceneDesktopWallpaperSession.swift")
    submission = read("Runtime/Session/SceneDesktopWallpaperSession+SurfaceSubmission.swift")
    pause = read("Runtime/Session/SceneDesktopWallpaperSession+VideoProviders.swift")
    teardown = read("Runtime/Session/SceneDesktopWallpaperSession+SurfaceTeardown.swift")
    assembly_path = "Runtime/Session/SceneDesktopWallpaperSession+SurfacePreparation.swift"
    assembly = sources.get(assembly_path, session) if sources is not None else read(assembly_path)
    context = read("Runtime/Frame/SceneFrameContext.swift")
    outcome = read("Rendering/Frame/SceneMetalRenderer+FrameOutcome.swift")
    view = read("Rendering/Frame/SceneMetalView.swift")
    geometry = read("Rendering/Frame/SceneMetalView+Geometry.swift")
    display = read("Rendering/Composition/SceneDisplayMappingPostProcess.swift")
    quality = (ROOT / "MyWallpaperX/Core/PlaybackControl/PlaybackPerformanceProfile.swift").read_text()
    # Frozen scenarios still fail if ordinary simulation is entered.
    frame = method(driver, "private func renderFrame()")
    frame = frame[:frame.index("        promotePendingDeferredLayerVisibilityIfReady()")]
    frame += ('        guard let activeSimulationProbe else { fatalError("ordinary simulation entered during paused recovery") }\n'
              '        return activeSimulationProbe()\n    }')
    # Surface identity and retry cancellation belong to this production prefix;
    # the later cursor/audio/VM context disposal is outside this transport test.
    retirement = method(teardown, "func teardownSurfaces(")
    marker = "        surfaces.removeAll()"
    retirement = retirement[:retirement.index(marker) + len(marker)] + "\n    }"
    methods = "\n".join([
        method(driver, "private var sceneFrameInterval:").replace("private var", "var"),
        method(driver, "private var sceneBusyFrameRetryInterval:").replace("private var", "var"),
        *(method(driver, signature) for signature in [
            "func startFrameDriver(", "func scheduleFrameDriver(", "private func armFrameDriver(",
            "private func waitForFrameAdmission(",
        ]),
        *(method(submission, signature) for signature in [
            "func renderSurfaces(", "var awaitsInitialPresentation:",
            "private func observeSurfaceCompletion(", "private func deliverInitialPresentationCohort(",
        ]),
        frame,
        method(pause, "func setPlaybackPaused("),
        method(session, "func textTexturePublicationDidChange("),
        method(session, "func enqueueMediaThumbnailPublication("),
        method(session, "func applyScenePostProcessing("),
        method(session, "func invalidatePausedDisplayOutput("),
        method(driver, "func refreshPausedMediaPublications("),
        method(teardown, "func teardownSurface("),
        retirement,
    ])
    harness = FIXTURE.read_text().replace("// INVALIDATION\n", method(assembly, "metalView.onRenderInvalidated =") + "\n")
    harness = harness.replace("// DISPLAY_OUTPUT_INVALIDATION",
        method(assembly, "metalView.onDisplayOutputChanged ="))
    harness = harness.replace("// DISPLAY_OUTPUT_METHODS", "\n".join([
        method(view, "func setDisplayHDRRequested("),
        method(geometry, "func refreshDisplayOutput()"),
        method(geometry, "func refreshDisplayOutputForScreenChange()"),
    ]))
    harness = harness.replace("// DISPLAY_OUTPUT_SCENARIO", DISPLAY_OUTPUT_SCENARIO)
    harness = harness.replace("// TEXT_FRAME_METHODS", "\n".join(
        method(view, signature) for signature in (
            "func commitPreparedDynamicTextFrame(", "func discardPreparedDynamicTextFrame(")))
    harness = harness.replace("// METHODS", methods)
    adoption_start = driver.index("        pendingProviderUpdate = (")
    adoption_end = driver.index("        )\n", adoption_start) + len("        )")
    harness = harness.replace("// PROVIDER_INPUT_ADOPTION", driver[adoption_start:adoption_end])
    harness = harness.replace("// PRODUCTION_FRAME_PREFIX", "\n".join([
        method(driver, "enum SceneFrameDriverAttempt"),
        read("Runtime/Session/SceneInitialPresentationCohort.swift"),
        method(quality, "nonisolated enum ScenePostProcessingMode:"),
        "enum SceneDisplayMappingPostProcess {\n" + swift_declaration(display, "enum Output:") + "\n}",
    ]))
    return harness.replace("// PRODUCTION_FRAME_TYPES", "\n".join([
        method(context, "nonisolated struct SceneFrameTiming:"),
        method(context, "nonisolated struct SceneClock {"),
        "extension SceneMetalRenderer {\n" + "\n".join(swift_declaration(outcome, signature) for signature in (
            "enum FrameOutcome:", "struct InitialVideoPresentation", "final class PreparedFrame:",
            "static func submitPreparedFrame(",
        )) + "\n}",
    ]))


class ScenePausedFrameRecoveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-paused-frame-recovery-")
        cls.addClassCleanup(cls.temporary.cleanup)
        directory = Path(cls.temporary.name)
        source = directory / "Harness.swift"
        source.write_text(production_harness())
        cls.binary = directory / "harness"
        result = subprocess.run([
            "xcrun", "swiftc", "-parse-as-library", "-module-cache-path",
            str(directory / "module-cache"), str(source), "-o", str(cls.binary),
        ], capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)

    def run_scenario(self, name):
        result = subprocess.run([str(self.binary), name], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("paused-frame-recovery-pass: " + name, result.stdout)

    def test_success_draws_once_per_invalidation(self):
        self.run_scenario("success")

    def test_one_async_failure_retries_then_stops(self):
        self.run_scenario("failOnce")

    def test_repeated_async_failures_do_not_extend_deadline(self):
        self.run_scenario("asyncExpiry")

    def test_synchronous_failures_expire(self):
        self.run_scenario("syncExpiry")

    def test_busy_admission_expire(self):
        self.run_scenario("busyExpiry")

    def test_active_wait_reuses_the_timer_and_simulates_once(self):
        for scenario in ("activeAdmissionWake", "activeAdmissionTimeout", "activeAdmissionMixed"):
            with self.subTest(scenario=scenario):
                self.run_scenario(scenario)

    def test_old_candidate_failure_preserves_new_success(self):
        self.run_scenario("oldCandidate")

    def test_reused_display_id_ignores_retired_surface(self):
        self.run_scenario("replacedSurface")

    def test_teardown_ignores_late_completion_and_invalidation(self):
        self.run_scenario("teardown")

    def test_first_frame_callback_teardown_precedes_retry_revalidation(self):
        self.run_scenario("callbackTeardown")

    def test_multiple_displays_only_retry_failed_surface(self):
        self.run_scenario("multipleSurfaces")

    def test_resume_pause_ignores_old_failure(self):
        self.run_scenario("resumePause")

    def test_cancelled_candidate_has_no_completion_and_retry_expires(self):
        self.run_scenario("cancellation")

    def test_text_and_media_publications_preserve_qualified_and_delivered_candidate(self):
        self.run_scenario("heldText")

    def test_two_surface_publications_cannot_replace_or_partially_deliver_cohort(self):
        self.run_scenario("heldTextTwoSurfaces")

    def test_real_invalidation_rejects_cross_attempt_success_and_fails_delivered_host(self):
        self.run_scenario("realInvalidation")

    def test_hdr_output_change_redraws_only_eligible_paused_surface_and_preserves_candidate(self):
        self.run_scenario("displayOutput")

    def test_candidate_gpu_failure_survives_text_publication(self):
        self.run_scenario("candidateGPUFailure")

    def test_old_submitted_gpu_failure_still_reaches_host_after_newer_delivery(self):
        self.run_scenario("staleGPUFailureAfterDelivery")

    def test_active_paused_text_adopts_latest_store_without_advancing_simulation(self):
        self.run_scenario("activePausedText")

    def test_shared_text_pending_follows_submission_and_freezes_attempt_publication(self):
        self.run_scenario("textPending")

    def test_paused_media_requires_complete_matching_frozen_frames_before_any_publication(self):
        self.run_scenario("frozenFrameCohort")

    def test_video_switch_withheld_submissions_retry_resources_and_preserve_peer(self):
        for scenario in ("videoSwitchRecovery", "videoSwitchExpiry", "videoSwitchGPUFailure", "videoSwitchCancel", "videoSwitchDrop"):
            with self.subTest(scenario=scenario):
                self.run_scenario(scenario)

    def test_video_source_set_follows_ordered_submissions_before_gpu_callbacks(self):
        self.run_scenario("submittedVideoSet")


if __name__ == "__main__":
    unittest.main()
