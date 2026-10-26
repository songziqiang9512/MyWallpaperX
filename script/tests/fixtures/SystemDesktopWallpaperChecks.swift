// Appended to the real Manager/transaction/provider gate. Only native desktop
// reads/writes and displays are controlled; no real desktop or media is used.
@MainActor func runSystemDesktopWallpaperChecks(root: URL) throws -> [String: Bool] {
    var checks: [String: Bool] = [:]
    let desktop = DesktopLeaf.shared
    let original = [root.appendingPathComponent("original-a.jpg"), root.appendingPathComponent("original-b.jpg")]
    let image = root.appendingPathComponent("temporary-still.png")
    let other = root.appendingPathComponent("second-still.png")
    let dynamic = root.appendingPathComponent("dynamic-sync.jpg")
    for file in original + [image, other, dynamic] { try Data([7]).write(to: file) }
    let option = NSWorkspace.DesktopImageOptionKey(rawValue: "fixture-crop")
    func setup(sync: Bool = false) -> WallpaperManager {
        DesktopLeaf.screens = [DesktopScreen(id: 0), DesktopScreen(id: 1)]
        desktop.urls = [0: original[0], 1: original[1]]
        desktop.options = [0: [option: 17], 1: [option: 29]]
        desktop.failScreen = nil; desktop.failURLs = []; desktop.attempts = []
        let manager = WallpaperManager()
        manager.settings.syncSystemWallpaper = sync
        manager.libraryPlaybackDispatcher = { [weak manager] pending in
            guard let manager else { return false }
            manager.setStaticWallpaper(URL(fileURLWithPath: pending.proposal.entry.reference.sourceID), libraryPending: pending)
            return true
        }
        return manager
    }
    func apply(_ url: URL, to manager: WallpaperManager) throws -> PlaybackSwitchTicket {
        let ref = WallpaperReference(provider: .staticImageLibrary, sourceID: url.path)
        let source = try WallpaperPlaybackSequence.Snapshot(source: .single(ref), revision: 1,
            entries: [.init(reference: ref, runtime: .systemStill, isPlayable: true)])
        guard let ticket = manager.requestLibraryPlayback(reference: ref, from: source) else {
            throw CocoaError(.fileReadUnknown)
        }
        return ticket
    }
    func quit(_ manager: WallpaperManager) {
        _ = manager.beginPlaybackIntent()
        manager.restoreSystemDesktopWallpaperOnTermination()
    }
    do {
        let manager = setup()
        let first = try apply(image, to: manager)
        let second = try apply(other, to: manager)
        checks["successful-static-images-retain-one-original-per-display"] = manager.playbackSwitch.committed?.ticket == second
            && first != second && manager.didApplySystemStillThisRun && manager.systemDesktopWallpapers.count == 2
            && manager.systemDesktopWallpapers[0]?.originalURL == original[0]
            && manager.systemDesktopWallpapers[1]?.originalURL == original[1]
        quit(manager)
        checks["normal-quit-restores-both-original-urls-and-options-when-sync-is-off"] = desktop.urls[0] == original[0]
            && desktop.urls[1] == original[1] && desktop.options[0]?[option] as? Int == 17
            && desktop.options[1]?[option] as? Int == 29
        let count = desktop.attempts.count
        manager.restoreSystemDesktopWallpaperOnTermination()
        checks["desktop-exit-restoration-settles-only-once"] = desktop.attempts.count == count
            && manager.systemDesktopWallpapers.isEmpty && !manager.didApplySystemStillThisRun
    }
    do {
        let manager = setup(sync: true)
        _ = try apply(image, to: manager)
        quit(manager)
        checks["sync-on-keeps-the-applied-static-desktop-on-normal-quit"] = desktop.urls[0] == image
            && desktop.urls[1] == image && desktop.attempts.count == 2
    }
    do {
        let manager = setup(sync: true)
        let synced = manager.applySourceImageDirectly(dynamic)
        manager.settings.syncSystemWallpaper = false
        _ = try apply(image, to: manager)
        quit(manager)
        checks["first-sync-write-baseline-survives-later-static-image-and-toggle-off"] = synced
            && desktop.urls[0] == original[0] && desktop.urls[1] == original[1]
    }
    do {
        let manager = setup()
        _ = try apply(image, to: manager)
        manager.settings.syncSystemWallpaper = true
        let synced = manager.applySourceImageDirectly(dynamic)
        manager.settings.syncSystemWallpaper = false
        quit(manager)
        checks["later-dynamic-frame-keeps-the-first-baseline-and-static-restoration-eligibility"] = synced
            && desktop.urls[0] == original[0] && desktop.urls[1] == original[1]
    }
    do {
        let manager = setup(sync: true)
        let synced = manager.applySourceImageDirectly(dynamic)
        manager.settings.syncSystemWallpaper = false
        quit(manager)
        checks["dynamic-only-run-does-not-gain-a-new-exit-restoration-policy"] = synced
            && desktop.urls[0] == dynamic && desktop.urls[1] == dynamic && desktop.attempts.count == 2
    }
    do {
        let manager = setup()
        _ = try apply(image, to: manager)
        manager.settings.syncSystemWallpaper = true
        quit(manager)
        checks["final-sync-toggle-on-suppresses-a-previous-static-restoration"] = desktop.urls[0] == image
            && desktop.urls[1] == image && desktop.attempts.count == 2
    }
    do {
        let manager = setup()
        desktop.failScreen = 1
        let failed = try apply(image, to: manager)
        checks["partial-static-apply-failure-rolls-back-without-granting-exit-ownership"] = manager.playbackSwitch.committed?.ticket != failed
            && !manager.didApplySystemStillThisRun && manager.systemDesktopWallpapers.isEmpty
            && desktop.urls[0] == original[0] && desktop.urls[1] == original[1]
        let count = desktop.attempts.count
        desktop.failScreen = nil
        quit(manager)
        checks["failed-static-attempt-does-not-restore-or-rewrite-desktops-at-quit"] = desktop.attempts.count == count
    }
    do {
        let manager = setup()
        desktop.failScreen = 1; desktop.failURLs = [original[0]]
        let failed = try apply(image, to: manager)
        checks["first-partial-static-write-with-failed-rollback-retains-its-real-baseline"] = manager.playbackSwitch.committed?.ticket != failed
            && manager.didApplySystemStillThisRun && manager.systemDesktopWallpapers.count == 1
            && manager.systemDesktopWallpapers[0]?.originalURL == original[0]
            && manager.systemDesktopWallpapers[0]?.lastWrittenURL == image && desktop.urls[0] == image
        desktop.failScreen = nil; desktop.failURLs = []
        quit(manager)
        checks["failed-selection-with-a-successful-screen-write-can-restore-at-quit"] = desktop.urls[0] == original[0]
            && desktop.urls[1] == original[1] && desktop.options[0]?[option] as? Int == 17
    }
    do {
        let manager = setup()
        let first = try apply(image, to: manager)
        desktop.failScreen = 1; desktop.failURLs = [image]
        let failed = try apply(other, to: manager)
        checks["later-partial-failure-does-not-commit-but-tracks-the-last-real-desktop-write"] = manager.playbackSwitch.committed?.ticket == first
            && manager.playbackSwitch.committed?.ticket != failed && desktop.urls[0] == other
            && manager.systemDesktopWallpapers[0]?.originalURL == original[0]
            && manager.systemDesktopWallpapers[0]?.lastWrittenURL == other
        desktop.failScreen = nil; desktop.failURLs = []
        quit(manager)
        checks["later-failed-rollback-still-restores-the-first-user-desktop"] = desktop.urls[0] == original[0]
            && desktop.urls[1] == original[1] && desktop.options[0]?[option] as? Int == 17
    }
    do {
        let manager = setup()
        _ = try apply(image, to: manager)
        let external = root.appendingPathComponent("external-user-choice.jpg")
        desktop.urls[0] = external
        quit(manager)
        checks["external-user-desktop-change-is-preserved-while-other-screen-restores"] = desktop.urls[0] == external
            && desktop.urls[1] == original[1] && desktop.attempts.filter { $0.0 == 0 }.count == 1
    }
    do {
        let manager = setup()
        _ = try apply(image, to: manager)
        desktop.options[0] = [option: 83]
        quit(manager)
        checks["external-options-only-change-keeps-the-user-crop-at-the-same-image-url"] = desktop.urls[0] == image
            && desktop.options[0]?[option] as? Int == 83 && desktop.urls[1] == original[1]
            && desktop.attempts.filter { $0.0 == 0 }.count == 1
    }
    do {
        let manager = setup()
        _ = try apply(image, to: manager)
        DesktopLeaf.screens = [DesktopScreen(id: 1)]
        let count = desktop.attempts.count
        quit(manager)
        checks["removed-display-is-not-restored-through-another-screens-index"] = desktop.attempts.count == count + 1
            && desktop.attempts.last?.0 == 1 && desktop.urls[0] == image && desktop.urls[1] == original[1]
    }
    do {
        let manager = setup()
        _ = try apply(image, to: manager)
        desktop.failURLs = [original[0]]
        quit(manager)
        checks["restoration-failure-is-local-to-one-display"] = desktop.urls[0] == image && desktop.urls[1] == original[1]
            && desktop.attempts.suffix(2).map(\.0) == [0, 1] && manager.systemDesktopWallpapers.isEmpty
    }
    do {
        let manager = setup()
        desktop.urls[0] = nil
        _ = try apply(image, to: manager)
        quit(manager)
        checks["unknown-original-desktop-is-not-replaced-by-a-guessed-file"] = desktop.urls[0] == image
            && desktop.urls[1] == original[1] && desktop.attempts.count == 3
    }
    do {
        let manager = setup()
        desktop.urls[0] = image
        _ = try apply(image, to: manager)
        _ = try apply(other, to: manager)
        quit(manager)
        checks["same-path-first-image-does-not-overwrite-baseline-url-or-options"] = desktop.urls[0] == image
            && desktop.options[0]?[option] as? Int == 17 && desktop.urls[1] == original[1]
    }
    do {
        let manager = setup(sync: true)
        let directory = root.appendingPathComponent("protected-system-frames", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        manager.staticFrameCacheDirectory = directory
        manager.thumbnailCacheDirectory = root.appendingPathComponent("discardable-thumbnails", isDirectory: true)
        let baseline = directory.appendingPathComponent("system-wallpaper-active-baseline.jpg")
        let current = directory.appendingPathComponent("system-wallpaper-active-current.jpg")
        let stale = directory.appendingPathComponent("system-wallpaper-active-stale.jpg")
        let preview = directory.appendingPathComponent("ordinary-frame.jpg")
        let removed = directory.appendingPathComponent("purged-derived-frame.jpg")
        for file in [baseline, current, stale, preview, removed] { try Data([8]).write(to: file) }
        desktop.urls = [0: baseline, 1: baseline]
        let synced = manager.applySourceImageDirectly(current)
        manager.removePreviousDesktopCopies(keeping: current)
        checks["sync-copy-cleanup-keeps-baseline-and-current-without-retaining-all-old-copies"] = synced
            && FileManager.default.fileExists(atPath: baseline.path) && FileManager.default.fileExists(atPath: current.path)
            && !FileManager.default.fileExists(atPath: stale.path)
        var failures: [WallpaperDeletionFailure] = []
        manager.removeFileIfExists(atPath: baseline.path, title: "Baseline", failures: &failures)
        manager.removeFileIfExists(atPath: current.path, title: "Desktop", failures: &failures)
        manager.removeFileIfExists(atPath: removed.path, title: "Unused derived file", failures: &failures)
        checks["actual-derived-file-cleanup-keeps-owned-desktops-but-removes-an-unrelated-frame"] = failures.isEmpty
            && FileManager.default.fileExists(atPath: baseline.path) && FileManager.default.fileExists(atPath: current.path)
            && !FileManager.default.fileExists(atPath: removed.path)
        _ = try apply(image, to: manager)
        manager.settings.syncSystemWallpaper = false
        manager.clearPreviewCacheArtifacts()
        checks["original-cache-clear-keeps-only-desktop-ownership-files"] = FileManager.default.fileExists(atPath: baseline.path)
            && !FileManager.default.fileExists(atPath: preview.path) && !FileManager.default.fileExists(atPath: current.path)
        quit(manager)
        checks["protected-app-managed-baseline-remains-restorable-after-cache-clear"] = desktop.urls[0] == baseline
            && desktop.urls[1] == baseline && FileManager.default.fileExists(atPath: baseline.path)
    }
    DesktopLeaf.screens = [DesktopScreen(id: 0), DesktopScreen(id: 1)]
    return checks
}
