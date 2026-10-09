#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
RESOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources"
STATE_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Providers/SceneVideoProviderLifecycleState.swift"
VIDEO_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Providers/SceneVideoTextureSource.swift"
REGISTRY_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Providers/SceneVideoTextureSourceRegistry.swift"
HOST_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost.swift"
)
HOST_FRAME_DRIVER_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift"
)
HOST_SURFACE_TEARDOWN_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfaceTeardown.swift"
)
HOST_FRAME_DRIVER_LIFECYCLE_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriverLifecycle.swift"
)
OWNER_EFFECTS_VALIDATION_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptOwnerEffectsRuntimeValidation.swift"
)
VECTOR_PROGRAM_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorProgram.swift"
)
VIEW_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView.swift"
)
ASSEMBLY_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneFrameLayerTextureAssembly.swift"
)

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        var state = SceneVideoProviderLifecycleState(epoch: 73)
        let initiallyPlaying = state.isPlaying
        let initialGeneration = state.contentGeneration

        state.start(sceneTime: 10, hostTime: 100)
        let first = state.planFrame(
            frameIndex: 9,
            sceneTime: 10.25,
            hostTime: 100.25
        )
        let duplicate = state.planFrame(
            frameIndex: 9,
            sceneTime: 99,
            hostTime: 999
        )
        let firstPublication = state.didPublish(frameIndex: 9)
        let duplicatePublication = state.didPublish(frameIndex: 9)
        let generationAfterDuplicate = state.contentGeneration

        let second = state.planFrame(
            frameIndex: 10,
            sceneTime: 10.5,
            hostTime: 100.5
        )
        let secondPublication = state.didPublish(frameIndex: 10)

        var discarded = SceneVideoProviderLifecycleState(epoch: 74)
        discarded.start(sceneTime: 0, hostTime: 0)
        let discardedPlan = discarded.planFrame(
            frameIndex: 20,
            sceneTime: 1,
            hostTime: 1
        )
        discarded.discardPlannedFrame(frameIndex: 20)
        let retriedAfterDiscard = discarded.planFrame(
            frameIndex: 20,
            sceneTime: 1,
            hostTime: 1
        )
        let retryPublication = discarded.didPublish(frameIndex: 20)

        let initialEpoch = state.epoch
        state.pause(sceneTime: 10.75, hostTime: 100.75)
        let pausedEpoch = state.epoch
        let paused = state.planFrame(
            frameIndex: 11,
            sceneTime: 50,
            hostTime: 500
        )
        state.resume(sceneTime: 20, hostTime: 200)
        let resumedEpoch = state.epoch
        let resumed = state.planFrame(
            frameIndex: 12,
            sceneTime: 20.25,
            hostTime: 200.25
        )
        state.rebuild(sceneTime: 20.5, hostTime: 200.5)
        let rebuiltEpoch = state.epoch
        let rebuilt = state.planFrame(
            frameIndex: 13,
            sceneTime: 20.75,
            hostTime: 8_000
        )

        var shiftedHost = SceneVideoProviderLifecycleState(epoch: 73)
        shiftedHost.start(sceneTime: 10, hostTime: 1_000)
        let shifted = shiftedHost.planFrame(
            frameIndex: 9,
            sceneTime: 10.25,
            hostTime: 9_000
        )

        var suspendedPause = SceneVideoProviderLifecycleState(epoch: 81)
        suspendedPause.start(sceneTime: 0, hostTime: 10)
        suspendedPause.suspend(sceneTime: 1, hostTime: 11)
        suspendedPause.pause(sceneTime: 9, hostTime: 19)
        let pausedWhileSuspended = suspendedPause.planFrame(
            frameIndex: 1,
            sceneTime: 12,
            hostTime: 22
        )

        var suspendedRebuild = SceneVideoProviderLifecycleState(epoch: 82)
        suspendedRebuild.start(sceneTime: 0, hostTime: 10)
        suspendedRebuild.suspend(sceneTime: 1, hostTime: 11)
        suspendedRebuild.rebuild(sceneTime: 9, hostTime: 19)
        let rebuiltWhileSuspended = suspendedRebuild.planFrame(
            frameIndex: 1,
            sceneTime: 12,
            hostTime: 22
        )

        var looping = SceneVideoProviderLifecycleState(epoch: 83)
        looping.start(sceneTime: 100, hostTime: 200)
        _ = looping.planFrame(
            frameIndex: 1,
            sceneTime: 105,
            hostTime: 205
        )
        looping.didReachEnd(duration: 5)
        let loopRestart = looping.planFrame(
            frameIndex: 2,
            sceneTime: 105.25,
            hostTime: 205.25
        )

        func loopPhase(rate: Double, observed: Double, next: Double) -> Double {
            var source = SceneVideoProviderLifecycleState(epoch: 84)
            source.start(sceneTime: 100, hostTime: 200)
            source.setRate(rate, sceneTime: 100, hostTime: 200)
            _ = source.planFrame(frameIndex: 1, sceneTime: 100 + observed, hostTime: 200 + observed)
            source.didReachEnd(duration: 5)
            return source.planFrame(frameIndex: 2, sceneTime: 100 + next,
                hostTime: 200 + next).itemTime
        }
        let delayedLoop = loopPhase(rate: 1, observed: 5.2, next: 5.25)
        let earlyLoop = loopPhase(rate: 1, observed: 4.99, next: 5.02)
        let fastLoop = loopPhase(rate: 2, observed: 2.6, next: 2.65)
        var repeatedLoop = SceneVideoProviderLifecycleState(epoch: 85)
        repeatedLoop.start(sceneTime: 0, hostTime: 0)
        for index in 1...10 {
            _ = repeatedLoop.planFrame(frameIndex: UInt64(index),
                sceneTime: Double(index) * 5.2, hostTime: Double(index) * 5.2)
            repeatedLoop.didReachEnd(duration: 5)
        }
        let repeatedLoopPhase = repeatedLoop.planFrame(frameIndex: 11,
            sceneTime: 52.05, hostTime: 52.05).itemTime

        var earlyAnchor = SceneVideoProviderLifecycleState(epoch: 86)
        earlyAnchor.start(sceneTime: 100, hostTime: 200)
        _ = earlyAnchor.planFrame(frameIndex: 1, sceneTime: 104.99, hostTime: 204.99)
        earlyAnchor.didReachEnd(duration: 5)
        var earlyPaused = earlyAnchor
        earlyPaused.pause(sceneTime: 104.995, hostTime: 204.995)
        earlyPaused.resume(sceneTime: 105.5, hostTime: 205.5)
        var earlyRate = earlyAnchor
        earlyRate.setRate(2, sceneTime: 105.01, hostTime: 205.01)
        var earlyRebuilt = earlyAnchor
        earlyRebuilt.rebuild(sceneTime: 105.01, hostTime: 205.01)
        var finalEnd = earlyAnchor
        finalEnd.setLoop(false)
        finalEnd.didReachEnd(duration: 5)
        let negativeAnchorTransitions = close(earlyPaused.currentTime(at: 105.52), 0.015)
            && close(earlyRate.currentTime(at: 105.03), 0.05)
            && close(earlyRebuilt.currentTime(at: 105.03), 0.03)
            && close(finalEnd.currentTime(at: 110), 5) && !finalEnd.isPlaying

        var playerEvents = SceneVideoPlayerEventState()
        let unanchoredEndRejected = !playerEvents.acceptsEndEvent(
            observedItemTime: 5,
            duration: 5,
            tolerance: 0.01
        )
        playerEvents.invalidateAnchor()
        playerEvents.didAnchorPlayback()
        let currentEndAccepted = playerEvents.acceptsEndEvent(
            observedItemTime: 4.995,
            duration: 5,
            tolerance: 0.01
        )
        let overDurationEndAccepted = playerEvents.acceptsEndEvent(
            observedItemTime: 5.02,
            duration: 5,
            tolerance: 0.01
        )
        playerEvents.invalidateAnchor()
        let staleEndRejectedAfterCommand = !playerEvents.acceptsEndEvent(
            observedItemTime: 5,
            duration: 5,
            tolerance: 0.01
        )
        playerEvents.didAnchorPlayback()
        let staleEndRejectedAfterRestart = !playerEvents.acceptsEndEvent(
            observedItemTime: 0.02,
            duration: 5,
            tolerance: 0.01
        )

        let firstStopRequestsCleanup = state.stop()
        let secondStopRequestsCleanup = state.stop()

        let payload: [String: Any] = [
            "initiallyDormant": !initiallyPlaying && initialGeneration == 0,
            "deterministicItemTime": close(first.itemTime, 0.25)
                && close(shifted.itemTime, first.itemTime),
            "sameFrameDeduplicated": first.shouldDecode
                && !duplicate.shouldDecode
                && close(duplicate.itemTime, first.itemTime),
            "generationIsPublicationDriven": first.contentGeneration == 0
                && firstPublication == 1
                && duplicatePublication == nil
                && generationAfterDuplicate == 1
                && second.shouldDecode
                && secondPublication == 2
                && state.contentGeneration == 2,
            "discardedPlanCanRetry": discardedPlan.shouldDecode
                && retriedAfterDiscard.shouldDecode
                && discardedPlan.contentGeneration == 0
                && retriedAfterDiscard.contentGeneration == 0
                && retryPublication == 1
                && discarded.contentGeneration == 1,
            "pauseHoldsItemTime": !paused.shouldDecode
                && close(paused.itemTime, 0.75),
            "resumeIsContinuous": resumed.shouldDecode
                && close(resumed.itemTime, 1.0),
            "rebuildIsContinuous": rebuilt.shouldDecode
                && close(rebuilt.itemTime, 1.5),
            "suspendedPauseDoesNotAdvance": !pausedWhileSuspended.shouldDecode
                && close(pausedWhileSuspended.itemTime, 1),
            "suspendedRebuildDoesNotAdvance": !rebuiltWhileSuspended.shouldDecode
                && close(rebuiltWhileSuspended.itemTime, 1),
            "loopNegativeAnchorTransitions": negativeAnchorTransitions,
            "loopPreservesElapsedPhase": close(delayedLoop, 0.25)
                && close(earlyLoop, 0.02) && close(fastLoop, 0.3)
                && close(repeatedLoopPhase, 2.05),
            "loopRestartsAtLatestSceneTime": loopRestart.shouldDecode
                && close(loopRestart.itemTime, 0.25),
            "endEventBelongsToCurrentAnchor": unanchoredEndRejected
                && currentEndAccepted
                && overDurationEndAccepted
                && staleEndRejectedAfterCommand
                && staleEndRejectedAfterRestart,
            "epochIsInherited": initialEpoch == 73
                && pausedEpoch == initialEpoch
                && resumedEpoch == initialEpoch
                && rebuiltEpoch == initialEpoch
                && paused.epoch == initialEpoch
                && resumed.epoch == initialEpoch
                && rebuilt.epoch == initialEpoch,
            "stopIsIdempotent": firstStopRequestsCleanup
                && !secondStopRequestsCleanup
                && !state.isPlaying,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    private static func close(
        _ lhs: TimeInterval,
        _ rhs: TimeInterval
    ) -> Bool {
        abs(lhs - rhs) < 0.000_001
    }
}
'''


def swift_block(source: str, marker: str) -> str | None:
    marker_index = source.find(marker)
    if marker_index < 0:
        return None
    open_index = source.find("{", marker_index)
    if open_index < 0:
        return None
    depth = 0
    for index in range(open_index, len(source)):
        character = source[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[open_index + 1:index]
    return None


class SceneVideoProviderLifecycleStateTests(unittest.TestCase):
    def test_scene_clock_mapping_deduplication_generation_and_lifecycle(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        self.assertTrue(
            STATE_SOURCE.is_file(),
            "Video Provider Lifecycle v1 needs a pure "
            "SceneVideoProviderLifecycleState production source",
        )

        with tempfile.TemporaryDirectory(prefix="mwx-video-lifecycle-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = root / "video-lifecycle"
            compilation = subprocess.run(
                [
                    "swiftc",
                    str(STATE_SOURCE),
                    str(harness),
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                compilation.returncode,
                0,
                f"Video lifecycle contract did not compile:\n{compilation.stderr}",
            )
            completed = subprocess.run(
                [str(binary)],
                check=True,
                capture_output=True,
                text=True,
            )
            result = json.loads(completed.stdout)

        for key in (
            "initiallyDormant",
            "deterministicItemTime",
            "sameFrameDeduplicated",
            "generationIsPublicationDriven",
            "pauseHoldsItemTime",
            "resumeIsContinuous",
            "rebuildIsContinuous",
            "suspendedPauseDoesNotAdvance",
            "suspendedRebuildDoesNotAdvance",
            "loopNegativeAnchorTransitions",
            "loopPreservesElapsedPhase",
            "loopRestartsAtLatestSceneTime",
            "endEventBelongsToCurrentAnchor",
            "epochIsInherited",
            "stopIsIdempotent",
            "discardedPlanCanRetry",
        ):
            with self.subTest(contract=key):
                self.assertTrue(result[key], key)


class SceneVideoTextureSourceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = VIDEO_SOURCE.read_text(encoding="utf-8")

    def test_initialization_prepares_the_source_without_autoplay(self) -> None:
        initializer = swift_block(self.source, "init?(")
        self.assertIsNotNone(initializer)
        assert initializer is not None
        self.assertNotIn(
            ".play()",
            initializer,
            "initialization must not start AVPlayer or restart it from the EOF observer",
        )
        self.assertIn(
            "player.automaticallyWaitsToMinimizeStalling = false",
            initializer,
            "synchronized setRate(time:atHostTime:) rejects automatic stalling waits",
        )

    def test_texture_publication_consumes_shared_timing_and_exposes_generation(
        self,
    ) -> None:
        for token in (
            "SceneVideoProviderLifecycleState",
            "SceneFrameTiming",
            "timing.frameIndex",
            "timing.sceneTime",
            "timing.hostTime",
            "contentGeneration",
            "lifecycle.planFrame(",
            "requestIdentity: .layerSource(layerID)",
            "candidate: SceneTextureCandidate(",
            "identity: .provider(.video(",
            "lifecycleEpoch: epoch",
            "generation: .provider(contentGeneration: contentGeneration)",
            "purpose: .premultipliedColor",
            "content: content",
            "resolvedColorContent(for: pixelBuffer)",
            "kCVImageBufferAlphaChannelIsOpaque",
            "kCVImageBufferAlphaChannelMode_PremultipliedAlpha",
        ):
            with self.subTest(token=token):
                self.assertIn(token, self.source)


    def test_last_ready_fallback_stays_inside_the_submission_transaction(self) -> None:
        current_frame = swift_block(self.source, "func prepareFrame(")
        self.assertIsNotNone(current_frame)
        assert current_frame is not None
        self.assertIn(
            "return pendingFrame ?? lastFrame",
            current_frame,
            "shared sources must reuse the last-ready frame for peer surfaces",
        )
        self.assertIn(
            "pendingFrameIndex = timing.frameIndex",
            current_frame,
            "a no-buffer plan must remain discardable when another surface drops",
        )
        for token in (
            "pendingPreparationSnapshot",
            "lifecycle: lifecycle",
            "hasStarted: hasStarted",
            "needsPlayerAnchor: needsPlayerAnchor",
            "playerEventState: playerEventState",
        ):
            with self.subTest(snapshot=token):
                self.assertIn(token, current_frame)

        commit = swift_block(self.source, "func commitPreparedFrame()")
        self.assertIsNotNone(commit)
        assert commit is not None
        self.assertIn(
            "lifecycle.discardPlannedFrame(frameIndex: frameIndex)",
            commit,
            "a submitted last-ready fallback must not arm same-frame deduplication",
        )
        discard = swift_block(self.source, "func discardPreparedFrame()")
        self.assertIsNotNone(discard)
        assert discard is not None
        self.assertIn(
            "lifecycle.discardPlannedFrame(frameIndex: frameIndex)",
            discard,
            "a dropped surface must make the no-buffer plan retryable",
        )
        for token in (
            "lifecycle = preparation.lifecycle",
            "hasStarted = preparation.hasStarted",
            "needsPlayerAnchor = preparation.needsPlayerAnchor",
            "playerEventState = preparation.playerEventState",
            "if preparation?.hasStarted ?? true",
        ):
            with self.subTest(restore=token):
                self.assertIn(token, discard)

    def test_stop_is_idempotent_and_releases_all_owned_resources(self) -> None:
        stop = swift_block(self.source, "func stop(")
        self.assertIsNotNone(
            stop,
            "SceneVideoTextureSource needs an explicit idempotent stop()",
        )
        assert stop is not None
        for token in (
            "lifecycle.stop()",
            "NotificationCenter.default.removeObserver",
            "player.pause()",
            "player.replaceCurrentItem(with: nil)",
            "FileManager.default.removeItem",
        ):
            with self.subTest(cleanup=token):
                self.assertIn(token, stop)

        deinitializer = swift_block(self.source, "deinit")
        self.assertIsNotNone(deinitializer)
        self.assertIn("stop()", deinitializer)


class SceneVideoProviderOwnershipContractTests(unittest.TestCase):

    def test_registry_fails_closed_without_stable_file_metadata(self) -> None:
        registry = REGISTRY_SOURCE.read_text(encoding="utf-8")
        source_method = swift_block(registry, "func source(")
        self.assertIsNotNone(source_method)
        assert source_method is not None
        self.assertIn(
            "guard let sourceKey = loader.sourceKey(for: url)",
            source_method,
        )
        self.assertIn("source: sourceKey", source_method)
        self.assertGreaterEqual(
            source_method.count("loader.sourceKey(for: url) == sourceKey"),
            2,
            "cached and newly created video sources must revalidate metadata",
        )
        self.assertLess(
            source_method.index("guard let sourceKey"),
            source_method.index("let identity = SourceIdentity("),
            "unavailable metadata must not form a video registry identity",
        )



if __name__ == "__main__":
    unittest.main()
