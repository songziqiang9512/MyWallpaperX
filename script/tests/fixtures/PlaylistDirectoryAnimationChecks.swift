import AppKit
import QuartzCore

// Test-copy observations and the existing accessibility preference leaf only.
// Production batch, model updates, completion and AppKit animation stay intact.
@MainActor enum PlaylistDirectoryAnimationProbe {
    static var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    static var reloads = 0
}

extension PlaylistDirectoryHarness {
    static func checkDirectoryAnimations(checks: inout [String: Bool]) {
        let systemMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        checks["directory-animation-default-policy-reads-real-system-reduce-motion"] = PlaylistDirectoryAnimationProbe.reduceMotion == systemMotion
        defer { PlaylistDirectoryAnimationProbe.reduceMotion = systemMotion }
        for columns in 3...6 {
            PlaylistDirectoryAnimationProbe.reduceMotion = false
            let controller = AppKitPlaylistDirectoryController()
            let entries = (0..<(columns * 2 - 1)).map {
                WallpaperPlaylistDirectoryEntry(id: UUID(), name: "Animation \($0)", count: $0 + 1, coverReference: nil)
            }
            let images = Dictionary(uniqueKeysWithValues: entries.enumerated().map { offset, entry in
                let image = NSImage(size: .init(width: 32, height: 32), flipped: false) { bounds in
                    NSColor(calibratedHue: CGFloat(offset) / CGFloat(entries.count), saturation: 0.4, brightness: 0.8, alpha: 1).setFill()
                    bounds.fill()
                    return true
                }
                return (entry.id, WallpaperPlaylistArtwork(image: image))
            })
            var writes = 0, demands: [Set<UUID>] = []
            controller.onReorder = { _, _ in writes += 1 }
            controller.onCoverDemand = { demands.append($0) }
            let window = NSWindow(contentViewController: controller)
            window.isReleasedWhenClosed = false
            window.setContentSize(.init(width: 800, height: 700))
            window.setFrameOrigin(.init(x: 180, y: 160))
            // The real main Shell has a layer-backed ancestor for its tint.
            window.contentView?.wantsLayer = true
            window.makeKeyAndOrderFront(nil)
            controller.update(entries: entries, covers: images, preferredColumns: columns,
                              permitsReordering: true, resetEpoch: UUID())
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            let collection = descendants(controller.view, of: NSCollectionView.self).first!
            let flow = collection.collectionViewLayout as! NSCollectionViewFlowLayout
            let items = Dictionary(uniqueKeysWithValues: entries.enumerated().compactMap { index, entry in
                collection.item(at: IndexPath(item: index + 1, section: 0)).map { (entry.id, $0) }
            })
            collection.selectionIndexPaths = [IndexPath(item: 2, section: 0)]
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally(); window.orderOut(nil); window.close() }
            func frame(_ item: NSCollectionViewItem, presented: Bool) -> NSRect {
                if presented, let layer = item.view.layer?.presentation() {
                    return collection.convert(layer.frame, from: item.view.superview)
                }
                return collection.convert(item.view.bounds, from: item.view)
            }
            func currentFrames() -> [UUID: NSRect] { items.mapValues { frame($0, presented: true) } }
            func targets() -> [UUID: NSRect] {
                Dictionary(uniqueKeysWithValues: controller.entries.enumerated().compactMap { index, entry in
                    flow.layoutAttributesForItem(at: IndexPath(item: index + 1, section: 0)).map { (entry.id, $0.frame) }
                })
            }
            func retained() -> Bool {
                controller.entries.enumerated().allSatisfy { index, entry in
                    let item = collection.item(at: IndexPath(item: index + 1, section: 0))
                    return item === items[entry.id]
                        && item.flatMap { descendants($0.view, of: NSImageView.self).last?.image } === images[entry.id]?.image
                } && controller.selectedPlaylistID == entries[1].id
            }
            func begin() -> DirectoryDropInfo? {
                guard let index = controller.entries.firstIndex(where: { $0.id == entries[0].id }),
                      let writer = controller.collectionView(collection, pasteboardWriterForItemAt: IndexPath(item: index + 1, section: 0)) else { return nil }
                board.clearContents(); board.writeObjects([writer])
                return DirectoryDropInfo(source: collection, board: board)
            }
            func hover(_ info: DirectoryDropInfo, before index: Int) -> NSDragOperation {
                var path = IndexPath(item: index, section: 0) as NSIndexPath
                var operation = NSCollectionView.DropOperation.on
                return controller.collectionView(collection, validateDrop: info, proposedIndexPath: &path, dropOperation: &operation)
            }
            func sample(_ phase: String, from start: [UUID: NSRect], to end: [UUID: NSRect]) -> Bool {
                var intermediate = false, samples: [[String: Any]] = []
                let began = ProcessInfo.processInfo.systemUptime
                CATransaction.flush()
                // Fixed observation turns, never retry an input until it passes.
                for _ in 0..<8 {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                    let rectangles = currentFrames()
                    var receipt: [String: String] = [:]
                    for entry in entries {
                        guard let initial = start[entry.id], let final = end[entry.id], let current = rectangles[entry.id] else { continue }
                        let dx = final.midX - initial.midX, dy = final.midY - initial.midY
                        let distanceSquared = dx * dx + dy * dy
                        let progress = distanceSquared > 1
                            ? ((current.midX - initial.midX) * dx + (current.midY - initial.midY) * dy) / distanceSquared : 0
                        if progress > 0.01, progress < 0.99, current != initial, current != final { intermediate = true }
                        let view = items[entry.id]?.view
                        receipt[entry.id.uuidString] = "start=\(initial) current=\(current) end=\(final) progress=\(progress) model=\(String(describing: view?.frame)) layer=\(String(describing: view?.layer?.frame)) keys=\(view?.layer?.animationKeys() ?? [])"
                    }
                    samples.append(["elapsed": ProcessInfo.processInfo.systemUptime - began, "frames": receipt])
                }
                let data = try! JSONSerialization.data(withJSONObject: ["phase": phase, "columns": columns, "samples": samples], options: [.sortedKeys])
                FileHandle.standardError.write(Data("directory-native-animation ".utf8) + data + Data("\n".utf8))
                return intermediate
            }
            let initial = currentFrames(), reloads = PlaylistDirectoryAnimationProbe.reloads, demandStart = demands.count
            let expectedWidth = WallpaperLibraryGridMetrics(clipWidth: collection.enclosingScrollView!.contentView.bounds.width, preferredColumns: columns).coverSide
            let initialTargets = targets(), expectedDemand = Set(entries.map(\.id))
            let layoutReceipt: [String: Any] = ["columns": columns, "windowVisible": window.isVisible,
                "allRealItemsMounted": items.count == entries.count, "itemCount": items.count, "expectedItemCount": entries.count,
                "flowWidthMatchesExactly": flow.itemSize.width == expectedWidth, "flowWidth": flow.itemSize.width, "expectedWidth": expectedWidth,
                "initialFramesMatchTargets": initial == initialTargets, "demandMatchesAllVisibleEntries": demands.last == expectedDemand,
                "clip": String(describing: collection.enclosingScrollView!.contentView.bounds),
                "visiblePaths": collection.indexPathsForVisibleItems().map(\.item).sorted(),
                "initialFrames": Dictionary(uniqueKeysWithValues: initial.map { ($0.key.uuidString, String(describing: $0.value)) }),
                "targetFrames": Dictionary(uniqueKeysWithValues: initialTargets.map { ($0.key.uuidString, String(describing: $0.value)) }),
                "expectedDemand": expectedDemand.map(\.uuidString).sorted(),
                "demandHistory": demands.map { $0.map(\.uuidString).sorted() }]
            FileHandle.standardError.write(Data("directory-native-animation-initial ".utf8)
                + (try! JSONSerialization.data(withJSONObject: layoutReceipt, options: [.sortedKeys])) + Data("\n".utf8))
            checks["directory-animation-\(columns)-uses-real-visible-two-row-native-layout"] = window.isVisible && items.count == entries.count
                && flow.itemSize.width == WallpaperLibraryGridMetrics(clipWidth: collection.enclosingScrollView!.contentView.bounds.width, preferredColumns: columns).coverSide
                && initial == targets() && demands.last == Set(entries.map(\.id))
            guard let drag = begin() else {
                checks["directory-animation-\(columns)-admits-original-native-source"] = false
                continue
            }
            let accepted = hover(drag, before: entries.count + 1), forward = targets()
            checks["directory-animation-\(columns)-forward-has-visible-intermediate-frame"] = accepted == .move
                && sample("forward", from: initial, to: forward)
            RunLoop.main.run(until: Date().addingTimeInterval(0.12))
            checks["directory-animation-\(columns)-forward-finishes-at-native-target-without-reload"] = currentFrames() == forward
                && retained() && PlaylistDirectoryAnimationProbe.reloads == reloads && writes == 0
            let beforeReverse = currentFrames()
            controller.collectionView(collection, draggingSession: DirectoryNativeDragProbe.session!, endedAt: .zero, dragOperation: [])
            let reverse = targets()
            checks["directory-animation-\(columns)-cancel-return-has-visible-intermediate-frame"] = sample("cancel", from: beforeReverse, to: reverse)
            RunLoop.main.run(until: Date().addingTimeInterval(0.12))
            checks["directory-animation-\(columns)-cancel-keeps-items-images-selection-and-cover-lease"] = controller.entries.map(\.id) == entries.map(\.id)
                && currentFrames() == initial && retained() && writes == 0 && PlaylistDirectoryAnimationProbe.reloads == reloads
                && demands.dropFirst(demandStart).allSatisfy { $0 == Set(entries.map(\.id)) }
            PlaylistDirectoryAnimationProbe.reduceMotion = true
            guard let reduced = begin() else {
                checks["directory-animation-\(columns)-reduce-motion-admits-original-source"] = false
                continue
            }
            let reducedAccepted = hover(reduced, before: entries.count + 1)
            CATransaction.flush()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            checks["directory-animation-\(columns)-reduce-motion-projects-final-frame-immediately"] = reducedAccepted == .move
                && currentFrames() == targets() && retained() && writes == 0
            controller.collectionView(collection, draggingSession: DirectoryNativeDragProbe.session!, endedAt: .zero, dragOperation: [])
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
    }
}
