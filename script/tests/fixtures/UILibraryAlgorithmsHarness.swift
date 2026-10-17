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

@MainActor private final class LayoutItems: NSObject, NSCollectionViewDataSource {
    var sectionCounts = [Int]()
    func numberOfSections(in collectionView: NSCollectionView) -> Int { sectionCounts.count }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        sectionCounts[section]
    }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("probe"), for: indexPath)
    }
}

private final class LayoutCell: NSCollectionViewItem {
    override func loadView() { view = NSView() }
}

@MainActor private final class LayoutProbe {
    let collectionView = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let layout = SILWaterfallLayout()
    let items = LayoutItems()

    init() {
        collectionView.register(LayoutCell.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("probe"))
        collectionView.dataSource = items
        collectionView.collectionViewLayout = layout
    }

    func prepare(width: CGFloat, columns: Int, ratios: [CGFloat], noSections: Bool = false, useDefaultRatio: Bool = false) {
        collectionView.setFrameSize(NSSize(width: width, height: 600))
        items.sectionCounts = noSections ? [] : [ratios.count]
        layout.columnCount = columns
        layout.aspectRatioProvider = useDefaultRatio ? nil : { ratios[$0.item] }
        collectionView.reloadData()
        layout.invalidateLayout()
        layout.prepare()
    }
}

/// Frozen pre-index frame calculation and linear rectangle query oracle. This
/// deliberately retains the original scan so the candidate index cannot define
/// which tall cards, boundary intersections, or item order count as correct.
@MainActor private func legacyWaterfall(
    width: CGFloat, ratios: [CGFloat], layout: SILWaterfallLayout,
    noSections: Bool = false, useDefaultRatio: Bool = false
) -> (frames: [NSRect], size: NSSize) {
    guard !noSections else { return ([], NSSize(width: width, height: 0)) }
    let cols = max(1, layout.columnCount)
    let contentWidth = width - layout.sectionInset.left - layout.sectionInset.right
    let estimatedColWidth = max(60, (contentWidth - layout.columnSpacing * CGFloat(cols - 1)) / CGFloat(cols))
    let minSpacing = estimatedColWidth * (CGFloat(1.05) - 1)
    let effectiveColSpacing = max(layout.columnSpacing, minSpacing)
    let effectiveRowSpacing = max(layout.rowSpacing, minSpacing)
    let colWidth = max(60, (contentWidth - effectiveColSpacing * CGFloat(cols - 1)) / CGFloat(cols))
    var heights = [CGFloat](repeating: layout.sectionInset.top, count: cols)
    var frames: [NSRect] = []
    for ratio in ratios {
        let column = heights.indices.min(by: { heights[$0] < heights[$1] }) ?? 0
        let resolvedRatio = useDefaultRatio ? CGFloat(16.0 / 9.0) : ratio
        let clamped = max(layout.minAspectRatio, min(layout.maxAspectRatio, resolvedRatio))
        let height = colWidth / clamped
        frames.append(NSRect(x: layout.sectionInset.left + CGFloat(column) * (colWidth + effectiveColSpacing),
                             y: heights[column], width: colWidth, height: height))
        heights[column] += height + effectiveRowSpacing
    }
    let height = max((heights.max() ?? layout.sectionInset.top) + layout.sectionInset.bottom - layout.rowSpacing,
                     layout.sectionInset.top + layout.sectionInset.bottom)
    return (frames, NSSize(width: width, height: height))
}

private func sameScalar(_ a: CGFloat, _ b: CGFloat) -> Bool {
    a == b || (a.isNaN && b.isNaN)
}

private func sameFrames(_ a: [NSRect], _ b: [NSRect]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy {
        sameScalar($0.origin.x, $1.origin.x) && sameScalar($0.origin.y, $1.origin.y)
            && sameScalar($0.width, $1.width) && sameScalar($0.height, $1.height)
    }
}

@MainActor private func rectangleChecks(probe: LayoutProbe, frames: [NSRect], size: NSSize) -> Bool {
    var rectangles: [NSRect] = [
        .zero, .null, .infinite,
        NSRect(x: -100, y: -100, width: size.width + 200, height: size.height + 200),
        NSRect(x: size.width + 100, y: 0, width: 30, height: size.height),
        NSRect(x: 50, y: 100, width: -40, height: -80),
        NSRect(x: 0, y: CGFloat.nan, width: 100, height: 20),
    ]
    for frame in frames {
        rectangles.append(frame.insetBy(dx: 1, dy: 1))
        rectangles.append(NSRect(x: frame.midX, y: frame.minY + frame.height * 0.75, width: 1, height: 1))
        rectangles.append(NSRect(x: frame.minX, y: frame.maxY, width: frame.width, height: 1))
        rectangles.append(NSRect(x: frame.minX, y: frame.minY - 1, width: frame.width, height: 1))
        rectangles.append(NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: 0))
    }
    for row in 0..<32 {
        let y = CGFloat(row) * max(1, size.height / 30) - 50
        rectangles.append(NSRect(x: -10, y: y, width: size.width + 20, height: 40))
        rectangles.append(NSRect(x: size.width * 0.3, y: y, width: 17, height: 330))
    }
    return rectangles.allSatisfy { rect in
        let expected = frames.indices.filter { frames[$0].intersects(rect) }
        let actual = probe.layout.layoutAttributesForElements(in: rect)
        return actual.compactMap { $0.indexPath?.item } == expected
            && actual.allSatisfy { $0.indexPath?.section == 0 }
            && sameFrames(actual.map(\.frame), expected.map { frames[$0] })
    }
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

        let layoutProbe = LayoutProbe()
        let mixed: [CGFloat] = (0..<97).map { [CGFloat(0.001), 0.25, 0.5, 1, 16.0 / 9.0, 3, 1000, .infinity][$0 % 8] }
        var scenario = 0
        // Reuse one layout across count, width and column changes to expose stale indexes.
        for width in [CGFloat(120), 575, 960] {
            for columns in [0, 1, 4, 7] {
                for ratios in [[], [CGFloat(0.001)], mixed] {
                    layoutProbe.prepare(width: width, columns: columns, ratios: ratios)
                    let reference = legacyWaterfall(width: layoutProbe.collectionView.bounds.width,
                                                     ratios: ratios, layout: layoutProbe.layout)
                    let frames = ratios.indices.compactMap {
                        layoutProbe.layout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame
                    }
                    checks["layoutFramesAndSize_\(scenario)"] = sameFrames(frames, reference.frames)
                        && layoutProbe.layout.collectionViewContentSize == reference.size
                    checks["layoutRectanglesPreserveCompleteOrderedHits_\(scenario)"] = rectangleChecks(
                        probe: layoutProbe, frames: reference.frames, size: reference.size)
                    checks["layoutInvalidIndexes_\(scenario)"] = [
                        IndexPath(), IndexPath(index: 0), IndexPath(indexes: [0, 0, 0]),
                        IndexPath(item: -1, section: 0), IndexPath(item: ratios.count, section: 0),
                        IndexPath(item: 0, section: 1), IndexPath(item: 0, section: -1),
                    ].allSatisfy { layoutProbe.layout.layoutAttributesForItem(at: $0) == nil }
                    scenario += 1
                }
            }
        }

        layoutProbe.prepare(width: 575, columns: 3, ratios: mixed, useDefaultRatio: true)
        let fallback = legacyWaterfall(width: layoutProbe.collectionView.bounds.width,
                                       ratios: mixed, layout: layoutProbe.layout, useDefaultRatio: true)
        checks["layoutDefaultAspectRatioFrames"] = mixed.indices.map {
            layoutProbe.layout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))!.frame
        } == fallback.frames
        checks["layoutDefaultAspectRatioRectangles"] = rectangleChecks(probe: layoutProbe, frames: fallback.frames, size: fallback.size)

        let invalidRatios: [CGFloat] = [.nan, 0, -.infinity, -100, .infinity, 0.25, 3]
        for minimumRatio in [CGFloat(0.25), 0, -1] {
            layoutProbe.layout.minAspectRatio = minimumRatio
            layoutProbe.prepare(width: 575, columns: 3, ratios: invalidRatios)
            let reference = legacyWaterfall(width: layoutProbe.collectionView.bounds.width,
                                             ratios: invalidRatios, layout: layoutProbe.layout)
            let frames = invalidRatios.indices.map {
                layoutProbe.layout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))!.frame
            }
            checks["layoutExceptionalRatiosPreserveFrames_\(minimumRatio)"] = sameFrames(frames, reference.frames)
                && sameScalar(layoutProbe.layout.collectionViewContentSize.height, reference.size.height)
            checks["layoutExceptionalRatiosPreserveQueries_\(minimumRatio)"] = rectangleChecks(
                probe: layoutProbe, frames: reference.frames, size: reference.size)
        }
        layoutProbe.layout.minAspectRatio = 0.25
        layoutProbe.prepare(width: 575, columns: 3, ratios: [], noSections: true)
        checks["layoutNoSectionsClearsPreviousIndexes"] = layoutProbe.layout.collectionViewContentSize == NSSize(width: 575, height: 0)
            && layoutProbe.layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)) == nil
            && layoutProbe.layout.layoutAttributesForElements(in: .infinite).isEmpty
        checks["layoutWidthInvalidationSemantics"] = !layoutProbe.layout.shouldInvalidateLayout(
            forBoundsChange: NSRect(x: 0, y: 400, width: 575, height: 600))
            && layoutProbe.layout.shouldInvalidateLayout(forBoundsChange: NSRect(x: 0, y: 0, width: 576, height: 600))

        // Optional observations only: no timing threshold and no speedup claim.
        let largeRatios = (0..<12_000).map { mixed[$0 % mixed.count] }
        layoutProbe.prepare(width: 960, columns: 5, ratios: largeRatios)
        var checksum: CGFloat = 0
        let itemStart = ProcessInfo.processInfo.systemUptime
        for query in 0..<2_000 {
            let ip = IndexPath(item: (query * 7_919) % largeRatios.count, section: 0)
            checksum += layoutProbe.layout.layoutAttributesForItem(at: ip)!.frame.minY
        }
        let itemSeconds = ProcessInfo.processInfo.systemUptime - itemStart
        let rectStart = ProcessInfo.processInfo.systemUptime
        for query in 0..<1_000 {
            let height = layoutProbe.layout.collectionViewContentSize.height
            let y = CGFloat((query * 347) % max(1, Int(height)))
            checksum += CGFloat(layoutProbe.layout.layoutAttributesForElements(
                in: NSRect(x: 0, y: y, width: 960, height: 600)).count)
        }
        let rectSeconds = ProcessInfo.processInfo.systemUptime - rectStart
        checks["layoutLargeQueryResultsConsumed"] = checksum.isFinite && checksum > 0
        FileHandle.standardError.write(Data(
            "UI algorithm observations: items=12000 itemQueries=2000 itemSeconds=\(itemSeconds) rectQueries=1000 rectSeconds=\(rectSeconds)\n".utf8))

        let data = try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
