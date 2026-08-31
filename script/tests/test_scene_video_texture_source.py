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
STATE_SOURCE = RESOURCE_ROOT / "SceneVideoProviderLifecycleState.swift"
VIDEO_SOURCE = RESOURCE_ROOT / "SceneVideoTextureSource.swift"
REGISTRY_SOURCE = RESOURCE_ROOT / "SceneVideoTextureSourceRegistry.swift"
HOST_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost.swift"
)
HOST_FRAME_DRIVER_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime"
    / "SceneDesktopWallpaperHost+FrameDriver.swift"
)
VIEW_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneMetalView.swift"
)
ASSEMBLY_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering"
    / "SceneFrameLayerTextureAssembly.swift"
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
            "loopRestartsAtLatestSceneTime": loopRestart.shouldDecode
                && close(loopRestart.itemTime, 0.25),
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
            "loopRestartsAtLatestSceneTime",
            "epochIsInherited",
            "stopIsIdempotent",
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

    def test_synchronized_anchor_retries_when_the_player_did_not_start(self) -> None:
        current_frame = swift_block(self.source, "func currentFrame(")
        self.assertIsNotNone(current_frame)
        assert current_frame is not None
        self.assertIn("needsPlayerAnchor || player.rate == 0", current_frame)
        self.assertIn("needsPlayerAnchor = player.rate == 0", current_frame)
        self.assertIn(
            "if lifecycle.isPlaying && player.rate == 0",
            current_frame,
            "an authored-playing source must retain the retry barrier",
        )
        self.assertIn(
            "if player.rate == 0",
            current_frame,
            "a missing first buffer must retain the retry barrier",
        )

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
    def test_launch_registry_survives_surface_rebuild_and_stops_with_scene(self) -> None:
        host = HOST_SOURCE.read_text(encoding="utf-8")
        frame_driver = HOST_FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        registry = REGISTRY_SOURCE.read_text(encoding="utf-8")
        view = VIEW_SOURCE.read_text(encoding="utf-8")
        assembly = ASSEMBLY_SOURCE.read_text(encoding="utf-8")

        self.assertIn(
            "var videoTextureSourceRegistry: SceneVideoTextureSourceRegistry?",
            host,
        )
        activate = swift_block(host, "func activate(")
        self.assertIsNotNone(activate)
        assert activate is not None
        self.assertIn("videoTextureSourceRegistry?.stop()", activate)
        self.assertIn(
            "videoTextureSourceRegistry = SceneVideoTextureSourceRegistry(",
            activate,
        )

        rebuild = swift_block(host, "private func rebuildSurfaces(")
        self.assertIsNotNone(rebuild)
        assert rebuild is not None
        self.assertIn("videoTextureSourceRegistry.beginSurfaceRebuild(", rebuild)
        self.assertIn("videoTextureSourceRegistry.completeSurfaceRebuild()", rebuild)
        self.assertLess(
            rebuild.index("videoTextureSourceRegistry.beginSurfaceRebuild("),
            rebuild.index("guard !screens.isEmpty"),
            "an empty screen set must stop headless video playback",
        )
        self.assertIn(
            "videoSourceRegistry: videoTextureSourceRegistry",
            rebuild,
        )
        self.assertIn("teardownSurfaces(clearContext: false", rebuild)
        self.assertNotIn(
            "videoTextureSourceRegistry = SceneVideoTextureSourceRegistry(",
            rebuild,
        )

        teardown = swift_block(frame_driver, "func teardownSurfaces(")
        self.assertIsNotNone(teardown)
        assert teardown is not None
        stop_index = teardown.index("videoTextureSourceRegistry?.stop()")
        clear_context_index = teardown.rfind("if clearContext {", 0, stop_index)
        self.assertGreaterEqual(clear_context_index, 0)
        clear_context = swift_block(
            teardown[clear_context_index:], "if clearContext {"
        )
        self.assertIsNotNone(clear_context)
        assert clear_context is not None
        self.assertIn("videoTextureSourceRegistry?.stop()", clear_context)
        self.assertIn("videoTextureSourceRegistry = nil", clear_context)

        self.assertIn("if let source = sources[identity]", registry)
        self.assertIn("sources[identity] = source", registry)
        self.assertIn("rebuildingSourceIdentities?.insert(identity)", registry)
        self.assertIn("sources.removeValue(forKey: identity)?.stop()", registry)
        self.assertIn("videoSourceRegistry.source(", view)
        self.assertNotIn("currentTexture(forHostTime:", view)
        self.assertIn("source.currentFrame(for: timing)", assembly)
        self.assertIn("pendingLayerSourceIDs.insert(layerID)", assembly)
        self.assertIn("pendingLayerSourceIDs: pendingLayerSourceIDs", assembly)

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

    def test_video_command_failure_withholds_its_visibility_owner(self) -> None:
        frame_driver = HOST_FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        application = frame_driver.index("videoTextureSourceRegistry?.apply(")
        rejection = frame_driver.index(
            ".rejectVideoCommandTargets(", application
        )
        publication = frame_driver.index(
            "commonSceneScriptValues.merge(\n"
            "            admittedSceneScriptVectorValues,",
            application,
        )
        self.assertLess(application, rejection)
        self.assertLess(rejection, publication)
        self.assertIn(
            "sceneScriptVectorResult.videoCommandTargets.contains($0.key)",
            frame_driver[application:publication],
        )


if __name__ == "__main__":
    unittest.main()
