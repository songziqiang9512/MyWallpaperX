import AppKit

/// Content only: NSPopover supplies the system Liquid Glass surface. An extra
/// visual-effect background would obscure it and create a second material pass.
final class StatusBarPanelView: NSView {
    override var isFlipped: Bool { true }
    let cover = StatusBarPanelCoverView()
    let openMain = StatusBarPanelSymbolButton(symbol: "house", help: "打开主界面", size: 18)
    let previous = StatusBarPanelSymbolButton(symbol: "backward.end.fill", help: "上一张壁纸", size: 18)
    let playback = StatusBarPanelSymbolButton(symbol: "pause.fill", help: "暂停壁纸", surface: .primary, size: 18)
    let next = StatusBarPanelSymbolButton(symbol: "forward.end.fill", help: "下一张壁纸", size: 18)
    let mute = StatusBarPanelSymbolButton(symbol: "speaker.wave.2.fill", help: "壁纸静音", size: 16)
    let quit = StatusBarPanelSymbolButton(symbol: "power", help: "退出 MyWallpaperX", surface: .subtle, size: 12)
    let mode = StatusBarPanelSymbolButton(symbol: "repeat.1", help: "播放方式", size: 16)
    let compactProperties = StatusBarPanelSymbolButton(symbol: "paintbrush", help: "属性调节", size: 16)
    let settings = NSButton(title: "打开设置", target: nil, action: nil)
    let volume = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
    let titleLabel = NSTextField(labelWithString: "")
    let statusLabel = NSTextField(labelWithString: "")
    private let appLabel = NSTextField(labelWithString: "MyWallpaperX")
    private let volumeLabel = NSTextField(labelWithString: "50%")
    private let metricTitles = ["CPU", "GPU", "内存"].map { NSTextField(labelWithString: $0) }
    private let metricValues = (0..<3).map { _ in NSTextField(labelWithString: "—") }
    private let upload = NSTextField(labelWithString: "")
    private let download = NSTextField(labelWithString: "")
    private let separators = (0..<2).map { _ in NSBox() }
    private let metricDividers = (0..<2).map { _ in NSBox() }
    private let networkDivider = NSBox()
    private var hasPlaybackControls = true
    private var hasVolumeControls = true
    private var hasProperties = false
    private var emptyContent = false
    private var greetingSelectedAt: ContinuousClock.Instant?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        appLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        appLabel.lineBreakMode = .byTruncatingTail
        appLabel.setAccessibilityIdentifier("status-panel-greeting")
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setAccessibilityIdentifier("status-panel-title")
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setAccessibilityIdentifier("status-panel-state")
        volumeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        volumeLabel.textColor = .secondaryLabelColor
        volumeLabel.alignment = .right
        quit.title = "退出"
        quit.font = .systemFont(ofSize: 12)
        quit.attributedTitle = NSAttributedString(string: "退出", attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor
        ])
        quit.imagePosition = .imageLeading
        quit.imageHugsTitle = true
        volume.isContinuous = true
        volume.controlSize = .small
        volume.setAccessibilityLabel("壁纸音量")
        volume.setAccessibilityIdentifier("status-panel-volume")
        settings.isBordered = false
        settings.bezelStyle = .regularSquare
        settings.font = .systemFont(ofSize: 12)
        settings.alignment = .left
        settings.attributedTitle = NSAttributedString(string: "打开设置", attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor
        ])
        settings.contentTintColor = .labelColor
        settings.image = NSImage(systemSymbolName: "arrow.up.forward.square", accessibilityDescription: nil)
        settings.imagePosition = .imageLeading
        settings.imageHugsTitle = true
        settings.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        settings.setAccessibilityLabel("打开设置")
        for label in metricTitles {
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
        }
        for (index, label) in metricValues.enumerated() {
            label.font = .monospacedDigitSystemFont(ofSize: index == 2 ? 14 : 16, weight: .semibold)
            label.lineBreakMode = .byTruncatingTail
        }
        for label in [upload, download] { label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium) }
        for separator in separators + metricDividers + [networkDivider] { separator.boxType = .separator }
        for child in [appLabel, openMain, cover, titleLabel, statusLabel, mode, compactProperties,
                      previous, playback, next, mute, volume, volumeLabel] + metricTitles + metricValues
                      + [upload, download, networkDivider] + separators + metricDividers
                      + [settings, quit] { addSubview(child) }
    }

    required init?(coder: NSCoder) { nil }

    /// Refresh only when opening, at most once an hour. Metrics and playback
    /// updates never change this greeting, and a closed panel does no work.
    func prepareForPresentation(at date: Date = Date(), calendar: Calendar = .current,
                                instant: ContinuousClock.Instant = .now) {
        if let selectedAt = greetingSelectedAt,
           instant < selectedAt.advanced(by: .seconds(3600)) { return }
        let messages: [String]
        switch calendar.component(.hour, from: date) {
        case 5..<8: messages = ["早安又是新一天", "把晨光带进桌面"]
        case 8..<12: messages = ["今天也有好风景", "给今天一点新鲜感"]
        case 12..<14: messages = ["歇一会儿看看风景", "留片刻给好心情"]
        case 14..<18: messages = ["午后适合换个风景", "偶尔走神也不错"]
        case 18..<23: messages = ["把晚风留在桌面", "今晚就慢一点吧"]
        default: messages = ["留一盏温柔的光", "让喜欢的画面陪你"]
        }
        let authorPrompt = "给作者点个星标吧"
        if appLabel.stringValue != authorPrompt && Int.random(in: 0..<10) == 0 {
            appLabel.stringValue = authorPrompt
        } else {
            let candidates = messages.filter { $0 != appLabel.stringValue }
            appLabel.stringValue = candidates.randomElement() ?? messages[0]
        }
        appLabel.toolTip = appLabel.stringValue
        greetingSelectedAt = instant
    }

    func apply(_ presentation: StatusBarPanelPresentation) {
        hasPlaybackControls = presentation.hasPlaybackControls
        hasVolumeControls = presentation.content.isDynamic
        emptyContent = presentation.content == .none
        titleLabel.stringValue = presentation.content.title
        titleLabel.toolTip = presentation.content.title
        statusLabel.stringValue = presentation.status
        statusLabel.toolTip = presentation.status
        hasProperties = presentation.content.hasProperties && !presentation.isStandby
        mode.isHidden = presentation.playbackMode == nil
        mode.image = NSImage(systemSymbolName: presentation.modeSymbol, accessibilityDescription: nil)
        mode.toolTip = presentation.modeHelp
        mode.setAccessibilityLabel(presentation.modeHelp)
        previous.isEnabled = presentation.canNavigate
        next.isEnabled = presentation.canNavigate
        playback.isEnabled = presentation.canTogglePlayback
        playback.image = NSImage(systemSymbolName: !presentation.isStandby && !presentation.isUserPaused ? "pause.fill" : "play.fill", accessibilityDescription: nil)
        playback.toolTip = presentation.playbackHelp
        playback.setAccessibilityLabel(presentation.playbackHelp)
        mute.image = NSImage(systemSymbolName: presentation.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", accessibilityDescription: nil)
        let muteHelp = presentation.isMuted ? "取消壁纸静音" : "壁纸静音"
        mute.toolTip = muteHelp
        mute.setAccessibilityLabel(muteHelp)
        mute.setAccessibilityValue(presentation.isMuted ? "已静音" : "未静音")
        // The volume is preserved behind the independent mute gate.
        volume.doubleValue = presentation.displayedVolume
        volumeLabel.stringValue = "\(Int(presentation.displayedVolume.rounded()))%"
        playback.isHidden = !hasPlaybackControls
        for control in [mute, volume, volumeLabel] { control.isHidden = !hasVolumeControls }
        previous.isHidden = emptyContent
        next.isHidden = emptyContent
        for button in [openMain, settings, previous, playback, next, mute, quit, mode, compactProperties] { button.needsDisplay = true }
        needsLayout = true
    }

    func applyMetrics(_ stats: SystemStats) {
        metricValues[0].stringValue = stats.cpuUsageString
        metricValues[1].stringValue = stats.gpuUsageString
        let gb = Double(stats.memUsed) / 1_073_741_824
        let total = Double(stats.memTotal) / 1_073_741_824
        metricValues[2].stringValue = String(format: "%.1f / %.0f GB", gb, total)
        metricValues[2].toolTip = "系统内存：\(stats.memUsedString) / \(stats.memTotalString)"
        upload.stringValue = "↑  \(stats.netUpString)"
        download.stringValue = "↓  \(stats.netDownString)"
        download.alignment = .right
        upload.setAccessibilityLabel("系统上传速度 \(stats.netUpString)")
        download.setAccessibilityLabel("系统下载速度 \(stats.netDownString)")
    }

    override func layout() {
        super.layout()
        let width = bounds.width - 32
        let coverHeight = emptyContent ? 44 : max(0, bounds.height - (hasPlaybackControls ? (hasVolumeControls ? 360 : 324) : 272))
        cover.properties.isHidden = !hasProperties || coverHeight < 44
        compactProperties.isHidden = !hasProperties || coverHeight >= 44
        appLabel.frame = NSRect(x: 20, y: 14, width: width - 44, height: 22)
        openMain.frame = NSRect(x: bounds.width - 48, y: 12, width: 28, height: 28)
        cover.frame = emptyContent ? NSRect(x: 20, y: 60, width: 44, height: 44)
            : NSRect(x: 16, y: 52, width: width, height: coverHeight)
        let titleY: CGFloat = emptyContent ? 62 : 64 + coverHeight
        let textX: CGFloat = emptyContent ? 80 : 20
        let accessoryWidth = CGFloat((mode.isHidden ? 0 : 40) + (compactProperties.isHidden ? 0 : 40))
        titleLabel.frame = NSRect(x: textX, y: titleY, width: bounds.width - textX - 20 - accessoryWidth, height: 20)
        statusLabel.frame = NSRect(x: textX, y: titleY + 24, width: bounds.width - textX - 20 - accessoryWidth, height: 16)
        mode.frame = NSRect(x: bounds.width - 52, y: titleY + 4, width: 32, height: 32)
        compactProperties.frame = mode.frame
        if !mode.isHidden { compactProperties.frame.origin.x -= 40 }
        let center = bounds.midX
        let controlsY = titleY + 52
        previous.frame = NSRect(x: hasPlaybackControls ? center - 82 : bounds.width - 92, y: hasPlaybackControls ? controlsY + 4 : titleY + 22, width: 32, height: hasPlaybackControls ? 32 : 28)
        playback.frame = NSRect(x: center - 22, y: controlsY - 2, width: 44, height: 44)
        next.frame = NSRect(x: hasPlaybackControls ? center + 50 : bounds.width - 52, y: hasPlaybackControls ? controlsY + 4 : titleY + 22, width: 32, height: hasPlaybackControls ? 32 : 28)
        if !hasPlaybackControls && !emptyContent { statusLabel.frame.size.width = max(0, width - 92) }
        let volumeY = controlsY + 52
        mute.frame = NSRect(x: 16, y: volumeY - 2, width: 28, height: 28)
        volume.frame = NSRect(x: 56, y: volumeY, width: width - 104, height: 24)
        volumeLabel.frame = NSRect(x: bounds.width - 56, y: volumeY + 4, width: 36, height: 16)
        let dividerY: CGFloat = emptyContent ? 124 : hasPlaybackControls ? controlsY + (hasVolumeControls ? 88 : 52) : titleY + 52
        separators[0].frame = NSRect(x: 16, y: dividerY, width: width, height: 1)
        let columns: [(CGFloat, CGFloat)] = [(20, 72), (112, 72), (204, width - 192)]
        for (index, column) in columns.enumerated() {
            metricTitles[index].frame = NSRect(x: column.0, y: dividerY + 12, width: column.1, height: 14)
            metricValues[index].frame = NSRect(x: column.0, y: dividerY + 29, width: column.1, height: 24)
        }
        for (index, divider) in metricDividers.enumerated() {
            divider.frame = NSRect(x: CGFloat(100 + index * 92), y: dividerY + 14, width: 1, height: 32)
        }
        networkDivider.frame = NSRect(x: 16, y: dividerY + 59, width: width, height: 1)
        upload.frame = NSRect(x: 20, y: dividerY + 75, width: width / 2 - 8, height: 20)
        download.frame = NSRect(x: bounds.midX + 4, y: dividerY + 75, width: width / 2 - 8, height: 20)
        separators[1].frame = NSRect(x: 16, y: dividerY + 105, width: width, height: 1)
        settings.frame = NSRect(x: 20, y: dividerY + 115, width: 128, height: 28)
        quit.frame = NSRect(x: bounds.width - 96, y: dividerY + 115, width: 76, height: 28)
    }
}
