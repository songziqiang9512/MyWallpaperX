import AppKit
import QuartzCore

/// Presentation only. The source adapter supplies current state and commands;
/// this view does not resolve identities, select items or write user data.
final class WallpaperCardControlsView: NSView {
    enum PrimaryState { case apply, switching, playing, download }

    let glass = WallpaperCardGlassBarView()
    let titleView = WallpaperCardMarqueeTextView()
    let detailButton = NSButton()
    let playButton = NSButton()
    var onPlay: (() -> Void)?
    var onInspect: (() -> Void)? {
        didSet { detailButton.isEnabled = onInspect != nil }
    }
    var primaryState: PrimaryState = .apply { didSet { if oldValue != primaryState { updateSymbols() } } }
    /// Sources can name an existing action such as cancelling a pending transfer.
    var primaryActionTitle: String? { didSet { if oldValue != primaryActionTitle { updateActionDescription() } } }
    private var metrics = WallpaperCardBarMetrics(cardWidth: 250)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 20
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        addSubview(glass)
        for button in [detailButton, playButton] {
            button.title = ""
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.focusRingType = .none
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            glass.addSubview(button)
        }
        (playButton.cell as? NSButtonCell)?.imageDimsWhenDisabled = false
        glass.addSubview(titleView)
        detailButton.target = self
        detailButton.action = #selector(inspect)
        detailButton.isEnabled = false
        playButton.target = self
        playButton.action = #selector(play)
        updateSymbols()
    }

    required init?(coder: NSCoder) { nil }

    func apply(title: String, metadata: String) {
        titleView.text = title
        toolTip = nil
        titleView.toolTip = nil
        titleView.setAccessibilityLabel(title)
        titleView.setAccessibilityHelp(metadata.isEmpty ? nil : metadata)
    }

    func apply(metrics: WallpaperCardBarMetrics) {
        let symbolsChanged = self.metrics.iconButtonSize != metrics.iconButtonSize
        self.metrics = metrics
        titleView.font = metrics.titleFont
        if symbolsChanged { updateSymbols() }
        needsLayout = true
    }

    func setActive(_ active: Bool) {
        titleView.setActive(active)
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
        let radius = max(8, min(14, floor((metrics.barHeight - 4) * 0.5)))
        glass.layer?.cornerRadius = radius
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let size = metrics.iconButtonSize
        let y = floor((bounds.height - size) * 0.5)
        detailButton.frame = NSRect(x: metrics.barEdgeInset, y: y, width: size, height: size)
        playButton.frame = NSRect(x: bounds.width - size - metrics.barEdgeInset, y: y, width: size, height: size)
        let x = detailButton.frame.maxX + metrics.barSpacing + metrics.marqueeSideInset
        titleView.frame = NSRect(x: x, y: 0,
            width: max(0, playButton.frame.minX - metrics.barSpacing - metrics.marqueeSideInset - x), height: bounds.height)
    }

    private func updateSymbols() {
        let configuration = NSImage.SymbolConfiguration(pointSize: max(11, metrics.iconButtonSize * 0.56), weight: .medium)
        detailButton.image = NSImage(systemSymbolName: "exclamationmark.circle",
            accessibilityDescription: "详细信息")?.withSymbolConfiguration(configuration)
        detailButton.contentTintColor = .labelColor
        detailButton.toolTip = "详细信息"
        detailButton.setAccessibilityLabel("详细信息")
        let playSymbol: String
        let playColor: NSColor
        switch primaryState {
        case .apply:
            playSymbol = "play.fill"; playColor = .labelColor
        case .playing:
            playSymbol = "stop.fill"; playColor = .controlAccentColor
        case .switching:
            playSymbol = "hourglass"; playColor = .labelColor
        case .download:
            playSymbol = "square.and.arrow.down"; playColor = .labelColor
        }
        playButton.image = NSImage(systemSymbolName: playSymbol,
            accessibilityDescription: primaryTitle)?.withSymbolConfiguration(configuration)
        playButton.contentTintColor = playColor
        updateActionDescription()
    }

    private var primaryTitle: String {
        if let primaryActionTitle { return primaryActionTitle }
        switch primaryState {
        case .apply: return "设为壁纸"
        case .switching: return "正在切换壁纸"
        case .playing: return "停止播放"
        case .download: return "下载壁纸"
        }
    }

    private func updateActionDescription() {
        playButton.toolTip = primaryTitle
        playButton.setAccessibilityLabel(primaryTitle)
    }

    @objc private func play() { onPlay?() }
    @objc private func inspect() { onInspect?() }
}
