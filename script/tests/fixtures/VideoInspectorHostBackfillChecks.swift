import AppKit
import QuartzCore

extension Harness {
    @MainActor static func hostBackfill() async throws {
        func wait(_ condition: () -> Bool) async -> Bool {
            for _ in 0..<250 {
                if condition() { return true }
                try? await Task.sleep(for: .milliseconds(8))
            }
            return condition()
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let source = root.appendingPathComponent("host-current.mp4"), jpeg = root.appendingPathComponent("host-preview.jpg")
        try Data("owned metadata leaf input".utf8).write(to: source)
        writeJPEG(jpeg.path, red: 0.10, green: 0.82, blue: 0.25, width: 1280, height: 720)
        let manager = WallpaperManager()
        manager.wallpapers = (0..<5000).map { VideoWallpaper(id: "host-\($0)", title: "Host \($0)",
            path: $0 == 4999 ? source.path : root.appendingPathComponent("other-\($0).mp4").path) }
        let current = manager.wallpapers.last!
        var expectedTitle = current.title, primaryWrites = 0
        let actions = WallpaperInspectorActions(state: .init(isPlaying: false, isFavorite: false, canPerformPrimary: true,
            canFavorite: false, canOrganize: false, playlistNames: ["Host Initial"]), onPrimary: { primaryWrites += 1 },
            onToggleFavorite: {}, onChoosePlaylist: { _ in })
        InspectorMetadataProbe.heldPaths.insert(source.path)
        manager.blockResolvedThumbnail(for: source.path)
        defer { InspectorMetadataProbe.release(source.path); manager.releaseResolvedThumbnail(for: source.path) }
        let inspector = VideoLibraryInspectorView(wallpaper: current, wallpaperManager: manager, libraryActions: actions)
        let sidebar = NSViewController(), content = NSViewController(), tint = AppKitListTintSurface()
        sidebar.view = tint; content.view = NSView()
        let split = AppKitMainSplitViewController(sidebar: sidebar, content: content, sidebarTintHost: tint)
        let window = NSWindow(contentRect: .init(x: 160, y: 160, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = split; window.setContentSize(.init(width: 1000, height: 700))
        window.makeKeyAndOrderFront(nil); NSApp.activate()
        defer { InspectorHostActions.postClose(); window.orderOut(nil); window.close() }
        let mount = NotificationCenter.default.addObserver(forName: .inspectorHostDidPresent, object: nil, queue: .main) { _ in
            InspectorHostActions.postMount(module: .videoLibrary, cardID: current.id, hostedView: inspector)
        }
        defer { NotificationCenter.default.removeObserver(mount) }
        var checks: [String: Bool] = [:], frames: [[String: Any]] = [], identities: [String: [String: Bool]] = [:]
        checks["native-window-is-visible-active-and-key"] = await wait { window.isVisible && window.isKeyWindow && NSApp.isActive }
        let host = split.children.flatMap(\.children).compactMap { $0 as? InspectorHostViewController }.first!
        let animationHost = host.view.superview!, overlay = animationHost.superview!
        func record(_ stage: String) {
            frames.append(["stage": stage, "hostSeconds": ProcessInfo.processInfo.systemUptime,
                "presentationFrame": (animationHost.layer?.presentation()?.frame).map { NSStringFromRect($0) } ?? "nil",
                "modelFrame": NSStringFromRect(animationHost.frame), "overlayBounds": NSStringFromRect(overlay.bounds), "visible": window.isVisible,
                "active": NSApp.isActive, "key": window.isKeyWindow])
        }
        func intermediate() -> Bool {
            guard let frame = animationHost.layer?.presentation()?.frame else { return false }
            let offset = frame.maxX - overlay.bounds.maxX
            return offset > 0.5 && offset < animationHost.frame.width + 48
        }
        let names = ["preview", "preview-parent", "scroll", "title", "title-parent", "codec-label", "codec-value", "codec-parent", "summary", "path"]
        func nodes() -> [NSView] {
            let preview = firstSubview(of: inspector) { $0 is VideoLibraryInspectorPreviewSurfaceView }!
            let title = firstSubview(of: inspector) { ($0 as? NSTextField)?.stringValue == expectedTitle }!
            let codec = firstSubview(of: inspector) { ($0 as? NSTextField)?.stringValue == "编解码器" }!
            let column = codec.superview as! NSStackView
            return [preview, preview.superview!, firstSubview(of: inspector) { $0 is InspectorFadingScrollView }!, title,
                title.superview!, codec, column.arrangedSubviews.last!, column,
                firstSubview(of: inspector) { ($0 as? NSTextField)?.stringValue.contains(" · ") == true }!,
                firstSubview(of: inspector) { ($0 as? NSTextField)?.stringValue == source.path }!]
        }
        window.contentView?.layoutSubtreeIfNeeded()
        checks["metadata-is-pending-before-post-open"] = await wait {
            InspectorMetadataProbe.pending[source.path]?.count == 1 && window.isVisible && window.isKeyWindow && NSApp.isActive
        }
        func sameFrame(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
            abs(lhs.minX - rhs.minX) <= 0.5 && abs(lhs.minY - rhs.minY) <= 0.5
                && abs(lhs.width - rhs.width) <= 0.5 && abs(lhs.height - rhs.height) <= 0.5
        }
        var previousStartupFrame: NSRect?
        checks["native-startup-geometry-is-stable-before-post-open"] = await wait {
            record("await-startup-geometry-poll")
            let model = animationHost.frame
            guard let presentation = animationHost.layer?.presentation()?.frame,
                  sameFrame(presentation, model), abs(model.height - overlay.bounds.height) <= 0.5 else {
                previousStartupFrame = nil
                return false
            }
            let unchanged = previousStartupFrame.map { sameFrame($0, model) } ?? false
            previousStartupFrame = model
            return unchanged
        }
        record("stable-window-before-post-open")
        InspectorHostActions.postOpen(module: .videoLibrary, presentation: .standard(cardID: current.id, title: "Host Backfill"))
        record("after-post-open")
        let initial = nodes(), initialConfigurations = InspectorContentBuildProbe.hostConfigurations
        func compare(_ stage: String) {
            identities[stage] = Dictionary(uniqueKeysWithValues: zip(names, zip(initial, nodes())).map { ($0.0, $0.1.0 === $0.1.1) })
            checks[stage + "-keeps-fields-and-parents"] = identities[stage]!.values.allSatisfy { $0 }
        }
        checks["real-view-is-mounted-before-release"] = inspector.isDescendant(of: host.view)
        checks["backfill-starts-during-actual-presentation"] = await wait {
            record("await-start-poll")
            guard let frame = animationHost.layer?.presentation()?.frame else { return false }
            let model = animationHost.frame
            return model.width > 0 && intermediate() && InspectorMetadataProbe.pending[source.path]?.count == 1
                && abs(frame.width - model.width) <= 0.5 && abs(frame.height - model.height) <= 0.5
                && frame.maxX - overlay.bounds.maxX >= model.width / 3
        }
        record("before-backfill")
        manager.setResolvedThumbnail(jpeg.path, for: source.path)
        manager.releaseResolvedThumbnail(for: source.path); InspectorMetadataProbe.release(source.path)
        let metadataArrived = await wait {
            InspectorMetadataProbe.terminals[source.path] == 1
                && firstSubview(of: inspector) { ($0 as? NSTextField)?.stringValue == "High Efficiency Video Coding Long Value" } != nil
        }
        record("after-metadata-backfill"); compare("metadata-backfill")
        checks["backfill-completes-before-entrance-settles"] = metadataArrived && intermediate()
        for batch in 0..<2 {
            var rows = manager.wallpapers
            for index in (batch * 128)..<((batch + 1) * 128) { rows[index].thumbnailPath = jpeg.path }
            manager.wallpapers = rows
        }
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        record("after-unrelated-publications"); compare("unrelated-publications")
        for index in 0..<16 {
            try? await Task.sleep(for: .milliseconds(16)); record("after-update-\(index)")
        }
        checks["actual-metadata-and-decoded-preview-arrive"] = await wait {
            metadataArrived && !placeholderVisible(in: inspector) && InspectorCacheDemandProbe.shared.loadCount(jpeg.path) > 0
        }
        checks["host-configure-does-not-repeat-for-body-updates"] = InspectorContentBuildProbe.hostConfigurations == initialConfigurations
        checks["entrance-reaches-original-final-geometry"] = !overlay.isHidden && abs(animationHost.frame.maxX - overlay.bounds.maxX) <= 0.5
        expectedTitle = "Host Updated Current"
        var updated = manager.wallpapers
        updated[4999] = VideoWallpaper(id: current.id, title: expectedTitle, path: source.path)
        manager.wallpapers = updated
        checks["current-tail-model-content-still-updates"] = await wait { firstSubview(of: inspector) { ($0 as? NSTextField)?.stringValue == expectedTitle } != nil }
        compare("current-content")
        let replacement = WallpaperInspectorActions(state: .init(isPlaying: true, isFavorite: false, canPerformPrimary: true,
            canFavorite: false, canOrganize: false, playlistNames: ["Host Updated List"]), onPrimary: { primaryWrites += 10 },
            onToggleFavorite: {}, onChoosePlaylist: { _ in })
        inspector.updateLibraryActions(replacement)
        let primary = firstSubview(of: inspector) { ($0 as? InspectorFooterButton)?.action == NSSelectorFromString("setAsWallpaper") } as! InspectorFooterButton
        checks["current-actions-and-playlist-still-update"] = primary.accessibilityPerformPress() && primaryWrites == 10 && manager.primaryWrites == 0
            && firstSubview(of: inspector) { ($0 as? NSTextField)?.stringValue == "Host Updated List" } != nil
        checks["final-real-preview-has-correct-pixels"] = looksGreen(centerPixel(in: inspector))
        let section = firstSubview(of: inspector) { ($0 as? NSTextField)?.stringValue == "原数据" }!.superview as! NSStackView
        let currentNodes = nodes()
        let stable = Array(currentNodes.prefix(5)) + Array(currentNodes.suffix(2)) + [section, section.superview!]
        let alternate = root.appendingPathComponent("host-empty-facts.mp4")
        try Data("owned empty metadata input".utf8).write(to: alternate)
        InspectorMetadataProbe.omittedFacts.insert(alternate.path)
        for (path, omitted, terminal) in [(alternate, true, 1), (source, false, 2)] {
            let previousGrid = section.arrangedSubviews.last!
            var rows = manager.wallpapers
            rows[4999] = VideoWallpaper(id: current.id, title: expectedTitle, path: path.path)
            manager.wallpapers = rows
            let completed = await wait { InspectorMetadataProbe.terminals[path.path] == terminal }
            let codec = firstSubview(of: inspector) { ($0 as? NSTextField)?.stringValue == "编解码器" && !$0.isHiddenOrHasHiddenAncestor }
            checks["facts-structure-\(omitted ? "empty" : "restored")-replaces-only-grid"] = completed
                && stable.allSatisfy { $0.isDescendant(of: inspector) } && section.arrangedSubviews.last !== previousGrid
                && (codec != nil) == !omitted && (currentNodes.last as? NSTextField)?.stringValue == path.path
                && (firstSubview(of: inspector) { ($0 as? NSTextField)?.stringValue == "添加时间" && !$0.isHiddenOrHasHiddenAncestor } != nil) == !omitted
        }
        checks["one-template-serves-backfill-and-current-updates"] = InspectorContentBuildProbe.bodiesByView[ObjectIdentifier(inspector)] == 1
        checks["sampled-window-remains-visible-active-and-key"] = frames.allSatisfy { ($0["visible"] as? Bool) == true && ($0["active"] as? Bool) == true && ($0["key"] as? Bool) == true }
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["checks": checks, "frames": frames,
            "identities": identities, "sourceCount": manager.wallpapers.count], options: [.sortedKeys]), as: UTF8.self))
    }
}
