import AppKit

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
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
