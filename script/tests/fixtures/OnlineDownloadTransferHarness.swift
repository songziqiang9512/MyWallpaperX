import Combine
import Darwin
import Foundation

nonisolated final class TransferProbe: @unchecked Sendable {
    struct Move {
        let source: URL
        let destination: URL
        let sameInode: Bool
        let sourceRemoved: Bool
    }
    static let shared = TransferProbe()
    private let lock = NSLock()
    private var moves: [Move] = []
    private var rejectedAdoptions = 0
    static func identity(_ url: URL) -> (UInt64, UInt64)? {
        var value = stat()
        guard stat(url.path, &value) == 0 else { return nil }
        return (UInt64(value.st_dev), UInt64(value.st_ino))
    }
    func moved(from source: URL, to destination: URL, identity original: (UInt64, UInt64)?) {
        let current = Self.identity(destination)
        let same = original != nil && current != nil && original!.0 == current!.0 && original!.1 == current!.1
        lock.lock()
        moves.append(.init(source: source, destination: destination, sameInode: same,
            sourceRemoved: !FileManager.default.fileExists(atPath: source.path)))
        lock.unlock()
    }
    var snapshot: [Move] { lock.lock(); defer { lock.unlock() }; return moves }
    var adoptionFailures: Int { lock.lock(); defer { lock.unlock() }; return rejectedAdoptions }
    func renameStaged(_ staging: URL, to destination: URL) -> Int32 {
        guard destination.lastPathComponent == "adoption-failure.mp4" else {
            return Darwin.rename(staging.path, destination.path)
        }
        precondition(FileManager.default.fileExists(atPath: staging.path)
            && FileManager.default.fileExists(atPath: destination.path), "adoption fixture needs both actual stage and old file")
        let parent = destination.deletingLastPathComponent()
        var original = stat()
        precondition(stat(parent.path, &original) == 0)
        precondition(chmod(parent.path, 0o555) == 0)
        let result = Darwin.rename(staging.path, destination.path)
        let savedError = errno
        precondition(chmod(parent.path, original.st_mode & 0o7777) == 0)
        if result != 0 {
            lock.lock(); rejectedAdoptions += 1; lock.unlock()
        }
        errno = savedError
        return result
    }
}

// DOWNLOAD_DELEGATE

// Recording leaves for the current library playback/publication boundary.
@MainActor enum WallpaperPlaybackSequence { struct Pending {} }
@MainActor struct ImportedVideoPlaybackAdmission {}
@MainActor struct ImportedVideoPlaybackRequest {
    let localURL: URL
    let admission: ImportedVideoPlaybackAdmission
    func post(name: Notification.Name) { OnlineLibraryService.playRequests.append(localURL) }
}
extension Notification.Name { static let onlineVideoReadyToPlay = Notification.Name("owned-online-play") }

@MainActor final class OnlineLibraryService {
    struct DownloadedEntry { let id: Int; let localURL: URL; var isAvailable = true }
    struct DownloadedContent { var entries: [DownloadedEntry] = [] }
    static var playRequests: [URL] = []
    @Published var downloadingIDs = Set<Int>()
    @Published var downloadProgressByID: [Int: Double] = [:]
    var downloadedIDs = Set<Int>()
    var lastDownloadedItemID: Int?
    var downloadSuccessMessage: String?
    var downloadError: String?
    var requestLibraryPlayback: ((WallpaperReference) -> Void)?
    var prepareExplicitLibraryRestoration: ((WallpaperReference) -> (() -> Void)?)?
    var prepareVideoPlaybackIntent: ((WallpaperReference, WallpaperPlaybackSequence.Pending?) -> ImportedVideoPlaybackAdmission?)? = { _, _ in .init() }
    var downloadedContent = DownloadedContent()
    var downloadedContentTask: Task<Void, Never>?
    var downloadedContentGeneration: UInt64 = 0
    var initialDownloadedScanCompleted = true

    init() {
        requestLibraryPlayback = { [weak self] reference in
            guard reference.provider == .pixabay, let id = Int(reference.sourceID) else { return }
            self?.postReadyToPlay(id: id, libraryPending: .init())
        }
    }

    func refreshDownloadedContent() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.downloadDirectory,
            includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        let entries: [DownloadedEntry] = files.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "mp4", name.hasPrefix("online_"),
                  let id = Int(name.dropFirst("online_".count)),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            return .init(id: id, localURL: url)
        }
        publishDownloadedContent(entries)
    }

    func publishDownloadedContent(_ entries: [DownloadedEntry]) {
        downloadedContent.entries = entries
        downloadedIDs = Set(entries.filter(\.isAvailable).map(\.id))
    }
    // SERVICE_METHODS
}

@main enum TransferHarness {
    enum Failure: Error { case deadline }
    @MainActor static func until(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(8)
        while !condition(), Date() < end { try await Task.sleep(nanoseconds: 5_000_000) }
        guard condition() else { throw Failure.deadline }
    }
    @MainActor static func main() async throws {
        let base = CommandLine.arguments[1]
        let home = URL(fileURLWithPath: CommandLine.arguments[2]).resolvingSymlinksInPath().standardizedFileURL
        let destination = OnlineLibraryService.downloadDirectory.resolvingSymlinksInPath().standardizedFileURL
        precondition(destination.path.hasPrefix(home.path + "/"), "test must never write user Movies")
        let service = OnlineLibraryService()
        var progress: [Int: [Double]] = [:]
        let subscription = service.$downloadProgressByID.sink { values in
            for (id, value) in values { progress[id, default: []].append(value) }
        }
        defer { subscription.cancel() }
        func file(_ path: String, size: Int) -> OnlineLibraryVideoFile {
            .init(url: path, width: 640, height: 360, size: size, thumbnail: "")
        }
        func item(_ id: Int, path: String, size: Int) -> OnlineLibraryVideoItem {
            .init(id: id, pageURL: "", tags: "", duration: 1, user: "",
                videos: .init(large: file(base + path, size: size), medium: nil, small: nil, tiny: nil))
        }
        let choice = OnlineLibraryVideoItem(id: 1, pageURL: "", tags: "", duration: 1, user: "",
            videos: .init(large: file("", size: 999), medium: file(base + "/variant-1", size: 42),
                small: file(base + "/variant-2", size: 73), tiny: nil))
        precondition(choice.bestVideoDownload?.url.absoluteString == base + "/variant-1"
            && choice.bestVideoDownload?.expectedBytes == 42, "URL and size must select the same variant")
        for selected in 0..<4 {
            let variants: [OnlineLibraryVideoFile?] = (0..<4).map { index in
                index < selected ? nil : file(base + "/variant-\(index)", size: 10 + index)
            }
            let candidate = OnlineLibraryVideoItem(id: 4 + selected, pageURL: "", tags: "", duration: 1, user: "",
                videos: .init(large: variants[0], medium: variants[1], small: variants[2], tiny: variants[3]))
            precondition(candidate.bestVideoDownload?.url.absoluteString == base + "/variant-\(selected)"
                && candidate.bestVideoDownload?.expectedBytes == Int64(10 + selected),
                "large/medium/small/tiny priority must pair the chosen URL with its own size")
        }
        let invalid = OnlineLibraryVideoItem(id: 2, pageURL: "", tags: "", duration: 1, user: "",
            videos: .init(large: file("http://[", size: 19), medium: file(base + "/known", size: 42), small: nil, tiny: nil))
        precondition(invalid.bestVideoDownload == nil, "a first nonempty invalid URL must preserve the former nil result")
        let relative = OnlineLibraryVideoItem(id: 3, pageURL: "", tags: "", duration: 1, user: "",
            videos: .init(large: file("relative.mp4", size: -1), medium: nil, small: nil, tiny: nil))
        precondition(relative.bestVideoDownload?.url.relativeString == "relative.mp4"
            && relative.bestVideoDownload?.expectedBytes == nil, "selection must not add a URL admission or invent a length")

        var callbackProgress: [Double] = []
        let progressDelegate = WallpaperFileTransfer(expectedBytes: 1,
            stagingURL: destination.appendingPathComponent(".unit-progress.pending"), progressHandler: { callbackProgress.append($0) })
        let dormant = URLSession.shared.downloadTask(with: URL(string: base + "/unused")!)
        defer { dormant.cancel() }
        progressDelegate.urlSession(.shared, downloadTask: dormant, didWriteData: 25,
            totalBytesWritten: 25, totalBytesExpectedToWrite: 100)
        progressDelegate.urlSession(.shared, downloadTask: dormant, didWriteData: 1,
            totalBytesWritten: 26, totalBytesExpectedToWrite: 100)
        progressDelegate.urlSession(.shared, downloadTask: dormant, didWriteData: 74,
            totalBytesWritten: 100, totalBytesExpectedToWrite: 100)
        try await until { callbackProgress.count == 2 }
        precondition(callbackProgress == [0.25, 1], "GET length wins; small immediate progress ticks remain coalesced")
        var fallbackProgress: [Double] = []
        let fallbackDelegate = WallpaperFileTransfer(expectedBytes: 100,
            stagingURL: destination.appendingPathComponent(".unit-fallback.pending"), progressHandler: { fallbackProgress.append($0) })
        fallbackDelegate.urlSession(.shared, downloadTask: dormant, didWriteData: 25,
            totalBytesWritten: 25, totalBytesExpectedToWrite: -1)
        try await until { fallbackProgress.count == 1 }
        precondition(fallbackProgress == [0.25], "selected variant size supplies only an unknown GET length")

        service.downloadAndSet(item: item(10, path: "/known", size: 1))
        try await until { !service.downloadingIDs.contains(10) }
        precondition(service.downloadedIDs.contains(10) && service.downloadError == nil)
        precondition(OnlineLibraryService.playRequests.isEmpty, "a new download must not autoplay")
        let downloaded = destination.appendingPathComponent("online_10.mp4")
        let payload = try Data(contentsOf: downloaded)
        precondition(payload.count == 524_288)
        precondition(progress[10, default: []].allSatisfy { $0 >= 0 && $0 <= 1 })
        service.downloadAndSet(item: item(10, path: "/known", size: 1))
        precondition(OnlineLibraryService.playRequests.map { $0.resolvingSymlinksInPath().standardizedFileURL } == [downloaded],
            "explicit second action must play the local file: \(OnlineLibraryService.playRequests), expected \(downloaded)")
        service.download(item: item(11, path: "/unknown", size: 0))
        try await until { !service.downloadingIDs.contains(11) }
        precondition(service.downloadedIDs.contains(11))
        precondition(progress[11, default: []].allSatisfy { $0 == 0 }, "unknown lengths must not invent percentages")
        service.download(item: item(12, path: "/unknown", size: 524_288))
        try await until { !service.downloadingIDs.contains(12) }
        precondition(service.downloadedIDs.contains(12) && progress[12, default: []].contains { $0 > 0.02 },
            "a missing GET length may use the selected variant's advertised size")
        let redirected = try await service.fetchAndMove(from: URL(string: base + "/redirect")!,
            expectedBytes: nil, name: "redirect.mp4", itemID: 13)
        let redirectedBytes = try Data(contentsOf: redirected)
        precondition(redirectedBytes == payload)
        for (id, path) in [(14, "/error"), (15, "/disconnect")] {
            service.downloadError = nil
            service.download(item: item(id, path: path, size: 524_288))
            try await until { !service.downloadingIDs.contains(id) }
            precondition(service.downloadError != nil && !service.downloadedIDs.contains(id))
            precondition(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("online_\(id).mp4").path),
                "an error body or interrupted download must not become a ready mp4")
        }
        let existing = destination.appendingPathComponent("preserve.mp4")
        try payload.write(to: existing)
        do {
            _ = try await service.fetchAndMove(from: URL(string: base + "/error")!, expectedBytes: nil,
                name: "preserve.mp4", itemID: 16)
            preconditionFailure("HTTP error was admitted")
        } catch {
            let preserved = try Data(contentsOf: existing)
            precondition(preserved == payload)
        }
        let oldSuccessBytes = Data(repeating: 0x5a, count: 32768)
        try oldSuccessBytes.write(to: existing)
        let replaced = try await service.fetchAndMove(from: URL(string: base + "/known")!, expectedBytes: nil,
            name: existing.lastPathComponent, itemID: 21)
        let replacedBytes = try Data(contentsOf: replaced)
        precondition(replaced == existing && replacedBytes == payload, "normal atomic adoption must replace an old ready file")
        let blocked = destination.appendingPathComponent("blocked")
        try Data("file blocks directory".utf8).write(to: blocked)
        do {
            _ = try await service.fetchAndMove(from: URL(string: base + "/known")!, expectedBytes: nil,
                name: "blocked/movie.mp4", itemID: 17)
            preconditionFailure("failed final publication was ignored")
        } catch {}
        let oldAdoption = destination.appendingPathComponent("adoption-failure.mp4")
        let oldAdoptionBytes = Data(repeating: 0x93, count: 65536)
        try oldAdoptionBytes.write(to: oldAdoption)
        let oldIdentity = TransferProbe.identity(oldAdoption)!
        do {
            _ = try await service.fetchAndMove(from: URL(string: base + "/known")!, expectedBytes: nil,
                name: oldAdoption.lastPathComponent, itemID: 20)
            preconditionFailure("actual final rename failure was ignored")
        } catch {
            let oldBytes = try Data(contentsOf: oldAdoption)
            let retainedIdentity = TransferProbe.identity(oldAdoption)!
            precondition(TransferProbe.shared.adoptionFailures == 1 && oldBytes == oldAdoptionBytes
                && retainedIdentity.0 == oldIdentity.0 && retainedIdentity.1 == oldIdentity.1,
                "failed final adoption must retain the complete old ready file and its inode")
        }
        let cancellation = Task {
            try await service.fetchAndMove(from: URL(string: base + "/cancel")!, expectedBytes: nil,
                name: "cancel.mp4", itemID: 18)
        }
        try await until { (service.downloadProgressByID[18] ?? 0) > 0 }
        cancellation.cancel()
        do { _ = try await cancellation.value; preconditionFailure("cancelled download succeeded") }
        catch { precondition(error is CancellationError || (error as NSError).code == NSURLErrorCancelled) }
        precondition(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("cancel.mp4").path))
        let preCancelled = Task {
            try await service.fetchAndMove(from: URL(string: base + "/cancel")!, expectedBytes: nil,
                name: "pre-cancel.mp4", itemID: 19)
        }
        preCancelled.cancel()
        do { _ = try await preCancelled.value; preconditionFailure("registration lost pre-cancellation") }
        catch { precondition(error is CancellationError || (error as NSError).code == NSURLErrorCancelled) }
        precondition(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("pre-cancel.mp4").path))
        for move in TransferProbe.shared.snapshot {
            precondition(move.sameInode && move.sourceRemoved, "delegate must transfer the actual URLSession file without copying")
            precondition(move.destination.deletingLastPathComponent() == destination
                && move.destination.lastPathComponent.hasPrefix(".online-"),
                "every owned stage must belong to the actual destination directory")
            precondition(!FileManager.default.fileExists(atPath: move.destination.path),
                "a published/failed transfer retained its intermediate owned file")
        }
        precondition(TransferProbe.shared.snapshot.count >= 5)
        let leftovers = try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".online-") && $0.pathExtension == "pending" }
        precondition(leftovers.isEmpty, "owned transfer files leaked on failure/cancellation")
        print("online-download-transfer-pass")
    }
}
