"""Run production frozen-frame scheduling with controlled transport completion.

The existing method-extraction scaffold executes the driver, Session text/media
notifications, invalidation, surface submission, cohort and PreparedFrame owners.
Only the normal simulation branch is replaced by a trap. Timer, dispatch,
raster readiness and Metal completion are hand-controlled transport boundaries;
no scheduler or publication policy is reproduced.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SESSION = SCENE / "Runtime/Session"


FIXTURE = Path(__file__).with_name("fixtures") / "ScenePausedFrameRecoveryHarness.swift"


def production_harness(sources=None):
    """Accept frozen source bytes for causal old/new checks; normal tests use live owners."""
    def read(relative):
        return sources[relative] if sources is not None else (SCENE / relative).read_text()

    driver = read("Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift")
    session = read("Runtime/Session/SceneDesktopWallpaperSession.swift")
    submission = read("Runtime/Session/SceneDesktopWallpaperSession+SurfaceSubmission.swift")
    pause = read("Runtime/Session/SceneDesktopWallpaperSession+VideoProviders.swift")
    teardown = read("Runtime/Session/SceneDesktopWallpaperSession+SurfaceTeardown.swift")
    context = read("Runtime/Frame/SceneFrameContext.swift")
    outcome = read("Rendering/Frame/SceneMetalRenderer+FrameOutcome.swift")
    view = read("Rendering/Frame/SceneMetalView.swift")
    # Execute the complete frozen branch. Entering ordinary clock/VM work is a
    # test failure, rather than a fake implementation that could conceal it.
    frame = method(driver, "private func renderFrame()")
    frame = frame[:frame.index("        promotePendingDeferredLayerVisibilityIfReady()")]
    frame += '        fatalError("normal cadence/VM branch entered during paused recovery")\n    }'
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
        ]),
        *(method(submission, signature) for signature in [
            "func renderSurfaces(", "var awaitsInitialPresentation:",
            "private func observeSurfaceCompletion(", "private func deliverInitialPresentationCohort(",
        ]),
        frame,
        method(pause, "func setPlaybackPaused("),
        method(session, "func textTexturePublicationDidChange("),
        method(session, "func enqueueMediaThumbnailPublication("),
        method(driver, "func refreshPausedMediaPublications("),
        retirement,
    ])
    harness = FIXTURE.read_text().replace("// INVALIDATION\n", method(session, "metalView.onRenderInvalidated =") + "\n")
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
    ]))
    return harness.replace("// PRODUCTION_FRAME_TYPES", "\n".join([
        method(context, "nonisolated struct SceneFrameTiming:"),
        method(context, "nonisolated struct SceneClock {"),
        outcome.replace("import Metal\n", ""),
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
