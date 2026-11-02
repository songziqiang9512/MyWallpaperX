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


// Only delivery and native capture are controlled; encoding, publication,
// desktop copies, identity guards and cleanup use the extracted Manager bodies.
@MainActor enum RuntimeFrameDelivery {
    static var delayed: [DispatchWorkItem] = [], workers: [() -> Void] = [], mains: [() -> Void] = []
    static var delays: [TimeInterval] = [], captures = 0, failCopy = false
    static var recordID: String?, image: NSImage?
    static func after(delay: TimeInterval, execute: DispatchWorkItem) { delays.append(delay); delayed.append(execute) }
    static func utility(_ work: @escaping () -> Void) { workers.append(work) }
    static func main(_ work: @escaping () -> Void) { mains.append(work) }
    static func copy(_ source: URL, to destination: URL) throws {
        if failCopy { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.copyItem(at: source, to: destination)
    }
}
extension WallpaperEngine {
    var currentWebRecordID: String? { RuntimeFrameDelivery.recordID }
    func captureWebWallpaperFrame(completion: @escaping (NSImage?) -> Void) {
        RuntimeFrameDelivery.captures += 1; completion(RuntimeFrameDelivery.image)
    }
}
extension SceneDaemonClient {
    var activeRecordID: String? { nil }
    var launchState: ScenePlaybackLoadRequest? { nil }
    func captureSurfaceFrame(completion: @escaping (URL?) -> Void) { preconditionFailure("Web frame checks do not capture Scene") }
}

@MainActor func runRuntimeFrameSystemWallpaperChecks(root: URL) throws -> [String: Bool] {
    var checks: [String: Bool] = [:]
    let desktop = DesktopLeaf.shared
    func jpeg(_ red: UInt8, _ blue: UInt8) throws -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8,
            samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 24, bitsPerPixel: 24)!
        for i in 0..<64 { rep.bitmapData![i * 3] = red; rep.bitmapData![i * 3 + 1] = 0; rep.bitmapData![i * 3 + 2] = blue }
        let url = root.appendingPathComponent(UUID().uuidString + ".jpg")
        try rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!.write(to: url)
        return NSImage(data: try Data(contentsOf: url))!
    }
    func rgb(_ url: URL) throws -> [Double] {
        let color = NSBitmapImageRep(data: try Data(contentsOf: url))!.colorAt(x: 0, y: 0)!.usingColorSpace(.deviceRGB)!
        return [color.redComponent, color.greenComponent, color.blueComponent].map(Double.init)
    }
    func temporaryFrames(_ manager: WallpaperManager) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: manager.staticFrameCacheDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("runtime-sync-web-") }
    }
    func setup(sync: Bool = true) throws -> WallpaperManager {
        RuntimeFrameDelivery.delayed = []; RuntimeFrameDelivery.workers = []; RuntimeFrameDelivery.mains = []
        RuntimeFrameDelivery.delays = []; RuntimeFrameDelivery.captures = 0; RuntimeFrameDelivery.failCopy = false
        RuntimeFrameDelivery.recordID = nil; RuntimeFrameDelivery.image = nil
        desktop.attempts = []; desktop.failURLs = []; desktop.failScreen = nil
        desktop.urls = [0: root.appendingPathComponent("original-a.jpg"), 1: root.appendingPathComponent("original-b.jpg")]
        let manager = WallpaperManager(); manager.settings.syncSystemWallpaper = sync
        manager.staticFrameCacheDirectory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        manager.thumbnailCacheDirectory = manager.staticFrameCacheDirectory.appendingPathComponent("thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: manager.staticFrameCacheDirectory, withIntermediateDirectories: true)
        return manager
    }
    @discardableResult func commit(_ manager: WallpaperManager, _ record: String, _ image: NSImage?) throws -> PlaybackSwitchTicket {
        let reference = WallpaperReference(provider: .steamWorkshop, sourceID: record)
        let source = try WallpaperPlaybackSequence.Snapshot(source: .single(reference), revision: 1,
            entries: [.init(reference: reference, runtime: .web, isPlayable: true)])
        manager.libraryPlaybackDispatcher = { [weak manager] pending in
            guard let manager else { return false }
            manager.setWebWallpaper(requestID: UUID(), entryURL: root.appendingPathComponent("index.html"), rootURL: root,
                propertiesJSON: nil, recordID: record, language: "en-us", runtimeProfile: .standard,
                resourceLifetime: nil, intentEpoch: pending.ticket.epoch, libraryPending: pending)
            return true
        }
        let ticket = manager.requestLibraryPlayback(reference: reference, from: source)!
        let endpoint = NativeEndpoint(ticket)
        endpoint.onFinalize = { RuntimeFrameDelivery.recordID = record; RuntimeFrameDelivery.image = image }
        manager.switchPrepared(ticket, endpoint: endpoint.endpoint); endpoint.show(manager)
        precondition(manager.playbackSwitch.committed?.ticket == ticket)
        return ticket
    }
    let red = try jpeg(255, 0), blue = try jpeg(0, 255)
    do {
        let manager = try setup()
        let a = try commit(manager, "A", red); RuntimeFrameDelivery.delayed.removeFirst().perform()
        let b = try commit(manager, "B", blue); RuntimeFrameDelivery.delayed.removeFirst().perform()
        RuntimeFrameDelivery.workers.remove(at: 1)(); RuntimeFrameDelivery.workers.removeFirst()()
        RuntimeFrameDelivery.mains.removeFirst()()
        let copied = desktop.urls[0]!, color = try rgb(copied), attempts = desktop.attempts.count
        RuntimeFrameDelivery.mains.removeFirst()()
        checks["runtime-sync-reversed-workers-copy-the-current-blue-frame"] = a != b && color[2] > 0.8 && color[0] < 0.2
            && manager.playbackSwitch.committed?.ticket == b && copied.lastPathComponent.hasPrefix("system-wallpaper-active-")
        let remaining = try temporaryFrames(manager)
        checks["runtime-sync-stale-main-cannot-write-and-releases-its-temporary-frame"] = attempts == 2
            && desktop.attempts.count == attempts && remaining.isEmpty
        checks["runtime-sync-keeps-the-original-five-second-capture-request"] = RuntimeFrameDelivery.delays == [5, 5]
    }
    do {
        var manager: WallpaperManager? = try setup()
        weak var released = manager
        try commit(manager!, "release", red); RuntimeFrameDelivery.delayed.removeFirst().perform()
        RuntimeFrameDelivery.workers.removeFirst()()
        let frames = try temporaryFrames(manager!)
        manager = nil; RuntimeFrameDelivery.mains.removeFirst()()
        checks["runtime-sync-released-manager-cleans-the-worker-file-without-writing"] = released == nil && frames.count == 1
            && frames.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } && desktop.attempts.isEmpty
    }
    do {
        let manager = try setup()
        let stable = manager.staticFrameCacheDirectory.appendingPathComponent("runtime-sync-web.jpg"), previous = Data([4, 8, 15, 16])
        try previous.write(to: stable)
        let protected = manager.applySourceImageDirectly(stable)
        desktop.attempts = []
        try commit(manager, "clear", blue); RuntimeFrameDelivery.delayed.removeFirst().perform()
        RuntimeFrameDelivery.workers.removeFirst()()
        manager.clearPreviewCacheArtifacts(); RuntimeFrameDelivery.mains.removeFirst()()
        let remaining = try temporaryFrames(manager), preserved = try Data(contentsOf: stable)
        checks["runtime-sync-cache-clear-makes-publication-fail-without-a-desktop-write"] = protected && desktop.attempts.isEmpty
            && preserved == previous && remaining.isEmpty
    }
    do {
        let manager = try setup()
        RuntimeFrameDelivery.failCopy = true
        try commit(manager, "copy-fallback", blue); RuntimeFrameDelivery.delayed.removeFirst().perform()
        RuntimeFrameDelivery.workers.removeFirst()(); RuntimeFrameDelivery.mains.removeFirst()()
        let stable = manager.staticFrameCacheDirectory.appendingPathComponent("runtime-sync-web.jpg")
        let color = try rgb(stable), remaining = try temporaryFrames(manager)
        checks["runtime-sync-copy-failure-retains-a-readable-stable-source"] = desktop.urls[0] == stable && desktop.urls[1] == stable
            && color[2] > 0.8 && remaining.isEmpty
    }
    do {
        let manager = try setup(sync: false)
        try commit(manager, "disabled", red)
        checks["runtime-sync-disabled-does-not-capture-encode-or-write"] = RuntimeFrameDelivery.delayed.isEmpty
            && RuntimeFrameDelivery.workers.isEmpty && RuntimeFrameDelivery.captures == 0 && desktop.attempts.isEmpty
    }
    do {
        let manager = try setup()
        try commit(manager, "no-image", nil); RuntimeFrameDelivery.delayed.removeFirst().perform()
        checks["runtime-sync-missing-capture-does-not-enqueue-a-worker"] = RuntimeFrameDelivery.captures == 1
            && RuntimeFrameDelivery.workers.isEmpty && RuntimeFrameDelivery.mains.isEmpty && desktop.attempts.isEmpty
    }
    do {
        let manager = try setup()
        manager.staticFrameCacheDirectory.appendPathComponent("missing-directory", isDirectory: true)
        try commit(manager, "writer-failure", red); RuntimeFrameDelivery.delayed.removeFirst().perform()
        RuntimeFrameDelivery.workers.removeFirst()()
        checks["runtime-sync-writer-failure-does-not-enqueue-application"] = RuntimeFrameDelivery.mains.isEmpty && desktop.attempts.isEmpty
    }
    return checks
}
