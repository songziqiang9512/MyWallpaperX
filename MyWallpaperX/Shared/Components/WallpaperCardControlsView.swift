import AppKit
import QuartzCore

/// Presentation only. The source adapter supplies current state and commands;
/// this view does not resolve identities, select items or write user data.
final class WallpaperCardControlsView: NSView {
    enum PrimaryState { case apply, switching, playing, applied, download }

    let glass = WallpaperCardGlassBarView()
    let titleView = WallpaperCardMarqueeTextView()
    let favoriteButton = NSButton()
    let playButton = NSButton()
    var onPlay: (() -> Void)?
    var onFavorite: (() -> Void)?
    var primaryState: PrimaryState = .apply { didSet { if oldValue != primaryState { updateSymbols() } } }
    var isFavorite = false { didSet { if oldValue != isFavorite { updateSymbols() } } }
    private var metrics = WallpaperCardBarMetrics(cardWidth: 250)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 20
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        addSubview(glass)
        for button in [favoriteButton, playButton] {
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.focusRingType = .none
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            glass.addSubview(button)
        }
        glass.addSubview(titleView)
        favoriteButton.target = self
        favoriteButton.action = #selector(toggleFavorite)
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
        favoriteButton.frame = NSRect(x: metrics.barEdgeInset, y: y, width: size, height: size)
        playButton.frame = NSRect(x: bounds.width - size - metrics.barEdgeInset, y: y, width: size, height: size)
        let x = favoriteButton.frame.maxX + metrics.barSpacing + metrics.marqueeSideInset
        titleView.frame = NSRect(x: x, y: 0,
            width: max(0, playButton.frame.minX - metrics.barSpacing - metrics.marqueeSideInset - x), height: bounds.height)
    }

    private func updateSymbols() {
        let configuration = NSImage.SymbolConfiguration(pointSize: max(11, metrics.iconButtonSize * 0.56), weight: .medium)
        let favoriteTitle = isFavorite ? "取消特别喜爱" : "特别喜爱"
        favoriteButton.image = NSImage(systemSymbolName: isFavorite ? "heart.fill" : "heart",
            accessibilityDescription: favoriteTitle)?.withSymbolConfiguration(configuration)
        favoriteButton.contentTintColor = isFavorite ? .controlAccentColor : .labelColor
        favoriteButton.toolTip = favoriteTitle
        favoriteButton.setAccessibilityLabel(favoriteTitle)
        let playTitle: String
        let playSymbol: String
        let playColor: NSColor
        switch primaryState {
        case .apply:
            playTitle = "设为壁纸"; playSymbol = "play.fill"; playColor = .labelColor
        case .playing:
            playTitle = "停止播放"; playSymbol = "stop.fill"; playColor = .controlAccentColor
        case .switching:
            playTitle = "正在切换壁纸"; playSymbol = "hourglass"; playColor = .labelColor
        case .applied:
            playTitle = "已应用，点按重新应用"; playSymbol = "checkmark"; playColor = .controlAccentColor
        case .download:
            playTitle = "下载原图"; playSymbol = "arrow.down"; playColor = .labelColor
        }
        playButton.image = NSImage(systemSymbolName: playSymbol,
            accessibilityDescription: playTitle)?.withSymbolConfiguration(configuration)
        playButton.contentTintColor = playColor
        playButton.toolTip = playTitle
        playButton.setAccessibilityLabel(playTitle)
    }

    @objc private func play() { onPlay?() }
    @objc private func toggleFavorite() { onFavorite?() }
}
