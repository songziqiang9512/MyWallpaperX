import AppKit
import Foundation
import ImageIO

// PRODUCTION_MODEL
// PRODUCTION_RESULT

/// The system wallpaper writer is a leaf. Both transaction inputs and the
/// original Commands primary factory are real values/methods. The Stop leaf
/// records dispatch and revokes the real reducers; it never writes a desktop.
@MainActor final class WallpaperManager {
    var playbackSwitch = PlaybackSwitchTransaction()
    var libraryPlaybackSequence = WallpaperPlaybackSequence()
    var stops = 0
    func stopCurrentPlayback() {
        stops += 1
        libraryPlaybackSequence.stop()
        _ = playbackSwitch.stop()
    }
}
@MainActor final class AppliedImageWorkspace {
    let manager: WallpaperManager
    let snapshot: WallpaperPlaybackSequence.Snapshot
    var relationships: UserCollectionsSnapshot
    var applications: [(WallpaperReference, WallpaperPlaybackSequence.Snapshot)] = []
    let presentation = AppliedImagePresentation()
    init(_ manager: WallpaperManager, snapshot: WallpaperPlaybackSequence.Snapshot, relationships: UserCollectionsSnapshot) {
        self.manager = manager; self.snapshot = snapshot; self.relationships = relationships
    }
    func isPlaying(_ reference: WallpaperReference) -> Bool {
        manager.libraryPlaybackSequence.committed?.reference == reference
            && manager.libraryPlaybackSequence.committed?.ticket == manager.playbackSwitch.committed?.ticket
    }
    func capturePlaybackSnapshot(for reference: WallpaperReference) throws -> WallpaperPlaybackSequence.Snapshot { snapshot }
    func play(_ reference: WallpaperReference, from source: WallpaperPlaybackSequence.Snapshot) { applications.append((reference, source)) }
}
@MainActor final class AppliedImagePresentation { var page: WallpaperLibraryPage = .images }
// Recovery is outside this available-image/Stop fixture. Its dedicated gate
// runs the real importer, availability owner and conditional SQLite command.
@MainActor final class WallpaperLibraryImportCoordinator {
    static func canRelocate<T>(_ item: WallpaperContentItem, relationships: T) -> Bool { false }
    func chooseReplacement(for reference: WallpaperReference) { preconditionFailure("Unexpected relocation") }
}
@MainActor enum WallpaperLibraryDownloadRecovery {
    static func makePrimaryAction<W,S,O>(for item: WallpaperContentItem, workspace: W, steam: S, pixabay: O) -> (() -> Void)? { nil }
}
@MainActor final class WallpaperLibraryCommands {
    let workspace: AppliedImageWorkspace
    let manager: WallpaperManager
    let imports = WallpaperLibraryImportCoordinator(), steam: Void = (), pixabay: Void = ()
    var canOrganize: Bool { false }
    init(_ workspace: AppliedImageWorkspace) { self.workspace = workspace; manager = workspace.manager }
    // PRODUCTION_PRIMARY_ACTIONS
}

/// The complete native grid owns geometry and keyboard/menu routing; only the
/// source card factory is a leaf in this geometry fixture.
final class SquareItem: NSCollectionViewItem {
    override func loadView() { view = WallpaperCardInteractionView() }
}
final class SquareGrid: NSView {
    let count = 31
    let controller = WallpaperLibraryGridController { collection, path, _, _ in
        collection.makeItem(withIdentifier: .init("fixture"), for: path)
    }
    var collectionView: NSCollectionView { controller.collection }
    var scrollView: NSScrollView { controller.scrollView }
    var gridLayout: NSCollectionViewFlowLayout { collectionView.collectionViewLayout as! NSCollectionViewFlowLayout }
    var content: [WallpaperContentItem] = []
    override init(frame: NSRect) {
        super.init(frame: frame)
        controller.loadViewIfNeeded()
        collectionView.register(SquareItem.self, forItemWithIdentifier: .init("fixture"))
        addSubview(controller.view)
    }
    required init?(coder: NSCoder) { nil }
    func prepare(width: CGFloat, zoom: Int) {
        setFrameSize(NSSize(width: width, height: 600))
        controller.view.frame = bounds
        controller.view.layoutSubtreeIfNeeded()
        content = (0..<count).map { index in
            let reference = WallpaperReference(provider: .staticImageLibrary, sourceID: String(index))
            return WallpaperContentItem(reference: reference, providerReference: reference,
                locator: .init(mediaKind: .image), title: String(index), kind: .image,
                publishedAvailability: .available, capabilities: [.play, .organize, .inspect],
                metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        }
        controller.update(page: .images, items: content, selection: .init(), preferredColumns: zoom,
            permitsDragging: false, scrollAnchor: nil)
        collectionView.layoutSubtreeIfNeeded()
        gridLayout.prepare()
    }
}

@main
struct SILSquareCardHarness {
    static func pump(_ interval: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(interval)) }
    static func main() throws {
        initializeNativeAppHarness()
        var checks: [String: Bool] = [:]
        let grid = SquareGrid(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let window = NSWindow(contentRect: grid.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = grid
        window.setFrameOrigin(NSPoint(x: 14000, y: 14000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.close() }
        for (scenario, input) in [(575.0, 5), (960.0, 3), (1300.0, 6), (800.0, 4)].enumerated() {
            grid.prepare(width: input.0, zoom: input.1)
            let metrics = WallpaperLibraryGridMetrics(clipWidth: grid.scrollView.contentView.bounds.width, preferredColumns: input.1)
            let columns = metrics.columns
            let expectedWidth = metrics.coverSide
            let frames = (0..<grid.count).map {
                grid.gridLayout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))!.frame
            }
            checks["native-square-size-and-column-policy-\(scenario)"] = columns == [5, 3, 6, 4][scenario]
                && frames.allSatisfy { $0.width == expectedWidth && $0.height == expectedWidth }
            checks["native-grid-preserves-row-major-item-order-\(scenario)"] = frames.enumerated().allSatisfy { index, frame in
                index % columns == 0 || frame.minY == frames[index-1].minY && frame.minX > frames[index-1].minX
            } && frames[columns].minY == frames[0].maxY + WallpaperLibraryGridMetrics.verticalSpacing
            checks["native-grid-keeps-insets-and-minimum-spacing-\(scenario)"] = frames[0].minX == metrics.horizontalInset && frames[0].minY == WallpaperLibraryGridMetrics.topInset
                && frames[columns-1].maxX <= grid.scrollView.contentView.bounds.width - metrics.horizontalInset
                && (1..<columns).allSatisfy { frames[$0].minX - frames[$0-1].maxX >= WallpaperLibraryGridMetrics.horizontalSpacing }
            let rect = NSRect(x: 0, y: frames[columns].minY + 1, width: grid.bounds.width, height: 20)
            let query = grid.gridLayout.layoutAttributesForElements(in: rect).filter { $0.representedElementCategory == .item }
            checks["native-grid-rectangle-query-keeps-visible-cards-\(scenario)"] = Set(query.compactMap(\.indexPath))
                == Set(frames.indices.filter { frames[$0].intersects(rect) }.map { IndexPath(item: $0, section: 0) })
        }

        let image = NSImage(size: NSSize(width: 400, height: 200))
        let card = SILGridItem()
        card.view.frame = NSRect(x: 0, y: 0, width: 240, height: 240)
        grid.addSubview(card.view)
        let wallpaper = try JSONDecoder().decode(SILWallpaper.self, from: Data("""
            {"id":"original","path":"/fixture/original.heic","title":"A very long original still image title",
             "fileSize":1048576,"pixelWidth":400,"pixelHeight":200,"tags":[],"lastUsed":0,"addedAt":0}
            """.utf8))
        var thumbnailLoads = 0
        card.configure(wallpaper: wallpaper, isSelected: false, isMultiSelectMode: false, thumbnailVisible: true) { _, finish in
            thumbnailLoads += 1
            finish(.image(image))
        }
        card.viewDidLayout()
        let landscape = card.thumbnailView.frame
        checks["square-thumbnail-centers-crop-without-stretch-or-mutating-original"] = card.imageContainer.bounds.size == NSSize(width: 240, height: 240)
            && landscape.size == NSSize(width: 480, height: 240) && landscape.minX == -120
            && image.size == NSSize(width: 400, height: 200)
        card.thumbnailView.image = NSImage(size: NSSize(width: 200, height: 400))
        card.updateThumbnailFrame()
        checks["portrait-thumbnail-centers-crop-without-stretch"] = card.thumbnailView.frame == NSRect(x: 0, y: -120, width: 240, height: 480)
        checks["static-card-does-not-build-an-idle-bar"] = card.controlBar == nil
        card.applyHoverVisibility(true, animated: false)
        card.controlBar!.layoutSubtreeIfNeeded()
        let bar = card.controlBar!
        checks["bar-shares-native-glass-and-hides-unconnected-favorite"] = bar.glass is NSGlassEffectView
            && !bar.detailButton.isHidden && !bar.detailButton.isEnabled && bar.playButton.accessibilityLabel() == "设为壁纸"
            && card.view.toolTip == nil && bar.toolTip == nil && bar.titleView.toolTip == nil
            && bar.titleView.accessibilityHelp()?.contains("400 × 200") == true
        var applied: [String] = []
        var inspections: [String] = []
        card.onApplyRequested = { applied.append($0) }
        bar.playButton.performClick(nil)
        checks["native-apply-button-emits-only-its-stable-target"] = applied == [wallpaper.id]
        let point = bar.playButton.convert(NSPoint(x: bar.playButton.bounds.midX, y: bar.playButton.bounds.midY), to: card.view.superview)
        checks["native-primary-button-is-reachable-through-real-hit-testing"] = card.view.hitTest(point) === bar.playButton
        card.view.appearance = NSAppearance(named: .aqua)
        card.refreshThemeAwareAppearance()
        let outlineColor = NSColor(cgColor: card.hoverOutline.layer!.borderColor!)!.usingColorSpace(.deviceRGB)!
        checks["light-appearance-keeps-the-same-white-hover-outline"] = outlineColor.redComponent > 0.99
            && outlineColor.greenComponent > 0.99 && outlineColor.blueComponent > 0.99
        card.onInspectRequested = { inspections.append($0) }
        bar.detailButton.performClick(nil)
        checks["detail-is-enabled-and-functional-only-after-binding"] = !bar.detailButton.isHidden && bar.detailButton.isEnabled && inspections == [wallpaper.id]
        let appliedImage = card.thumbnailView.image
        card.applyPlayingState(isPlaying: true)
        checks["organization-state-updates-native-icons-without-redecoding"] = thumbnailLoads == 1
            && card.thumbnailView.image === appliedImage && bar.detailButton.isEnabled && bar.primaryState == .playing
            && bar.playButton.accessibilityLabel() == "停止播放"
        card.applySwitchingState(isSwitching: true)
        card.onApplyRequested = { applied.append($0) }
        bar.playButton.performClick(nil)
        checks["pending-image-pins-hourglass-and-rejects-repeat-without-thumbnail-work"] = bar.primaryState == .switching
            && !bar.isHidden && bar.superview != nil && !bar.playButton.isEnabled && applied.count == 1
            && bar.playButton.accessibilityLabel() == "正在切换壁纸" && thumbnailLoads == 1
            && card.thumbnailView.image === appliedImage
        card.applyPlayingState(isPlaying: false)
        checks["pending-image-wins-over-playing-echo"] = bar.primaryState == .switching && !bar.playButton.isEnabled
        card.applySwitchingState(isSwitching: false)
        card.applySelectionState(isSelected: true, multiSelectMode: true)
        bar.playButton.performClick(nil)
        bar.detailButton.performClick(nil)
        checks["multi-selection-detaches-bar-and-rejects-late-actions"] = bar.superview == nil && applied.count == 1 && inspections.count == 1
        card.applySelectionState(isSelected: false, multiSelectMode: false)
        card.applyHoverVisibility(true, animated: false)
        card.applyHoverVisibility(false, animated: true)
        card.applyHoverVisibility(true, animated: true)
        pump(0.4)
        checks["late-fade-completion-cannot-detach-reentered-bar"] = bar.superview != nil && !bar.isHidden && bar.alphaValue == 1
        card.isHovering = true
        card.applyHoverVisibility(true, animated: false)
        let allowsMotion = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        checks["visible-long-image-title-runs-native-marquee"] = (bar.titleView.activeMarqueeAnimation != nil) == allowsMotion
        let readyImage = card.thumbnailView.image
        card.setThumbnailVisible(false)
        checks["offscreen-image-card-revokes-repeating-title-animation"] = bar.titleView.activeMarqueeAnimation == nil
        card.currentTitle = String(repeating: "updated image title ", count: 8)
        card.updateControlBarContent()
        card.applyHoverVisibility(true, animated: false)
        card.applySelectionState(isSelected: true, multiSelectMode: false)
        checks["offscreen-image-title-hover-selection-updates-cannot-resume-marquee"] = bar.titleView.text == card.currentTitle
            && bar.titleView.activeMarqueeAnimation == nil
        card.setThumbnailVisible(true)
        checks["ready-image-reshow-restores-marquee-without-decoding-again"] = card.thumbnailView.image === readyImage
            && thumbnailLoads == 1 && (bar.titleView.activeMarqueeAnimation != nil) == allowsMotion
        card.setThumbnailVisible(false)
        card.configure(wallpaper: wallpaper, isSelected: false, isMultiSelectMode: false, thumbnailVisible: false) { _, finish in
            thumbnailLoads += 1
            finish(.image(image))
        }
        checks["offscreen-image-configure-defers-decode-and-repeating-animation"] = thumbnailLoads == 1
            && bar.titleView.text == wallpaper.title && bar.titleView.activeMarqueeAnimation == nil
        card.setThumbnailVisible(true)
        FileHandle.standardError.write(Data("sil-reentry loads=\(thumbnailLoads) imageMatches=\(card.thumbnailView.image === image) hover=\(card.isHovering) attached=\(card.view.window != nil) marquee=\(bar.titleView.activeMarqueeAnimation != nil) allowsMotion=\(allowsMotion)\n".utf8))
        checks["new-image-demand-respects-the-hover-recomputed-by-real-native-layout"] = thumbnailLoads == 2
            && card.thumbnailView.image === image
            && (bar.titleView.activeMarqueeAnimation != nil) == (allowsMotion && card.isHovering)
        let hoverPoint = card.imageContainer.convert(NSPoint(x: 120, y: 120), to: nil)
        let moved = NSEvent.mouseEvent(with: .mouseMoved, location: hoverPoint, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 9, clickCount: 0, pressure: 0)!
        card.mouseMoved(with: moved)
        checks["new-image-demand-restores-existing-loader-and-title-animation"] = thumbnailLoads == 2
            && card.thumbnailView.image === image && card.isHovering && (bar.titleView.activeMarqueeAnimation != nil) == allowsMotion
        card.applySwitchingState(isSwitching: true)
        card.prepareForReuse()
        bar.playButton.performClick(nil)
        bar.detailButton.performClick(nil)
        checks["reuse-cancels-card-actions-and-marquee-visibility"] = card.onApplyRequested == nil
            && card.onInspectRequested == nil && bar.superview == nil && applied.count == 1 && inspections.count == 1
            && !card.isSwitching && bar.primaryState == .apply
        var boundApplied: [String] = [], boundInspections: [String] = []
        func bind(_ id: String) {
            var value = wallpaper; value.id = id
            card.configure(wallpaper: value, isSelected: false, isMultiSelectMode: false, thumbnailVisible: false) { _, _ in
                preconditionFailure("bar identity fixture must not request a hidden thumbnail")
            }
            card.onApplyRequested = { boundApplied.append(id + ":" + $0) }; card.onInspectRequested = { boundInspections.append(id + ":" + $0) }
        }
        bind("A")
        let heldAApply = bar.onPlay, heldAInspect = bar.onInspect
        bind("B"); heldAApply?(); heldAInspect?()
        checks["retained-image-bar-keeps-captured-provider-target-instead-of-new-B"] = boundApplied == ["A:A"] && boundInspections == ["A:A"]
        bar.playButton.performClick(nil); bar.detailButton.performClick(nil)
        checks["replacement-image-native-bar-targets-both-current-actions-once"] = boundApplied == ["A:A", "B:B"] && boundInspections == boundApplied
        var echoApplied: [String] = [], echoInspections: [String] = []
        card.onApplyRequested = { echoApplied.append($0) }; card.onInspectRequested = { echoInspections.append($0) }
        let heldBApply = bar.onPlay, heldBInspect = bar.onInspect
        bar.playButton.performClick(nil); bar.detailButton.performClick(nil)
        checks["same-image-state-echo-rebinds-changed-native-action-consumers"] = echoApplied == ["B"] && echoInspections == ["B"] && boundApplied.count == 2
        card.prepareForReuse(); heldBApply?(); heldBInspect?()
        checks["image-reuse-rejects-retained-both-actions"] = echoApplied == ["B"] && echoInspections == ["B"]

        do {
            let reference = WallpaperReference(provider: .staticImageLibrary, sourceID: wallpaper.id)
            let playlist = WallpaperPlaylist(name: "Image membership", sidebarRank: 0)
            let source = try WallpaperPlaybackSequence.Snapshot(source: .page(.playlist(playlist.id)), revision: 2,
                entries: [.init(reference: reference, runtime: .systemStill, isPlayable: true)])
            let relationships = UserCollectionsSnapshot(revision: 3, resetEpoch: UUID(), migrationManifestID: nil,
                playlists: [playlist], members: [.init(playlistID: playlist.id, reference: reference, position: 0, addedAt: Date())],
                favorites: [.init(reference: reference, favoritedAt: nil)], recent: [], aliases: [], locators: [])
            let manager = WallpaperManager()
            let proposal = manager.libraryPlaybackSequence.proposeSelection(reference, from: source)!
            let (ticket, _) = manager.playbackSwitch.begin(.systemStill)
            precondition(manager.libraryPlaybackSequence.stage(proposal, ticket: ticket))
            let execution = UUID()
            _ = manager.playbackSwitch.prepared(ticket, executionID: execution)
            _ = manager.playbackSwitch.visible(ticket, executionID: execution)
            precondition(manager.libraryPlaybackSequence.commit(ticket) != nil)
            let workspace = AppliedImageWorkspace(manager, snapshot: source, relationships: relationships)
            let commands = WallpaperLibraryCommands(workspace)
            let content = WallpaperContentItem(reference: reference, providerReference: reference,
                locator: .init(mediaKind: .image), title: wallpaper.title, kind: .image,
                publishedAvailability: .available, capabilities: [.play, .organize], metadata: .init(),
                acquisition: .idle, update: .idle, aliases: [])
            let appliedCard = SILGridItem()
            appliedCard.view.frame = NSRect(x: 0, y: 0, width: 240, height: 240)
            grid.addSubview(appliedCard.view)
            let fixedStop = commands.makePrimaryAction(for: content)!
            appliedCard.onApplyRequested = { id in
                precondition(id == reference.sourceID)
                fixedStop()
            }
            appliedCard.onInspectRequested = { _ in }
            appliedCard.configure(wallpaper: wallpaper, isSelected: false, isMultiSelectMode: false, thumbnailVisible: true,
                isPlaying: true) { _, finish in finish(.image(image)) }
            appliedCard.viewDidLayout()
            let appliedBar = appliedCard.controlBar!
            let metrics = WallpaperCardBarMetrics(cardWidth: appliedCard.imageContainer.bounds.width)
            let stopSymbol = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)!
                .withSymbolConfiguration(.init(pointSize: max(11, metrics.iconButtonSize * 0.56), weight: .medium))!
            checks["applied-image-keeps-native-bar-with-stop-and-system-accent"] = appliedBar.primaryState == .playing
                && !appliedBar.isHidden && appliedBar.alphaValue == 1 && appliedBar.superview != nil
                && appliedBar.playButton.contentTintColor == .controlAccentColor
                && stopSymbol.tiffRepresentation != nil && appliedBar.playButton.image?.tiffRepresentation == stopSymbol.tiffRepresentation
            checks["applied-image-native-accessibility-describes-stop"] = appliedBar.playButton.accessibilityLabel() == "停止播放"
                && appliedBar.playButton.toolTip == "停止播放" && appliedBar.playButton.isEnabled
            appliedBar.playButton.performClick(nil)
            appliedBar.playButton.performClick(nil)
            checks["applied-image-stop-uses-original-primary-factory-and-revokes-held-stop"] = workspace.applications.isEmpty
                && manager.stops == 1 && manager.playbackSwitch.committed == nil && manager.libraryPlaybackSequence.committed == nil
            checks["image-stop-preserves-favorite-and-playlist-membership"] = workspace.relationships == relationships
                && appliedBar.detailButton.isEnabled && appliedBar.primaryState == .playing
            appliedCard.applyPlayingState(isPlaying: false)
            checks["stopped-image-restores-apply-label-without-losing-favorite"] = appliedBar.primaryState == .apply
                && appliedBar.playButton.accessibilityLabel() == "设为壁纸" && appliedBar.detailButton.isEnabled
            let fixedApply = commands.makePrimaryAction(for: content)!
            appliedCard.onApplyRequested = { _ in fixedApply() }
            appliedBar.playButton.performClick(nil)
            checks["stopped-image-can-apply-again-from-the-original-source-without-another-stop"] = manager.stops == 1
                && workspace.applications.count == 1 && workspace.applications[0].0 == reference && workspace.applications[0].1 == source
            appliedCard.prepareForReuse()
        }

        let chosen = grid.content[0], other = grid.content[1]
        var selection = WallpaperLibrarySelectionState()
        selection.references = [chosen.reference]; selection.focusedReference = chosen.reference
        grid.controller.update(page: .images, items: grid.content, selection: selection,
            preferredColumns: 5, permitsDragging: false, scrollAnchor: nil)
        var requested: [WallpaperReference] = [], inspected: [WallpaperReference] = []
        grid.controller.onPrimaryAction = { requested.append($0.reference) }
        grid.controller.onInspect = { inspected.append($0.reference) }
        let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        let handled = grid.controller.collection.onKey?(enter)
        checks["native-keyboard-primary-emits-fixed-target-without-changing-selection-or-opening-detail"] = handled == true
            && requested == [chosen.reference] && inspected.isEmpty && grid.controller.selection == selection
        selection.isSelecting = true; selection.references.insert(other.reference)
        grid.controller.update(page: .images, items: grid.content, selection: selection,
            preferredColumns: 5, permitsDragging: false, scrollAnchor: nil)
        var menuTargets: [WallpaperReference] = []
        grid.controller.menuProvider = { values in menuTargets = values.map(\.reference); return NSMenu() }
        _ = grid.controller.collection.contextMenuProvider?(IndexPath(item: 0, section: 0))
        checks["native-context-menu-preserves-all-current-multiselect-targets"] = menuTargets == [chosen.reference, other.reference]
            && grid.controller.selection == selection && requested == [chosen.reference]
        print(String(decoding: try JSONEncoder().encode(checks), as: UTF8.self))
    }
}
