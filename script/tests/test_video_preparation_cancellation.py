"""Video two-slot prepare/commit/finalize and cross-runtime cancellation gates."""

from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
DAEMON = ROOT / "WallpaperDaemonSources"
ENGINE = ROOT / "MyWallpaperX/Core/Playback"



HELPER_HARNESS = r'''
import AppKit
import AVFoundation
import CoreVideo
import Darwin

@main enum Harness {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard let screen = NSScreen.screens.first,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let daemon = WallpaperDaemon(displayID: number.uint32Value) else { preconditionFailure("no display") }
        daemon.window.ignoresMouseEvents = true
        defer {
            daemon.window.orderOut(nil)
            for player in daemon.players { player.pause(); player.removeAllItems() }
        }
        func item() -> AVPlayerItem { AVPlayerItem(asset: AVMutableComposition()) }
        func prepare(_ id: Int, path: String) {
            daemon.cancelVideoPreparation()
            daemon.switchToken += 1
            daemon.videoPreparation = .init(token: daemon.switchToken, requestID: id,
                videoPath: path, incomingSlot: daemon.inactiveSlot, previousSlot: daemon.activeSlot,
                previousVideoPath: daemon.currentVideoPath, previousRequestID: daemon.currentRequestID,
                previousFillMode: daemon.currentFillMode)
            daemon.videoPreparation?.isPrepared = true
            daemon.inactivePlayer.insert(item(), after: nil)
        }
        // This gate isolates two-slot ownership. Native visibility acceptance
        // is exercised separately by the real visibility harness; fake items
        // need an explicit confirmed fact before testing slot finalization.
        func finalizeSlot(_ id: Int) {
            daemon.videoPreparation?.visibilityConfirmed = true
            daemon.finalizeVideoPreparation(requestID: id)
        }
        let original = item()
        daemon.primaryPlayer.insert(original, after: nil)
        daemon.currentVideoPath = "A"; daemon.currentRequestID = 1
        daemon.primaryLayer.opacity = 1
        prepare(2, path: "B")
        let tokenB = daemon.switchToken
        daemon.commitVideoPreparation(requestID: 2)
        precondition(daemon.currentVideoPath == "B" && daemon.activeSlot == .secondary)
        daemon.completeVideoTransition(token: tokenB)
        precondition(daemon.primaryPlayer.currentItem === original, "old A released before finalize")
        daemon.cancelVideoPreparation(requestID: 2)
        precondition(daemon.currentVideoPath == "A" && daemon.activeSlot == .primary)
        precondition(daemon.primaryPlayer.currentItem === original && daemon.secondaryPlayer.currentItem == nil)
        precondition(daemon.primaryLayer.opacity == 1 && daemon.secondaryLayer.opacity == 0)

        prepare(3, path: "C")
        let tokenC = daemon.switchToken
        daemon.commitVideoPreparation(requestID: 3)
        finalizeSlot(3)
        prepare(4, path: "D")
        let itemD = daemon.primaryPlayer.currentItem
        precondition(itemD != nil)
        daemon.completeVideoTransition(token: tokenC)
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        precondition(daemon.primaryPlayer.currentItem === itemD, "stale crossfade cleanup destroyed new D")
        daemon.cancelVideoPreparation(requestID: 2)
        precondition(daemon.videoPreparation?.requestID == 4, "stale cancellation touched D")
        daemon.cancelVideoPreparation(requestID: 4)
        precondition(daemon.currentVideoPath == "C" && daemon.secondaryPlayer.currentItem != nil)

        daemon.clearVideoSlot(.primary); daemon.clearVideoSlot(.secondary)
        daemon.currentVideoPath = nil; daemon.currentRequestID = nil
        prepare(5, path: "first")
        daemon.commitVideoPreparation(requestID: 5)
        daemon.cancelVideoPreparation(requestID: 5)
        precondition(daemon.currentVideoPath == nil)
        precondition(daemon.window.level.rawValue < WallpaperDaemon.desktopWindowLevel.rawValue)
        precondition(daemon.players.allSatisfy { $0.currentItem == nil })

        prepare(6, path: "confirmed")
        daemon.commitVideoPreparation(requestID: 6)
        finalizeSlot(6)
        daemon.completeVideoTransition(token: daemon.switchToken)
        daemon.cancelVideoPreparation(requestID: 6)
        precondition(daemon.currentVideoPath == "confirmed" && daemon.activePlayer.currentItem != nil)
        daemon.play(videoPath: "/mwx-no-such-video", framePath: nil,
            fillMode: "aspectFill", shouldLoopCurrentItem: false, requestID: 7)
        precondition(daemon.currentVideoPath == "confirmed", "missing candidate damaged confirmed output")

        // Exercise actual decoder/layer readiness below the current desktop,
        // including policy-paused first playback (no time-based success gate).
        let fixture = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mwx-video-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: fixture) }
        do {
            let writer = try AVAssetWriter(outputURL: fixture, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
            writer.add(input)
            precondition(writer.startWriting())
            writer.startSession(atSourceTime: .zero)
            for frame in 0..<12 {
                while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.001) }
                var pixel: CVPixelBuffer?
                precondition(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
                    nil, &pixel) == kCVReturnSuccess)
                guard let pixel else { preconditionFailure("no pixel") }
                CVPixelBufferLockBaseAddress(pixel, [])
                memset(CVPixelBufferGetBaseAddress(pixel), 0x77, CVPixelBufferGetDataSize(pixel))
                CVPixelBufferUnlockBaseAddress(pixel, [])
                precondition(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
            }
            input.markAsFinished()
            let finished = DispatchSemaphore(value: 0)
            writer.finishWriting { finished.signal() }
            precondition(finished.wait(timeout: .now() + 5) == .success && writer.status == .completed)
        } catch { preconditionFailure("video fixture: \(error)") }
        for paused in [true, false] {
            daemon.cancelVideoPreparation()
            daemon.clearVideoSlot(.primary); daemon.clearVideoSlot(.secondary)
            daemon.currentVideoPath = nil; daemon.currentRequestID = nil
            daemon.paused = paused
            daemon.window.level = NSWindow.Level(rawValue: WallpaperDaemon.desktopWindowLevel.rawValue - 2)
            daemon.play(videoPath: fixture.path, framePath: nil, fillMode: "aspectFill",
                shouldLoopCurrentItem: false, requestID: 8)
            let deadline = Date().addingTimeInterval(5)
            while daemon.videoPreparation?.isPrepared != true && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
            precondition(daemon.videoPreparation?.isPrepared == true, "real layer readiness failed, paused=\(paused)")
            precondition(daemon.currentVideoPath == nil && daemon.inactivePlayer.volume == 0)
            let preparedTime = daemon.inactivePlayer.currentTime().seconds
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            precondition(preparedTime < 0.03 && abs(daemon.inactivePlayer.currentTime().seconds - preparedTime) < 0.01,
                "short candidate ran to its end before commit")
            daemon.handle(DaemonCommand(action: "setFillMode", videoPath: nil, framePath: nil,
                propertiesJSON: nil, fillMode: "aspectFit", shouldLoopCurrentItem: nil,
                volume: nil, playbackRate: nil, spectrumEnabled: nil, spectrumLevels: nil,
                spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil,
                spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: nil))
            daemon.commitVideoPreparation(requestID: 8)
            precondition(daemon.activeLayer.frame.size != daemon.window.contentView?.bounds.size,
                "commit used a frame prepared before the new fill mode: mode=\(daemon.currentFillMode) item=\(String(describing: daemon.activePlayer.currentItem?.presentationSize)) actual=\(daemon.activeLayer.frame) bounds=\(String(describing: daemon.window.contentView?.bounds))")
            RunLoop.current.run(until: Date().addingTimeInterval(0.08))
            precondition(daemon.activePlayer.currentTime().seconds < 0.25, "commit started near the end")
            if !paused {
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                precondition(daemon.pendingEndObservation == nil, "short committed clip did not emit ended")
            }
            daemon.cancelVideoPreparation(requestID: 8)
        }

        // Existing but undecodable files must traverse item preparation and
        // produce a correlated failure, retaining the actual committed movie.
        daemon.paused = true
        daemon.play(videoPath: fixture.path, framePath: nil, fillMode: "aspectFill",
            shouldLoopCurrentItem: false, requestID: 9)
        let activeDeadline = Date().addingTimeInterval(5)
        while daemon.videoPreparation?.isPrepared != true && Date() < activeDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(daemon.videoPreparation?.isPrepared == true)
        daemon.commitVideoPreparation(requestID: 9)
        finalizeSlot(9)
        daemon.completeVideoTransition(token: daemon.switchToken)
        let committedItem = daemon.activePlayer.currentItem
        let corrupt = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mwx-corrupt-video-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: corrupt) }
        try! Data("not-a-video-container".utf8).write(to: corrupt)
        precondition(FileManager.default.fileExists(atPath: corrupt.path))
        let emitted = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        precondition(originalStdout >= 0 && dup2(emitted.fileHandleForWriting.fileDescriptor, STDOUT_FILENO) >= 0)
        let corruptCohort = UUID()
        daemon.play(videoPath: corrupt.path, framePath: nil, fillMode: "aspectFill",
            shouldLoopCurrentItem: false, requestID: 10, cohortID: corruptCohort)
        let failureDeadline = Date().addingTimeInterval(9)
        while daemon.videoPreparation != nil && Date() < failureDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        func cancelFailed(_ requestID: Int, cohortID: UUID) -> UUID {
            let activationID = UUID()
            let json = """
                {"action":"cancelVideoPreparation","requestID":\(requestID),"cohortID":"\(cohortID.uuidString)","activationID":"\(activationID.uuidString)"}
                """
            daemon.handle(try! JSONDecoder().decode(DaemonCommand.self, from: Data(json.utf8)))
            return activationID
        }
        let corruptCancellation = cancelFailed(10, cohortID: corruptCohort)
        let missingCohort = UUID()
        daemon.play(videoPath: "/mwx-no-such-typed-video", framePath: nil,
            fillMode: "aspectFill", shouldLoopCurrentItem: false, requestID: 11, cohortID: missingCohort)
        let missingCancellation = cancelFailed(11, cohortID: missingCohort)
        fflush(stdout)
        precondition(dup2(originalStdout, STDOUT_FILENO) >= 0)
        close(originalStdout)
        try! emitted.fileHandleForWriting.close()
        let eventData = emitted.fileHandleForReading.readDataToEndOfFile()
        let failures = eventData.split(separator: 0x0A).compactMap {
            try? JSONDecoder().decode(DaemonEvent.self, from: Data($0))
        }
        precondition(failures.contains { $0.type == "failed" && $0.requestID == 10
            && $0.videoPath == corrupt.path && $0.cohortID == corruptCohort
            && $0.preparationGeneration != nil && $0.activationID == nil },
            "existing corrupt video lost its typed preparation identity")
        precondition(failures.contains { $0.type == "failed" && $0.requestID == 11
            && $0.message == "video_not_found" && $0.cohortID == missingCohort
            && $0.preparationGeneration != nil && $0.activationID == nil },
            "pre-readiness file rejection lost its typed preparation identity")
        for (requestID, cohort, activation) in [(10, corruptCohort, corruptCancellation), (11, missingCohort, missingCancellation)] {
            precondition(failures.contains { $0.type == "cancelled" && $0.requestID == requestID
                && $0.cohortID == cohort && $0.activationID == activation && $0.preparationGeneration == nil },
                "failed candidate did not ACK the parent's exact pre-readiness cancellation")
        }
        precondition(!failures.contains { $0.type == "prepared" || $0.type == "ready" })
        precondition(daemon.videoPreparation == nil && daemon.currentVideoPath == fixture.path
            && daemon.currentRequestID == 9 && daemon.activePlayer.currentItem === committedItem,
            "corrupt existing candidate replaced or damaged committed A")
        print("video-slot-cancellation-pass")
    }
}
'''


class VideoPreparationCancellationTests(unittest.TestCase):
    def compile_run(self, sources: list[Path], harness: str, marker: str) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-video-preparation-") as directory:
            root = Path(directory)
            source = root / "Harness.swift"
            source.write_text(harness)
            binary = root / "harness"
            compiled = subprocess.run(["xcrun", "swiftc", "-parse-as-library", *map(str, sources),
                                       str(source), "-o", str(binary)], capture_output=True, text=True, timeout=60)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=25)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(marker, result.stdout)

    def test_helper_retains_previous_slot_until_finalized(self) -> None:
        sources = list((DAEMON / "Daemon").rglob("*.swift"))
        sources += [ENGINE / "DaemonProtocol.swift", ROOT / "MyWallpaperX/Core/DaemonKit/DaemonNewlineJSON.swift",
                    ROOT / "MyWallpaperX/Core/DaemonKit/DaemonParentLifetime.swift",
                    ROOT / "MyWallpaperX/Core/PlaybackControl/PlaybackSurfaceVisibility.swift"]
        self.compile_run(sources, HELPER_HARNESS, "video-slot-cancellation-pass")

    # Parent transaction/cancellation/retirement now executes the actual typed
    # owners in test_playback_switch_endpoints.py. The removed extracted fixture
    # encoded the retired cross-engine rollback and auto-commit authority.


if __name__ == "__main__":
    unittest.main()
