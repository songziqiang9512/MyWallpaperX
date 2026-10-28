import AppKit
import QuartzCore

// The driver observes real NSString cache misses and native symbol setup.
@MainActor enum WallpaperCardControlsProbe {
    static var widthMeasurements = 0
    static var symbolConfigurations = 0
}

@main struct WallpaperCardControlsHarness {
    static func main() throws {
        initializeNativeAppHarness()
        let window = NSWindow(contentRect: NSRect(x: 160, y: 160, width: 360, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSView(), bar = WallpaperCardControlsView()
        window.contentView = host
        host.addSubview(bar)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close() }
        var checks: [String: Bool] = [:]
        let title = String(repeating: "真实字体度量和卡片标题 ", count: 5)
        bar.apply(title: title, metadata: "Source metadata")
        func apply(_ width: CGFloat) -> WallpaperCardBarMetrics {
            let metrics = WallpaperCardBarMetrics(cardWidth: width)
            bar.frame = NSRect(x: 20, y: 20, width: width - 2 * metrics.barHorizontalInset, height: metrics.barHeight)
            bar.apply(metrics: metrics)
            host.layoutSubtreeIfNeeded()
            bar.layoutSubtreeIfNeeded()
            bar.titleView.layoutSubtreeIfNeeded()
            return metrics
        }
        let base = apply(250)
        checks["initial-default-scale-still-applies-the-real-title-font"] = bar.titleView.font == base.titleFont
            && bar.titleView.font.pointSize == 12.5 && WallpaperCardControlsProbe.widthMeasurements > 0
        let initialMeasurements = WallpaperCardControlsProbe.widthMeasurements
        let initialSymbols = WallpaperCardControlsProbe.symbolConfigurations
        let initialDetail = bar.detailButton.image, initialPlay = bar.playButton.image
        let initialFrames = [bar.detailButton.frame, bar.playButton.frame, bar.titleView.frame]
        for _ in 0..<20 { _ = apply(250) }
        checks["identical-metrics-do-not-remeasure-text-or-rebuild-symbols"] = WallpaperCardControlsProbe.widthMeasurements == initialMeasurements
            && initialSymbols > 0 && WallpaperCardControlsProbe.symbolConfigurations == initialSymbols
            && bar.detailButton.image === initialDetail && bar.playButton.image === initialPlay
            && [bar.detailButton.frame, bar.playButton.frame, bar.titleView.frame] == initialFrames
        bar.titleView.font = .systemFont(ofSize: 17, weight: .semibold)
        bar.titleView.layoutSubtreeIfNeeded()
        let changedMeasurements = WallpaperCardControlsProbe.widthMeasurements
        checks["real-font-change-invalidates-the-original-width-cache"] = changedMeasurements > initialMeasurements
            && bar.titleView.font.pointSize == 17
        bar.titleView.font = .systemFont(ofSize: 17, weight: .semibold)
        bar.titleView.layoutSubtreeIfNeeded()
        checks["equal-font-value-does-not-repeat-native-text-measurement"] = WallpaperCardControlsProbe.widthMeasurements == changedMeasurements
        _ = apply(250)
        checks["metrics-restore-font-even-when-icon-size-is-unchanged"] = bar.titleView.font == base.titleFont
            && WallpaperCardControlsProbe.widthMeasurements > changedMeasurements
            && bar.detailButton.image === initialDetail && bar.playButton.image === initialPlay
        let narrow = apply(150)
        let configuration = NSImage.SymbolConfiguration(pointSize: max(11, narrow.iconButtonSize * 0.56), weight: .medium)
        let expectedPlay = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)!.withSymbolConfiguration(configuration)!
        checks["real-icon-size-change-updates-symbol-configuration-and-native-hit-frames"] = bar.playButton.image?.size == expectedPlay.size
            && WallpaperCardControlsProbe.symbolConfigurations == initialSymbols + 1
            && bar.playButton.frame.width == narrow.iconButtonSize && bar.detailButton.frame.width == narrow.iconButtonSize
            && bar.playButton.image !== initialPlay
        bar.primaryState = .playing
        let detail = bar.detailButton.image, stop = bar.playButton.image
        checks["state-changes-still-update-symbols-and-accessible-actions"] = bar.detailButton.accessibilityLabel() == "详细信息"
            && bar.playButton.accessibilityLabel() == "停止播放" && bar.playButton.contentTintColor == .controlAccentColor
            && WallpaperCardControlsProbe.symbolConfigurations == initialSymbols + 2
        _ = apply(150)
        checks["same-metrics-retain-the-current-detail-and-stop-symbols"] = bar.detailButton.image === detail && bar.playButton.image === stop
            && WallpaperCardControlsProbe.symbolConfigurations == initialSymbols + 2
        _ = apply(400)
        let clampedMeasurements = WallpaperCardControlsProbe.widthMeasurements
        let clampedSymbols = WallpaperCardControlsProbe.symbolConfigurations
        let clampedDetail = bar.detailButton.image, clampedStop = bar.playButton.image
        _ = apply(430)
        checks["different-widths-with-equal-clamped-metrics-reuse-font-measurements-and-symbols"] = WallpaperCardControlsProbe.widthMeasurements == clampedMeasurements
            && WallpaperCardControlsProbe.symbolConfigurations == clampedSymbols
            && bar.detailButton.image === clampedDetail && bar.playButton.image === clampedStop
        var play = 0, inspections = 0
        bar.onPlay = { play += 1 }; bar.onInspect = { inspections += 1 }
        bar.playButton.performClick(nil); bar.detailButton.performClick(nil)
        let stock = NSButton(title: "Reference", target: nil, action: nil)
        stock.frame = NSRect(x: 0, y: 0, width: 60, height: 20); host.addSubview(stock)
        checks["original-native-button-targets-deliver-detail-and-primary-once"] = play == 1 && inspections == 1
            && bar.playButton.target === bar && bar.detailButton.target === bar
            && bar.playButton.cell is NSButtonCell && bar.detailButton.cell is NSButtonCell
            && bar.playButton.accessibilityRole() == stock.accessibilityRole()
            && bar.detailButton.accessibilityRole() == stock.accessibilityRole()

        // AppKit's direct AX methods can be unavailable without an external
        // AX client. Compare the same live native control, not a fabricated role.
        stock.target = bar; stock.action = bar.playButton.action
        let beforeStock = play
        let stockAccessible = stock.accessibilityPerformPress()
        let stockDeliveries = play - beforeStock
        let beforeAccessible = (play, inspections)
        let primaryAccessible = bar.playButton.accessibilityPerformPress()
        let detailAccessible = bar.detailButton.accessibilityPerformPress()
        checks["native-accessibility-actions-match-stock-support-and-exact-delivery"] = (0...1).contains(stockDeliveries)
            && primaryAccessible == stockAccessible && detailAccessible == stockAccessible
            && play == beforeAccessible.0 + stockDeliveries && inspections == beforeAccessible.1 + stockDeliveries
        stock.removeFromSuperview()
        play = 1; inspections = 1 // Independent scenarios retain their own command-count baseline.
        let ordinaryFrames = [bar.detailButton.frame, bar.playButton.frame, bar.titleView.frame]
        let buttons = bar.glass.subviews.compactMap { $0 as? NSButton }
        checks["every-bar-has-exactly-the-two-native-detail-and-primary-controls"] = buttons.count == 2
            && buttons.contains { $0 === bar.detailButton } && buttons.contains { $0 === bar.playButton }
            && !bar.detailButton.isHidden && !bar.playButton.isHidden
        _ = apply(150)
        checks["narrow-two-button-bar-keeps-native-hit-targets-and-title-separate"] = bar.detailButton.frame.maxX < bar.titleView.frame.minX
            && bar.titleView.frame.maxX < bar.playButton.frame.minX && bar.titleView.frame.width >= 0
            && bar.detailButton.frame.width == narrow.iconButtonSize && bar.playButton.frame.width == narrow.iconButtonSize
        bar.onInspect = nil; _ = apply(430)
        bar.detailButton.performClick(nil)
        checks["missing-detail-command-disables-its-native-control-without-changing-the-two-key-layout"] =
            !bar.detailButton.isEnabled && !bar.detailButton.isHidden && inspections == 1
            && [bar.detailButton.frame, bar.playButton.frame, bar.titleView.frame] == ordinaryFrames
        bar.onInspect = { inspections += 1 }
        bar.detailButton.performClick(nil)
        checks["restored-detail-command-delivers-once-without-replacing-the-bar"] = bar.detailButton.isEnabled && inspections == 2

        func matchesSymbol(_ button: NSButton, name: String, metrics: WallpaperCardBarMetrics) -> Bool {
            let configuration = NSImage.SymbolConfiguration(pointSize: max(11, metrics.iconButtonSize * 0.56), weight: .medium)
            guard let actual = button.image?.tiffRepresentation,
                  let expected = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(configuration)?.tiffRepresentation else { return false }
            return actual == expected
        }
        let states: [(String, WallpaperCardControlsView.PrimaryState, String, String)] = [
            ("apply", .apply, "play.fill", "设为壁纸"),
            ("switching", .switching, "hourglass", "正在切换壁纸"),
            ("playing", .playing, "stop.fill", "停止播放"),
            ("download", .download, "square.and.arrow.down", "下载壁纸")
        ]
        for (name, state, symbol, title) in states {
            bar.primaryState = state
            let metrics = apply(250)
            checks["\(name)-state-presents-only-its-native-symbol-and-matching-accessible-command"] =
                matchesSymbol(bar.playButton, name: symbol, metrics: metrics)
                && matchesSymbol(bar.detailButton, name: "exclamationmark.circle", metrics: metrics)
                && bar.playButton.accessibilityLabel() == title && bar.playButton.toolTip == title
                && bar.detailButton.accessibilityLabel() == "详细信息"
                && bar.playButton.contentTintColor == (name == "playing" ? .controlAccentColor : .labelColor)
                && bar.detailButton.contentTintColor == .labelColor
                && bar.glass.subviews.compactMap { $0 as? NSButton }.count == 2
        }
        bar.primaryState = .switching
        checks["switching-symbol-retains-full-contrast-while-native-repeat-execution-is-disabled"] =
            (bar.playButton.cell as? NSButtonCell)?.imageDimsWhenDisabled == false
            && bar.playButton.contentTintColor == .labelColor
        bar.primaryActionTitle = "取消下载：固定来源"
        bar.playButton.performClick(nil)
        let cancelMetrics = apply(400)
        checks["pending-source-retains-its-original-cancel-command-and-description-after-resize"] =
            play == 2 && inspections == 2 && matchesSymbol(bar.playButton, name: "hourglass", metrics: cancelMetrics)
            && bar.playButton.accessibilityLabel() == "取消下载：固定来源" && bar.playButton.toolTip == "取消下载：固定来源"
        bar.primaryActionTitle = nil

        // Observe the actual CATextLayers and their rendered glyphs, rather
        // than assigning a second test-only color to the title.
        func textLayers(in layer: CALayer?) -> [CATextLayer] {
            guard let layer else { return [] }
            return (layer as? CATextLayer).map { [$0] } ?? (layer.sublayers ?? []).flatMap { textLayers(in: $0) }
        }
        func rgb(_ color: NSColor) -> [CGFloat]? {
            guard let resolved = color.usingColorSpace(.deviceRGB) else { return nil }
            return [resolved.redComponent, resolved.greenComponent, resolved.blueComponent, resolved.alphaComponent]
        }
        func expectedLabel() -> [CGFloat]? {
            var result: [CGFloat]?
            bar.titleView.effectiveAppearance.performAsCurrentDrawingAppearance { result = rgb(.labelColor) }
            return result
        }
        func textMatchesAppearance() -> Bool {
            let actual = textLayers(in: bar.titleView.layer)
            guard actual.count == 2, let expected = expectedLabel() else { return false }
            return actual.allSatisfy { layer in
                guard let color = layer.foregroundColor, let native = NSColor(cgColor: color), let actual = rgb(native) else { return false }
                return zip(actual, expected).allSatisfy { pair in abs(pair.0 - pair.1) <= 1 / 255 }
            }
        }
        func progressMatchesAppearance() -> Bool {
            let gradients = (bar.glass.layer?.sublayers ?? []).flatMap { $0.sublayers ?? [] }.compactMap { $0 as? CAGradientLayer }
            guard gradients.count == 1, let colors = gradients[0].colors as? [CGColor], colors.count == 3 else { return false }
            var expected: [[CGFloat]] = []
            bar.glass.effectiveAppearance.performAsCurrentDrawingAppearance {
                expected = [CGFloat(0.88), 0.72, 0.84].compactMap { rgb(NSColor.systemGreen.withAlphaComponent($0)) }
            }
            guard expected.count == 3 else { return false }
            return zip(colors, expected).allSatisfy { pair in
                guard let color = NSColor(cgColor: pair.0), let actual = rgb(color) else { return false }
                return zip(actual, pair.1).allSatisfy { abs($0.0 - $0.1) <= 1 / 255 }
            }
        }
        func hasReadableRenderedText(dark: Bool) -> Bool {
            guard let layer = bar.titleView.layer else { return false }
            let width = Int(ceil(bar.titleView.bounds.width * 2)), height = Int(ceil(bar.titleView.bounds.height * 2))
            guard width > 0, height > 0,
                  let pixels = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                  let data = pixels.data else { return false }
            let background: CGFloat = dark ? 0.1 : 1
            pixels.setFillColor(CGColor(gray: background, alpha: 1))
            pixels.fill(CGRect(x: 0, y: 0, width: width, height: height))
            pixels.scaleBy(x: 2, y: 2)
            layer.render(in: pixels)
            let bytes = data.assumingMemoryBound(to: UInt8.self)
            var readablePixels = 0
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * pixels.bytesPerRow + x * 4
                    let lightness = (CGFloat(bytes[offset]) + CGFloat(bytes[offset + 1]) + CGFloat(bytes[offset + 2])) / (3 * 255)
                    if dark ? lightness > 0.7 : lightness < 0.3 { readablePixels += 1 }
                }
            }
            return readablePixels > 20
        }
        func useAppearance(_ name: NSAppearance.Name) {
            window.appearance = NSAppearance(named: name)!
            RunLoop.main.run(until: Date().addingTimeInterval(0.06))
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
        }
        bar.primaryState = .apply
        bar.apply(title: "Readable 标题", metadata: "Unchanged metadata")
        _ = apply(320)
        bar.glass.applyProgress(style: .downloading, fraction: 0.35, indeterminate: false, animated: false)
        let appearanceMeasurements = WallpaperCardControlsProbe.widthMeasurements
        let appearanceSymbols = WallpaperCardControlsProbe.symbolConfigurations
        let appearanceImages = [bar.detailButton.image, bar.playButton.image]
        let appearanceFrames = [bar.detailButton.frame, bar.playButton.frame, bar.titleView.frame]
        useAppearance(.darkAqua)
        checks["dark-bar-title-uses-its-own-resolved-label-and-renders-readable-glyphs"] = textMatchesAppearance()
            && hasReadableRenderedText(dark: true)
        checks["dark-progress-gradient-resolves-semantic-green-in-the-glass-appearance"] = progressMatchesAppearance()
        useAppearance(.aqua)
        checks["warm-dark-to-light-switch-refreshes-real-text-layers-and-readable-glyphs"] = textMatchesAppearance()
            && hasReadableRenderedText(dark: false)
        checks["light-progress-gradient-refreshes-without-new-progress-input"] = progressMatchesAppearance()
        useAppearance(.darkAqua)
        checks["warm-light-to-dark-switch-restores-readable-title-without-reconfiguration"] = textMatchesAppearance()
            && hasReadableRenderedText(dark: true)
        checks["appearance-only-switches-preserve-font-width-cache-symbols-and-hit-geometry"] =
            WallpaperCardControlsProbe.widthMeasurements == appearanceMeasurements
            && WallpaperCardControlsProbe.symbolConfigurations == appearanceSymbols
            && bar.detailButton.image === appearanceImages[0] && bar.playButton.image === appearanceImages[1]
            && [bar.detailButton.frame, bar.playButton.frame, bar.titleView.frame] == appearanceFrames
        bar.playButton.isEnabled = false; bar.detailButton.isEnabled = false
        let beforeDisabled = (play, inspections)
        bar.playButton.performClick(nil); bar.detailButton.performClick(nil)
        _ = bar.playButton.accessibilityPerformPress(); _ = bar.detailButton.accessibilityPerformPress()
        checks["disabled-native-and-accessibility-presses-do-not-deliver-either-command"] =
            play == beforeDisabled.0 && inspections == beforeDisabled.1
        useAppearance(.aqua)
        checks["disabled-native-controls-remain-disabled-after-appearance-switch"] = !bar.playButton.isEnabled
            && !bar.detailButton.isEnabled && textMatchesAppearance() && hasReadableRenderedText(dark: false)
        let fixedColor = NSColor(calibratedRed: 0.1, green: 0.6, blue: 0.25, alpha: 1)
        bar.titleView.textColor = fixedColor
        useAppearance(.darkAqua)
        let fixedLayers = textLayers(in: bar.titleView.layer)
        checks["appearance-refresh-preserves-an-explicit-provider-title-color"] = fixedLayers.count == 2 && fixedLayers.allSatisfy { layer in
            guard let value = layer.foregroundColor, let color = NSColor(cgColor: value),
                  let actual = rgb(color), let expected = rgb(fixedColor) else { return false }
            return zip(actual, expected).allSatisfy { abs($0.0 - $0.1) <= 1 / 255 }
        }
        var coldTitle: WallpaperCardMarqueeTextView?
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance { coldTitle = WallpaperCardMarqueeTextView() }
        let cold = coldTitle!
        cold.appearance = NSAppearance(named: .aqua)
        cold.frame = NSRect(x: 20, y: 60, width: 260, height: 30)
        cold.text = "Cold light 标题"
        host.addSubview(cold)
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        cold.layoutSubtreeIfNeeded()
        let coldColors = textLayers(in: cold.layer).compactMap { $0.foregroundColor }.compactMap { NSColor(cgColor: $0) }.compactMap { rgb($0) }
        checks["cold-light-title-ignores-a-dark-construction-drawing-context"] = coldColors.count == 2
            && coldColors.allSatisfy { $0[0] < 0.3 && $0[1] < 0.3 && $0[2] < 0.3 && $0[3] > 0.7 }

        let footerKinds: [(String, InspectorFooterButtonKind)] = [("primary", .primary), ("secondary", .secondary), ("danger", .danger)]
        let footers = footerKinds.map { name, kind in
            let button = InspectorFooterButton(title: name, image: nil, kind: kind, target: nil, action: nil)
            button.frame = NSRect(x: 20, y: 0, width: 100, height: 38)
            host.addSubview(button)
            return button
        }
        func footerColorMatches(_ button: InspectorFooterButton, kind: InspectorFooterButtonKind, dark: Bool) -> Bool {
            let alpha: CGFloat = button.isEnabled ? 1 : 0.45
            var expected: [CGFloat]?
            button.effectiveAppearance.performAsCurrentDrawingAppearance {
                let color: NSColor
                switch kind {
                case .primary: color = NSColor.controlAccentColor.withAlphaComponent((dark ? 0.95 : 0.88) * alpha)
                case .secondary: color = NSColor.black.withAlphaComponent((dark ? 0.26 : 0.06) * alpha)
                case .danger: color = NSColor.systemRed.withAlphaComponent((dark ? 0.74 : 0.66) * alpha)
                }
                expected = rgb(color)
            }
            guard let cgColor = button.layer?.backgroundColor, let color = NSColor(cgColor: cgColor),
                  let actual = rgb(color), let expected else { return false }
            let matches = zip(actual, expected).allSatisfy { abs($0.0 - $0.1) <= 1 / 255 }
            FileHandle.standardError.write(Data("Footer \(kind) dark=\(dark) enabled=\(button.isEnabled) effective=\(button.effectiveAppearance.name.rawValue) actual=\(actual) expected=\(expected) match=\(matches)\n".utf8))
            return matches
        }
        for (appearance, dark) in [(NSAppearance.Name.aqua, false), (.darkAqua, true)] {
            useAppearance(appearance)
            for (index, entry) in footerKinds.enumerated() {
                let button = footers[index]
                // Native state changes may arrive while another view's drawing
                // appearance is current. The button still owns its layer colors.
                NSAppearance(named: dark ? .aqua : .darkAqua)!.performAsCurrentDrawingAppearance { button.isEnabled = true }
                checks["\(entry.0)-footer-\(dark ? "dark" : "light")-color-resolves-in-its-own-appearance"] = footerColorMatches(button, kind: entry.1, dark: dark)
                NSAppearance(named: dark ? .aqua : .darkAqua)!.performAsCurrentDrawingAppearance { button.isEnabled = false }
                checks["\(entry.0)-footer-\(dark ? "dark" : "light")-disabled-alpha-is-preserved"] = footerColorMatches(button, kind: entry.1, dark: dark)
            }
        }
        FileHandle.standardError.write(Data("Card appearance: textLayers=\(textLayers(in: bar.titleView.layer).count), coldColors=\(coldColors), measurements=\(appearanceMeasurements)->\(WallpaperCardControlsProbe.widthMeasurements), symbols=\(appearanceSymbols)->\(WallpaperCardControlsProbe.symbolConfigurations)\n".utf8))
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
