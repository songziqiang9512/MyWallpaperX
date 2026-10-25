import AppKit

/// Real header constraints inside the production grid and native window. The
/// older fixed-height generic-header tests remain in the main grid harness.
@MainActor enum WallpaperPlaylistHeaderChecks {
    private static func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0, of: type) }
    }

    /// Draw only the real cell's native bezel, excluding title and symbol.
    /// Raw alpha distinguishes a blank result from a translucent native body.
    private static func bezelPixels(_ button: NSButton) -> (bodyRows: Range<Int>?, nonzeroRows: Range<Int>?,
                                                          maxAlpha: CGFloat, centerMaxAlpha: CGFloat, nonzeroPixels: Int)? {
        guard let cell = button.cell as? NSButtonCell, let window = button.window else { return nil }
        let scale = window.backingScaleFactor
        let width = Int(ceil(button.bounds.width * scale)), height = Int(ceil(button.bounds.height * scale))
        guard width > 0, height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.cgContext.scaleBy(x: scale, y: scale)
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            cell.drawBezel(withFrame: button.bounds, in: button)
        }
        var maxAlpha: CGFloat = 0, centerMaxAlpha: CGFloat = 0
        var nonzeroPixels = 0, centerAlphas: [CGFloat] = [], nonzeroRows: [Int] = []
        for y in 0..<height {
            for x in 0..<width {
                let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                maxAlpha = max(maxAlpha, alpha)
                if alpha > 0 { nonzeroPixels += 1 }
            }
            let centerAlpha = bitmap.colorAt(x: width / 2, y: y)?.alphaComponent ?? 0
            centerAlphas.append(centerAlpha)
            centerMaxAlpha = max(centerMaxAlpha, centerAlpha)
            if centerAlpha > 0 { nonzeroRows.append(y) }
        }
        // Native bezels are translucent. Measure their peak-alpha plateau,
        // independently of the absolute material opacity; blank paint fails.
        let bodyRows = centerMaxAlpha > 0
            ? centerAlphas.indices.filter { centerAlphas[$0] >= centerMaxAlpha * 0.95 } : []
        let body = bodyRows.first.flatMap { first in bodyRows.last.map { first..<($0 + 1) } }
        let nonzero = nonzeroRows.first.flatMap { first in nonzeroRows.last.map { first..<($0 + 1) } }
        return (body, nonzero, maxAlpha, centerMaxAlpha, nonzeroPixels)
    }

    static func run(grid: WallpaperLibraryGridController, window: NSWindow, values: [WallpaperContentItem],
                    settle: () -> Void, checks: inout [String: Bool]) {
        let header = WallpaperPlaylistHeaderView()
        let page = WallpaperLibraryPage.playlist(UUID())
        let shortName = "轻松时光"
        let longName = String(repeating: "窗前的风景与日落 🌇 家庭共享的特别壁纸 🎨 ", count: 8)
        var currentName = shortName
        var currentSummary = "\(values.count) 张壁纸"
        var currentPlayableCount = values.count
        var currentDescription: String?
        var currentImage: NSImage?
        var playCount = 0, randomCount = 0, addCount = 0
        var measuredWidths: [CGFloat] = []
        func configure(canPlay: Bool = true, canAdd: Bool = true) {
            header.update(name: currentName, summary: currentSummary, image: currentImage,
                canPlay: canPlay, canAdd: canAdd, descriptionText: currentDescription, playableCount: canPlay ? currentPlayableCount : 0, play: { playCount += 1 },
                random: { randomCount += 1 }, add: { addCount += 1 })
        }
        func publish() {
            grid.update(page: page, items: values, selection: .init(), preferredColumns: 5,
                permitsDragging: false, scrollAnchor: nil, header: (header, { width in
                    measuredWidths.append(width)
                    return header.preferredHeight(forWidth: width)
                }))
            settle()
        }
        func rectInHeader(_ view: NSView) -> NSRect { view.convert(view.bounds, to: header) }
        func frameInWindow(_ index: Int) -> NSRect? {
            guard let cell = grid.collection.item(at: IndexPath(item: index, section: 0)) else { return nil }
            return cell.view.convert(cell.view.bounds, to: nil)
        }
        func offsetInWindow(_ index: Int) -> CGFloat? {
            frameInWindow(index).map { window.contentLayoutRect.maxY - $0.maxY }
        }
        func scrollToMiddle(_ index: Int = 20) {
            let flow = grid.collection.collectionViewLayout as! NSCollectionViewFlowLayout
            let frame = flow.layoutAttributesForItem(at: IndexPath(item: index, section: 0))!.frame
            grid.scrollView.contentView.scroll(to: NSPoint(x: 0, y: frame.minY + 13 - grid.scrollView.contentInsets.top))
            grid.scrollView.reflectScrolledClipView(grid.scrollView.contentView)
            settle()
        }
        func contained(_ views: [NSView]) -> Bool {
            views.allSatisfy { view in
                let rect = rectInHeader(view)
                return rect.minX >= 8 - 1 && rect.maxX <= header.bounds.width - 8 + 1
                    && rect.minY >= 16 - 1 && rect.maxY <= header.bounds.height - 16 + 1
            }
        }

        window.setContentSize(NSSize(width: 1000, height: 650))
        FileHandle.standardError.write(Data("header-stage initial-publish\n".utf8))
        configure(); publish()
        FileHandle.standardError.write(Data("header-stage initial-published size=\(header.bounds.size)\n".utf8))
        let cover = descendants(header, of: NSImageView.self).first!
        let title = descendants(header, of: NSTextField.self).first { $0.stringValue == shortName }!
        let count = descendants(header, of: NSTextField.self).first { $0.stringValue == currentSummary }!
        let buttons = descendants(header, of: NSButton.self).sorted { $0.tag < $1.tag }
        func visibleCountFitsAfterTitle() -> Bool {
            let titleRect = title.superview!.convert(title.alignmentRect(forFrame: title.frame), to: header)
            let countRect = count.superview!.convert(count.alignmentRect(forFrame: count.frame), to: header)
            return count.stringValue == currentSummary && !count.isHiddenOrHasHiddenAncestor
                && count.accessibilityLabel() == currentSummary && header.accessibilityHelp() == nil
                && count.font?.pointSize == 12 && count.textColor == .secondaryLabelColor
                && count.maximumNumberOfLines == 1 && count.bounds.width > 0
                && count.superview === title.superview && (count.superview as? NSStackView)?.alignment == .firstBaseline
                && abs(countRect.minX - titleRect.maxX - 8) < 1 && contained([count])
        }
        checks["real-header-shows-a-smaller-secondary-count-after-the-title-without-duplicate-accessibility-help"] = visibleCountFitsAfterTitle()
        let shortHeight = header.bounds.height, shortTitleHeight = title.bounds.height
        checks["real-header-keeps-72-square-cover-22-point-title-and-all-three-native-buttons"] = cover.bounds.size == NSSize(width: 72, height: 72)
            && title.font?.pointSize == 22 && title.maximumNumberOfLines == 2
            && buttons.map(\.title) == ["播放", "", ""]
            && buttons.map { $0.accessibilityLabel() } == ["播放", "随机播放", "添加壁纸"]
            && buttons.allSatisfy { $0.borderShape == .capsule && $0.bezelStyle == .flexiblePush }
            && Set(buttons.map { $0.bounds.height }).count == 1
            && buttons.allSatisfy { $0.bounds.height == 28 }
            && buttons[1].frame.minX < buttons[0].frame.minX && buttons[0].frame.minX < buttons[2].frame.minX
        let bezelPaint = buttons.map(bezelPixels)
        let bezelRows = bezelPaint.map { $0?.bodyRows }
        let paintedBezelRows = bezelRows.compactMap { $0 }
        let allBezelBodiesPainted = buttons.count == 3 && paintedBezelRows.count == buttons.count
        let identicalBezelEdges = paintedBezelRows.first.map { first in paintedBezelRows.allSatisfy { $0 == first } } ?? false
        checks["real-header-native-bezel-bodies-have-identical-backing-pixel-edges"] = allBezelBodiesPainted && identicalBezelEdges
        FileHandle.standardError.write(Data("header-native-bezel backingScale=\(window.backingScaleFactor) bounds=\(buttons.map(\.bounds)) rows=\(bezelRows) paint=\(bezelPaint)\n".utf8))
        checks["real-header-short-title-fits-compact-height-and-closed-vertical-insets"] = shortHeight >= 100 && shortHeight <= 128
            && contained([cover, title] + buttons)
        checks["real-header-aligns-with-grid-eight-point-edge-and-sixteen-point-image-gap"] = abs(rectInHeader(cover).minX - 8) < 1
            && abs(title.superview!.convert(title.alignmentRect(forFrame: title.frame), to: header).minX
                - rectInHeader(cover).maxX - 16) < 1
        let headerRect = header.convert(header.bounds, to: nil)
        checks["real-header-is-wholly-below-unified-toolbar-and-first-card-follows-it"] = grid.scrollView.contentInsets.top > 0
            && abs(headerRect.maxY - window.contentLayoutRect.maxY) < 1
            && frameInWindow(0).map { abs(headerRect.minY - $0.maxY - 8) < 1 } == true
        buttons.forEach { $0.performClick(nil) }
        checks["real-header-native-buttons-preserve-three-distinct-actions"] = playCount == 1 && randomCount == 1 && addCount == 1
        configure(canPlay: false, canAdd: false)
        buttons.forEach { $0.performClick(nil) }
        checks["real-header-disabled-buttons-never-claim-play-random-or-add"] = buttons.allSatisfy { !$0.isEnabled }
            && playCount == 1 && randomCount == 1 && addCount == 1
        configure(); publish()

        currentSummary = "显示 3 / 共 \(values.count) 张壁纸"; currentPlayableCount = 2
        configure(); publish()
        checks["real-header-filter-summary-updates-inline-without-growing-a-second-result-row"] = visibleCountFitsAfterTitle()
            && abs(header.bounds.height - shortHeight) < 1 && contained([cover, title, count] + buttons)
        checks["real-header-play-and-random-help-explain-current-playable-result-scope"] = buttons[0].toolTip == "播放当前显示结果中可播放的 2 张壁纸"
            && buttons[1].toolTip == "随机播放当前显示结果中可播放的 2 张壁纸"
            && buttons[0].accessibilityHelp() == buttons[0].toolTip && buttons[2].accessibilityLabel() == "添加壁纸"
        currentSummary = "\(values.count) 张壁纸"; currentPlayableCount = values.count
        configure(); publish()

        currentDescription = String(repeating: "可选描述，与壁纸列表同步。", count: 20)
        configure(); publish()
        let description = descendants(header, of: NSTextField.self).first { $0.stringValue == currentDescription }!
        checks["real-header-description-wraps-at-most-three-lines-with-native-buttons-contained"] = !description.isHidden
            && description.maximumNumberOfLines == 3 && description.bounds.height > 13 && contained([cover, title, description] + buttons)
            && header.bounds.height > shortHeight
        currentDescription = "  \n  "; configure(); publish()
        checks["real-header-empty-description-hides-and-restores-original-compact-height"] = description.isHidden
            && abs(header.bounds.height - shortHeight) < 1
        currentDescription = nil; configure(); publish()

        FileHandle.standardError.write(Data("header-stage title-growth\n".utf8))
        scrollToMiddle()
        let originalOffset = offsetInWindow(20)
        checks["real-header-content-growth-test-starts-from-fixed-middle-reference"] = originalOffset.map { abs($0 + 13) < 1 } == true
        currentName = longName; configure(); publish()
        FileHandle.standardError.write(Data("header-wrap width=\(header.bounds.width) titleFrame=\(title.frame) preferred=\(title.preferredMaxLayoutWidth) intrinsic=\(title.intrinsicContentSize) fitting=\(title.fittingSize) wraps=\(title.cell?.wraps ?? false) scrollable=\(title.cell?.isScrollable ?? false) height=\(header.bounds.height)\n".utf8))
        checks["real-header-long-chinese-and-emoji-wrap-to-two-lines-without-clipping-actions"] = title.stringValue == longName
            && title.toolTip == longName && title.bounds.height > shortTitleHeight + 2 && header.bounds.height > shortHeight
            && title.cell?.truncatesLastVisibleLine == true && visibleCountFitsAfterTitle() && contained([cover, title, count] + buttons)
        checks["real-header-content-height-change-preserves-fixed-middle-card-offset"] = originalOffset != nil
            && offsetInWindow(20).map { abs($0 - originalOffset!) < 1 } == true
        currentName = shortName; configure(); publish()
        checks["real-header-shrinking-title-restores-compact-height-without-jumping-anchor"] = abs(header.bounds.height - shortHeight) < 1
            && originalOffset != nil && offsetInWindow(20).map { abs($0 - originalOffset!) < 1 } == true
        let beforeSameHeight = grid.collection.item(at: IndexPath(item: 20, section: 0))
        currentName = "晴朗午后"; configure(); publish()
        checks["real-header-same-height-metadata-keeps-native-cell-identity"] = beforeSameHeight != nil
            && grid.collection.item(at: IndexPath(item: 20, section: 0)) === beforeSameHeight
            && abs(header.bounds.height - shortHeight) < 1

        FileHandle.standardError.write(Data("header-stage window-width\n".utf8))
        currentName = longName; configure(); publish(); scrollToMiddle()
        let beforeWindowResize = offsetInWindow(20)
        window.setContentSize(NSSize(width: 580, height: 650)); settle()
        checks["real-header-window-resize-measures-actual-narrow-clip-and-keeps-all-controls"] = measuredWidths.last == grid.scrollView.contentView.bounds.width
            && grid.scrollView.contentView.bounds.width < 600 && cover.bounds.size == NSSize(width: 64, height: 64)
            && visibleCountFitsAfterTitle() && contained([cover, title, count] + buttons)
        checks["real-header-window-resize-preserves-reference-and-relative-offset"] = beforeWindowResize != nil
            && offsetInWindow(20).map { abs($0 - beforeWindowResize!) < 1 } == true
        window.setContentSize(NSSize(width: 1000, height: 650)); settle()
        checks["real-header-window-width-roundtrip-remeasures-wide-cover-without-anchor-drift"] = cover.bounds.size == NSSize(width: 72, height: 72)
            && visibleCountFitsAfterTitle()
            && beforeWindowResize != nil && offsetInWindow(20).map { abs($0 - beforeWindowResize!) < 1 } == true
        grid.scrollToTop(animated: false); settle()
        checks["real-header-native-return-to-top-keeps-full-header-visible-after-width-roundtrip"] = abs(header.convert(header.bounds, to: nil).maxY - window.contentLayoutRect.maxY) < 1
            && contained([cover, title] + buttons)

        // Actual NSSplitView geometry changes only the viewport width, just as
        // dragging the product sidebar does. No toolbar callback rerenders it.
        FileHandle.standardError.write(Data("header-stage sidebar-width\n".utf8))
        let split = NSSplitViewController(), sidebar = NSViewController()
        sidebar.view = NSView()
        split.splitView.isVertical = true
        split.view.frame = NSRect(x: 0, y: 0, width: 900, height: 650)
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 200; sidebarItem.maximumThickness = 320
        sidebarItem.canCollapse = false
        window.contentViewController = nil
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: grid))
        window.contentViewController = split
        window.setContentSize(NSSize(width: 900, height: 650))
        split.splitView.setPosition(200, ofDividerAt: 0); settle()
        scrollToMiddle()
        let beforeSidebarResize = offsetInWindow(20)
        let wideClip = grid.scrollView.contentView.bounds.width
        split.splitView.setPosition(320, ofDividerAt: 0); settle()
        checks["real-header-sidebar-resize-uses-native-clip-width-not-window-width"] = wideClip >= 600
            && grid.scrollView.contentView.bounds.width < 600 && measuredWidths.last == grid.scrollView.contentView.bounds.width
            && cover.bounds.size == NSSize(width: 64, height: 64) && visibleCountFitsAfterTitle() && contained([cover, title, count] + buttons)
        checks["real-header-sidebar-resize-preserves-fixed-middle-card-offset"] = beforeSidebarResize != nil
            && offsetInWindow(20).map { abs($0 - beforeSidebarResize!) < 1 } == true
        split.splitView.setPosition(200, ofDividerAt: 0); settle()
        checks["real-header-sidebar-width-roundtrip-keeps-wide-cover-and-anchor"] = cover.bounds.size == NSSize(width: 72, height: 72)
            && beforeSidebarResize != nil && offsetInWindow(20).map { abs($0 - beforeSidebarResize!) < 1 } == true

        FileHandle.standardError.write(Data("header-stage image-and-appearance\n".utf8))
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let clearPixel = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0)
        for x in 0..<8 { for y in 0..<8 { bitmap.setColor(clearPixel, atX: x, y: y) } }
        let transparent = NSImage(size: NSSize(width: 8, height: 8)); transparent.addRepresentation(bitmap)
        let beforeImageHeight = header.bounds.height
        let beforeImageCell = grid.collection.item(at: IndexPath(item: 20, section: 0))
        currentImage = transparent; configure(); publish()
        let imageButtonFrames = buttons.map { $0.convert($0.bounds, to: header) }
        checks["real-header-transparent-cover-arrival-keeps-image-height-cell-and-hit-geometry"] = cover.image === transparent
            && bitmap.colorAt(x: 0, y: 0)?.alphaComponent == 0 && abs(header.bounds.height - beforeImageHeight) < 1
            && beforeImageCell != nil && grid.collection.item(at: IndexPath(item: 20, section: 0)) === beforeImageCell
        func colorMatchesOwnAppearance() -> Bool {
            var expected: CGColor?
            cover.effectiveAppearance.performAsCurrentDrawingAppearance { expected = NSColor.controlBackgroundColor.cgColor }
            return expected == cover.layer?.backgroundColor
        }
        header.appearance = NSAppearance(named: .darkAqua); settle()
        let darkColor = cover.layer?.backgroundColor
        checks["real-header-dark-appearance-resolves-own-semantic-cover-background"] = colorMatchesOwnAppearance()
        header.appearance = NSAppearance(named: .aqua); settle()
        checks["real-header-light-appearance-updates-background-without-baking-image-or-moving-controls"] = colorMatchesOwnAppearance()
            && darkColor != cover.layer?.backgroundColor && cover.image === transparent
            && bitmap.colorAt(x: 0, y: 0)?.alphaComponent == 0 && abs(header.bounds.height - beforeImageHeight) < 1
            && imageButtonFrames == buttons.map { $0.convert($0.bounds, to: header) }

        // A zero-width initial publication must not measure or consume the
        // original pending reference before the native viewport becomes real.
        FileHandle.standardError.write(Data("header-stage zero-width\n".utf8))
        let zero = WallpaperLibraryGridController { _, _, _, _ in HeaderZeroProbeCell() }
        zero.loadViewIfNeeded(); zero.view.frame = .zero; zero.view.layoutSubtreeIfNeeded()
        let zeroHeader = WallpaperPlaylistHeaderView()
        zeroHeader.update(name: longName, summary: "80 张壁纸", image: nil, canPlay: false, canAdd: false,
            play: {}, random: {}, add: {})
        var zeroMeasurements = 0
        zero.update(page: page, items: values, selection: .init(), preferredColumns: 5, permitsDragging: false,
            scrollAnchor: values[20].reference, scrollOffset: -13, scrollAtTop: false,
            header: (zeroHeader, { width in zeroMeasurements += 1; return zeroHeader.preferredHeight(forWidth: width) }))
        checks["real-header-zero-width-defers-height-measurement"] = zero.scrollView.contentView.bounds.width == 0 && zeroMeasurements == 0
        window.contentViewController = zero
        window.setContentSize(NSSize(width: 1000, height: 650))
        for _ in 0..<4 {
            window.contentView?.layoutSubtreeIfNeeded(); zero.view.layoutSubtreeIfNeeded(); zero.collection.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let targetPath = IndexPath(item: 20, section: 0)
        let restored = zero.collection.item(at: targetPath)
        let restoredTop = restored.map { $0.view.convert($0.view.bounds, to: nil).maxY }
        let zeroFlow = zero.collection.collectionViewLayout as! NSCollectionViewFlowLayout
        let targetFrame = zeroFlow.layoutAttributesForItem(at: targetPath)?.frame
        checks["real-header-first-native-width-measures-and-restores-the-original-pending-reference"] = zeroMeasurements > 0
            && restoredTop.map { abs(window.contentLayoutRect.maxY - $0 + 13) < 1 } == true
        FileHandle.standardError.write(Data("header-stage zero-mounted width=\(zero.scrollView.contentView.bounds.width) origin=\(zero.scrollView.contentView.bounds.origin) inset=\(zero.scrollView.contentInsets) measurements=\(zeroMeasurements) targetMounted=\(restored != nil) targetFrame=\(String(describing: targetFrame)) itemSize=\(zeroFlow.itemSize) headerSize=\(zeroFlow.headerReferenceSize) collectionBounds=\(zero.collection.bounds) visibleItems=\(zero.collection.indexPathsForVisibleItems().map { $0.item }.sorted()) windowLayout=\(window.contentLayoutRect)\n".utf8))
        FileHandle.standardError.write(Data("header-stage failed-checks=\(checks.filter { !$0.value }.keys.sorted())\n".utf8))
        FileHandle.standardError.write(Data("real-header sizes short=\(shortHeight) title=\(shortTitleHeight) final=\(header.bounds.height) measuredWidths=\(measuredWidths)\n".utf8))
    }
}

private final class HeaderZeroProbeCell: NSCollectionViewItem {
    override func loadView() { view = WallpaperCardInteractionView() }
}
