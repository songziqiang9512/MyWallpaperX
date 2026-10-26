"""Video two-slot prepare/commit/finalize and cross-runtime cancellation gates."""

from pathlib import Path
import hashlib
import json
import os
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
import QuartzCore

@main enum Harness {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard let screen = NSScreen.screens.first,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let daemon = WallpaperDaemon(displayID: number.uint32Value) else { preconditionFailure("no display") }
        daemon.window.ignoresMouseEvents = true
        var renderingFacts: [String: Bool] = [:]
        func renderingFact(_ name: String, _ passed: Bool) {
            renderingFacts[name] = passed
            precondition(passed, name)
        }
        func fixedRendering(_ name: String) {
            renderingFact(name, daemon.window.isOpaque && daemon.window.backgroundColor == NSColor.black
                && daemon.window.contentView?.wantsLayer == true
                && daemon.window.contentView?.layer?.backgroundColor?.components == NSColor.black.cgColor.components
                && daemon.primaryLayer.videoGravity == .resizeAspectFill
                && daemon.secondaryLayer.videoGravity == .resizeAspectFill)
        }
        func setFillMode(_ mode: String) {
            daemon.handle(DaemonCommand(action: "setFillMode", videoPath: nil, framePath: nil,
                propertiesJSON: nil, fillMode: mode, shouldLoopCurrentItem: nil,
                volume: nil, playbackRate: nil, spectrumEnabled: nil, spectrumLevels: nil,
                spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil,
                spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: nil))
        }
        fixedRendering("initializedFixedProperties")
        defer {
            daemon.window.orderOut(nil)
            for player in daemon.players { player.pause(); player.removeAllItems() }
        }
        let spectrumFacts = VideoSpectrumLayerLifecycleChecks.run(daemon)
        print("spectrum-lifecycle-facts=" + String(data:
            try! JSONSerialization.data(withJSONObject: spectrumFacts, options: [.sortedKeys]), encoding: .utf8)!)
        fflush(stdout)
        let fixtureRoot = URL(fileURLWithPath:
            ProcessInfo.processInfo.environment["MWX_VIDEO_FIXTURE_ROOT"]!, isDirectory: true)
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
        daemon.window.contentView!.layoutSubtreeIfNeeded()
        let bounds = daemon.window.contentView!.bounds
        let outgoingLayer = daemon.primaryLayer
        let candidateLayer = daemon.secondaryLayer
        let insetFrame = bounds.insetBy(dx: bounds.width / 8, dy: bounds.height / 8)
        func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
            abs(lhs.minX - rhs.minX) < 0.01 && abs(lhs.minY - rhs.minY) < 0.01
                && abs(lhs.width - rhs.width) < 0.01 && abs(lhs.height - rhs.height) < 0.01
        }
        func outgoingLayoutIsSettled() -> Bool {
            guard let presentation = outgoingLayer.presentation() else { return false }
            return framesMatch(outgoingLayer.frame, insetFrame) && framesMatch(presentation.frame, insetFrame)
        }
        func frameValue(_ value: CGRect?) -> Any {
            guard let value else { return NSNull() }
            return ["x": Double(value.minX), "y": Double(value.minY),
                    "width": Double(value.width), "height": Double(value.height)]
        }
        func transitionDiagnostic(_ stage: String) {
            let facts: [String: Any] = ["stage": stage,
                "request": daemon.currentRequestID.map { $0 as Any } ?? NSNull(),
                "path": daemon.currentVideoPath.map { $0 as Any } ?? NSNull(),
                "slot": daemon.activeSlot == .primary ? "primary" : "secondary",
                "modelFrame": frameValue(outgoingLayer.frame),
                "presentationFrame": frameValue(outgoingLayer.presentation()?.frame),
                "insetFrame": frameValue(insetFrame), "targetFrame": frameValue(bounds),
                "candidateModelFrame": frameValue(candidateLayer.frame),
                "animationKeys": candidateLayer.animationKeys() ?? [],
                "level": daemon.window.level.rawValue,
                "expectedLevel": PlaybackSurfaceVisibility.activationLevel(normal: WallpaperDaemon.desktopWindowLevel).rawValue,
                "requestMatches": daemon.currentRequestID == 2,
                "transformAnimationPresent": candidateLayer.animation(forKey: "switchInPosition") != nil,
                "layoutSettled": outgoingLayoutIsSettled()]
            print("video-transition-diagnostic=" + String(data:
                try! JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]), encoding: .utf8)!)
            fflush(stdout)
        }
        // Production deliberately reads the presentation frame. Establish the
        // fixture's smaller outgoing frame in that real tree before committing.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outgoingLayer.removeAllAnimations()
        outgoingLayer.frame = insetFrame
        CATransaction.commit()
        CATransaction.flush()
        daemon.window.displayIfNeeded()
        let layoutDeadline = Date().addingTimeInterval(2)
        while !outgoingLayoutIsSettled() && Date() < layoutDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        transitionDiagnostic("before-animated-commit")
        precondition(outgoingLayoutIsSettled(), "fixture outgoing presentation did not settle to its inset frame")
        let tokenB = daemon.switchToken
        daemon.commitVideoPreparation(requestID: 2)
        transitionDiagnostic("after-animated-commit")
        precondition(daemon.currentVideoPath == "B" && daemon.activeSlot == .secondary)
        renderingFact("animatedCommitPublishesCurrentOutput", daemon.currentRequestID == 2
            && daemon.activeLayer.animation(forKey: "switchInPosition") != nil
            && daemon.window.level == PlaybackSurfaceVisibility.activationLevel(normal: WallpaperDaemon.desktopWindowLevel))
        precondition(daemon.videoPreparation?.transitionComplete == false,
            "an animated switch must retain its animation completion")
        daemon.completeVideoTransition(token: tokenB)
        precondition(daemon.primaryPlayer.currentItem === original, "old A released before finalize")
        daemon.cancelVideoPreparation(requestID: 2)
        precondition(daemon.currentVideoPath == "A" && daemon.activeSlot == .primary)
        precondition(daemon.primaryPlayer.currentItem === original && daemon.secondaryPlayer.currentItem == nil)
        precondition(daemon.primaryLayer.opacity == 1 && daemon.secondaryLayer.opacity == 0)
        renderingFact("animatedCancelRestoresGeometry", daemon.currentRequestID == 1
            && daemon.activeLayer.frame == daemon.window.contentView!.bounds
            && daemon.window.level == WallpaperDaemon.desktopWindowLevel)
        fixedRendering("fixedPropertiesAfterAnimatedCancel")

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
        renderingFact("firstCommitPublishesCurrentOutput", daemon.currentVideoPath == "first"
            && daemon.currentRequestID == 5 && daemon.activeLayer.opacity == 1
            && daemon.inactiveLayer.opacity == 0 && daemon.fallbackLayer.opacity == 0
            && daemon.window.level == PlaybackSurfaceVisibility.activationLevel(normal: WallpaperDaemon.desktopWindowLevel))
        precondition(daemon.videoPreparation?.transitionComplete == true,
            "first play has no animation and must not wait for a crossfade timer")
        precondition(daemon.videoPreparation?.visibilityConfirmed == false,
            "finishing an unanimated transition must not invent a decoded visible frame")
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
        let fixture = fixtureRoot
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
            setFillMode("aspectFit")
            daemon.commitVideoPreparation(requestID: 8)
            precondition(daemon.videoPreparation?.transitionComplete == true,
                "real paused and playing first frames must not inherit a crossfade delay")
            precondition(daemon.activeLayer.frame.size != daemon.window.contentView?.bounds.size,
                "commit used a frame prepared before the new fill mode: mode=\(daemon.currentFillMode) item=\(String(describing: daemon.activePlayer.currentItem?.presentationSize)) actual=\(daemon.activeLayer.frame) bounds=\(String(describing: daemon.window.contentView?.bounds))")
            fixedRendering(paused ? "pausedFirstPlayKeepsFixedProperties" : "playingFirstPlayKeepsFixedProperties")
            daemon.window.setFrame(CGRect(origin: screen.frame.origin,
                size: CGSize(width: screen.frame.width * 0.8, height: screen.frame.height * 0.7)), display: true)
            setFillMode("aspectFill")
            let filledResizedBounds = daemon.activeLayer.frame == daemon.window.contentView!.bounds
            setFillMode("aspectFit")
            let resizedBounds = daemon.window.contentView!.bounds
            let fittedFrame = daemon.activeLayer.frame
            renderingFact(paused ? "pausedResizePreservesFillGeometry" : "playingResizePreservesFillGeometry",
                filledResizedBounds && abs(fittedFrame.width - fittedFrame.height) < 0.01
                    && fittedFrame.width <= resizedBounds.width + 0.01
                    && fittedFrame.height <= resizedBounds.height + 0.01)
            daemon.window.setFrame(screen.frame, display: true)
            setFillMode("aspectFit")
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
        let corrupt = fixtureRoot
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
            && $0.videoPath == nil && $0.cohortID == corruptCohort
            && $0.preparationGeneration != nil && $0.activationID == nil },
            "existing corrupt video lost its typed preparation identity")
        precondition(failures.contains { $0.type == "failed" && $0.requestID == 11
            && $0.message == "video_not_found" && $0.videoPath == nil && $0.cohortID == missingCohort
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
        // Execute the actual command receiver and stdout encoder. Diagnostics
        // are optional; failure and activity correlation are product IPC.
        let commandCohort = UUID()
        let activityID = UUID()
        func handle(_ fields: [String: Any]) {
            daemon.handle(try! JSONDecoder().decode(DaemonCommand.self,
                from: JSONSerialization.data(withJSONObject: fields)))
        }
        let missingCommandPath = fixtureRoot
            .appendingPathComponent("mwx-missing-command-\(UUID().uuidString).mov").path
        handle(["action": "play", "videoPath": missingCommandPath, "requestID": 9001,
                "cohortID": commandCohort.uuidString])
        precondition(daemon.currentRequestID == 9 && daemon.activePlayer.currentItem === committedItem)
        precondition(daemon.outputActivityAllowed)
        handle(["action": "setOutputActivity", "requestID": 9, "outputActive": false])
        precondition(daemon.outputActivityAllowed, "missing activity identity must not change output")
        handle(["action": "setOutputActivity", "requestID": 9002, "outputActive": false,
                "activityID": activityID.uuidString])
        precondition(daemon.outputActivityAllowed, "a stale request must not revoke the current output")
        handle(["action": "setOutputActivity", "requestID": 9, "outputActive": false,
                "activityID": activityID.uuidString])
        precondition(!daemon.outputActivityAllowed && daemon.activePlayer.volume == 0)
        print("helper-command-facts=" + String(data: try! JSONSerialization.data(withJSONObject: [
            "cohortID": commandCohort.uuidString, "activityID": activityID.uuidString,
            "videoPath": missingCommandPath], options: [.sortedKeys]), encoding: .utf8)!)
        print("video-rendering-facts=" + String(data:
            try! JSONSerialization.data(withJSONObject: renderingFacts, options: [.sortedKeys]), encoding: .utf8)!)
        print("video-slot-cancellation-pass")
    }
}
'''


class VideoPreparationCancellationTests(unittest.TestCase):
    def compile_run(self, sources: list[Path], harness: str, marker: str) -> None:
        configured = os.environ.get("MWX_VIDEO_PREPARATION_EVIDENCE")
        retained = Path(configured) if configured else None
        if retained:
            retained.mkdir(parents=True, exist_ok=True)
        context = tempfile.TemporaryDirectory(prefix="mwx-video-preparation-") if retained is None else None
        directory = Path(context.name) if context else retained
        try:
            rendering_by_configuration = {}
            for configuration, flags in (("debug", ["-D", "DEBUG"]), ("release", [])):
                root = directory / configuration
                root.mkdir()
                for child in ("home", "tmp", "modules"):
                    (root / child).mkdir()
                environment = dict(os.environ, HOME=str(root / "home"), CFFIXED_USER_HOME=str(root / "home"),
                                   TMPDIR=str(root / "tmp") + "/", MWX_VIDEO_FIXTURE_ROOT=str(root / "tmp"),
                                   CLANG_MODULE_CACHE_PATH=str(root / "modules"))
                source = root / "Harness.swift"
                source.write_text(harness)
                binary = root / "harness"
                command = ["xcrun", "swiftc", "-parse-as-library", *flags, *map(str, sources),
                           str(source), "-o", str(binary)]
                compiled = subprocess.run(command, capture_output=True, text=True, timeout=120, env=environment)
                (root / "compile.log").write_text(compiled.stdout + compiled.stderr)
                self.assertEqual(compiled.returncode, 0, compiled.stderr)
                result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=40, env=environment)
                (root / "stdout.log").write_text(result.stdout)
                (root / "stderr.log").write_text(result.stderr)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(marker, result.stdout)
                lines = result.stdout.splitlines()
                events = [json.loads(line) for line in lines if line.startswith('{"')]
                facts = json.loads(next(line.split("=", 1)[1] for line in lines
                                        if line.startswith("helper-command-facts=")))
                spectrum = json.loads(next(line.split("=", 1)[1] for line in lines
                                           if line.startswith("spectrum-lifecycle-facts=")))
                self.assertEqual(sum(e["type"] == "launched" for e in events), int(configuration == "debug"))
                self.assertEqual(sum(e["type"] == "accepted" for e in events), int(configuration == "debug"))
                if configuration == "debug":
                    accepted = next(e for e in events if e["type"] == "accepted")
                    self.assertEqual((accepted["requestID"], accepted["videoPath"]), (9001, facts["videoPath"]))
                failed = [e for e in events if e["type"] == "failed" and e.get("requestID") == 9001]
                self.assertEqual(len(failed), 1)
                self.assertEqual((failed[0]["message"], failed[0]["cohortID"], failed[0].get("videoPath")),
                                 ("video_not_found", facts["cohortID"], None))
                self.assertGreater(failed[0]["preparationGeneration"], 0)
                acknowledged = [e for e in events if e["type"] == "outputActivityChanged"]
                self.assertEqual(len(acknowledged), 1)
                self.assertEqual((acknowledged[0]["requestID"], acknowledged[0]["activityID"],
                                  acknowledged[0]["outputActive"]), (9, facts["activityID"], False))
                self.assertTrue(any(e["type"] == "prepared" and e.get("requestID") == 8 for e in events))
                self.assertTrue(all(e.get("videoPath") is None for e in events
                                    if e["type"] in {"prepared", "ready", "failed", "activationDeferred"}))
                self.assertEqual(spectrum["cold"], {"bars": 0, "peaks": 0, "children": 0})
                rendering = json.loads(next(line.split("=", 1)[1] for line in lines
                                            if line.startswith("video-rendering-facts=")))
                self.assertTrue({"initializedFixedProperties", "animatedCommitPublishesCurrentOutput",
                    "animatedCancelRestoresGeometry", "fixedPropertiesAfterAnimatedCancel",
                    "firstCommitPublishesCurrentOutput", "pausedFirstPlayKeepsFixedProperties",
                    "playingFirstPlayKeepsFixedProperties", "pausedResizePreservesFillGeometry",
                    "playingResizePreservesFillGeometry"}.issubset(rendering))
                self.assertTrue(all(rendering.values()), rendering)
                rendering_by_configuration[configuration] = rendering
                (root / "result.json").write_text(json.dumps({"configuration": configuration, "command": command,
                    "sourceSHA256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                     for p in sources}, "diagnosticEvents": {name: sum(e["type"] == name for e in events)
                                     for name in ("launched", "accepted")}, "events": events,
                    "spectrum": spectrum, "rendering": rendering, "passed": True}, indent=2) + "\n")
            self.assertEqual(rendering_by_configuration["debug"], rendering_by_configuration["release"])
        finally:
            if context:
                context.cleanup()

    def test_helper_retains_previous_slot_until_finalized(self) -> None:
        sources = list((DAEMON / "Daemon").rglob("*.swift"))
        sources += [ENGINE / "DaemonProtocol.swift", ROOT / "MyWallpaperX/Core/DaemonKit/DaemonNewlineJSON.swift",
                    ROOT / "MyWallpaperX/Core/DaemonKit/DaemonParentLifetime.swift",
                    ROOT / "MyWallpaperX/Core/PlaybackControl/PlaybackSurfaceVisibility.swift",
                    ROOT / "script/tests/fixtures/VideoSpectrumLayerLifecycleChecks.swift"]
        self.compile_run(sources, HELPER_HARNESS, "video-slot-cancellation-pass")

    # Parent transaction/cancellation/retirement now executes the actual typed
    # owners in test_playback_switch_endpoints.py. The removed extracted fixture
    # encoded the retired cross-engine rollback and auto-commit authority.


if __name__ == "__main__":
    unittest.main()
