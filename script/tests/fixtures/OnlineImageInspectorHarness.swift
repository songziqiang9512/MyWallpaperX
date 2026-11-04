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
    func load(path: String, request: ThumbnailRequest?, cancellation: ThumbnailCacheRequestCancellation, completion: (SILThumbnailLoadResult) -> Void) {
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
    struct Request { let request: OnlineImageFixtureThumbnailRequest; let target: ThumbnailRequest }
    let ready = DecodedThumbnailMemoryCache(countLimit: 16, totalCostLimit: 64 * 1024 * 1024)
    var requests: [Request] = []
    var inspected: [Request] = []
    var holds = false
    var pending: [Int: CheckedContinuation<NSImage?, Never>] = [:]
    func key(_ request: OnlineImageFixtureThumbnailRequest) -> NSString {
        "\(request.scopeID):\(request.url.absoluteString)" as NSString
    }
    func install(_ image: NSImage, for request: OnlineImageFixtureThumbnailRequest) {
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let pixels = CGSize(width: cg.width, height: cg.height)
        ready.setObject(image, forKey: key(request), cost: cg.bytesPerRow * cg.height, pixels: pixels, nativeSize: pixels)
    }
    func readyImage(for remote: OnlineImageFixtureThumbnailRequest, request: ThumbnailRequest) -> NSImage? {
        inspected.append(.init(request: remote, target: request))
        return ready.object(forKey: key(remote), request: request)
    }
    func image(for remote: OnlineImageFixtureThumbnailRequest, request: ThumbnailRequest, priority: Priority) async -> NSImage? {
        let ticket = requests.count
        requests.append(.init(request: remote, target: request))
        if holds { return await withCheckedContinuation { pending[ticket] = $0 } }
        return ready.object(forKey: key(remote), request: request)
    }
    func complete(_ ticket: Int, image: NSImage?) { pending.removeValue(forKey: ticket)?.resume(returning: image) }
}

@main struct OnlineImageInspectorHarness {
    @MainActor static var assetVisits = 0
    @MainActor static var membershipVisits = 0
    @MainActor static var controlsCalls = 0
    @MainActor static var progressObservations: [(marker: Double?, calls: Int, visits: Int)] = []
    @MainActor static let progressMarker = OnlineImageAssetID(source: .wallhaven, artworkID: "unrelated-progress-marker")
    @MainActor static func pump(_ until: () -> Bool) async {
        for _ in 0..<120 { if until() { return }; try? await Task.sleep(for: .milliseconds(8)) }
    }
    @MainActor static func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }
    @MainActor static func title(_ button: InspectorFooterButton) -> String { button.accessibilityLabel() ?? "" }
    @MainActor static func makeImage(_ color: NSColor) -> NSImage {
        let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
            bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color.cgColor); context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        return NSImage(cgImage: context.makeImage()!, size: .init(width: 1024, height: 1024))
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
        cache.install(green, for: request)
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
            onAuthor: { authors.append($0) })
        checks["zero-unmounted-preview-does-not-request-images"] = cache.requests.isEmpty && cache.inspected.isEmpty
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
        let firstTarget = ThumbnailRequest(size: view.preview.bounds.size, scale: window.backingScaleFactor, mode: .fill)
        checks["first-mount-requests-real-preview-backing-fill"] = firstTarget != nil && cache.inspected.last?.target == firstTarget
        let firstPixel = view.preview.image, beforeResize = cache.requests.count
        inspectorWidth.constant = 500; host.layoutSubtreeIfNeeded()
        let resizedTarget = ThumbnailRequest(size: view.preview.bounds.size, scale: window.backingScaleFactor, mode: .fill)
        checks["compatible-two-target-native-resize-reuses-shared-ready-image"] = resizedTarget != firstTarget
            && cache.inspected.last?.target == resizedTarget && view.preview.image === firstPixel && cache.requests.count == beforeResize
        inspectorWidth.constant = 356; host.layoutSubtreeIfNeeded()
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
        let pending = OnlineImageInspectorView(artwork: pixiv, library: secondLibrary, makeLibraryActions: { _ in nil })
        host.addSubview(pending)
        NSLayoutConstraint.activate([pending.leadingAnchor.constraint(equalTo: host.leadingAnchor), pending.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            pending.topAnchor.constraint(equalTo: host.topAnchor), pending.bottomAnchor.constraint(equalTo: host.bottomAnchor)])
        host.layoutSubtreeIfNeeded()
        await pump { pending.assets.count == 2 && !cache.pending.isEmpty }
        let firstTicket = cache.requests.count - 1
        checks["cold-inspector-uses-grid-thumbnail-url-scope-and-pixel-tier"] = cache.requests[firstTicket].request.url == thumb
            && cache.requests[firstTicket].request.scopeID == "fixture-pixiv" && cache.requests[firstTicket].target == ThumbnailRequest(size: pending.preview.bounds.size, scale: window.backingScaleFactor, mode: .fill)
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
        pending.retire(); pending.removeFromSuperview()

        let lookupLibrary = OnlineImageLibrary()
        let lookupArtwork = OnlineImageArtwork(source: .pixiv, artworkID: "lookup-pages", title: "Lookup pages",
            sourceURL: art.sourceURL, author: "Artwork Author", authorID: "artwork-author", kind: .image)
        let lookupPages = (0..<64).map { page in
            OnlineImageAsset(id: .init(source: .pixiv, artworkID: "lookup-pages", pageIndex: page),
                title: "Page \(page)", sourceURL: art.sourceURL, originalURL: asset.originalURL,
                author: "Asset \(page)", authorID: "asset-\(page)")
        }
        lookupLibrary.detailResolver = { _ in lookupArtwork }; lookupLibrary.assetResolver = { _ in lookupPages }
        var lookupSwitching = false
        let lookupActions: (WallpaperReference) -> WallpaperInspectorActions? = { reference in
            guard lookupLibrary.record(for: reference) != nil else { return nil }
            return .init(state: .init(isPlaying: false, isSwitching: lookupSwitching, isFavorite: false,
                canPerformPrimary: !lookupSwitching && lookupLibrary.content(for: reference)?.publishedAvailability.isAvailable == true,
                canFavorite: true, canOrganize: true, playlistNames: []), onPrimary: {}, onToggleFavorite: {}, onChoosePlaylist: { _ in })
        }
        let lookupView = OnlineImageInspectorView(artwork: lookupArtwork, library: lookupLibrary,
            makeLibraryActions: lookupActions, onAuthor: { _ in }, initialPageIndex: 63)
        await pump { !lookupView.isResolving && lookupView.assets == lookupPages }
        checks["lookup-multi-page-details-reach-the-real-tail-page"] = lookupView.assets == lookupPages
            && lookupView.pageIndex == 63 && lookupView.pageLabel.stringValue == "第64 / 共64张"
            && title(lookupView.primaryButton) == "下载图片" && lookupView.primaryButton.isEnabled
        func lookupRecord(_ author: String?, _ authorID: String?, title: String = "Local lookup") -> OnlineImageLocalRecord {
            .init(assetID: lookupPages[63].id, title: title, sourceURL: art.sourceURL,
                author: author, authorID: authorID, tags: [], relativePath: "lookup.png", pixelWidth: 10, pixelHeight: 10,
                fileSizeBytes: 10, firstDownloadedAt: .distantPast, revision: UUID())
        }
        let completeRecord = lookupRecord("Local Author", "local-author")
        var progressWork: [String: [String: Int]] = [:], authorWork: [String: Int] = [:]
        var metadataWork: [String: [String: Int]] = [:]
        func deliverProgress(_ values: [OnlineImageAssetID: Double]) async -> (marker: Double?, calls: Int, visits: Int)? {
            let before = progressObservations.count, marker = values[progressMarker]
            lookupLibrary.progress = values
            await pump { progressObservations.dropFirst(before).contains { $0.marker == marker } }
            return progressObservations.dropFirst(before).last { $0.marker == marker }
        }
        for (index, phase) in ["remote", "local", "switchingRemote", "remoteAgain"].enumerated() {
            lookupSwitching = phase == "switchingRemote"
            lookupLibrary.snapshot = .init(records: phase == "local" || lookupSwitching ? [completeRecord] : [],
                unavailable: lookupSwitching ? [completeRecord.id] : [])
            let previous = lookupLibrary.progress[lookupPages[63].id]
            let preparedTitle = lookupSwitching ? "正在切换壁纸" : phase == "local" ? "设为壁纸" : previous != nil ? "取消下载" : "下载图片"
            await pump { title(lookupView.primaryButton) == preparedTitle && lookupView.primaryButton.isEnabled == (!lookupSwitching || previous != nil) }
            checks["lookup-independent-snapshot-controls-\(phase)"] = title(lookupView.primaryButton) == preparedTitle
                && lookupView.primaryButton.isEnabled == (!lookupSwitching || previous != nil)
            let current: Double? = phase == "remote" ? 0.2 : lookupSwitching ? 0.4 : nil
            let marker = Double(index + 1) / 10
            var values = [progressMarker: marker]; values[lookupPages[63].id] = current
            let observed = await deliverProgress(values)
            if let observed { progressWork[phase] = ["calls": observed.calls, "asset": observed.visits] }
            let expectedTitle = lookupSwitching ? "正在切换壁纸" : phase == "local" ? "设为壁纸" : current != nil ? "取消下载" : "下载图片"
            checks["lookup-real-progress-delivery-\(phase)"] = observed != nil && !lookupView.isRetired
                && title(lookupView.primaryButton) == expectedTitle && lookupView.primaryButton.isEnabled == (!lookupSwitching || current != nil)
                && lookupView.renderedProgress == current
            for suffix in ["Unrelated", "Duplicate"] {
                if suffix == "Unrelated" { values[progressMarker] = marker + 0.01 }
                let repeated = await deliverProgress(values)
                if let repeated { progressWork[phase + suffix] = ["calls": repeated.calls, "asset": repeated.visits] }
                checks["lookup-unchanged-progress-preserves-controls-\(phase)-\(suffix)"] = repeated != nil
                    && title(lookupView.primaryButton) == expectedTitle && lookupView.renderedProgress == current
                    && lookupView.primaryButton.isEnabled == (!lookupSwitching || current != nil)
            }
            let beforeAsset = assetVisits, beforeMembership = membershipVisits
            lookupView.refreshContent()
            metadataWork[phase] = ["asset": assetVisits - beforeAsset, "membership": membershipVisits - beforeMembership]
            checks["lookup-metadata-keeps-tail-page-and-author-\(phase)"] = lookupView.pageLabel.stringValue == "第64 / 共64张"
                && lookupView.authorButton.isEnabled && title(lookupView.primaryButton) == expectedTitle
        }
        lookupLibrary.snapshot = .init(records: [completeRecord])
        await pump { title(lookupView.primaryButton) == "设为壁纸" }
        var sameProgress = [progressMarker: 0.5, lookupPages[63].id: 0.6, lookupPages[62].id: 0.6]
        let setup = await deliverProgress(sameProgress)
        if let setup { progressWork["sameProgressSetup"] = ["calls": setup.calls, "asset": setup.visits] }
        checks["lookup-equal-page-progress-starts-through-real-controls"] = setup != nil
            && lookupView.renderedProgress == 0.6 && title(lookupView.primaryButton) == "设为壁纸"
        let beforeQueued = progressObservations.count
        sameProgress[progressMarker] = 0.51
        lookupLibrary.progress = sameProgress
        _ = lookupView.previousButton.accessibilityPerformPress()
        await pump { progressObservations.dropFirst(beforeQueued).contains { $0.marker == 0.51 } }
        let queued = progressObservations.dropFirst(beforeQueued).last { $0.marker == 0.51 }
        if let queued { progressWork["queuedPageSameProgress"] = ["calls": queued.calls, "asset": queued.visits] }
        _ = lookupView.primaryButton.accessibilityPerformPress()
        checks["lookup-queued-progress-after-equal-value-page-change-cancels-current-page"] = queued != nil
            && lookupView.pageIndex == 62 && lookupView.renderedProgress == 0.6 && title(lookupView.primaryButton) == "取消下载"
            && lookupLibrary.cancellations == [lookupPages[62].id]
        _ = lookupView.nextButton.accessibilityPerformPress()
        let ended = await deliverProgress([progressMarker: 0.6])
        if let ended { progressWork["localEndAfterPage"] = ["calls": ended.calls, "asset": ended.visits] }
        checks["lookup-page-return-and-current-progress-end-refresh-local-controls"] = ended != nil
            && lookupView.pageIndex == 63 && lookupView.renderedProgress == nil && title(lookupView.primaryButton) == "设为壁纸"
        let beforeStale = progressObservations.count
        lookupLibrary.progress = [progressMarker: 0.61, lookupPages[63].id: 0.8]
        lookupLibrary.progress = [progressMarker: 0.62]
        await pump { progressObservations.dropFirst(beforeStale).contains { $0.marker == 0.62 } }
        var sawQueuedPayloads = true
        for (name, marker) in [("stalePayloadFirst", 0.61), ("stalePayloadLatest", 0.62)] {
            let delivered = progressObservations.dropFirst(beforeStale).last { $0.marker == marker }
            if let delivered { progressWork[name] = ["calls": delivered.calls, "asset": delivered.visits] }
            sawQueuedPayloads = sawQueuedPayloads && delivered != nil
        }
        checks["lookup-queued-payloads-cannot-replace-the-latest-current-progress"] = sawQueuedPayloads
            && lookupView.renderedProgress == nil && title(lookupView.primaryButton) == "设为壁纸"
        lookupView.pageIndex = 67
        let beforeMissingAsset = assetVisits, beforeMissingMembership = membershipVisits
        lookupView.refreshContent()
        metadataWork["missing"] = ["asset": assetVisits - beforeMissingAsset, "membership": membershipVisits - beforeMissingMembership]
        checks["lookup-missing-page-keeps-fallback-label-and-disabled-download"] = lookupView.pageLabel.stringValue == "第68张"
            && !lookupView.primaryButton.isEnabled && lookupView.previousButton.isEnabled && !lookupView.nextButton.isEnabled
        _ = lookupView.previousButton.accessibilityPerformPress()
        checks["lookup-following-page-input-restores-the-real-tail-asset"] = lookupView.pageIndex == 63
            && lookupView.pageLabel.stringValue == "第64 / 共64张" && lookupView.primaryButton.isEnabled

        let authorCases: [(String, Bool, String?, String?, Int, OnlineImageAuthor?)] = [
            ("remote", false, nil, nil, 63, .init(source: .pixiv, id: "asset-63", name: "Asset 63")),
            ("missing", false, nil, nil, 67, .init(source: .pixiv, id: "artwork-author", name: "Artwork Author")),
            ("completeLocal", true, "Local Author", "local-author", 63, .init(source: .pixiv, id: "local-author", name: "Local Author")),
            ("partialLocal", true, "Local Author", nil, 63, .init(source: .pixiv, id: "asset-63", name: "Local Author")),
            ("nameMissingLocal", true, nil, "local-author", 63, .init(source: .pixiv, id: "local-author", name: "Asset 63")),
            ("bothMissingLocal", true, nil, nil, 63, .init(source: .pixiv, id: "asset-63", name: "Asset 63")),
            ("emptyID", true, "Local Author", "", 63, nil),
            ("emptyName", true, "", nil, 63, .init(source: .pixiv, id: "asset-63", name: ""))
        ]
        for (name, local, author, authorID, page, expected) in authorCases {
            lookupLibrary.snapshot = .init(records: local ? [lookupRecord(author, authorID)] : [])
            lookupView.pageIndex = page
            let before = assetVisits
            let resolved = lookupView.resolvedAuthor
            authorWork[name] = assetVisits - before
            checks["lookup-author-result-\(name)"] = resolved == expected
        }
        var noIdentity = lookupArtwork; noIdentity.authorID = nil
        lookupView.artwork = noIdentity; lookupView.pageIndex = 67; lookupLibrary.snapshot = .init()
        let beforeAbsent = assetVisits
        let absentAuthor = lookupView.resolvedAuthor
        authorWork["absentIdentity"] = assetVisits - beforeAbsent
        checks["lookup-missing-pixiv-author-identity-remains-unavailable"] = absentAuthor == nil
        let wallhavenName = OnlineImageArtwork(source: .wallhaven, artworkID: "name-only", title: "Name only",
            sourceURL: art.sourceURL, author: "Wallhaven Author", kind: .unknown)
        let wallhavenView = OnlineImageInspectorView(artwork: wallhavenName, library: OnlineImageLibrary(), makeLibraryActions: { _ in nil })
        let beforeWallhaven = assetVisits
        let wallhavenAuthor = wallhavenView.resolvedAuthor
        authorWork["wallhavenName"] = assetVisits - beforeWallhaven
        checks["lookup-wallhaven-keeps-name-as-author-identity-fallback"] = wallhavenAuthor == OnlineImageAuthor(source: .wallhaven, id: "Wallhaven Author", name: "Wallhaven Author")
        wallhavenView.retire()

        lookupView.artwork = lookupArtwork; lookupView.pageIndex = 63
        lookupLibrary.snapshot = .init(records: [completeRecord])
        await pump { title(lookupView.primaryButton) == "设为壁纸" }
        host.addSubview(lookupView)
        lookupView.removeFromSuperview()
        let retiredForRemount = lookupView.isRetired && lookupView.hasMounted
        lookupLibrary.snapshot = .init(records: [lookupRecord("Local Author", "local-author", title: "Current hidden source")])
        lookupLibrary.progress = [progressMarker: 0.9, lookupPages[63].id: 0.8]
        var remountDetail: CheckedContinuation<OnlineImageArtwork, Never>?
        lookupLibrary.detailResolver = { _ in await withCheckedContinuation { remountDetail = $0 } }
        defer { remountDetail?.resume(returning: lookupArtwork) }
        host.addSubview(lookupView)
        checks["remount-synchronously-catches-up-current-local-content-and-progress"] = lookupView.titleLabel.stringValue == "Current hidden source"
            && lookupView.renderedProgress == 0.8 && lookupView.isResolving && title(lookupView.primaryButton) == "设为壁纸"
        await pump { remountDetail != nil }
        remountDetail?.resume(returning: lookupArtwork); remountDetail = nil
        lookupLibrary.detailResolver = { _ in lookupArtwork }
        await pump { !lookupView.isResolving && lookupView.assets == lookupPages && lookupView.renderedProgress == 0.8 }
        checks["lookup-remount-replays-current-progress-without-a-source-action"] = retiredForRemount && !lookupView.isRetired
            && lookupView.window === window && lookupView.renderedProgress == 0.8 && title(lookupView.primaryButton) == "设为壁纸"
            && lookupLibrary.downloads.isEmpty && lookupLibrary.cancellations == [lookupPages[62].id]
        let remountEnd = await deliverProgress([progressMarker: 0.91])
        if let remountEnd { progressWork["remountEnd"] = ["calls": remountEnd.calls, "asset": remountEnd.visits] }
        checks["lookup-remount-current-progress-end-still-enters-controls"] = remountEnd != nil
            && lookupView.renderedProgress == nil && title(lookupView.primaryButton) == "设为壁纸"
        PixivSession.shared.state = .init(scopeID: "r26-account-after-pages")
        await pump { lookupView.observedScope == "r26-account-after-pages" }
        checks["lookup-account-change-retires-pages-but-keeps-local-receipt-action"] = lookupView.assets.isEmpty
            && lookupView.primaryButton.isEnabled && title(lookupView.primaryButton) == "设为壁纸"
            && lookupView.resolvedAuthor == OnlineImageAuthor(source: .pixiv, id: "local-author", name: "Local Author")
        lookupLibrary.snapshot = .init()
        await pump { !lookupView.primaryButton.isEnabled }
        checks["lookup-account-change-cannot-reuse-retired-pages-after-local-removal"] = lookupView.assets.isEmpty
            && !lookupView.primaryButton.isEnabled && !lookupView.authorButton.isEnabled && lookupView.preview.image == nil
        lookupView.removeFromSuperview()
        let lookupWork: [String: Any] = ["progress": progressWork, "metadata": metadataWork, "authors": authorWork]
        let lookupJSON = String(decoding: try JSONSerialization.data(withJSONObject: lookupWork, options: [.sortedKeys]), as: UTF8.self)
        FileHandle.standardError.write(Data("Inspector lookup work: \(lookupJSON)\n".utf8))
        let recoveryLibrary = OnlineImageLibrary()
        let recoveryError = OnlineImageError.message("fixture detail request failed")
        let recoverySeed = OnlineImageArtwork(source: .wallhaven, artworkID: "remount-recovery", title: "Before recovery",
            sourceURL: art.sourceURL, thumbnailURL: thumb, kind: .image)
        var recoveredArtwork = recoverySeed; recoveredArtwork.title = "Recovered detail"
        let recoveryAsset = OnlineImageAsset(id: recoverySeed.firstAssetID, title: "Recovered page",
            sourceURL: art.sourceURL, originalURL: asset.originalURL)
        recoveryLibrary.detailResolver = { _ in throw recoveryError }
        recoveryLibrary.assetResolver = { _ in [recoveryAsset] }
        let recoveryView = OnlineImageInspectorView(artwork: recoverySeed, library: recoveryLibrary,
            makeLibraryActions: { _ in nil })
        host.addSubview(recoveryView)
        NSLayoutConstraint.activate([recoveryView.leadingAnchor.constraint(equalTo: host.leadingAnchor), recoveryView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            recoveryView.topAnchor.constraint(equalTo: host.topAnchor), recoveryView.bottomAnchor.constraint(equalTo: host.bottomAnchor)])
        host.layoutSubtreeIfNeeded()
        await pump { !recoveryView.isResolving }
        checks["detail-failure-before-remount-is-visible-and-finishes-request"] = recoveryView.detailTask == nil
            && !recoveryView.isResolving && !recoveryView.notice.isHidden
            && recoveryView.notice.stringValue == recoveryError.localizedDescription && !recoveryView.primaryButton.isEnabled
        recoveryView.removeFromSuperview()
        let retiredRecovery = recoveryView.isRetired && recoveryView.hasMounted && recoveryView.window == nil
        var recoveryDetail: CheckedContinuation<OnlineImageArtwork, Never>?
        recoveryLibrary.detailResolver = { _ in await withCheckedContinuation { recoveryDetail = $0 } }
        defer { recoveryDetail?.resume(returning: recoveredArtwork) }
        host.addSubview(recoveryView)
        checks["remount-keeps-existing-error-priority-while-new-detail-is-held"] = recoveryView.isResolving
            && recoveryView.errorText == recoveryError.localizedDescription && !recoveryView.notice.isHidden
            && recoveryView.notice.stringValue == recoveryError.localizedDescription
        await pump { recoveryDetail != nil }
        recoveryDetail?.resume(returning: recoveredArtwork); recoveryDetail = nil
        host.layoutSubtreeIfNeeded()
        await pump { !recoveryView.isResolving && recoveryView.assets == [recoveryAsset] }
        checks["successful-detail-after-remount-clears-prior-error"] = retiredRecovery && !recoveryView.isRetired
            && recoveryView.window === window && recoveryView.errorText == nil && recoveryView.notice.isHidden
            && recoveryView.notice.stringValue.isEmpty && recoveryView.artwork == recoveredArtwork
            && recoveryView.titleLabel.stringValue == recoveryAsset.title && recoveryView.detailTask == nil
            && recoveryLibrary.detailRequests.count == 2
        let recoveryCanDownload = recoveryView.primaryButton.isEnabled && title(recoveryView.primaryButton) == "下载图片"
            && recoveryView.preview.image === green
        _ = recoveryView.primaryButton.accessibilityPerformPress()
        checks["remount-recovery-restores-current-download-action"] = recoveryCanDownload
            && recoveryLibrary.downloads == [recoveryAsset.id] && recoveryLibrary.downloadApplyFlags == [false]
        recoveryView.removeFromSuperview()
        let unknownLibrary = OnlineImageLibrary()
        let unknownSeed = OnlineImageArtwork(source: .wallhaven, artworkID: "remount-unknown", title: "Unknown work", sourceURL: art.sourceURL)
        let unknownView = OnlineImageInspectorView(artwork: unknownSeed, library: unknownLibrary, makeLibraryActions: { _ in nil })
        checks["unknown-constructor-shows-loading-before-detail-task-runs"] = unknownView.isResolving
            && unknownView.notice.stringValue == "正在获取作品详情…"
        host.addSubview(unknownView)
        await pump { !unknownView.isResolving }
        checks["unknown-completed-detail-keeps-original-unconfirmed-type-notice"] = !unknownView.isResolving
            && unknownView.notice.stringValue == "作品类型尚未确认，暂不支持下载或应用。" && !unknownView.primaryButton.isEnabled
        unknownView.removeFromSuperview()
        var unknownDetails: [Int: CheckedContinuation<OnlineImageArtwork, Never>] = [:]
        unknownLibrary.detailResolver = { _ in
            let request = unknownLibrary.detailRequests.count
            return await withCheckedContinuation { unknownDetails[request] = $0 }
        }
        defer {
            unknownLibrary.detailResolver = nil
            for continuation in unknownDetails.values { continuation.resume(returning: unknownSeed) }
        }
        host.addSubview(unknownView)
        checks["unknown-remount-synchronously-replaces-unconfirmed-notice-with-loading"] = unknownView.isResolving
            && unknownView.notice.stringValue == "正在获取作品详情…" && !unknownView.notice.isHidden
        await pump { unknownDetails[2] != nil }
        let retiredDetail = unknownView.detailTask
        unknownView.removeFromSuperview()
        host.addSubview(unknownView)
        await pump { unknownDetails[3] != nil }
        var obsolete = unknownSeed; obsolete.title = "Obsolete detail must not appear"
        let oldCompletion = unknownDetails.removeValue(forKey: 2)
        oldCompletion?.resume(returning: obsolete)
        if oldCompletion != nil { await retiredDetail?.value }
        checks["late-retired-detail-cannot-replace-new-remount-request"] = oldCompletion != nil && retiredDetail?.isCancelled == true
            && unknownDetails[3] != nil && unknownView.isResolving && unknownView.artwork == unknownSeed
            && unknownView.titleLabel.stringValue == unknownSeed.title
        var currentUnknown = unknownSeed; currentUnknown.title = "Current unknown detail"
        unknownDetails.removeValue(forKey: 3)?.resume(returning: currentUnknown)
        await pump { !unknownView.isResolving }
        checks["current-remount-detail-completes-with-original-unknown-type-rules"] = unknownView.artwork == currentUnknown
            && unknownView.notice.stringValue == "作品类型尚未确认，暂不支持下载或应用。" && unknownView.detailTask == nil
            && !unknownView.primaryButton.isEnabled && unknownView.titleLabel.stringValue == currentUnknown.title
        unknownView.removeFromSuperview()
        let report = try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys])
        print(String(decoding: report, as: UTF8.self))
    }
}
