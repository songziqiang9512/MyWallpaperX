import AppKit
import Combine

private typealias MetadataInput = (path: String, size: Int64, duration: Int?, resolution: String?)

/// Only the model/observer leaves are replaced; the batch method, its input type,
/// and the thumbnail notification method are extracted unchanged from production.
@MainActor private final class MetadataProbe: ObservableObject {
    @Published var wallpapers: [VideoWallpaper]
    private let thumbnailReadySubject = PassthroughSubject<String, Never>()
    private var cancellables = Set<AnyCancellable>()
    var publishedSnapshots: [[VideoWallpaper]] = []
    var notifiedPaths: [String] = []
    var notificationSnapshots: [[VideoWallpaper]] = []
    var normalizationCount = 0

    init(_ wallpapers: [VideoWallpaper]) {
        self.wallpapers = wallpapers
        $wallpapers.dropFirst().sink { [weak self] value in
            self?.publishedSnapshots.append(value)
        }.store(in: &cancellables)
        thumbnailReadySubject.sink { [weak self] path in
            guard let self else { return }
            self.notifiedPaths.append(path)
            self.notificationSnapshots.append(self.wallpapers)
        }.store(in: &cancellables)
    }

    func apply(_ values: [MetadataInput]) {
        applyImportedAssetMetadataUpdates(values.map {
            ImportedAssetMetadataUpdate(path: $0.path, size: $0.size, duration: $0.duration, resolution: $0.resolution)
        })
    }

    /// Frozen original owner loop, using the same production notify method.
    /// Its normalized notification keys, order and duplicates are the contract;
    /// the candidate intentionally publishes only the final model snapshot.
    func applyLegacy(_ values: [MetadataInput]) {
        for update in values {
            let normalized = normalizedPath(update.path)
            if let index = wallpapers.firstIndex(where: { normalizedPath($0.path) == normalized }) {
                wallpapers[index].fileSize = update.size
                wallpapers[index].duration = update.duration
                wallpapers[index].resolution = update.resolution
                notifyThumbnailReady(forPath: update.path)
            }
        }
    }

    func resetObservations() {
        publishedSnapshots.removeAll()
        notifiedPaths.removeAll()
        notificationSnapshots.removeAll()
        normalizationCount = 0
    }

    func normalizedPath(_ path: String) -> String {
        normalizationCount += 1
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    // PRODUCTION_METADATA_TYPE
    // PRODUCTION_METADATA_COMMIT
    // PRODUCTION_THUMBNAIL_NOTIFICATION
}

@main private struct UILibraryAlgorithmsHarness {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        var checks: [String: Bool] = [:]
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let a = root.appendingPathComponent("a.mp4")
        let alias = root.appendingPathComponent("alias.mp4")
        let b = root.appendingPathComponent("b.mp4")
        let missing = root.appendingPathComponent("removed.mp4")
        try Data().write(to: a)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: a)
        let first = VideoWallpaper(id: "first", title: "A", path: a.path, isFavorite: true,
                                   lastUsed: .distantPast, tags: ["kept"], fileSize: 10, duration: 1, resolution: "old")
        let duplicate = VideoWallpaper(id: "duplicate", title: "Alias", path: alias.path, lastUsed: .distantPast)
        let second = VideoWallpaper(id: "second", title: "B", path: b.path, lastUsed: .distantPast,
                                    fileSize: 20, duration: 2, resolution: "old B")
        let probe = MetadataProbe([first, duplicate, second])
        let updates: [MetadataInput] = [
            (alias.path, 100, 10, "100x100"),
            (b.path, 200, nil, nil),
            (a.path, 110, 11, "110x110"),
            (missing.path, 999, 99, "missing"),
        ]
        probe.apply(updates)
        let legacy = MetadataProbe([first, duplicate, second])
        legacy.applyLegacy(updates)
        // notifyThumbnailReady publishes canonical keys, not the raw input URL.
        let normalizedA = URL(fileURLWithPath: a.path).resolvingSymlinksInPath().standardizedFileURL.path
        let normalizedB = URL(fileURLWithPath: b.path).resolvingSymlinksInPath().standardizedFileURL.path
        var expectedFirst = first
        expectedFirst.fileSize = 110; expectedFirst.duration = 11; expectedFirst.resolution = "110x110"
        var expectedSecond = second
        expectedSecond.fileSize = 200; expectedSecond.duration = nil; expectedSecond.resolution = nil
        let expected = [expectedFirst, duplicate, expectedSecond]
        checks["metadataBatchFinalValuesAndOrder"] = probe.wallpapers == expected
        checks["metadataSamePathMatchesFirstRecord"] = probe.wallpapers[1] == duplicate
        checks["metadataDuplicateUpdatesKeepLastValue"] = probe.wallpapers[0] == expectedFirst
        checks["metadataNullableFieldsCanBeCleared"] = probe.wallpapers[2].duration == nil && probe.wallpapers[2].resolution == nil
        checks["metadataOnePublishedSnapshot"] = probe.publishedSnapshots == [expected]
        checks["metadataNotificationsKeepOrderAndDuplicates"] = probe.notifiedPaths == legacy.notifiedPaths
            && probe.notifiedPaths == [normalizedA, normalizedB, normalizedA]
        checks["metadataBatchMatchesLegacyFinalValues"] = probe.wallpapers == legacy.wallpapers
        checks["metadataNotificationsSeeCommittedBatch"] = probe.notificationSnapshots == [expected, expected, expected]
        checks["metadataPathWorkIsLinear"] = probe.normalizationCount == 3 + updates.count + 3

        probe.resetObservations()
        let unchangedUpdates: [MetadataInput] = [(a.path, 110, 11, "110x110"), (alias.path, 110, 11, "110x110")]
        probe.apply(unchangedUpdates)
        legacy.resetObservations()
        legacy.applyLegacy(unchangedUpdates)
        checks["metadataUnchangedBatchDoesNotPublish"] = probe.publishedSnapshots.isEmpty && probe.wallpapers == expected
        checks["metadataUnchangedMatchesStillNotify"] = probe.notifiedPaths == legacy.notifiedPaths
            && probe.notifiedPaths == [normalizedA, normalizedA]

        probe.resetObservations()
        let revertedUpdates: [MetadataInput] = [(a.path, 500, nil, nil), (a.path, 110, 11, "110x110")]
        probe.apply(revertedUpdates)
        legacy.resetObservations()
        legacy.applyLegacy(revertedUpdates)
        checks["metadataRevertedBatchDoesNotPublish"] = probe.publishedSnapshots.isEmpty && probe.wallpapers == expected
        checks["metadataRevertedBatchRetainsBothNotifications"] = probe.notifiedPaths == legacy.notifiedPaths
            && probe.notifiedPaths == [normalizedA, normalizedA]

        let single = MetadataProbe([first, duplicate, second])
        single.apply([(a.path, 99, 9, "single")])
        checks["metadataSingleFirstMatchOnlyNormalizesFirstRecord"] = single.normalizationCount == 3
            && single.publishedSnapshots.count == 1 && single.wallpapers[0].fileSize == 99
            && single.wallpapers[1] == duplicate && single.wallpapers[2] == second
        let unknownFirst = MetadataProbe([first, duplicate, second])
        unknownFirst.apply([(missing.path, 999, nil, nil), (a.path, 99, nil, nil)])
        checks["metadataMissScansOnceThenReusesEarlierFirstMatch"] = unknownFirst.normalizationCount == 3 + 2 + 1
            && unknownFirst.wallpapers[0].fileSize == 99 && unknownFirst.wallpapers[1] == duplicate
            && unknownFirst.notifiedPaths == [normalizedA]

        probe.wallpapers.removeAll { $0.id == "first" || $0.id == "duplicate" }
        probe.resetObservations()
        probe.apply([(a.path, 700, 7, "late"), (missing.path, 800, 8, "unknown")])
        checks["metadataLateDeletedAndUnknownPathsDoNotResurrect"] = probe.wallpapers == [expectedSecond]
            && probe.publishedSnapshots.isEmpty && probe.notifiedPaths.isEmpty
        probe.resetObservations()
        probe.apply([])
        checks["metadataEmptyBatchHasNoWorkOrEvents"] = probe.normalizationCount == 0
            && probe.publishedSnapshots.isEmpty && probe.notifiedPaths.isEmpty
        let empty = MetadataProbe([])
        empty.apply([(a.path, 10, nil, nil)])
        checks["metadataEmptyLibraryDoesNotInsert"] = empty.wallpapers.isEmpty
            && empty.publishedSnapshots.isEmpty && empty.notifiedPaths.isEmpty

        let data = try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
