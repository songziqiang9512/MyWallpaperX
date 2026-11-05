import AppKit
import Combine

@MainActor enum InspectorOnlineFirstTurnObservation {
    static var refreshes: [ObjectIdentifier: Int] = [:]
}

@main struct InspectorOnlineFirstTurnChecks {
    @MainActor static func main() {
        initializeNativeAppHarness()
        let app = NSApplication.shared
        Task { @MainActor in
            do { try await run() }
            catch { fputs("\(error)\n", stderr); exit(1) }
            app.stop(nil)
            if let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { app.postEvent(wake, atStart: false) }
        }
        app.run()
    }

    @MainActor static func wait(_ name: String, _ condition: () -> Bool) async throws {
        for _ in 0..<120 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw NSError(domain: "InspectorFirstTurn", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out: \(name); active=\(NSApp.isActive)"])
    }

    @MainActor static func run() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let library = OnlineImageLibrary.shared
        library.root = root
        let ids = (0..<3).map { OnlineImageAssetID(source: .pixiv, artworkID: "119", pageIndex: $0) }
        let pixels = CGContext(data: nil, width: 32, height: 16, bitsPerComponent: 8, bytesPerRow: 128,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        pixels.setFillColor(NSColor.systemGreen.cgColor); pixels.fill(CGRect(x: 0, y: 0, width: 32, height: 16))
        let cgImage = pixels.makeImage()!
        let image = NSImage(cgImage: cgImage, size: .init(width: 32, height: 16))
        let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])!
        library.snapshot = .init(records: try ids.enumerated().map { index, id in
            let name = "page-\(index).png", url = root.appendingPathComponent("page-\(index).png")
            try data.write(to: url)
            SILThumbnailProvider.images[url.path] = image
            return .init(assetID: id, title: "Page \(index)", sourceURL: URL(string: "https://example.invalid/work/119")!,
                author: nil, authorID: nil, tags: [], relativePath: name, pixelWidth: 32, pixelHeight: 16,
                fileSizeBytes: Int64(data.count), firstDownloadedAt: Date(), revision: UUID())
        })
        let window = NSWindow(contentRect: .init(x: 160, y: 160, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let sidebar = NSViewController(), content = NSViewController(), tint = AppKitListTintSurface()
        sidebar.view = tint; content.view = NSView()
        let split = AppKitMainSplitViewController(sidebar: sidebar, content: content, sidebarTintHost: tint)
        window.contentViewController = split; window.setContentSize(.init(width: 1000, height: 700))
        window.makeKeyAndOrderFront(nil); app.activate()
        defer { window.orderOut(nil); window.close() }
        try await wait("native window admission") { app.isActive && window.isKeyWindow && window.isVisible }
        let workspace = WallpaperLibraryWorkspace()
        workspace.playing = ids[0].reference
        var factories = 0, applied: [WallpaperReference] = []
        let coordinator = WallpaperLibraryInspectorCoordinator(workspace: workspace, manager: WallpaperManager(),
            images: SILService(), steam: SteamWorkshopService(), pixabay: PixabayService(),
            makePrimaryAction: { item in factories += 1; return { applied.append(item.reference) } },
            makeFavoriteAction: { _ in nil }, canOrganize: { false },
            availabilityChanges: Empty<Void, Never>().eraseToAnyPublisher(), onChoosePlaylist: { _, _ in })
        let probe = InspectorProbe()
        var checks: [String: Bool] = [:], receipts: [String: [String: Any]] = [:]
        func currentView() throws -> OnlineImageInspectorView {
            guard let view = probe.mounts.last?.1 as? OnlineImageInspectorView else {
                throw NSError(domain: "InspectorFirstTurn", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Real Online Inspector was not mounted"])
            }
            return view
        }
        func receipt(_ view: OnlineImageInspectorView, factoryDelta: Int) -> [String: Any] {
            ["enabled": view.primaryButton.isEnabled, "title": view.primaryButton.accessibilityLabel() ?? "",
             "boundReference": view.boundActions?.0.storageKey ?? "nil", "page": view.pageIndex,
             "factoryDelta": factoryDelta, "refreshes": InspectorOnlineFirstTurnObservation.refreshes[ObjectIdentifier(view), default: 0],
             "mounted": view.window === window]
        }
        let art = OnlineImageArtwork(source: .pixiv, artworkID: "119", title: "Local pages",
            sourceURL: URL(string: "https://example.invalid/work/119")!, kind: .image)
        var firstDetail: CheckedContinuation<OnlineImageArtwork, Never>?
        library.detailResolver = { _ in await withCheckedContinuation { firstDetail = $0 } }
        defer { firstDetail?.resume(returning: art) }
        let beforeFirst = factories
        coordinator.inspectOnlineArtwork(art)
        let first = try currentView()
        receipts["firstBeforePump"] = receipt(first, factoryDelta: factories - beforeFirst)
        checks["coordinator-first-turn-local-actions-are-bound-and-native-button-enabled"] =
            first.boundActions?.0 == ids[0].reference && first.primaryButton.isEnabled
        checks["already-playing-local-first-turn-shows-stop"] = first.primaryButton.accessibilityLabel() == "停止播放"
        checks["constructor-binding-reuses-one-action-factory-and-one-facts-build"] = factories == beforeFirst + 1
            && InspectorOnlineFirstTurnObservation.refreshes[ObjectIdentifier(first)] == 1
        checks["constructor-synchronously-shows-loading-before-detail-completion"] = first.isResolving
            && !first.notice.isHidden && first.notice.stringValue == "正在获取作品详情…"
        let beforeFirstPress = applied.count
        let firstPressed = first.primaryButton.accessibilityPerformPress()
        checks["native-first-turn-button-dispatches-the-first-page"] = firstPressed
            && Array(applied.dropFirst(beforeFirstPress)) == [ids[0].reference]
        let firstFacts = first.facts.arrangedSubviews[0]
        var mainTurnDelivered = false
        DispatchQueue.main.async { mainTurnDelivered = true }
        try await wait("held initial detail and snapshot seed turn") { firstDetail != nil && mainTurnDelivered }
        checks["snapshot-seed-turn-does-not-repeat-real-facts-refresh"] = InspectorOnlineFirstTurnObservation.refreshes[ObjectIdentifier(first)] == 1
        checks["snapshot-seed-turn-keeps-the-existing-facts-view"] = first.facts.arrangedSubviews.first === firstFacts
        receipts["firstSeedPumped"] = receipt(first, factoryDelta: factories - beforeFirst)
        let beforeSame = InspectorOnlineFirstTurnObservation.refreshes[ObjectIdentifier(first), default: 0]
        let beforeSameFacts = first.facts.arrangedSubviews[0]
        let sameSnapshot = library.snapshot; library.snapshot = sameSnapshot
        mainTurnDelivered = false; DispatchQueue.main.async { mainTurnDelivered = true }
        try await wait("later same snapshot publication") { mainTurnDelivered }
        checks["later-same-snapshot-still-refreshes-facts"] = InspectorOnlineFirstTurnObservation.refreshes[ObjectIdentifier(first)] == beforeSame + 1
            && first.facts.arrangedSubviews.first !== beforeSameFacts && first.primaryButton.isEnabled
        let beforeChanged = InspectorOnlineFirstTurnObservation.refreshes[ObjectIdentifier(first), default: 0]
        let beforeChangedFacts = first.facts.arrangedSubviews[0]
        var changedSnapshot = library.snapshot; changedSnapshot.unavailable.insert(ids[0])
        library.snapshot = changedSnapshot
        mainTurnDelivered = false; DispatchQueue.main.async { mainTurnDelivered = true }
        try await wait("later changed snapshot publication") { mainTurnDelivered }
        checks["later-changed-snapshot-still-refreshes-current-availability"] = InspectorOnlineFirstTurnObservation.refreshes[ObjectIdentifier(first)] == beforeChanged + 1
            && first.facts.arrangedSubviews.first !== beforeChangedFacts && !first.primaryButton.isEnabled && !first.isLocalAvailable
        firstDetail?.resume(returning: art); firstDetail = nil; library.detailResolver = nil
        let firstToken = coordinator.inspectorToken
        first.changePage(1)
        let beforePagePress = applied.count
        let pagePressed = first.primaryButton.accessibilityPerformPress()
        checks["later-page-keeps-fresh-factory-actions-with-the-current-host-token"] = first.pageIndex == 1
            && first.boundActions?.0 == ids[1].reference && first.primaryButton.isEnabled && pagePressed
            && Array(applied.dropFirst(beforePagePress)) == [ids[1].reference] && coordinator.inspectorToken == firstToken
        let retiredAction = first.boundActions?.1.onPrimary
        let beforePageTwo = factories
        coordinator.inspect(content: library.content(for: ids[2].reference)!)
        let second = try currentView()
        receipts["pageTwoBeforePump"] = receipt(second, factoryDelta: factories - beforePageTwo)
        checks["direct-page-two-first-turn-keeps-its-own-reference-and-enabled-action"] = second.pageIndex == 2
            && second.boundActions?.0 == ids[2].reference && second.primaryButton.isEnabled
        checks["direct-page-two-does-not-add-an-action-factory-or-facts-build"] = factories == beforePageTwo + 1
            && InspectorOnlineFirstTurnObservation.refreshes[ObjectIdentifier(second)] == 1
        let beforeRetiredAction = applied.count
        retiredAction?()
        checks["replacing-inspector-revokes-the-real-former-pages-action"] = applied.count == beforeRetiredAction
            && coordinator.inspectorToken != firstToken
        try await wait("queued local snapshot and detail completion") { second.boundActions?.0 == ids[2].reference && !second.isResolving }
        let heldAction = second.boundActions?.1.onPrimary
        let beforeClose = applied.count
        coordinator.closeInspector(); heldAction?()
        checks["close-revokes-the-real-view-bound-action"] = heldAction != nil && applied.count == beforeClose
            && coordinator.inspectedReference == nil
        try await wait("closed inspector unmount") { second.window == nil }
        let remote = OnlineImageArtwork(source: .wallhaven, artworkID: "remote", title: "Remote",
            sourceURL: URL(string: "https://example.invalid/remote")!, kind: .image)
        coordinator.inspectOnlineArtwork(remote)
        let remoteView = try currentView()
        checks["remote-first-turn-does-not-borrow-local-actions"] = remoteView.boundActions == nil
            && !remoteView.primaryButton.isEnabled && remoteView.artwork.artworkID == remote.artworkID
        coordinator.closeInspector()
        try await wait("remote inspector unmount") { remoteView.window == nil }
        library.snapshot.unavailable.insert(ids[2])
        coordinator.inspect(content: library.content(for: ids[2].reference)!)
        let unavailable = try currentView()
        checks["unavailable-local-first-turn-does-not-enable-a-stale-local-action"] = unavailable.boundActions == nil
            && !unavailable.primaryButton.isEnabled
        coordinator.closeInspector()
        try await wait("unavailable inspector unmount") { unavailable.window == nil }
        library.snapshot.unavailable.remove(ids[2])
        coordinator.inspect(content: library.content(for: ids[2].reference)!)
        let restored = try currentView()
        try await wait("restored local binding") { restored.boundActions?.0 == ids[2].reference }
        let epochAction = restored.boundActions?.1.onPrimary, beforeEpoch = applied.count
        let previous = workspace.relationships
        workspace.relationships = .init(revision: previous.revision + 1, resetEpoch: UUID(), playlists: previous.playlists, members: previous.members, favorites: previous.favorites,
            recent: previous.recent, aliases: previous.aliases, locators: previous.locators)
        epochAction?()
        checks["reset-epoch-still-revokes-the-initially-bound-action"] = epochAction != nil && applied.count == beforeEpoch
        coordinator.closeInspector()
        try await wait("final inspector unmount") { restored.window == nil }
        FileHandle.standardError.write(Data(("ONLINE FIRST TURN " + String(decoding: try JSONSerialization.data(withJSONObject: receipts,
            options: [.sortedKeys]), as: UTF8.self) + "\n").utf8))
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
        withExtendedLifetime((coordinator, probe)) {}
    }
}
