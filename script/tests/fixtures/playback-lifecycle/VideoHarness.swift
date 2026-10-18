import AppKit
import AVFoundation
import CoreVideo
import Foundation

@main enum Harness {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard let screen = NSScreen.screens.first,
              let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let daemon = WallpaperDaemon(displayID: display.uint32Value) else { fatalError("display unavailable") }
        defer { daemon.window.orderOut(nil); daemon.players.forEach { $0.pause(); $0.removeAllItems() } }
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        do {
            let writer = try AVAssetWriter(outputURL: fixture, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
            writer.add(input); precondition(writer.startWriting()); writer.startSession(atSourceTime: .zero)
            for index in 0..<60 {
                while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.001) }
                var buffer: CVPixelBuffer?
                precondition(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess)
                CVPixelBufferLockBaseAddress(buffer!, [])
                memset(CVPixelBufferGetBaseAddress(buffer!), 0x55, CVPixelBufferGetDataSize(buffer!))
                CVPixelBufferUnlockBaseAddress(buffer!, [])
                precondition(adaptor.append(buffer!, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
            }
            input.markAsFinished()
            let done = DispatchSemaphore(value: 0); writer.finishWriting { done.signal() }
            precondition(done.wait(timeout: .now() + 5) == .success && writer.status == .completed)
        } catch { fatalError("fixture: \(error)") }
        func until(_ predicate: () -> Bool) {
            let deadline = Date().addingTimeInterval(8)
            while !predicate() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            precondition(predicate(), "bounded child state did not settle")
        }
        func command(_ action: String, request: Int, cohort: UUID, generation: UInt64? = nil,
                     activation: UUID? = nil, active: Bool? = nil, activity: UUID? = nil) -> DaemonCommand {
            var value = DaemonCommand(action: action, videoPath: nil, framePath: nil, propertiesJSON: nil,
                fillMode: nil, shouldLoopCurrentItem: nil, volume: nil, playbackRate: nil, spectrumEnabled: nil,
                spectrumLevels: nil, spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil,
                spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: request)
            value.cohortID = cohort; value.preparationGeneration = generation; value.activationID = activation
            value.outputActive = active; value.activityID = activity
            return value
        }
        daemon.paused = true
        let cohortA = UUID(), activationA = UUID()
        daemon.play(videoPath: fixture.path, framePath: nil, fillMode: "aspectFill", shouldLoopCurrentItem: true, requestID: 1, cohortID: cohortA)
        until { daemon.videoPreparation?.isPrepared == true }
        let generationA = UInt64(daemon.switchToken)
        daemon.handle(command("commitVideo", request: 1, cohort: cohortA, generation: generationA, activation: activationA))
        precondition(daemon.videoPreparation?.visibilityConfirmed == false, "immediate ready before WindowServer check")
        until { daemon.videoPreparation?.visibilityConfirmed == true }
        precondition(daemon.window.level == PlaybackSurfaceVisibility.activationLevel(normal: WallpaperDaemon.desktopWindowLevel))
        daemon.handle(command("finalizeVideo", request: 1, cohort: cohortA, generation: generationA, activation: UUID()))
        precondition(daemon.videoPreparation != nil, "stale finalize retired state")
        daemon.handle(command("finalizeVideo", request: 1, cohort: cohortA, generation: generationA, activation: activationA))
        precondition(daemon.videoPreparation == nil && daemon.window.level == WallpaperDaemon.desktopWindowLevel)
        let original = daemon.activePlayer.currentItem
        let cohortB = UUID(), activationB = UUID()
        daemon.play(videoPath: fixture.path, framePath: nil, fillMode: "aspectFill", shouldLoopCurrentItem: true, requestID: 2, cohortID: cohortB)
        until { daemon.videoPreparation?.isPrepared == true }
        let generationB = UInt64(daemon.switchToken)
        daemon.updateVideoLoopPolicy(false)
        precondition(daemon.primaryLooper == nil && daemon.secondaryLooper == nil)
        precondition(daemon.primaryPlayer.items().count == 1 && daemon.secondaryPlayer.items().count == 1)
        precondition(daemon.primaryEndObservation != nil && daemon.secondaryEndObservation != nil,
            "loop policy did not reach candidate and rollback slot")
        daemon.updateVideoLoopPolicy(true)
        precondition(daemon.primaryLoopEndObservation != nil && daemon.secondaryLoopEndObservation != nil)
        let activity = UUID()
        daemon.handle(command("setOutputActivity", request: 1, cohort: cohortA, active: false, activity: activity))
        precondition(!daemon.outputActivityAllowed && daemon.activePlayer.volume == 0)
        daemon.handle(command("commitVideo", request: 2, cohort: cohortB, generation: generationB, activation: activationB))
        until { daemon.videoPreparation?.visibilityConfirmed == true }
        precondition(daemon.inactivePlayer.currentItem === original, "previous item released before finalize")
        daemon.handle(command("cancelVideoPreparation", request: 2, cohort: cohortB, generation: generationB, activation: UUID()))
        precondition(daemon.currentRequestID == 2, "stale cancel affected candidate")
        daemon.handle(command("cancelVideoPreparation", request: 2, cohort: cohortB, generation: generationB, activation: activationB))
        precondition(daemon.currentRequestID == 1 && daemon.activePlayer.currentItem === original)
        precondition(!daemon.outputActivityAllowed && daemon.activePlayer.volume == 0)
        daemon.handle(command("setOutputActivity", request: 1, cohort: cohortA, active: true, activity: UUID()))
        precondition(daemon.outputActivityAllowed && daemon.activePlayer.rate == 0, "restore overwrote paused policy")
        let cohortC = UUID()
        daemon.play(videoPath: fixture.path, framePath: nil, fillMode: "aspectFill", shouldLoopCurrentItem: true, requestID: 3, cohortID: cohortC)
        daemon.handle(command("cancelVideoPreparation", request: 3, cohort: cohortC, activation: UUID()))
        precondition(daemon.videoPreparation == nil && daemon.currentRequestID == 1, "early cancel lost retained slot")
        let cohortD = UUID(), activationD = UUID()
        daemon.play(videoPath: fixture.path, framePath: nil, fillMode: "aspectFill", shouldLoopCurrentItem: true, requestID: 4, cohortID: cohortD)
        until { daemon.videoPreparation?.isPrepared == true }
        let generationD = UInt64(daemon.switchToken)
        daemon.window.alphaValue = 0.2
        daemon.handle(command("commitVideo", request: 4, cohort: cohortD, generation: generationD, activation: activationD))
        until { daemon.videoPreparation == nil }
        precondition(daemon.currentRequestID == 1 && daemon.activePlayer.currentItem === original,
            "low-alpha timeout destroyed retained output")
        precondition(!daemon.outputActivityAllowed)
        daemon.handle(command("cancelVideoPreparation", request: 4, cohort: cohortD, generation: generationD, activation: activationD))
        daemon.window.alphaValue = 1
        print("video-visible-cancellation-pass")
    }
}
