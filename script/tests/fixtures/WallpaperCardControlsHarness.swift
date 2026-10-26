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
        let initialHeart = bar.favoriteButton.image, initialPlay = bar.playButton.image
        let initialFrames = [bar.favoriteButton.frame, bar.playButton.frame, bar.titleView.frame]
        for _ in 0..<20 { _ = apply(250) }
        checks["identical-metrics-do-not-remeasure-text-or-rebuild-symbols"] = WallpaperCardControlsProbe.widthMeasurements == initialMeasurements
            && initialSymbols > 0 && WallpaperCardControlsProbe.symbolConfigurations == initialSymbols
            && bar.favoriteButton.image === initialHeart && bar.playButton.image === initialPlay
            && [bar.favoriteButton.frame, bar.playButton.frame, bar.titleView.frame] == initialFrames
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
            && bar.favoriteButton.image === initialHeart && bar.playButton.image === initialPlay
        let narrow = apply(150)
        let configuration = NSImage.SymbolConfiguration(pointSize: max(11, narrow.iconButtonSize * 0.56), weight: .medium)
        let expectedPlay = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)!.withSymbolConfiguration(configuration)!
        checks["real-icon-size-change-updates-symbol-configuration-and-native-hit-frames"] = bar.playButton.image?.size == expectedPlay.size
            && WallpaperCardControlsProbe.symbolConfigurations == initialSymbols + 1
            && bar.playButton.frame.width == narrow.iconButtonSize && bar.favoriteButton.frame.width == narrow.iconButtonSize
            && bar.playButton.image !== initialPlay
        bar.isFavorite = true
        bar.primaryState = .playing
        let heart = bar.favoriteButton.image, stop = bar.playButton.image
        checks["state-changes-still-update-symbols-and-accessible-actions"] = bar.favoriteButton.accessibilityLabel() == "取消特别喜爱"
            && bar.playButton.accessibilityLabel() == "停止播放" && bar.playButton.contentTintColor == .controlAccentColor
            && WallpaperCardControlsProbe.symbolConfigurations == initialSymbols + 3
        _ = apply(150)
        checks["same-metrics-retain-the-current-favorite-and-stop-symbols"] = bar.favoriteButton.image === heart && bar.playButton.image === stop
            && WallpaperCardControlsProbe.symbolConfigurations == initialSymbols + 3
        _ = apply(400)
        let clampedMeasurements = WallpaperCardControlsProbe.widthMeasurements
        let clampedSymbols = WallpaperCardControlsProbe.symbolConfigurations
        let clampedHeart = bar.favoriteButton.image, clampedStop = bar.playButton.image
        _ = apply(430)
        checks["different-widths-with-equal-clamped-metrics-reuse-font-measurements-and-symbols"] = WallpaperCardControlsProbe.widthMeasurements == clampedMeasurements
            && WallpaperCardControlsProbe.symbolConfigurations == clampedSymbols
            && bar.favoriteButton.image === clampedHeart && bar.playButton.image === clampedStop
        var play = 0, favorite = 0
        bar.onPlay = { play += 1 }; bar.onFavorite = { favorite += 1 }
        bar.playButton.performClick(nil); bar.favoriteButton.performClick(nil)
        checks["original-native-button-targets-deliver-each-command-once"] = play == 1 && favorite == 1
            && bar.playButton.target === bar && bar.favoriteButton.target === bar

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
        bar.isFavorite = false; bar.primaryState = .apply
        bar.apply(title: "Readable 标题", metadata: "Unchanged metadata")
        _ = apply(320)
        bar.glass.applyProgress(style: .downloading, fraction: 0.35, indeterminate: false, animated: false)
        let appearanceMeasurements = WallpaperCardControlsProbe.widthMeasurements
        let appearanceSymbols = WallpaperCardControlsProbe.symbolConfigurations
        let appearanceImages = [bar.favoriteButton.image, bar.playButton.image]
        let appearanceFrames = [bar.favoriteButton.frame, bar.playButton.frame, bar.titleView.frame]
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
            && bar.favoriteButton.image === appearanceImages[0] && bar.playButton.image === appearanceImages[1]
            && [bar.favoriteButton.frame, bar.playButton.frame, bar.titleView.frame] == appearanceFrames
        bar.playButton.isEnabled = false; bar.favoriteButton.isEnabled = false
        useAppearance(.aqua)
        checks["disabled-native-controls-remain-disabled-after-appearance-switch"] = !bar.playButton.isEnabled
            && !bar.favoriteButton.isEnabled && textMatchesAppearance() && hasReadableRenderedText(dark: false)
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
