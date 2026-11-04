// Compiled with the existing Inspector gate's controlled source/transport leaves.
// The complete production SIL view, sections, formatter, notices and controls run.
@MainActor enum SILRenderSnapshotProbe {
    static var queries = 0
    static var visits = 0
    static func reset() { queries = 0; visits = 0 }
    static var snapshot: [String: Int] { ["queries": queries, "visits": visits] }
}

@main struct SILInspectorRenderSnapshotChecks {
    @MainActor static func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
    @MainActor static func labels(_ root: NSView) -> [String] {
        views(root).compactMap { ($0 as? NSTextField)?.stringValue }
    }
    @MainActor static func fact(_ root: NSView, _ title: String) -> String? {
        let label = views(root).compactMap { $0 as? NSTextField }.first { $0.stringValue == title }
        return (label?.superview as? NSStackView)?.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue }.dropFirst().first
    }
    @MainActor static func primary(_ root: NSView) -> InspectorFooterButton? {
        views(root).compactMap { $0 as? InspectorFooterButton }.first { $0.action == NSSelectorFromString("setAsDesktopWallpaper") }
    }
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let original = root.appendingPathComponent("tail photo 壁纸.JpG", isDirectory: false)
        let replacement = root.appendingPathComponent("new tail image.JPEG", isDirectory: false)
        let newest = root.appendingPathComponent("latest command and preview.PNG", isDirectory: false)
        for file in [original, replacement, newest] { try Data("owned source".utf8).write(to: file) }
        let service = SILService()
        service.wallpapers = (0..<5000).map {
            SILWallpaper(id: "model-\($0)", title: "Neighbor \($0)", path: root.appendingPathComponent("other-\($0).png", isDirectory: false).path)
        }
        var tail = SILWallpaper(id: "model-4999", title: "Original tail", path: original.path)
        tail.fileSize = 2 * 1_048_576; tail.pixelWidth = 3840; tail.pixelHeight = 2160
        tail.addedAt = Date(timeIntervalSince1970: 1_600_000_000)
        tail.lastUsed = Date(timeIntervalSince1970: 1_700_000_000)
        service.wallpapers[4999] = tail
        var primaryCalls = 0
        func actions(_ favorite: Bool = false, playing: Bool = false, enabled: Bool = true) -> WallpaperInspectorActions {
            .init(state: .init(isPlaying: playing, isFavorite: favorite, canPerformPrimary: enabled,
                canFavorite: true, canOrganize: true, playlistNames: ["Owned list"]),
                onPrimary: { primaryCalls += 1 }, onToggleFavorite: {}, onChoosePlaylist: { _ in })
        }
        var checks: [String: Bool] = [:], work: [String: [String: Int]] = [:]
        var receipts: [String: [String]] = [:]
        func receipt(_ view: NSView) -> [String] {
            labels(view).map { $0.replacingOccurrences(of: root.path, with: "<fixture>") }.sorted()
        }
        SILRenderSnapshotProbe.reset()
        let view = SILInspectorView(wallpaper: tail, service: service, libraryActions: actions())
        work["construct"] = SILRenderSnapshotProbe.snapshot
        receipts["initial"] = receipt(view)
        let originalAdded = fact(view, "添加时间"), originalUsed = fact(view, "最近使用")
        checks["tail-item-title-path-size-format-dimensions-and-dates"] = labels(view).contains(tail.title)
            && labels(view).contains(original.path) && labels(view).contains { $0.contains("2.00 MB") && $0.contains("JPG") }
            && fact(view, "分辨率") == "3840 × 2160" && originalAdded?.isEmpty == false && originalUsed?.isEmpty == false
            && labels(view).contains("Owned list") && !labels(view).contains("Neighbor 4998")
        SILRenderSnapshotProbe.reset()
        view.updateLibraryActions(actions())
        work["echo"] = SILRenderSnapshotProbe.snapshot
        checks["same-model-and-action-echo-preserves-all-rendered-values"] = receipt(view) == receipts["initial"]

        tail = SILWallpaper(id: tail.id, title: "Updated tail", path: tail.path, tags: tail.tags,
            addedAt: tail.addedAt.addingTimeInterval(86_400),
            lastUsed: tail.lastUsed.addingTimeInterval(86_400),
            fileSize: 3 * 1_048_576, pixelWidth: 1920, pixelHeight: 1080)
        service.wallpapers[4999] = tail
        SILRenderSnapshotProbe.reset()
        view.updateLibraryActions(actions())
        work["metadata"] = SILRenderSnapshotProbe.snapshot
        receipts["metadata"] = receipt(view)
        checks["same-id-late-metadata-updates-title-size-dimensions-and-both-dates"] = labels(view).contains("Updated tail")
            && !labels(view).contains("Original tail") && labels(view).contains { $0.contains("3.00 MB") && $0.contains("JPG") }
            && fact(view, "分辨率") == "1920 × 1080" && fact(view, "添加时间") != originalAdded && fact(view, "最近使用") != originalUsed
        SILRenderSnapshotProbe.reset()
        view.updateLibraryActions(actions(true))
        work["action"] = SILRenderSnapshotProbe.snapshot
        checks["action-only-rebuild-keeps-existing-body-and-footer-semantics"] = receipt(view) == receipts["metadata"]
        checks["latest-fixed-action-is-still-dispatched"] = primary(view)?.accessibilityPerformPress() == true && primaryCalls == 1

        tail.path = replacement.path; service.wallpapers[4999] = tail
        SILRenderSnapshotProbe.reset()
        view.updateLibraryActions(actions(true))
        work["source"] = SILRenderSnapshotProbe.snapshot
        receipts["source"] = receipt(view)
        checks["same-id-source-change-updates-real-path-and-format"] = labels(view).contains(replacement.path)
            && !labels(view).contains(original.path) && labels(view).contains { $0.contains("3.00 MB") && $0.contains("JPEG") }
        service.currentActiveWallpaperPath = replacement.path
        view.updateLibraryActions(actions(true, playing: true))
        checks["active-source-notice-is-retained"] = labels(view).contains("当前桌面正在使用这张图片")
        try FileManager.default.removeItem(at: replacement)
        view.updateLibraryActions(actions(true, playing: true, enabled: false))
        checks["missing-file-and-active-notices-still-coexist"] = labels(view).contains("原始图片文件当前不可用")
            && labels(view).contains("当前桌面正在使用这张图片") && primary(view)?.isEnabled == false
        try Data("restored source".utf8).write(to: replacement)
        service.currentActiveWallpaperPath = nil
        view.updateLibraryActions(actions(true))
        checks["restored-file-and-stopped-source-remove-both-notices"] = !labels(view).contains("原始图片文件当前不可用")
            && !labels(view).contains("当前桌面正在使用这张图片")
        service.wallpapers.removeLast()
        view.updateLibraryActions(actions(true))
        checks["absent-fixed-id-falls-back-to-original-not-neighbor"] = labels(view).contains("Original tail")
            && labels(view).contains(original.path) && !labels(view).contains("Neighbor 4998")
        service.wallpapers.append(tail)
        view.updateLibraryActions(actions(true))

        // Mount only after recording synchronous render work. Preview has its
        // own live-source boundary, independent of this round's render value.
        let cache = SILThumbnailStore.sharedCache
        cache.holdsCompletions = true
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 356, height: 560),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 356, height: 560))
        window.contentView = container
        view.frame = container.bounds; container.addSubview(view)
        container.layoutSubtreeIfNeeded(); view.layoutSubtreeIfNeeded()
        let requestBeforeNewModel = cache.requestedKeys.count
        tail.path = newest.path; service.wallpapers[4999] = tail
        view.viewDidChangeBackingProperties()
        checks["preview-boundary-still-reads-latest-model-without-a-render-cache"] = requestBeforeNewModel > 0
            && cache.requestedKeys.last == newest.path && !labels(view).contains(newest.path)
        window.contentView = nil; window.close()
        checks["model-lookup-work-really-scans-the-5000-item-tail"] = work.values.allSatisfy {
            $0["queries", default: 0] > 0 && $0["visits"] == $0["queries", default: 0] * 5000
        }
        let budgets: [String: Bool] = [
            "construct-resolves-once-per-initial-phase": work["construct"]?["queries"] == 2,
            "unchanged-update-resolves-once": work["echo"]?["queries"] == 1,
            "metadata-update-resolves-once": work["metadata"]?["queries"] == 1,
            "action-update-resolves-once": work["action"]?["queries"] == 1,
            "source-update-resolves-once": work["source"]?["queries"] == 1]
        let report: [String: Any] = ["checks": checks, "budgets": budgets, "work": work, "receipts": receipts,
            "scope": "Actual SIL UI and live getter/predicate counts with existing source/cache leaves; no screen animation or product timing claim. Fixture path prefix alone is normalized in UI receipts."]
        print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
