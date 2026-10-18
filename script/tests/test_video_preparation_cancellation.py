"""Video two-slot prepare/commit/finalize and cross-runtime cancellation gates."""

from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
DAEMON = ROOT / "WallpaperDaemonSources"
ENGINE = ROOT / "MyWallpaperX/Core/Playback"


def method(source: str, name: str) -> str:
    start = source.index(f"    func {name}(") if f"    func {name}(" in source else source.index(f"    private func {name}(")
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end].replace("private func", "func", 1)


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
        daemon.finalizeVideoPreparation(requestID: 3)
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
        daemon.finalizeVideoPreparation(requestID: 6)
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
        daemon.finalizeVideoPreparation(requestID: 9)
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
        daemon.play(videoPath: corrupt.path, framePath: nil, fillMode: "aspectFill",
            shouldLoopCurrentItem: false, requestID: 10)
        let failureDeadline = Date().addingTimeInterval(9)
        while daemon.videoPreparation != nil && Date() < failureDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        fflush(stdout)
        precondition(dup2(originalStdout, STDOUT_FILENO) >= 0)
        close(originalStdout)
        try! emitted.fileHandleForWriting.close()
        let eventData = emitted.fileHandleForReading.readDataToEndOfFile()
        let failures = eventData.split(separator: 0x0A).compactMap {
            try? JSONDecoder().decode(DaemonEvent.self, from: Data($0))
        }
        precondition(failures.contains { $0.type == "failed" && $0.requestID == 10
            && $0.videoPath == corrupt.path }, "existing corrupt video produced no correlated failed event")
        precondition(!failures.contains { $0.type == "prepared" || $0.type == "ready" })
        precondition(daemon.videoPreparation == nil && daemon.currentVideoPath == fixture.path
            && daemon.currentRequestID == 9 && daemon.activePlayer.currentItem === committedItem,
            "corrupt existing candidate replaced or damaged committed A")
        print("video-slot-cancellation-pass")
    }
}
'''


PARENT_STUB = r'''
final class WebDaemonHostAdapter { var activeRequest: String? }
import Foundation
import QuartzCore
enum WallpaperRuntimeKind { case video, web, scene }
var runtimeSwitchCount = 0
func postWallpaperRuntimeWillSwitch(to: WallpaperRuntimeKind, recordID: String? = nil) { runtimeSwitchCount += 1 }
final class WallpaperEngine {
    enum PlaybackContentKind: String { case video, web }
    enum WebWallpaperRuntimeCommand { case stop, pause }
    enum WebWallpaperHostEvent { case accepted(UUID), ready(UUID), audioSpectrumDemandChanged(Bool, UUID), failed(message: String, requestID: UUID), stopped(UUID) }
    final class DisplayDaemonSession {
        final class ProcessState { var isRunning = true }
        let process = ProcessState()
        let displayID: UInt32
        var launched = false
        var latestRequestedPlayRequestID: Int?
        var latestAcceptedPlayRequestID: Int?
        var latestPreparedPlayRequestID: Int?
        var latestCommittedPlayRequestID: Int?
        var latestReadyPlayRequestID: Int?
        var latestFinalizedPlayRequestID: Int?
        init(_ id: UInt32, requested: Int, finalized: Int?) {
            displayID = id; latestRequestedPlayRequestID = requested
            latestFinalizedPlayRequestID = finalized
        }
    }
    struct ActiveVideoPlayback { let id = UUID(); let wallpaper: String; let path: String; let multiDisplayEnabled: Bool }
    var activeVideoPlayback: ActiveVideoPlayback? {
        didSet { if activeVideoPlayback?.id != oldValue?.id { videoEndState = nil } }
    }
    var videoEndState: (playbackID: UUID, delivered: Bool)?
    var retainedVideoWallpaper: String?, retainedVideoContentPath: String?
    var retainedVideoMultiDisplayEnabled: Bool?
    var dedicatedWebHostAdapter: Any = WebDaemonHostAdapter()
    var playbackPaused = false
    func restoreActiveWebRequest(_ request: String) {}
    func beginPlaybackIntent() { playbackIntentEpoch += 1 }
    var pendingVideoDisplayIDs: Set<UInt32> = []
    var pendingVideoIsRetainedRecovery = false
    var videoPreparationIntentEpoch: UInt64 = 0
    var playbackIntentEpoch: UInt64 = 0
    var pendingVideoRetirementOnWebReady = false
    var displaySessions: [UInt32: DisplayDaemonSession] = [:]
    var currentPlaybackContentKind: PlaybackContentKind? = .video
    var currentWallpaper: String? = "/B", currentContentPath: String? = "/B"
    var currentMultiDisplayEnabled = true
    var pendingWebRetirementOnVideoReady = false
    var currentWebRequestID: UUID?
    var currentWebRecordID: String?, currentWebPropertiesJSON: String?
    var lastFailureVideoPath: String?, lastFailureAt: Double = 0
    var displayCrashCounts: [UInt32: Int] = [:]
    var admitted = true
    var runtimeCommitAdmission: ((WallpaperRuntimeKind) -> Bool)?
    var commands: [(String, UInt32, Int)] = []
    var displayIDs: [UInt32] = [1, 2]
    var currentVideoFillMode = "aspectFill", currentShouldLoopCurrentItem = true
    var recoveryApplies = 0
    static let webPlaybackReadyNotification = Notification.Name("web-ready")
    static let playbackEndedNotification = Notification.Name("ended")
    static let playbackReadyNotification = Notification.Name("ready")
    static let playbackFailedNotification = Notification.Name("failed")
    func sendVideoPreparationCommand(_ action: String, requestID: Int, to session: DisplayDaemonSession) {
        commands.append((action, session.displayID, requestID))
    }
    func terminateSession(for id: UInt32) {
        displaySessions.removeValue(forKey: id)
        if displaySessions.isEmpty, currentPlaybackContentKind != .video,
           !pendingVideoRetirementOnWebReady { activeVideoPlayback = nil }
    }
    func dispatchWebRuntimeCommand(_ command: WebWallpaperRuntimeCommand) {}
    func setWebAudioSpectrumRequested(_ requested: Bool) {}
    func rollbackVideoPreparationToWeb() -> Bool { false }
    func scanDisplays() {}
    func applyWallpaper(_ wallpaper: String, multiDisplayEnabled: Bool,
        videoFillMode: String, shouldLoopCurrentItem: Bool, retainedVideoRecovery: Bool = false) {
        precondition(retainedVideoRecovery)
        recoveryApplies += 1
        pendingVideoIsRetainedRecovery = true
        videoPreparationIntentEpoch = playbackIntentEpoch
        pendingVideoDisplayIDs = [1, 2]
        displaySessions = [1: .init(1, requested: 10, finalized: nil), 2: .init(2, requested: 10, finalized: nil)]
    }
}
'''


PARENT_HARNESS = r'''
@main enum Harness {
    static func main() {
        func make(_ hasActive: Bool = true) -> WallpaperEngine {
            let engine = WallpaperEngine()
            engine.displaySessions = [1: .init(1, requested: 2, finalized: hasActive ? 1 : nil),
                                      2: .init(2, requested: 3, finalized: hasActive ? 1 : nil)]
            engine.pendingVideoDisplayIDs = [1, 2]
            if hasActive { engine.activeVideoPlayback = .init(wallpaper: "/A", path: "/A", multiDisplayEnabled: true) }
            engine.runtimeCommitAdmission = { [weak engine] _ in engine?.admitted == true }
            return engine
        }
        func deliver(_ engine: WallpaperEngine, _ type: String, _ display: UInt32, _ id: Int, path: String = "/B") {
            guard let session = engine.displaySessions[display] else { return }
            engine.handleDaemonEvent(.init(type: type, displayID: display, requestID: id,
                message: "bad-video", videoPath: path, contentKind: "video"), for: session)
        }
        let cancelled = make()
        deliver(cancelled, "prepared", 1, 2)
        precondition(cancelled.commands.isEmpty, "one screen prematurely committed")
        deliver(cancelled, "prepared", 2, 3)
        precondition(cancelled.commands.filter { $0.0 == "commitVideo" }.count == 2)
        deliver(cancelled, "ready", 1, 2)
        cancelled.admitted = false
        cancelled.cancelVideoPreparationRetainingActivePlayback()
        deliver(cancelled, "ready", 2, 3)
        precondition(cancelled.commands.filter { $0.0 == "finalizeVideo" }.isEmpty)
        precondition(cancelled.commands.filter { $0.0 == "cancelVideoPreparation" }.count == 2)
        precondition(cancelled.currentContentPath == "/A" && cancelled.displaySessions.count == 2)

        let noActive = make(false)
        noActive.cancelVideoPreparationRetainingActivePlayback()
        precondition(noActive.displaySessions.isEmpty && noActive.currentContentPath == nil)
        let failed = make()
        deliver(failed, "failed", 1, 2)
        precondition(failed.currentContentPath == "/A" && failed.currentWallpaper == "/A")
        let identityRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: identityRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: identityRoot) }
        let resource = identityRoot.appendingPathComponent("renamed-resource.mov")
        let alias = identityRoot.appendingPathComponent("selected-alias.mov")
        try! Data("fixture".utf8).write(to: resource)
        try! FileManager.default.createSymbolicLink(at: alias, withDestinationURL: resource)
        let aliasFailure = make()
        aliasFailure.currentContentPath = aliasFailure.normalizedPath(resource.path)
        deliver(aliasFailure, "failed", 1, 2, path: alias.path)
        precondition(aliasFailure.currentContentPath == "/A", "alias failure lost rollback authority")
        let unrelatedFailure = make()
        unrelatedFailure.currentContentPath = unrelatedFailure.normalizedPath(resource.path)
        deliver(unrelatedFailure, "failed", 1, 2, path: identityRoot.appendingPathComponent("other.mov").path)
        precondition(unrelatedFailure.commands.isEmpty, "different resource gained failure authority")
        let aliasReady = make()
        aliasReady.currentContentPath = aliasReady.normalizedPath(resource.path)
        deliver(aliasReady, "prepared", 1, 2, path: alias.path)
        deliver(aliasReady, "prepared", 2, 3, path: resource.path)
        deliver(aliasReady, "ready", 1, 2, path: resource.path)
        deliver(aliasReady, "ready", 2, 3, path: alias.path)
        precondition(aliasReady.commands.filter { $0.0 == "finalizeVideo" }.count == 2,
            "equivalent resource spelling could not finalize")
        let dead = make()
        for session in dead.displaySessions.values { session.process.isRunning = false }
        dead.cancelVideoPreparationRetainingActivePlayback()
        precondition(dead.displaySessions.isEmpty && dead.currentContentPath == "/A",
            "the committed A identity needed for recovery was discarded")

        let committed = make()
        deliver(committed, "prepared", 1, 2); deliver(committed, "prepared", 2, 3)
        deliver(committed, "ready", 1, 2)
        precondition(committed.commands.filter { $0.0 == "finalizeVideo" }.isEmpty)
        deliver(committed, "ready", 2, 3)
        precondition(committed.commands.filter { $0.0 == "finalizeVideo" }.count == 2)
        precondition(committed.activeVideoPlayback?.path == "/B")
        committed.cancelVideoPreparationRetainingActivePlayback()
        precondition(committed.displaySessions.count == 2 && committed.currentContentPath == "/B")

        let recovery = make()
        recovery.currentContentPath = "/A"; recovery.currentWallpaper = "/A"
        recovery.pendingVideoIsRetainedRecovery = true
        recovery.admitted = false // A is retained while product prepares Web.
        let switchesBeforeRecovery = runtimeSwitchCount
        deliver(recovery, "prepared", 1, 2, path: "/A")
        deliver(recovery, "prepared", 2, 3, path: "/A")
        precondition(recovery.commands.filter { $0.0 == "commitVideo" }.count == 2)
        deliver(recovery, "ready", 1, 2, path: "/A")
        deliver(recovery, "ready", 2, 3, path: "/A")
        precondition(recovery.commands.filter { $0.0 == "finalizeVideo" }.count == 2)
        precondition(recovery.activeVideoPlayback?.path == "/A" && runtimeSwitchCount == switchesBeforeRecovery,
            "retained recovery either stalled or stole the new runtime intent")

        let staleRecovery = make()
        staleRecovery.currentContentPath = "/A"; staleRecovery.currentWallpaper = "/A"
        staleRecovery.pendingVideoIsRetainedRecovery = true
        staleRecovery.admitted = false
        staleRecovery.playbackIntentEpoch = 1
        deliver(staleRecovery, "prepared", 1, 2, path: "/A")
        deliver(staleRecovery, "prepared", 2, 3, path: "/A")
        precondition(staleRecovery.commands.isEmpty, "stale recovery epoch bypassed intent admission")

        let rolledBack = make()
        rolledBack.displaySessions.removeAll()
        rolledBack.currentPlaybackContentKind = .web
        rolledBack.currentContentPath = "pending-Web"
        rolledBack.admitted = false
        rolledBack.pendingVideoDisplayIDs.removeAll()
        rolledBack.pendingVideoRetirementOnWebReady = true
        rolledBack.retainedVideoWallpaper = "/A"; rolledBack.retainedVideoContentPath = "/A"
        rolledBack.retainedVideoMultiDisplayEnabled = true
        let failedWeb = UUID(); rolledBack.currentWebRequestID = failedWeb
        rolledBack.handleWebHostEvent(.failed(message: "timeout", requestID: failedWeb))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        precondition(rolledBack.recoveryApplies == 1 && rolledBack.pendingVideoIsRetainedRecovery)
        deliver(rolledBack, "prepared", 1, 10, path: "/A")
        deliver(rolledBack, "prepared", 2, 10, path: "/A")
        precondition(rolledBack.commands.filter { $0.0 == "commitVideo" }.count == 2)

        let partial = make()
        partial.pendingVideoDisplayIDs.removeAll()
        partial.displaySessions = [1: .init(1, requested: 1, finalized: 1)]
        partial.currentPlaybackContentKind = .web; partial.currentContentPath = "pending-Web"
        partial.pendingVideoRetirementOnWebReady = true
        partial.retainedVideoWallpaper = "/A"; partial.retainedVideoContentPath = "/A"
        let partialWeb = UUID(); partial.currentWebRequestID = partialWeb
        partial.handleWebHostEvent(.failed(message: "late-old", requestID: UUID()))
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        precondition(partial.recoveryApplies == 0 && partial.currentPlaybackContentKind == .web)
        partial.handleWebHostEvent(.failed(message: "natural-failure", requestID: partialWeb))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        precondition(partial.recoveryApplies == 1, "healthy remaining display masked the missing helper")

        let ended = make()
        ended.pendingVideoDisplayIDs.removeAll()
        ended.currentContentPath = "/A"; ended.currentWallpaper = "/A"
        ended.displaySessions = [1: .init(1, requested: 2, finalized: 1)]
        ended.admitted = false // Web is still parsing, before Engine kind changes.
        var endedNotifications = 0
        let endedObserver = NotificationCenter.default.addObserver(forName: WallpaperEngine.playbackEndedNotification,
            object: nil, queue: nil) { _ in endedNotifications += 1 }
        defer { NotificationCenter.default.removeObserver(endedObserver) }
        ended.handleDaemonEvent(.init(type: "ended", displayID: 1, requestID: nil,
            message: nil, videoPath: "/A", contentKind: "video"), for: ended.displaySessions[1]!)
        precondition(ended.videoEndState == nil, "uncorrelated terminal was admitted")
        deliver(ended, "ended", 1, 99, path: "/A")
        precondition(ended.videoEndState == nil, "stale helper request became a terminal")
        deliver(ended, "ended", 1, 1, path: "/A")
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        precondition(endedNotifications == 0 && ended.videoEndState?.delivered == false)
        ended.admitted = true
        ended.replayDeferredVideoEndIfNeeded()
        ended.replayDeferredVideoEndIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        precondition(endedNotifications == 1, "rollback lost or duplicated the retained terminal")
        deliver(ended, "ended", 1, 1, path: "/A")
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        precondition(endedNotifications == 1, "multi-display duplicate consumed twice")
        ended.activeVideoPlayback = .init(wallpaper: "/A", path: "/A", multiDisplayEnabled: true)
        ended.admitted = false; ended.currentPlaybackContentKind = .web
        deliver(ended, "ended", 1, 1, path: "/A")
        ended.currentPlaybackContentKind = .video; ended.admitted = true
        ended.replayDeferredVideoEndIfNeeded()
        ended.activeVideoPlayback = .init(wallpaper: "/A", path: "/A", multiDisplayEnabled: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        precondition(endedNotifications == 1, "old terminal crossed same-path replay identity")

        let superseded = make()
        superseded.displaySessions.removeAll()
        superseded.cancelVideoPreparationRetainingActivePlayback()
        superseded.playbackIntentEpoch += 1
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        precondition(superseded.recoveryApplies == 0, "old deferred recovery crossed a new epoch")
        print("video-parent-cancellation-pass")
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
        sources += [ENGINE / "DaemonProtocol.swift", ROOT / "MyWallpaperX/Core/DaemonKit/DaemonNewlineJSON.swift"]
        self.compile_run(sources, HELPER_HARNESS, "video-slot-cancellation-pass")

    def test_parent_cancels_exact_requests_and_restores_active_video(self) -> None:
        events = (ENGINE / "WallpaperEngine+DaemonEvents.swift").read_text()
        lifecycle = (ENGINE / "WallpaperEngine+DaemonSessionLifecycle.swift").read_text()
        functions = [method((ENGINE / "WallpaperEngine.swift").read_text(), "normalizedPath")]
        functions += [method(events, name) for name in ["handleDaemonEvent", "handlePlaybackFailureEvent", "reportVideoPlaybackFailure", "handlePlaybackEndedEvent", "replayDeferredVideoEndIfNeeded"]]
        functions += [method(lifecycle, "cancelVideoPreparationRetainingActivePlayback")]
        functions += [method(lifecycle, "scheduleRetainedVideoRecoveryIfNeeded")]
        functions += [method((ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Engine/WallpaperEngine+WebWallpaper.swift").read_text(), "handleWebHostEvent")]
        harness = PARENT_STUB + "\nextension WallpaperEngine {\n" + "\n".join(functions) + "\n}\n" + PARENT_HARNESS
        self.compile_run([ENGINE / "DaemonProtocol.swift"], harness, "video-parent-cancellation-pass")


if __name__ == "__main__":
    unittest.main()
