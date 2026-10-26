import AppKit

// Native gestures, selection and controls use the complete current product grid.
// The original provider/card leaf below retains its controlled asset validator.

@MainActor func videoNativeClickChecks() -> [String: Bool] {
    let manager = WallpaperManager()
    let provider = AppKitThumbnailProvider(wallpaperManager: manager)
    let reference = WallpaperReference(provider: .videoLibrary, sourceID: "native target")
    let value = WallpaperContentItem(reference: reference, providerReference: reference,
        locator: .init(path: "/fixture-unread.mp4", mediaKind: .video), title: "native target", kind: .video,
        publishedAvailability: .available, capabilities: [.inspect, .play], metadata: .init(),
        acquisition: .idle, update: .idle, aliases: [])
    var played: [String] = [], selections = 0, inspections: [WallpaperReference] = []
    let controller = WallpaperLibraryGridController { collection, path, _, _ in
        let item = collection.makeItem(withIdentifier: AppKitWallpaperItem.reuseIdentifier, for: path) as! AppKitWallpaperItem
        item.setThumbnailVisible(false)
        item.configure(wallpaper: VideoWallpaper(id: "native target", path: "/fixture-unread.mp4", thumbnailPath: nil),
            isSelected: false, isPlaying: true, isFavorite: false, multiSelectMode: false,
            wallpaperManager: manager, thumbnailProvider: provider)
        item.onPlayRequested = { played.append($0) }
        return item
    }
    controller.loadViewIfNeeded()
    controller.collection.register(AppKitWallpaperItem.self, forItemWithIdentifier: AppKitWallpaperItem.reuseIdentifier)
    controller.onSelection = { _, _ in selections += 1; return UUID() }
    controller.onInspect = { inspections.append($0.reference) }
    let window = NSWindow(contentViewController: controller)
    window.setContentSize(NSSize(width: 330, height: 330))
    window.setFrameOrigin(NSPoint(x: 14000, y: 14000))
    window.isReleasedWhenClosed = false
    window.orderFrontRegardless()
    window.makeKey()
    controller.update(page: .videos, items: [value], selection: .init(), preferredColumns: 5,
        permitsDragging: false, scrollAnchor: nil)
    window.contentView?.layoutSubtreeIfNeeded()
    controller.collection.layoutSubtreeIfNeeded()
    defer { window.orderOut(nil); window.close(); provider.cancelAllPrefetch() }
    guard let card = controller.collection.item(at: IndexPath(item: 0, section: 0)) as? AppKitWallpaperItem else {
        return ["video.native-collection-registers-real-card": false]
    }
    card.view.layoutSubtreeIfNeeded()
    card.viewDidLayout()
    guard let bar = card.controlBar else { return ["video.native-collection-mounts-real-bar": false] }
    bar.layoutSubtreeIfNeeded()
    func click(_ point: NSPoint, label: String) {
        func diagnose(_ phase: String) {
            let hit = window.contentView?.hitTest(point)
            let values: [String] = [
                "video-native-click \(label) \(phase) active=\(NSApp.isActive) key=\(window.isKeyWindow) keyWindow=\(NSApp.keyWindow?.windowNumber ?? 0)",
                "window=\(window.windowNumber) point=\(point) hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil")",
                "card=\(card.view.frame) cover=\(card.imageContainer.frame) clip=\(controller.scrollView.contentView.bounds)",
                "selected=\(controller.selection.references.map(\.storageKey)) native=\(controller.collection.selectionIndexPaths) cancelled=\(controller.collection.cancelSelectionTracking)",
                "play=\(played) selectionEvents=\(selections) inspections=\(inspections.map(\.storageKey))"
            ]
            FileHandle.standardError.write(Data((values.joined(separator: " ") + "\n").utf8))
        }
        diagnose("before")
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime + 0.01, windowNumber: window.windowNumber,
            context: nil, eventNumber: 3, clickCount: 1, pressure: 0)!
        NSApp.postEvent(up, atStart: true)
        window.sendEvent(down)
        let until = Date().addingTimeInterval(0.02)
        repeat {
            while let event = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.002))
        } while Date() < until
        diagnose("after")
    }
    let button = bar.playButton
    click(button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil), label: "button")
    var checks = ["video.native-primary-click-plays-once-without-collection-selection": played == ["native target"]
        && selections == 0 && inspections.isEmpty && controller.selection.references.isEmpty]
    click(button.convert(NSPoint(x: button.bounds.minX - 4, y: button.bounds.midY), to: nil), label: "button-neighbor")
    checks["video.button-neighbor-keeps-card-selection-without-playing"] = played == ["native target"]
        && selections == 1 && inspections == [reference] && controller.selection.references == [reference]
    click(card.imageContainer.convert(NSPoint(x: 100, y: 150), to: nil), label: "cover")
    checks["video.cover-keeps-card-selection-without-playing"] = played == ["native target"]
        && selections == 2 && inspections == [reference, reference] && controller.selection.references == [reference]
    return checks
}

/// The runner compiles the complete production card and provider. Only the
/// pre-existing model/asset-validation leaves from the prefetch fixture are
/// supplied; no card methods, hierarchy or event bodies are substituted.
@main struct VideoCardInteractionHarness {
    @MainActor static func main() throws {
        initializeNativeAppHarness()
        if CommandLine.arguments.dropFirst().first == "--card-reflow" {
            let manager = WallpaperManager()
            let provider = AppKitThumbnailProvider(wallpaperManager: manager)
            defer { provider.cancelAllPrefetch() }
            let checks = wallpaperGridCardReflowChecks(label: "video", provider: .videoLibrary,
                itemClass: AppKitWallpaperItem.self, reuseIdentifier: AppKitWallpaperItem.reuseIdentifier,
                resetColdTracking: AppKitWallpaperItem.resetHoverTrackingActivation,
                makeCard: { collection, path, state, playing in
                    let card = collection.makeItem(withIdentifier: AppKitWallpaperItem.reuseIdentifier, for: path) as! AppKitWallpaperItem
                    card.setThumbnailVisible(false)
                    card.configure(wallpaper: VideoWallpaper(id: "reflow-\(path.item)", path: "/fixture-reflow-\(path.item).mp4", thumbnailPath: nil),
                        isSelected: state.isSelected, isPlaying: playing, isFavorite: false, multiSelectMode: state.isSelecting,
                        wallpaperManager: manager, thumbnailProvider: provider)
                    return card
                }, updateState: { cell, state, playing in
                    let card = cell as! AppKitWallpaperItem
                    card.applySelectionState(isSelected: state.isSelected, multiSelectMode: state.isSelecting)
                    card.applyPlayingState(isPlaying: playing)
                }, isHovering: { ($0 as! AppKitWallpaperItem).isHovering },
                bar: { ($0 as! AppKitWallpaperItem).controlBar })
            print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
            return
        }
        let card = AppKitWallpaperItem()
        _ = card.view
        var checks: [String: Bool] = ["video.idle-card-has-no-glass-badge": card.controlBar == nil]
        let manager = WallpaperManager()
        let provider = AppKitThumbnailProvider(wallpaperManager: manager)
        card.setThumbnailVisible(false)
        card.configure(wallpaper: VideoWallpaper(id: "interaction", path: "/fixture-unread-video.mp4", thumbnailPath: nil),
            isSelected: false, isPlaying: false, isFavorite: false, multiSelectMode: false,
            wallpaperManager: manager, thumbnailProvider: provider)
        checks.merge(gridCardInteractionChecks(item: card, cardRoot: card.imageContainer,
            outline: card.hoverOutlineView, isHovering: { card.isHovering }, label: "video",
            dragImageView: card.thumbnailImageView, layoutDragImage: { card.layoutThumbnail() })
        ) { _, new in new }
        let firstBadge = card.controlBar
        checks["video.first-hover-builds-badge-at-current-size"] = firstBadge != nil
            && firstBadge!.frame == card.controlBarFrame && firstBadge!.frame.width > 20
        card.refreshGridHover(isScrolling: true)
        checks["video.scroll-detaches-native-hover-tracking"] = card.imageContainer.trackingAreas.isEmpty
        card.applyPlayingState(isPlaying: true)
        checks["video.playing-stays-visible-without-hover"] = firstBadge?.isHidden == false
            && firstBadge?.alphaValue == 1 && firstBadge?.primaryState == .playing
        if let badge = firstBadge {
            let metrics = WallpaperCardBarMetrics(cardWidth: card.imageContainer.bounds.width)
            let stopSymbol = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)!
                .withSymbolConfiguration(.init(pointSize: max(11, metrics.iconButtonSize * 0.56), weight: .medium))!
            checks["video-playing-keeps-real-stop-symbol-and-accessibility"] = badge.playButton.accessibilityLabel() == "停止播放"
                && badge.playButton.toolTip == "停止播放" && badge.playButton.contentTintColor == .controlAccentColor
                && stopSymbol.tiffRepresentation != nil && badge.playButton.image?.tiffRepresentation == stopSymbol.tiffRepresentation
        }
        if let badge = firstBadge {
            badge.layoutSubtreeIfNeeded()
            card.applySelectionState(isSelected: true, multiSelectMode: true)
            checks["video.multi-select-detaches-play-target"] = badge.isHidden && badge.superview == nil
            card.applySelectionState(isSelected: false, multiSelectMode: false)
            card.refreshGridHover(isScrolling: false)
            checks["video.restore-does-not-duplicate-tracking-or-badge"] = card.controlBar === badge
                && card.imageContainer.trackingAreas.count == 1
        }
        if let bar = firstBadge {
            let hitWindow = NSWindow(contentRect: NSRect(x: 14_000, y: 14_000, width: 280, height: 280),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
            hitWindow.isReleasedWhenClosed = false
            let hitHost = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 280))
            hitWindow.contentView = hitHost
            card.view.frame = NSRect(x: 20, y: 20, width: 240, height: 240)
            hitHost.addSubview(card.view)
            hitWindow.orderFrontRegardless()
            defer { card.view.removeFromSuperview(); hitWindow.orderOut(nil); hitWindow.close() }
            card.applySelectionState(isSelected: false, multiSelectMode: false)
            card.applyPlayingState(isPlaying: true)
            card.view.layoutSubtreeIfNeeded()
            card.viewDidLayout()
            bar.layoutSubtreeIfNeeded()
            card.applyHoverVisibility(true, animated: false)
            // Exercise the fully visible decoration while testing hit routing.
            // Pointer tracking itself is covered by the window fixture above.
            checks["video.unbound-organization-heart-is-hidden"] = bar.favoriteButton.isHidden
            var played: [String] = []
            var favorites: [String] = []
            card.onPlayRequested = { played.append($0) }
            card.onFavoriteRequested = { favorites.append($0) }
            card.hoverOutlineView.alphaValue = 1
            func hits(_ button: NSButton) -> Bool {
                let point = hitHost.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
                let hit = hitHost.hitTest(point)
                return hit === button || hit?.isDescendant(of: button) == true
            }
            checks["video.visible-hover-outline-does-not-intercept-native-play-button"] = card.hoverOutlineView.alphaValue == 1 && hits(bar.playButton)
            checks["video.playing-hit-target-survives-lazy-creation"] = hits(bar.playButton)
            checks["video.visible-hover-outline-does-not-intercept-native-favorite-button"] = hits(bar.favoriteButton)
            card.view.appearance = NSAppearance(named: .aqua)
            card.refreshThemeAwareAppearance()
            let lightOutline = NSColor(cgColor: card.hoverOutlineView.layer!.borderColor!)!.usingColorSpace(.deviceRGB)!
            checks["video.light-mode-also-retains-white-hover-outline"] = lightOutline.redComponent > 0.99
                && lightOutline.greenComponent > 0.99 && lightOutline.blueComponent > 0.99
            card.view.appearance = NSAppearance(named: .darkAqua)
            card.refreshThemeAwareAppearance()
            card.applyPlayingState(isPlaying: false)
            card.applyHoverVisibility(false, animated: true)
            card.applyHoverVisibility(true, animated: true)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            checks["video.late-fade-completion-cannot-detach-newly-visible-bar"] = bar.superview != nil
                && !bar.isHidden && bar.alphaValue == 1
            card.applyPlayingState(isPlaying: true)
            bar.playButton.performClick(nil)
            bar.favoriteButton.performClick(nil)
            checks["video.native-buttons-target-the-current-card"] = played == ["interaction"] && favorites == ["interaction"]
            checks["video.buttons-retain-native-accessibility"] = bar.playButton.accessibilityLabel() == "停止播放"
                && bar.favoriteButton.accessibilityLabel() == "特别喜爱"
            card.applyFavoriteState(isFavorite: true)
            checks["video.favorite-state-keeps-one-bar-heart-without-duplicate-corner-badge"] = bar.isFavorite
                && card.isFavoriteState && bar.favoriteButton.accessibilityLabel() == "取消特别喜爱"
                && card.imageContainer.subviews.filter { $0 is NSImageView }.count == 1
                && card.view.toolTip == nil && bar.toolTip == nil && bar.titleView.toolTip == nil
            let replacementID = String(repeating: "replacement title ", count: 10)
            let thumbnail = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 30,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            try bitmap.representation(using: .png, properties: [:])!.write(to: thumbnail)
            defer { try? FileManager.default.removeItem(at: thumbnail) }
            let replacement = VideoWallpaper(id: replacementID, path: "/fixture-new-video.mp4", thumbnailPath: thumbnail.path)
            card.configure(wallpaper: replacement,
                isSelected: false, isPlaying: false, isFavorite: false, multiSelectMode: false,
                wallpaperManager: manager, thumbnailProvider: provider)
            bar.playButton.performClick(nil)
            bar.favoriteButton.performClick(nil)
            checks["video.reconfigure-resolves-current-identity-not-stale-closure"] = played == ["interaction", replacementID]
                && favorites == ["interaction", replacementID] && bar.primaryState == .apply && !bar.isFavorite
            card.isHovering = true
            card.setThumbnailVisible(true)
            let readyDeadline = Date().addingTimeInterval(3)
            while card.thumbnailImageView.image == nil, Date() < readyDeadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            }
            bar.layoutSubtreeIfNeeded()
            let allowsMotion = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            checks["video.visible-ready-long-title-runs-marquee"] = card.thumbnailImageView.image != nil
                && !card.thumbnailRequestIsPending && (bar.titleView.activeMarqueeAnimation != nil) == allowsMotion
            let sourceValidations = manager.count(replacementID)
            card.setThumbnailVisible(false)
            checks["video.offscreen-stops-repeating-title-animation"] = bar.titleView.activeMarqueeAnimation == nil
            card.applyHoverVisibility(true, animated: false)
            card.applyPlayingState(isPlaying: true)
            card.updateControlBarContent(isFavorite: true)
            checks["video.offscreen-hover-and-state-updates-cannot-restart-marquee"] = bar.titleView.activeMarqueeAnimation == nil
            card.setThumbnailVisible(true)
            checks["video.ready-reshow-resumes-marquee-without-new-thumbnail-validation"] = card.thumbnailImageView.image != nil
                && manager.count(replacementID) == sourceValidations && card.imageTaskID == nil
                && (bar.titleView.activeMarqueeAnimation != nil) == allowsMotion
            card.setThumbnailVisible(false)
            card.configure(wallpaper: replacement, isSelected: false, isPlaying: true, isFavorite: true,
                multiSelectMode: false, wallpaperManager: manager, thumbnailProvider: provider)
            checks["video.offscreen-configure-updates-title-without-resuming-marquee"] = bar.titleView.text == replacementID
                && bar.titleView.activeMarqueeAnimation == nil && manager.count(replacementID) == sourceValidations
            card.applySelectionState(isSelected: true, multiSelectMode: true)
            bar.playButton.performClick(nil)
            bar.favoriteButton.performClick(nil)
            checks["video.multi-select-rejects-late-button-actions"] = played.count == 2 && favorites.count == 2
                && !hits(bar.playButton) && bar.superview == nil
            card.prepareForReuse()
            bar.playButton.performClick(nil)
            bar.favoriteButton.performClick(nil)
            checks["video.reuse-revokes-all-callbacks"] = played.count == 2 && favorites.count == 2
                && card.onPlayRequested == nil && card.onFavoriteRequested == nil && bar.superview == nil
        }
        card.prepareForReuse()
        checks["video.reuse-clears-badge-state-and-hit-target"] = card.controlBar === firstBadge
            && firstBadge?.isHidden == true && firstBadge?.primaryState == .apply
        let playingCard = AppKitWallpaperItem()
        playingCard.view.frame.size = NSSize(width: 230, height: 180)
        playingCard.viewDidLayout()
        playingCard.setThumbnailVisible(false)
        playingCard.configure(wallpaper: VideoWallpaper(id: "multi", path: "/fixture-unread-video.mp4", thumbnailPath: nil),
            isSelected: true, isPlaying: true, isFavorite: false, multiSelectMode: true,
            wallpaperManager: manager, thumbnailProvider: provider)
        checks["video.multi-select-does-not-build-first-playing-badge"] = playingCard.controlBar == nil
        playingCard.applySelectionState(isSelected: false, multiSelectMode: false)
        checks["video.leaving-multi-select-first-shows-playing-badge"] = playingCard.controlBar?.isHidden == false
            && playingCard.controlBar?.primaryState == .playing && playingCard.controlBar?.alphaValue == 1
        playingCard.applyPlayingState(isPlaying: false)
        checks["video.stop-without-hover-hides-playing-badge"] = playingCard.controlBar?.isHidden == true
            && playingCard.controlBar?.alphaValue == 0
        playingCard.view.frame = NSRect(x: 0, y: 0, width: 240, height: 242)
        playingCard.view.layoutSubtreeIfNeeded()
        playingCard.viewDidLayout()
        checks["video.square-cover-does-not-stretch-landscape-thumbnail"] = playingCard.imageContainer.bounds.width == playingCard.imageContainer.bounds.height
        playingCard.thumbnailImageView.image = NSImage(size: NSSize(width: 320, height: 180))
        playingCard.layoutThumbnail()
        let landscape = playingCard.thumbnailImageView.frame
        checks["video.landscape-thumbnail-fills-square-with-centered-crop"] = abs(landscape.width / landscape.height - 320.0 / 180) < 0.001
            && landscape.width > playingCard.imageContainer.bounds.width && landscape.height == playingCard.imageContainer.bounds.height
            && abs(landscape.midX - playingCard.imageContainer.bounds.midX) < 0.001
        playingCard.thumbnailImageView.image = NSImage(size: NSSize(width: 180, height: 320))
        playingCard.layoutThumbnail()
        let portrait = playingCard.thumbnailImageView.frame
        checks["video.portrait-thumbnail-fills-square-with-centered-crop"] = abs(portrait.width / portrait.height - 180.0 / 320) < 0.001
            && portrait.height > playingCard.imageContainer.bounds.height && portrait.width == playingCard.imageContainer.bounds.width
            && abs(portrait.midY - playingCard.imageContainer.bounds.midY) < 0.001
        var pendingPlays = 0
        playingCard.onPlayRequested = { _ in pendingPlays += 1 }
        let pendingImage = playingCard.thumbnailImageView.image
        playingCard.applySwitchingState(isSwitching: true)
        let pendingBar = playingCard.controlBar!
        checks["video.pending-pins-hourglass-without-hover-or-thumbnail-work"] = pendingBar.primaryState == .switching
            && !pendingBar.isHidden && pendingBar.alphaValue == 1 && pendingBar.superview != nil
            && !pendingBar.playButton.isEnabled && pendingBar.playButton.accessibilityLabel() == "正在切换壁纸"
            && playingCard.thumbnailImageView.image === pendingImage
        playingCard.onPlayRequested = { _ in pendingPlays += 1 }
        pendingBar.playButton.performClick(nil)
        playingCard.applyPlayingState(isPlaying: true)
        checks["video.pending-rejects-repeated-primary-and-wins-over-playing-echo"] = pendingPlays == 0
            && pendingBar.primaryState == .switching && !pendingBar.playButton.isEnabled
        playingCard.applySwitchingState(isSwitching: false)
        checks["video.pending-completion-restores-native-stop"] = pendingBar.primaryState == .playing && pendingBar.playButton.isEnabled
        playingCard.applySwitchingState(isSwitching: true)
        playingCard.prepareForReuse()
        checks["video.reuse-retires-pending-presentation"] = !playingCard.isSwitching && pendingBar.primaryState == .apply
            && pendingBar.isHidden && pendingBar.superview == nil && playingCard.onPlayRequested == nil
        provider.cancelAllPrefetch()
        checks.merge(videoNativeClickChecks()) { _, new in new }
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
