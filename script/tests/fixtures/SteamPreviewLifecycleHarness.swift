import AppKit
import ImageIO

@main struct SteamPreviewLifecycleHarness {
    @MainActor static func main() throws {
        if CommandLine.arguments.dropFirst().first == "--card-interactions" {
            initializeNativeAppHarness()
            var checks: [String: Bool] = [:]
            for context in [AppKitSteamWorkshopBrowserItem.DisplayContext.browser, .downloads] {
                let card = AppKitSteamWorkshopBrowserItem(); _ = card.view
                card.currentDisplayContext = context
                checks.merge(gridCardInteractionChecks(item: card, cardRoot: card.cardView,
                    outline: card.hoverOutlineView, isHovering: { card.isHovering },
                    label: context == .browser ? "steam-browser" : "steam-downloads")) { _, new in new }
            }
            print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
            return
        }
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        func cgImage(_ color: NSColor) -> CGImage {
            let context = CGContext(data: nil, width: 48, height: 48, bitsPerComponent: 8,
                bytesPerRow: 48 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
            return context.makeImage()!
        }
        func gif(_ name: String, _ colors: [NSColor]) -> URL {
            let url = root.appendingPathComponent(name).appendingPathExtension("gif")
            let destination = CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, colors.count, nil)!
            for color in colors {
                CGImageDestinationAddImage(destination, cgImage(color),
                    [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
            }
            precondition(CGImageDestinationFinalize(destination))
            return url
        }
        func pump(until condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(4)
            while !condition(), Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            return condition()
        }
        func animated(_ image: NSImage?) -> Bool {
            image?.representations.contains { ($0 as? NSBitmapImageRep)?.value(forProperty: .frameCount) as? Int ?? 1 > 1 } ?? false
        }
        func imageView(_ root: NSView) -> NSImageView? {
            if let image = root as? NSImageView { return image }
            return root.subviews.compactMap(imageView).first
        }
        func placeholder(_ root: NSView) -> SteamWorkshopPreviewPlaceholderView? {
            if let view = root as? SteamWorkshopPreviewPlaceholderView { return view }
            return root.subviews.compactMap(placeholder).first
        }
        let media = gif("renamed-animation", [.systemRed, .systemBlue])
        let black = gif("legitimate-black-still", [.black])
        let window = NSWindow(contentRect: NSRect(x: 14000, y: 14000, width: 320, height: 240),
            styleMask: [.titled], backing: .buffered, defer: false)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        window.contentView = container
        window.orderFrontRegardless()
        let item = AppKitSteamWorkshopBrowserItem()
        item.view.frame = NSRect(x: 20, y: 20, width: 250, height: 180)
        container.addSubview(item.view)
        item.view.layoutSubtreeIfNeeded()
        item.setPreviewVisible(true)
        item.loadPreview(from: media, fallbackVideoURL: nil)
        var checks: [String: Bool] = [:]
        checks["gridLoadsStatic"] = pump { item.previewImageView.image != nil }
        let still = item.previewImageView.image
        // The cursor remains outside this offscreen window. Drive the same
        // presentation entry directly so real tracking events cannot race it.
        func hover(_ active: Bool) {
            item.isHovering = active
            item.syncPreviewAnimationState()
        }
        hover(true)
        checks["gridLoadsRealAnimation"] = pump { animated(item.previewImageView.image) }
        SteamWorkshopPreviewImageCache.shared.removeAll()
        hover(false)
        checks["evictionDuringHoverPreservesStatic"] = item.previewImageView.image === still && still != nil
        hover(true)
        checks["hoverAfterEvictionRecovers"] = pump { animated(item.previewImageView.image) }
        item.setPreviewVisible(false)
        checks["hiddenCardKeepsStatic"] = item.previewImageView.image === still && !item.previewImageView.animates
        let detail = SteamWorkshopPreviewImageContainerView(frame: NSRect(x: 0, y: 0, width: 280, height: 156))
        detail.configure(itemID: "one", previewImageURL: media, fallbackVideoURL: nil, refreshToken: 0)
        checks["detailLoadsAnimation"] = pump { animated(imageView(detail)?.image) }
        SteamWorkshopPreviewImageCache.shared.removeAll()
        detail.configure(itemID: "one", previewImageURL: media, fallbackVideoURL: nil, refreshToken: 0)
        checks["sameDetailConfigurationNeverShowsLoading"] = placeholder(detail)?.isHidden == true
        let blackDetail = SteamWorkshopPreviewImageContainerView(frame: detail.frame)
        blackDetail.configure(itemID: "black", previewImageURL: black, fallbackVideoURL: nil, refreshToken: 0)
        checks["blackImageAcceptedByDetail"] = pump { imageView(blackDetail)?.image != nil && placeholder(blackDetail)?.isHidden == true }
        let first = SteamWorkshopPreviewState()
        let second = SteamWorkshopPreviewState()
        SteamWorkshopPreviewImageCache.shared.removeAll()
        first.configure(previewURL: media, fallbackVideoURL: nil)
        second.configure(previewURL: media, fallbackVideoURL: nil)
        first.reset()
        checks["recycledConsumerDoesNotCancelSharedLoad"] = pump { second.image != nil } && first.image == nil
        let remote = URL(string: "https://example.invalid/renamed-resource.bin?variant=one")!
        let remoteKey = steamWorkshopPreviewCacheKey(for: remote)
        let encoded = try Data(contentsOf: media)
        var diskReady = false
        SteamWorkshopPreviewImageCache.shared.loadRawDataAsync(forKey: remoteKey, loader: { encoded }) { _ in diskReady = true }
        checks["rawGIFDiskFixtureReady"] = pump { diskReady }
        SteamWorkshopPreviewImageCache.shared.removeAll()
        let row = SteamPopoverPreviewProbe(url: remote)
        row.load()
        checks["popoverUsesStaticDecodeForRawGIF"] = pump {
            guard let cached = steamWorkshopCachedPreviewImage(for: remote) else { return false }
            return row.thumbnailView.image === cached && !animated(cached)
        }
        let cardAfterRow = SteamWorkshopPreviewState()
        cardAfterRow.configure(previewURL: remote, fallbackVideoURL: nil)
        row.unbind()
        checks["popoverCannotPolluteSharedStaticCache"] = cardAfterRow.image != nil && !animated(cardAfterRow.image)
        let corruptLocal = root.appendingPathComponent("corrupt-preview.gif")
        try Data("invalid image bytes".utf8).write(to: corruptLocal)
        let corruptState = SteamWorkshopPreviewState()
        corruptState.configure(previewURL: corruptLocal, fallbackImageURL: remote, fallbackVideoURL: nil)
        checks["realCorruptLocalDecodesRemoteFallback"] = pump { corruptState.image != nil && corruptState.placeholder == .hidden }
        corruptState.setAnimationActive(true)
        checks["realCorruptLocalAnimatesSuccessfulRemote"] = pump { animated(corruptState.image) }
        let localVersionURL = root.appendingPathComponent("stable-preview.gif")
        try encoded.write(to: localVersionURL, options: .atomic)
        let versionState = SteamWorkshopPreviewState()
        versionState.configure(previewURL: localVersionURL, fallbackVideoURL: nil)
        checks["localVersionInitiallyLoads"] = pump { versionState.image != nil }
        let oldLocalImage = versionState.image
        let date = try FileManager.default.attributesOfItem(atPath: localVersionURL.path)[.modificationDate] as! Date
        try encoded.write(to: localVersionURL, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: localVersionURL.path)
        versionState.configure(previewURL: localVersionURL, fallbackVideoURL: nil)
        checks["realSameURLReplacedFileLoadsNewCacheEntry"] = pump { versionState.image != nil && versionState.image !== oldLocalImage }
        checks.merge(try steamPreviewStateChecks(still: still!, animation: imageView(detail)!.image!, localVersionURL: localVersionURL)) { _, new in new }
        if let path = ProcessInfo.processInfo.environment["MWX_PREVIEW_PROOF_DIR"] {
            let output = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            window.setContentSize(NSSize(width: 610, height: 240))
            detail.frame = NSRect(x: 300, y: 30, width: 280, height: 156)
            container.addSubview(detail)
            container.layoutSubtreeIfNeeded()
            if let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds) {
                container.cacheDisplay(in: container.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("preview.png"))
            }
        }
        window.orderOut(nil)
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
