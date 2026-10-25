import Foundation

extension SteamWorkshopService {
    func runOpaqueDeletionFixtureIfNeeded(mode: String) async throws -> Bool {
        guard mode == "opaque-source-delete" else { return false }
        let directory = steamDownloadLibraryRootURL.appendingPathComponent("Video")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let nfc = "video:\u{e9}", nfd = "video:e\u{301}"
        let first = directory.appendingPathComponent("first.mp4"), second = directory.appendingPathComponent("second.mp4")
        try Data([1]).write(to: first); try Data([2]).write(to: second)
        SteamReadyUpdateDeletionFixtureState.contentType = .video
        SteamReadyUpdateDeletionFixtureState.videoURLs = [Data(nfc.utf8): first, Data(nfd.utf8): second]
        defer { SteamReadyUpdateDeletionFixtureState.videoURLs = [:] }
        func rows() -> [SteamWorkshopDownloadRecord] {
            [nfc, nfd].map { .init(id: $0, title: $0, sizeText: "", status: .ready) }
        }
        downloads = rows()
        let result: WallpaperSourceDeletionResult = await withCheckedContinuation { continuation in
            deleteSourceFiles(itemIDs: [nfd]) { continuation.resume(returning: $0) }
        }
        precondition(result.items.count == 1 && result.items[0].reference.sourceID.utf8.elementsEqual(nfd.utf8)
            && result.items[0].succeeded && !FileManager.default.fileExists(atPath: second.path))
        let firstBytes = try Data(contentsOf: first)
        precondition(firstBytes == Data([1]))
        precondition(downloads.count == 1 && downloads[0].id.utf8.elementsEqual(nfc.utf8))
        let outside = libraryRootURL.deletingLastPathComponent().appendingPathComponent("outside.mp4")
        try Data([3]).write(to: outside); try Data([4]).write(to: second)
        SteamReadyUpdateDeletionFixtureState.videoURLs[Data(nfc.utf8)] = outside
        downloads = rows()
        let partial: WallpaperSourceDeletionResult = await withCheckedContinuation { continuation in
            deleteSourceFiles(itemIDs: [nfc, nfd]) { continuation.resume(returning: $0) }
        }
        let outcomes = Dictionary(uniqueKeysWithValues: partial.items.map { ($0.reference, $0.succeeded) })
        precondition(outcomes.count == 2 && outcomes[.init(provider: .steamWorkshop, sourceID: nfc)] == false
            && outcomes[.init(provider: .steamWorkshop, sourceID: nfd)] == true)
        let outsideBytes = try Data(contentsOf: outside), remainingFirstBytes = try Data(contentsOf: first)
        precondition(outsideBytes == Data([3]))
        precondition(remainingFirstBytes == Data([1]))
        precondition(!FileManager.default.fileExists(atPath: second.path))
        await steamServiceClient.stop(shutdownTimeout: 0)
        print("EXECUTION PASS: \(mode)")
        return true
    }
}
