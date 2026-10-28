import AppKit
import Combine

@MainActor final class PixivSession {
    struct State { let scopeID: String }
    @Published var state = State(scopeID: "fixture-pixiv")
    static let shared = PixivSession()
    var scopeID: String { state.scopeID }
}
extension OnlineImageLibrary {
    var pixivSession: PixivSession? { PixivSession.shared }
    var pixivScope: String { PixivSession.shared.state.scopeID }
}

nonisolated final class ThumbnailCacheRequestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return isCancelled }
    func cancel() { lock.lock(); isCancelled = true; lock.unlock() }
}
enum SILThumbnailLoadResult { case image(NSImage), unavailable }
@MainActor final class SILThumbnailProvider {
    static var images: [String: NSImage] = [:]
    func load(path: String, cancellation: ThumbnailCacheRequestCancellation, completion: (SILThumbnailLoadResult) -> Void) {
        completion(Self.images[path].map(SILThumbnailLoadResult.image) ?? .unavailable)
    }
}
enum WallpaperLibrarySheetPresentation {
    @MainActor static func permitsInput(in window: NSWindow?) -> Bool { window?.attachedSheet == nil }
}
@MainActor enum InspectorBrowserProbe {
    static var urls: [URL] = []
    @discardableResult static func open(_ url: URL) -> Bool {
        urls.append(url); return true
    }
}

/// Only transport/cache leaves vary. The original Inspector and its native
/// footer, preview, scroll, source/page identity and cancellation code execute.
@MainActor final class OnlineImageThumbnailCache {
    static let shared = OnlineImageThumbnailCache()
    enum Priority { case visible }
    struct Request { let request: OnlineImageFixtureThumbnailRequest; let pixels: Int }
    var ready: [String: NSImage] = [:]
    var requests: [Request] = []
    var inspected: [Request] = []
    var holds = false
    var pending: [Int: CheckedContinuation<NSImage?, Never>] = [:]
    func key(_ request: OnlineImageFixtureThumbnailRequest, _ pixels: Int) -> String {
        "\(request.scopeID):\(request.url.absoluteString)@\(pixels)"
    }
    func readyImage(for request: OnlineImageFixtureThumbnailRequest, maxPixelSize: Int) -> NSImage? {
        inspected.append(.init(request: request, pixels: maxPixelSize))
        return ready[key(request, maxPixelSize)]
    }
    func image(for request: OnlineImageFixtureThumbnailRequest, maxPixelSize: Int, priority: Priority) async -> NSImage? {
        let ticket = requests.count
        requests.append(.init(request: request, pixels: maxPixelSize))
        if holds { return await withCheckedContinuation { pending[ticket] = $0 } }
        return ready[key(request, maxPixelSize)]
    }
    func complete(_ ticket: Int, image: NSImage?) { pending.removeValue(forKey: ticket)?.resume(returning: image) }
}

@main struct OnlineImageInspectorHarness {
    @MainActor static func pump(_ until: () -> Bool) async {
        for _ in 0..<120 { if until() { return }; try? await Task.sleep(for: .milliseconds(8)) }
    }
    @MainActor static func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }
    @MainActor static func title(_ button: InspectorFooterButton) -> String { button.accessibilityLabel() ?? "" }
    @MainActor static func makeImage(_ color: NSColor) -> NSImage {
        NSImage(size: .init(width: 10, height: 10), flipped: false) { rect in color.setFill(); rect.fill(); return true }
    }
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var checks: [String: Bool] = [:]
        let cache = OnlineImageThumbnailCache.shared, library = OnlineImageLibrary()
        let green = makeImage(.green), blue = makeImage(.blue), red = makeImage(.red)
        let thumb = URL(string: "https://example.invalid/grid-small.jpg")!
        let art = OnlineImageArtwork(source: .wallhaven, artworkID: "first", title: "Artwork",
            sourceURL: URL(string: "https://example.invalid/work")!, thumbnailURL: thumb,
            previewURL: URL(string: "https://example.invalid/large.jpg")!, author: String(repeating: "Long author ", count: 12),
            authorID: "author-1", kind: .image)
        var detail = art; detail.thumbnailURL = URL(string: "https://example.invalid/different-detail-thumbnail.jpg")
        library.detailResolver = { _ in detail }
        let asset = OnlineImageAsset(id: art.firstAssetID, title: art.title, sourceURL: art.sourceURL,
            originalURL: URL(string: "https://example.invalid/original.png")!, previewURL: art.previewURL,
            author: art.author, authorID: art.authorID)
        library.assetResolver = { _ in [asset] }
        let request = library.thumbnailRequest(url: thumb, source: .wallhaven)
        cache.ready[cache.key(request, 512)] = green
        var applied: [WallpaperReference] = [], authors: [OnlineImageAuthor] = []
        var switching = false, playing = false, canPerformPrimary = true
        let playback = try playingImagePrimary(asset.id.reference)
        let actions: (WallpaperReference) -> WallpaperInspectorActions? = { reference in
            guard library.content(for: reference)?.publishedAvailability.isAvailable == true else { return nil }
            return .init(state: .init(isPlaying: playing, isSwitching: switching, isFavorite: false,
                canPerformPrimary: !switching && canPerformPrimary, canFavorite: true, canOrganize: true, playlistNames: []),
                onPrimary: playing ? playback.commands.makePrimaryAction(for: playback.content)! : { applied.append(reference) },
                onToggleFavorite: { preconditionFailure("retired favorite button") },
                onChoosePlaylist: { _ in preconditionFailure("retired playlist button") })
        }
        let view = OnlineImageInspectorView(artwork: art, library: library, makeLibraryActions: actions,
            onAuthor: { authors.append($0) }, thumbnailPixelSize: 512)
        let window = NSWindow(contentRect: .init(x: 14000, y: 14000, width: 356, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSView(frame: .init(x: 0, y: 0, width: 356, height: 700)); window.contentView = host
        host.addSubview(view)
        let inspectorWidth = view.widthAnchor.constraint(equalToConstant: 356)
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: host.leadingAnchor), inspectorWidth,
            view.topAnchor.constraint(equalTo: host.topAnchor), view.bottomAnchor.constraint(equalTo: host.bottomAnchor)])
        window.orderFrontRegardless()
        await pump { !view.isResolving }
        host.layoutSubtreeIfNeeded()
        checks["grid-cache-image-is-reused-with-no-remote-image-request-or-detail-source-upgrade"] = view.preview.image === green
            && cache.requests.isEmpty && cache.inspected.allSatisfy { $0.request.url == thumb }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            view.appearance = NSAppearance(named: appearance)
            host.layoutSubtreeIfNeeded()
            let dividers = descendants(view).compactMap { $0 as? NSBox }
            checks["section-dividers-fill-their-real-stack-in-\(appearance.rawValue)"] = !dividers.isEmpty && dividers.allSatisfy {
                $0.bounds.width > 100 && $0.bounds.height == 1 && abs($0.bounds.width - ($0.superview?.bounds.width ?? 0)) < 0.5
            }
            var alpha: CGFloat = 0
            view.effectiveAppearance.performAsCurrentDrawingAppearance {
                alpha = (dividers.first?.fillColor.usingColorSpace(.deviceRGB)?.alphaComponent) ?? 0
            }
            checks["section-dividers-use-visible-native-appearance-color-in-\(appearance.rawValue)"] = alpha > 0.1
                && dividers.allSatisfy { $0.fillColor == NSColor.separatorColor.withAlphaComponent(0.25) }
            checks["browser-keeps-translucent-secondary-background-in-\(appearance.rawValue)"] = view.sourceButton.layer?.backgroundColor.map { $0.alpha > 0 && $0.alpha < 1 } == true
        }
        let footer = view.primaryButton.superview as! NSStackView
        checks["footer-has-exactly-primary-and-browser-without-retired-actions"] = footer.arrangedSubviews == [view.primaryButton, view.sourceButton]
            && descendants(view).compactMap { $0 as? NSControl }.allSatisfy { !["toggleFavorite", "choosePlaylist", "downloadCurrent", "openFile"].contains($0.action.map(NSStringFromSelector) ?? "") }
        checks["browser-has-shared-translucent-background-and-current-title"] = view.sourceButton.layer?.backgroundColor.map { $0.alpha > 0 && $0.alpha < 1 } == true
            && descendants(view.sourceButton).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "打开原网页" }
        _ = view.sourceButton.accessibilityPerformPress()
        checks["browser-opens-current-artwork-without-a-download"] = InspectorBrowserProbe.urls == [art.sourceURL] && library.downloads.isEmpty
        for width: CGFloat in [300, 356, 450] {
            inspectorWidth.constant = width
            window.setContentSize(.init(width: width, height: 700)); host.layoutSubtreeIfNeeded()
            let a = view.primaryButton.frame, b = view.sourceButton.frame
            let preview = view.preview.convert(view.preview.bounds, to: view)
            let row = footer.convert(footer.bounds, to: view)
            checks["equal-text-buttons-and-footer-thumbnail-edge-alignment-\(Int(width))"] = abs(view.bounds.width - width) < 0.5 && abs(a.width - b.width) < 0.5
                && abs(preview.minX - row.minX) < 0.5 && abs(preview.maxX - row.maxX) < 0.5
                && abs(a.width + b.width + 8 - row.width) < 0.5
        }
        let longAuthor = view.artwork.author
        for author in ["A", "Muscot", "joy0v0", "", "   "] {
            view.assets[0].author = author; view.refreshContent()
            host.layoutSubtreeIfNeeded()
            let a = view.primaryButton.frame, b = view.sourceButton.frame
            checks["short-or-missing-author-still-fills-entire-footer-\(author)"] = a.minX == footer.bounds.minX
                && abs(b.maxX - footer.bounds.maxX) < 0.5 && abs(a.width - b.width) < 0.5
                && a.width >= InspectorFooterMetrics.textMinWidth
            let authorFrame = view.authorButton.convert(view.authorButton.bounds, to: view)
            let titleFrame = view.titleLabel.superview!.convert(view.titleLabel.alignmentRect(forFrame: view.titleLabel.frame), to: view)
            checks["author-pill-keeps-natural-width-left-below-title-\(author)"] = abs(authorFrame.minX - titleFrame.minX) < 0.5
                && authorFrame.maxY < titleFrame.minY && authorFrame.height == 36
                && view.authorButton.layer?.cornerRadius == 18 && authorFrame.width < view.preview.bounds.width
                && title(view.authorButton) == (author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "作者信息暂缺" : author)
            if checks["author-pill-keeps-natural-width-left-below-title-\(author)"] != true {
                FileHandle.standardError.write(Data("author frame=\(authorFrame), title=\(titleFrame), preview=\(view.preview.bounds), radius=\(view.authorButton.layer?.cornerRadius ?? -1), label=\(title(view.authorButton))\n".utf8))
            }
            let label = descendants(view.authorButton).compactMap { $0 as? NSTextField }.first!
            checks["ordinary-author-name-fits-without-unnecessary-truncation-\(author)"] = label.bounds.width >= label.intrinsicContentSize.width
            if checks["ordinary-author-name-fits-without-unnecessary-truncation-\(author)"] != true {
                FileHandle.standardError.write(Data("author=\(author), button=\(view.authorButton.frame), label=\(label.frame), intrinsic=\(label.intrinsicContentSize), cell=\(label.cell!.cellSize), text=\(label.attributedStringValue.size())\n".utf8))
            }
        }
        view.assets[0].author = longAuthor; view.refreshContent(); host.layoutSubtreeIfNeeded()
        let authorLabels = descendants(view.authorButton).compactMap { $0 as? NSTextField }
        checks["long-author-keeps-full-accessible-name-and-native-tail-truncation"] = title(view.authorButton) == art.author
            && authorLabels.contains { $0.lineBreakMode == .byTruncatingTail && $0.stringValue == art.author }
        checks["page-count-remains-left-aligned"] = view.pageLabel.superview is NSStackView
            && (view.pageLabel.superview as? NSStackView)?.arrangedSubviews.first === view.pageLabel
        _ = view.authorButton.accessibilityPerformPress()
        checks["title-author-opens-original-source-author-context"] = authors.first?.id == "author-1"
        checks["remote-primary-is-download-only-and-enabled-after-details"] = title(view.primaryButton) == "下载图片" && view.primaryButton.isEnabled
        _ = view.primaryButton.accessibilityPerformPress()
        checks["one-primary-download-never-implicitly-applies"] = library.downloads == [asset.id] && library.downloadApplyFlags == [false] && applied.isEmpty
        library.progress[asset.id] = 0.4
        await pump { title(view.primaryButton) == "取消下载" }
        _ = view.primaryButton.accessibilityPerformPress()
        checks["download-progress-and-cancel-use-same-original-task"] = title(view.primaryButton) == "取消下载" && library.cancellations == [asset.id]
        library.progress[asset.id] = nil
        await pump { title(view.primaryButton) == "下载图片" }
        checks["cancel-or-failure-restores-download-without-reopening"] = title(view.primaryButton) == "下载图片" && view.primaryButton.isEnabled
        let record = OnlineImageLocalRecord(assetID: asset.id, title: "Local", sourceURL: art.sourceURL, author: art.author,
            authorID: art.authorID, tags: [], relativePath: "owned.png", pixelWidth: 10, pixelHeight: 10,
            fileSizeBytes: 10, firstDownloadedAt: Date(), revision: UUID())
        SILThumbnailProvider.images[library.localURL(for: record)!.path] = blue
        library.snapshot = .init(records: [record])
        await pump { title(view.primaryButton) == "设为壁纸" }
        _ = view.primaryButton.accessibilityPerformPress()
        checks["published-image-switches-same-button-to-local-wallpaper-action"] = applied == [asset.id.reference] && view.preview.image === blue
            && cache.requests.isEmpty
        let sheet = NSWindow(contentRect: .init(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.beginSheet(sheet, completionHandler: nil)
        view.openSource()
        view.openAuthor()
        checks["modal-cannot-open-underlying-webpage"] = InspectorBrowserProbe.urls.count == 1
        checks["modal-cannot-open-underlying-author"] = authors.count == 1
        window.endSheet(sheet)
        library.snapshot = .init(records: [])
        await pump { title(view.primaryButton) == "下载图片" }
        _ = view.sourceButton.accessibilityPerformPress()
        checks["removing-local-receipt-keeps-current-source-webpage-usable"] = title(view.primaryButton) == "下载图片"
            && InspectorBrowserProbe.urls == [art.sourceURL, art.sourceURL]
        library.snapshot = .init(records: [record])
        await pump { title(view.primaryButton) == "设为壁纸" }
        switching = true
        view.updateLibraryActions(actions(asset.id.reference)!)
        checks["pending-wallpaper-action-immediately-shows-disabled-hourglass-state"] = title(view.primaryButton) == "正在切换壁纸" && !view.primaryButton.isEnabled
        switching = false; playing = true
        view.updateLibraryActions(actions(asset.id.reference)!)
        let healthyPrimary = view.primaryButton
        _ = healthyPrimary.accessibilityPerformPress()
        _ = healthyPrimary.accessibilityPerformPress()
        let stopIcon = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))!
        checks["playing-online-image-renders-and-executes-stop-without-reapplying"] = title(healthyPrimary) == "停止播放"
            && healthyPrimary.toolTip == "停止播放" && healthyPrimary.isEnabled
            && descendants(healthyPrimary).compactMap { ($0 as? NSImageView)?.image?.tiffRepresentation }.contains(stopIcon.tiffRepresentation!)
            && playback.commands.manager.stops == 1 && playback.commands.manager.playbackSwitch.committed == nil
            && playback.commands.manager.libraryPlaybackSequence.committed == nil
            && playback.commands.workspace.applications.isEmpty && applied == [asset.id.reference]
        canPerformPrimary = false
        view.updateLibraryActions(actions(asset.id.reference)!)
        checks["unavailable-online-image-primary-refuses-stop-and-apply"] = !healthyPrimary.isEnabled
            && !healthyPrimary.accessibilityPerformPress() && playback.commands.manager.stops == 1 && applied.count == 1
        canPerformPrimary = true; playing = false
        view.updateLibraryActions(actions(asset.id.reference)!)
        _ = healthyPrimary.accessibilityPerformPress()
        checks["same-online-image-view-restores-apply-and-replaces-stop-action"] = view.primaryButton === healthyPrimary
            && title(healthyPrimary) == "设为壁纸" && healthyPrimary.toolTip == "设为壁纸"
            && applied == [asset.id.reference, asset.id.reference] && playback.commands.manager.stops == 1
        view.removeFromSuperview()
        window.close()

        // Cold thumbnail decode takes exactly the current grid tier. Page
        // replacement and retirement reject a late result from the old lease.
        let pixiv = OnlineImageArtwork(source: .pixiv, artworkID: "pages", title: "Pages", sourceURL: art.sourceURL,
            thumbnailURL: thumb, author: "Pixiv artist", authorID: "21", kind: .image)
        let pages = (0..<2).map { index in OnlineImageAsset(id: .init(source: .pixiv, artworkID: "pages", pageIndex: index),
            title: "Page \(index)", sourceURL: art.sourceURL, originalURL: URL(string: "https://example.invalid/original-\(index).jpg")!,
            previewURL: URL(string: "https://example.invalid/page-\(index)-regular.jpg")) }
        let secondLibrary = OnlineImageLibrary()
        secondLibrary.detailResolver = { _ in pixiv }; secondLibrary.assetResolver = { _ in pages }
        cache.holds = true
        let pending = OnlineImageInspectorView(artwork: pixiv, library: secondLibrary, makeLibraryActions: { _ in nil }, thumbnailPixelSize: 1200)
        await pump { pending.assets.count == 2 && !cache.pending.isEmpty }
        let firstTicket = cache.requests.count - 1
        checks["cold-inspector-uses-grid-thumbnail-url-scope-and-pixel-tier"] = cache.requests[firstTicket].request.url == thumb
            && cache.requests[firstTicket].request.scopeID == "fixture-pixiv" && cache.requests[firstTicket].pixels == 1200
        _ = pending.nextButton.accessibilityPerformPress()
        await pump { cache.requests.count == firstTicket + 2 }
        let secondTicket = cache.requests.count - 1
        cache.complete(firstTicket, image: red)
        await pump { cache.pending[firstTicket] == nil }
        checks["late-first-page-image-cannot-replace-new-page"] = pending.preview.image == nil && pending.pageIndex == 1
        cache.complete(secondTicket, image: blue)
        await pump { pending.preview.image === blue }
        checks["other-page-keeps-own-regular-preview-not-original-hd"] = cache.requests[secondTicket].request.url == pages[1].previewURL && pending.preview.image === blue
        let beforeScope = cache.requests.count
        PixivSession.shared.state = .init(scopeID: "fixture-new-account")
        await pump { pending.observedScope == "fixture-new-account" }
        checks["account-change-retires-old-grid-url-without-reissuing-it"] = cache.requests.count == beforeScope && pending.preview.image == nil
        let report = try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys])
        print(String(decoding: report, as: UTF8.self))
    }
}
