import AppKit
import AVFoundation
import CoreVideo
import Darwin
import Foundation
import ImageIO

/// An observer of the production callback, not a replacement publisher.
@MainActor private final class Receipt<Value> {
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Result<Value, Error>, Never>?
    private(set) var count = 0
    func receive(_ result: Result<Value, Error>) {
        count += 1
        self.result = result
        let waiting = continuation
        continuation = nil
        waiting?.resume(returning: result)
    }
    func value() async -> Result<Value, Error> {
        if let result { return result }
        return await withCheckedContinuation { continuation = $0 }
    }
}

/// Stop a real FileManager copy at its OS delegate boundary. The actual epoch,
/// copy, cleanup, rename and configuration code remain production code.
private nonisolated final class CopyGate: NSObject, FileManagerDelegate, @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    private let source: String
    private var blocked = false
    init(source: URL) { self.source = source.resolvingSymlinksInPath().standardizedFileURL.path }
    func fileManager(_ fileManager: FileManager, shouldCopyItemAt srcURL: URL, to dstURL: URL) -> Bool {
        if !blocked, srcURL.path == source {
            blocked = true
            entered.signal()
            _ = release.wait(timeout: .now() + 10)
        }
        return true
    }
    func waitUntilEntered() -> Bool { entered.wait(timeout: .now() + 5) == .success }
}

/// The injection records only OS scheduling. The publisher's work queue and
/// the test's gate setter exchange this one reference under the same lock.
private nonisolated final class CopyController: @unchecked Sendable {
    private let lock = NSLock()
    private var gate: CopyGate?
    func setGate(_ value: CopyGate?) { lock.withLock { gate = value } }
    func copy(_ source: URL, _ destination: URL) throws {
        let manager = FileManager()
        let current = lock.withLock { gate }
        manager.delegate = current
        try manager.copyItem(at: source, to: destination)
        withExtendedLifetime(current) {}
    }
}

@main private enum ScreenSaverIntegrationChecks {
    @MainActor private static var phase = "fixture setup" {
        didSet { FileHandle.standardError.write(Data(("ScreenSaver publisher phase=" + phase + "\n").utf8)) }
    }
    private nonisolated struct CheckFailure: Error { let description: String }
    private nonisolated static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw CheckFailure(description: message) }
    }

    @MainActor private static func begin(_ owner: ScreenSaverIntegration,
                                        _ input: ScreenSaverIntegration.PublicationInput) -> Receipt<ScreenSaverConfiguration> {
        let receipt = Receipt<ScreenSaverConfiguration>()
        owner.publish(input, fillMode: "aspectFill", playsOnBattery: false, completion: receipt.receive)
        return receipt
    }
    @MainActor private static func publish(_ owner: ScreenSaverIntegration, _ url: URL,
                                          title: String) async throws -> ScreenSaverConfiguration {
        try await begin(owner, .init(videoURL: url, title: title)).value().get()
    }
    @MainActor private static func options(_ owner: ScreenSaverIntegration) async throws -> ScreenSaverConfiguration {
        let receipt = Receipt<ScreenSaverConfiguration>()
        owner.updateOptions(fillMode: "aspectFit", playsOnBattery: true, completion: receipt.receive)
        return try await receipt.value().get()
    }
    @MainActor private static func prepareStorage(_ owner: ScreenSaverIntegration) async throws {
        let receipt = Receipt<Void>()
        owner.prepareSharedStorage(completion: receipt.receive)
        try await receipt.value().get()
    }
    @MainActor private static func clear(_ owner: ScreenSaverIntegration) async throws -> ScreenSaverConfiguration {
        let receipt = Receipt<ScreenSaverConfiguration>()
        owner.clear(completion: receipt.receive)
        return try await receipt.value().get()
    }
    private nonisolated static func wasCancelled<Value>(_ result: Result<Value, Error>) -> Bool {
        guard case let .failure(error) = result else { return false }
        return (error as? CocoaError)?.code == .userCancelled
    }
    private nonisolated static func failed<Value>(_ result: Result<Value, Error>) -> Bool {
        if case .failure = result { return true }
        return false
    }
    private nonisolated static func currentData(_ root: URL) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("current.json"))
    }
    private nonisolated static func media(_ value: ScreenSaverConfiguration, root: URL) throws -> URL {
        guard let content = value.content else { throw CheckFailure(description: "missing published content") }
        return try ScreenSaverPaths.mediaRoot(in: root, generation: content.mediaGeneration)
    }
    private nonisolated static func makeVideo(_ url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 32, AVVideoHeightKey: 32])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 32, kCVPixelBufferHeightKey as String: 32])
        writer.add(input)
        try require(writer.startWriting(), "fixture video start")
        writer.startSession(atSourceTime: .zero)
        let deadline = Date().addingTimeInterval(5)
        for index in 0..<3 {
            while !input.isReadyForMoreMediaData, Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
            try require(input.isReadyForMoreMediaData, "fixture video encoder deadline")
            var buffer: CVPixelBuffer?
            try require(CVPixelBufferCreate(kCFAllocatorDefault, 32, 32, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess,
                        "fixture video pixel buffer")
            guard let buffer else { throw CheckFailure(description: "fixture buffer missing") }
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer)!, 0x55, CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            try require(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)), "fixture video frame")
        }
        input.markAsFinished()
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        try require(finished.wait(timeout: .now() + 5) == .success && writer.status == .completed,
                    "fixture video finalization")
    }
    @MainActor private static func eventually(_ predicate: () -> Bool) async throws -> Bool {
        for _ in 0..<500 {
            if predicate() { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return predicate()
    }

    @MainActor static func main() async {
        do { try await run() }
        catch {
            let failure = error as NSError
            let detail = "ScreenSaver publisher fixture phase=\(phase)\n\(failure)\nuserInfo=\(failure.userInfo)\n"
            FileHandle.standardError.write(Data(detail.utf8))
            exit(EXIT_FAILURE)
        }
    }

    @MainActor private static func run() async throws {
        let cases = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: cases, withIntermediateDirectories: true)
        var checks: [String: Bool] = [:]
        let root = cases.appendingPathComponent("published")
        let component = cases.appendingPathComponent("source/MyWallpaperXSystemWallpaper.appex")
        try FileManager.default.createDirectory(at: component, withIntermediateDirectories: true)
        let copyController = CopyController()
        let owner = ScreenSaverIntegration(rootURL: root,
            componentSourceURL: component, copyFile: { try copyController.copy($0, $1) })
        phase = "prepare isolated video fixture"
        let video = cases.appendingPathComponent("first.mov")
        let second = cases.appendingPathComponent("second.mov")
        let delayed = cases.appendingPathComponent("delayed.mov")
        try await Task.detached(priority: .utility) { try makeVideo(video) }.value
        try FileManager.default.copyItem(at: video, to: second)
        try FileManager.default.copyItem(at: video, to: delayed)
        phase = "first revisioned publication"
        let revisionRoot = cases.appendingPathComponent("revisioned")
        let revisionOwner = ScreenSaverIntegration(rootURL: revisionRoot,
            componentSourceURL: component)
        let revisionVideo = cases.appendingPathComponent("revisioned.mov")
        try FileManager.default.copyItem(at: video, to: revisionVideo)
        let revisionInput = ScreenSaverIntegration.PublicationInput(videoURL: revisionVideo, title: "revisioned",
            revision: "r1", sourceIdentity: "video:revisioned")
        let revisionFirst = try await begin(revisionOwner, revisionInput).value().get()
        checks["RevisionedFirstPublicationDeploysCurrentContent"] = try revisionFirst.content?.kind == .video
            && revisionFirst.content?.sourceIdentity == revisionInput.sourceIdentity
            && JSONDecoder().decode(ScreenSaverConfiguration.self, from: currentData(revisionRoot)) == revisionFirst
        phase = "matching revision reuses after source removal"
        try FileManager.default.removeItem(at: revisionVideo)
        let revisionReused = try await begin(revisionOwner, revisionInput).value().get()
        checks["MatchingRevisionReusesGenerationWithoutReadingDeletedSource"] = revisionReused.content == revisionFirst.content
            && revisionReused.publicationID != revisionFirst.publicationID
        try FileManager.default.copyItem(at: video, to: revisionVideo)
        phase = "changed revision redeploys"
        let updatedRevision = ScreenSaverIntegration.PublicationInput(videoURL: revisionVideo, title: revisionInput.title,
            revision: "r2", sourceIdentity: revisionInput.sourceIdentity)
        let revisionChanged = try await begin(revisionOwner, updatedRevision).value().get()
        checks["ChangedRevisionDeploysANewGeneration"] = revisionChanged.content?.mediaGeneration != revisionReused.content?.mediaGeneration
            && revisionChanged.content?.title == updatedRevision.title
        phase = "changed input redeploys with same revision"
        let changedInput = ScreenSaverIntegration.PublicationInput(videoURL: second, title: updatedRevision.title,
            revision: updatedRevision.revision, sourceIdentity: updatedRevision.sourceIdentity)
        let inputChanged = try await begin(revisionOwner, changedInput).value().get()
        checks["ChangedInputWithSameRevisionDeploysANewGeneration"] = inputChanged.content?.mediaGeneration != revisionChanged.content?.mediaGeneration
            && inputChanged.content?.sourceIdentity == changedInput.sourceIdentity
        phase = "matching input cannot reuse corrupt current"
        try Data("broken-current".utf8).write(to: revisionRoot.appendingPathComponent("current.json"))
        let revisionRecovered = try await begin(revisionOwner, changedInput).value().get()
        checks["MatchingInputAfterCorruptCurrentRedeploysValidConfiguration"] = try revisionRecovered.content?.mediaGeneration != inputChanged.content?.mediaGeneration
            && JSONDecoder().decode(ScreenSaverConfiguration.self, from: currentData(revisionRoot)) == revisionRecovered
        phase = "nil revision always requests a fresh snapshot"
        let unversioned = ScreenSaverIntegration.PublicationInput(videoURL: second, title: changedInput.title,
            sourceIdentity: changedInput.sourceIdentity)
        let unversionedFirst = try await begin(revisionOwner, unversioned).value().get()
        let unversionedSecond = try await begin(revisionOwner, unversioned).value().get()
        checks["NilRevisionNeverReusesThePreviousGeneration"] = unversionedFirst.content?.mediaGeneration != revisionRecovered.content?.mediaGeneration
            && unversionedSecond.content?.mediaGeneration != unversionedFirst.content?.mediaGeneration
        revisionOwner.cancelForExit()

        phase = "first video publication"
        let first = try await publish(owner, video, title: "first")
        let firstMedia = try media(first, root: root)
        let deployedVideo = try ScreenSaverPaths.resource(first.content!.entryRelativePath, in: firstMedia)
        let poster = try ScreenSaverPaths.resource(first.content!.posterRelativePath, in: firstMedia)
        let originalVideo = try Data(contentsOf: video)
        try Data("source-was-replaced".utf8).write(to: video)
        checks["VideoPublishesAnIndependentCopyAndItsOwnRequiredPoster"] = try Data(contentsOf: deployedVideo) == originalVideo
            && CGImageSourceCreateWithURL(poster as CFURL, nil) != nil && !(try Data(contentsOf: poster)).isEmpty
        let beforeBadVideo = try currentData(root)
        let invalidVideo = await begin(owner, .init(videoURL: video, title: "broken")).value()
        checks["VideoPosterFailureKeepsThePreviousConfiguration"] = try failed(invalidVideo)
            && (try currentData(root)) == beforeBadVideo
        try FileManager.default.removeItem(at: video)
        let edited = try await options(owner)
        checks["OptionsRetainGenerationWithoutReadingDeletedSource"] = edited.content?.mediaGeneration == first.content?.mediaGeneration
            && edited.publicationID != first.publicationID && edited.fillMode == "aspectFit" && edited.playsOnBattery

        let beforeCancel = try currentData(root)
        phase = "cancel already-started copy"
        do {
            let gate = CopyGate(source: delayed)
            copyController.setGate(gate)
            defer { gate.release.signal(); copyController.setGate(nil) }
            let cancelled = begin(owner, .init(videoURL: delayed, title: "cancelled"))
            try require(gate.waitUntilEntered(), "real copy did not enter delegate")
            owner.cancel(); gate.release.signal()
            checks["CancelRevokesAnAlreadyStartedCopyWithoutPublication"] = try wasCancelled(await cancelled.value())
                && cancelled.count == 1 && (try currentData(root)) == beforeCancel
        }
        phase = "latest request replaces already-started copy"
        do {
            let gate = CopyGate(source: delayed)
            copyController.setGate(gate)
            defer { gate.release.signal(); copyController.setGate(nil) }
            let obsolete = begin(owner, .init(videoURL: delayed, title: "obsolete"))
            try require(gate.waitUntilEntered(), "latest-request copy did not enter delegate")
            let latest = begin(owner, .init(videoURL: second, title: "latest"))
            gate.release.signal()
            let oldResult = await obsolete.value()
            let newValue = try await latest.value().get()
            checks["LatestRequestRetiresAnOlderStartedPublication"] = try wasCancelled(oldResult)
                && obsolete.count == 1 && latest.count == 1 && newValue.content?.title == "latest"
                && (try JSONDecoder().decode(ScreenSaverConfiguration.self, from: currentData(root))) == newValue
        }
        phase = "clear invalidates already-started copy"
        do {
            let gate = CopyGate(source: delayed)
            copyController.setGate(gate)
            defer { gate.release.signal(); copyController.setGate(nil) }
            let obsolete = begin(owner, .init(videoURL: delayed, title: "must-not-revive"))
            try require(gate.waitUntilEntered(), "clear copy did not enter delegate")
            let cleared = Receipt<ScreenSaverConfiguration>()
            owner.clear(completion: cleared.receive)
            gate.release.signal()
            let oldResult = await obsolete.value()
            let empty = try await cleared.value().get()
            checks["ClearRevokesStartedPublicationAndKeepsConfigurationEmpty"] = try wasCancelled(oldResult)
                && empty.content == nil && (try JSONDecoder().decode(ScreenSaverConfiguration.self, from: currentData(root))).content == nil
        }

        let afterClear = try currentData(root)
        let emptyOptions = Receipt<ScreenSaverConfiguration>()
        owner.updateOptions(fillMode: "aspectFit", playsOnBattery: true, completion: emptyOptions.receive)
        checks["OptionsCannotCreateContentAfterClear"] = try failed(await emptyOptions.value())
            && (try currentData(root)) == afterClear

        phase = "generation lease retention and collection"
        let leased = try await publish(owner, second, title: "leased")
        let leasedRoot = try media(leased, root: root)
        let descriptor = Darwin.open(leasedRoot.appendingPathComponent(".lease").path, O_RDONLY | O_CLOEXEC)
        try require(descriptor >= 0 && flock(descriptor, LOCK_SH | LOCK_NB) == 0, "real consumer shared lease")
        var leaseOpen = true
        defer { if leaseOpen { flock(descriptor, LOCK_UN); Darwin.close(descriptor) } }
        let previous = try await publish(owner, second, title: "previous")
        _ = try await publish(owner, second, title: "current")
        _ = try await options(owner) // follows the previous commit's queued GC
        checks["RetiredGenerationSurvivesARealSharedConsumerLease"] = FileManager.default.fileExists(atPath: leasedRoot.path)
        let previousRoot = try media(previous, root: root)
        checks["PreviousConfigurationStillRetainsItsGeneration"] = try FileManager.default.fileExists(atPath: previousRoot.path)
            && JSONDecoder().decode(ScreenSaverConfiguration.self,
                from: Data(contentsOf: root.appendingPathComponent("previous.json"))).content?.mediaGeneration == previous.content?.mediaGeneration
        flock(descriptor, LOCK_UN); Darwin.close(descriptor); leaseOpen = false
        _ = try await options(owner)
        checks["ReleasedRetiredGenerationIsCollectedAtNextMaintenance"] = try await eventually {
            !FileManager.default.fileExists(atPath: leasedRoot.path)
        }
        let unknown = root.appendingPathComponent("Media/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: true)
        try Data("not-owned".utf8).write(to: unknown.appendingPathComponent(".lease"))
        _ = try await options(owner)
        checks["MaintenancePreservesUnknownMediaDirectories"] = FileManager.default.fileExists(atPath: unknown.path)

        let beforeMissingPoster = try currentData(root)
        let current = try JSONDecoder().decode(ScreenSaverConfiguration.self, from: beforeMissingPoster)
        let currentRoot = try media(current, root: root)
        try FileManager.default.removeItem(at: ScreenSaverPaths.resource(current.content!.posterRelativePath, in: currentRoot))
        let missingPosterOptions = Receipt<ScreenSaverConfiguration>()
        owner.updateOptions(fillMode: "aspectFit", playsOnBattery: true, completion: missingPosterOptions.receive)
        checks["OptionsRejectMissingRequiredMediaWithoutChangingConfiguration"] = try failed(await missingPosterOptions.value())
            && (try currentData(root)) == beforeMissingPoster

        phase = "replace unsupported and corrupt configuration only after video success"
        var invalidKindObject = try JSONSerialization.jsonObject(with: currentData(root)) as! [String: Any]
        var invalidKindContent = invalidKindObject["content"] as! [String: Any]
        invalidKindContent["kind"] = "web"
        invalidKindObject["content"] = invalidKindContent
        let unsupported = try JSONSerialization.data(withJSONObject: invalidKindObject, options: [.sortedKeys])
        let invalidSource = cases.appendingPathComponent("invalid-video.mov")
        try Data("not-a-video".utf8).write(to: invalidSource)
        invalidKindContent["kind"] = "scene"
        invalidKindObject["content"] = invalidKindContent
        let unsupportedPrevious = try JSONSerialization.data(withJSONObject: invalidKindObject, options: [.sortedKeys])
        let previousURL = root.appendingPathComponent("previous.json")
        for (name, original, stalePrevious) in [("UnsupportedKind", unsupported, unsupportedPrevious),
                ("Corrupt", Data("not-json".utf8), Data("not-json-previous".utf8))] {
            let retired = try JSONDecoder().decode(ScreenSaverConfiguration.self, from: currentData(root))
            let retiredRoot = try media(retired, root: root)
            let retiredLease = Darwin.open(retiredRoot.appendingPathComponent(".lease").path, O_RDONLY | O_CLOEXEC)
            try require(retiredLease >= 0 && flock(retiredLease, LOCK_SH | LOCK_NB) == 0, "replacement consumer lease")
            var retiredLeaseOpen = true
            defer { if retiredLeaseOpen { flock(retiredLease, LOCK_UN); Darwin.close(retiredLease) } }
            try original.write(to: root.appendingPathComponent("current.json"))
            try stalePrevious.write(to: previousURL)
            let rejectedOptions = Receipt<ScreenSaverConfiguration>()
            owner.updateOptions(fillMode: "aspectFit", playsOnBattery: true, completion: rejectedOptions.receive)
            checks[name + "OptionsCannotOverwriteUnusableConfiguration"] = try failed(await rejectedOptions.value())
                && (try currentData(root)) == original && (try Data(contentsOf: previousURL)) == stalePrevious
            let failedCandidate = await begin(owner, .init(videoURL: invalidSource, title: "invalid replacement")).value()
            checks[name + "FailedVideoLeavesBothOriginalDiskValuesUntouched"] = try failed(failedCandidate)
                && (try currentData(root)) == original && (try Data(contentsOf: previousURL)) == stalePrevious
            do {
                let gate = CopyGate(source: second)
                copyController.setGate(gate)
                defer { gate.release.signal(); copyController.setGate(nil) }
                let cancelled = begin(owner, .init(videoURL: second, title: "cancelled replacement"))
                try require(gate.waitUntilEntered(), "cancelled replacement copy did not enter delegate")
                owner.cancel(); gate.release.signal()
                checks[name + "CancelledVideoKeepsBothOriginalDiskValues"] = try wasCancelled(await cancelled.value())
                    && (try currentData(root)) == original && (try Data(contentsOf: previousURL)) == stalePrevious
            }
            let gate = CopyGate(source: second)
            copyController.setGate(gate)
            defer { gate.release.signal(); copyController.setGate(nil) }
            let candidate = begin(owner, .init(videoURL: second, title: "replacement " + name))
            try require(gate.waitUntilEntered(), "replacement video copy did not enter delegate")
            checks[name + "BothDiskValuesRemainWhileVideoCandidateIsPreparing"] = try currentData(root) == original
                && (try Data(contentsOf: previousURL)) == stalePrevious
            gate.release.signal()
            let replacement = try await candidate.value().get()
            checks[name + "ValidVideoReplacesCurrentAndRetiresStalePrevious"] = try replacement.content?.kind == .video
                && (try JSONDecoder().decode(ScreenSaverConfiguration.self, from: currentData(root))) == replacement
                && !FileManager.default.fileExists(atPath: previousURL.path)
            _ = try await options(owner)
            checks[name + "ReplacementMaintenanceHonorsActiveLeaseAndUnknownDirectory"] =
                FileManager.default.fileExists(atPath: retiredRoot.path) && FileManager.default.fileExists(atPath: unknown.path)
            flock(retiredLease, LOCK_UN); Darwin.close(retiredLease); retiredLeaseOpen = false
            _ = try await options(owner)
            checks[name + "RetiredOwnedMediaCanBeCollectedAfterLeaseRelease"] = try await eventually {
                !FileManager.default.fileExists(atPath: retiredRoot.path)
            }
        }

        phase = "direct current-root initialization"
        let sharedRoot = cases.appendingPathComponent("current-shared-root")
        let oldPrivateRoot = cases.appendingPathComponent("old-private-root")
        try FileManager.default.createDirectory(at: oldPrivateRoot, withIntermediateDirectories: true)
        let oldPrivateFile = oldPrivateRoot.appendingPathComponent("current.json")
        let oldPrivateBytes = Data("retired private data stays untouched".utf8)
        try oldPrivateBytes.write(to: oldPrivateFile)
        let currentOwner = ScreenSaverIntegration(rootURL: sharedRoot, componentSourceURL: component)
        try await prepareStorage(currentOwner)
        checks["PreparationInitializesOnlyTheCurrentRootWithoutASymbolicLink"] = try currentOwner.hasBundledComponent
            && currentOwner.configurationRoot?.standardizedFileURL.path == sharedRoot.standardizedFileURL.path
            && FileManager.default.fileExists(atPath: sharedRoot.path)
            && (try sharedRoot.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == false
            && Data(contentsOf: oldPrivateFile) == oldPrivateBytes
        let blockedRoot = cases.appendingPathComponent("blocked-storage-parent")
        try Data("not a directory".utf8).write(to: blockedRoot)
        let blockedOwner = ScreenSaverIntegration(rootURL: blockedRoot.appendingPathComponent("child"), componentSourceURL: component)
        let preparationFailure = Receipt<Void>()
        blockedOwner.prepareSharedStorage(completion: preparationFailure.receive)
        checks["CurrentRootPreparationReportsFilesystemFailureWithoutFallback"] = try failed(await preparationFailure.value())
            && preparationFailure.count == 1 && blockedOwner.errorMessage != nil
            && Data(contentsOf: blockedRoot) == Data("not a directory".utf8) && Data(contentsOf: oldPrivateFile) == oldPrivateBytes
        currentOwner.cancelForExit(); blockedOwner.cancelForExit()

        phase = "corrupt current configuration clear"
        try Data("not-json".utf8).write(to: root.appendingPathComponent("current.json"))
        let recovered = try await clear(owner)
        checks["ExplicitClearReplacesCorruptConfigurationWithValidEmptyConfig"] = try recovered.content == nil
            && (try JSONDecoder().decode(ScreenSaverConfiguration.self, from: currentData(root))).content == nil
        owner.cancelForExit()
        let late = await begin(owner, .init(videoURL: second, title: "after-exit")).value()
        checks["ExitRevocationCannotPublishAgain"] = try wasCancelled(late)
            && (try JSONDecoder().decode(ScreenSaverConfiguration.self, from: currentData(root))).content == nil
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
    }
}
