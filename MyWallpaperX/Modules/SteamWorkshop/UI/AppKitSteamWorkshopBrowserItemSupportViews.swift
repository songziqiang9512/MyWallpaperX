import AppKit
import QuartzCore

final class SteamWorkshopOverlayIconButton: NSButton {
    var normalBackgroundColor: NSColor = .clear {
        didSet { updateAppearance() }
    }
    var hoverBackgroundColor: NSColor = NSColor.white.withAlphaComponent(0.12) {
        didSet { updateAppearance() }
    }
    var pressedBackgroundColor: NSColor = NSColor.white.withAlphaComponent(0.18) {
        didSet { updateAppearance() }
    }
    var iconTintColor: NSColor = .labelColor {
        didSet { contentTintColor = iconTintColor }
    }
    var cornerRadius: CGFloat = 12 {
        didSet { layer?.cornerRadius = cornerRadius }
    }
    var borderColor: NSColor = .clear {
        didSet { layer?.borderColor = borderColor.cgColor }
    }
    var borderWidth: CGFloat = 0 {
        didSet { layer?.borderWidth = borderWidth }
    }

    private var isHovering = false {
        didSet { updateAppearance() }
    }
    private var isPressing = false {
        didSet { updateAppearance() }
    }
    private var trackingAreaRef: NSTrackingArea?

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
        isPressing = false
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            super.mouseDown(with: event)
            return
        }
        isPressing = true
        super.mouseDown(with: event)
        isPressing = false
    }

    private func commonInit() {
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        layer?.borderColor = borderColor.cgColor
        layer?.borderWidth = borderWidth
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        contentTintColor = iconTintColor
        updateAppearance()
    }

    private func updateAppearance() {
        let background: NSColor
        if !isEnabled {
            background = .clear
        } else if isPressing {
            background = pressedBackgroundColor
        } else if isHovering {
            background = hoverBackgroundColor
        } else {
            background = normalBackgroundColor
        }
        layer?.backgroundColor = background.cgColor
        contentTintColor = isEnabled ? iconTintColor : .disabledControlTextColor
        alphaValue = isEnabled ? 1 : 0.45
    }
}

final class SteamWorkshopMarqueeTextView: NSView {
    private let clippingView = NSView()
    private let containerLayer = CALayer()
    private let leadingTextLayer = CATextLayer()
    private let trailingTextLayer = CATextLayer()
    private let fadeMaskLayer = CAGradientLayer()
    private var displayText = ""
    private var marqueeSegmentWidth: CGFloat = 0
    private var isActive = false
    private var isPerformingLayout = false
    private let repeatedGap = "     "

    var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            updateDisplayedText()
        }
    }

    var font: NSFont = .systemFont(ofSize: 13, weight: .semibold) {
        didSet {
            updateTextLayerAppearance()
            updateDisplayedText()
        }
    }

    var textColor: NSColor = .labelColor {
        didSet {
            updateTextLayerAppearance()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override func layout() {
        super.layout()
        isPerformingLayout = true
        defer { isPerformingLayout = false }
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            clippingView.frame = .zero
            containerLayer.frame = .zero
            containerLayer.removeAnimation(forKey: "steam.marquee")
            return
        }
        clippingView.frame = bounds
        updateFadeMask()
        layoutTextLayers()
        updateAnimation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
    }

    func setActive(_ active: Bool) {
        if isActive == active {
            if active {
                updateAnimation()
            }
            return
        }
        isActive = active
        updateAnimation()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.mask = fadeMaskLayer

        clippingView.wantsLayer = true
        clippingView.layer?.backgroundColor = NSColor.clear.cgColor
        clippingView.layer?.masksToBounds = true
        addSubview(clippingView)

        clippingView.layer?.addSublayer(containerLayer)
        [leadingTextLayer, trailingTextLayer].forEach { layer in
            layer.alignmentMode = .left
            layer.isWrapped = false
            layer.truncationMode = .none
            layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            containerLayer.addSublayer(layer)
        }
        updateTextLayerAppearance()
    }

    private func updateDisplayedText() {
        displayText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        marqueeSegmentWidth = 0
        leadingTextLayer.string = displayText
        trailingTextLayer.string = displayText
        if !isPerformingLayout {
            needsLayout = true
        }
    }

    private func updateTextLayerAppearance() {
        let cgColor = textColor.cgColor
        let fontRef = font as CTFont
        [leadingTextLayer, trailingTextLayer].forEach { layer in
            layer.font = fontRef
            layer.fontSize = font.pointSize
            layer.foregroundColor = cgColor
        }
    }

    private func layoutTextLayers() {
        let height = max(0, bounds.height.isFinite ? bounds.height : 0)
        let textHeight = ceil(font.pointSize + 4)
        let y = floor((height - textHeight) * 0.5)
        let baseWidth = measuredWidth(for: displayText)
        if shouldScroll(baseWidth: baseWidth) {
            marqueeSegmentWidth = baseWidth + measuredWidth(for: repeatedGap)
            containerLayer.frame = CGRect(x: 0, y: y.isFinite ? y : 0, width: max(0, marqueeSegmentWidth + baseWidth), height: textHeight)
            leadingTextLayer.isHidden = false
            trailingTextLayer.isHidden = false
            leadingTextLayer.frame = CGRect(x: 0, y: 0, width: max(0, baseWidth), height: textHeight)
            trailingTextLayer.frame = CGRect(x: marqueeSegmentWidth, y: 0, width: max(0, baseWidth), height: textHeight)
        } else {
            marqueeSegmentWidth = 0
            let centeredX = floor((bounds.width - baseWidth) * 0.5)
            containerLayer.frame = CGRect(x: centeredX.isFinite ? centeredX : 0, y: y.isFinite ? y : 0, width: max(0, baseWidth), height: textHeight)
            leadingTextLayer.isHidden = false
            trailingTextLayer.isHidden = true
            leadingTextLayer.frame = CGRect(x: 0, y: 0, width: max(0, baseWidth), height: textHeight)
            trailingTextLayer.frame = .zero
        }
    }

    private func updateFadeMask() {
        fadeMaskLayer.frame = bounds
        fadeMaskLayer.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMaskLayer.endPoint = CGPoint(x: 1, y: 0.5)
        fadeMaskLayer.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fadeMaskLayer.locations = [0, 0.09, 0.91, 1]
    }

    private func updateAnimation() {
        containerLayer.removeAnimation(forKey: "steam.marquee")
        guard !displayText.isEmpty else { return }
        guard bounds.width.isFinite, bounds.height.isFinite else { return }

        let baseWidth = measuredWidth(for: displayText)
        guard shouldScroll(baseWidth: baseWidth),
              isActive,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            containerLayer.transform = CATransform3DIdentity
            CATransaction.commit()
            return
        }

        let travel = marqueeSegmentWidth > 0 ? marqueeSegmentWidth : (baseWidth + measuredWidth(for: repeatedGap))
        guard travel.isFinite, travel > 8 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        containerLayer.transform = CATransform3DIdentity
        CATransaction.commit()

        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = -travel
        animation.duration = max(7, Double(travel / 22))
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        containerLayer.add(animation, forKey: "steam.marquee")
    }

    private func shouldScroll(baseWidth: CGFloat) -> Bool {
        guard baseWidth.isFinite, bounds.width.isFinite else { return false }
        return baseWidth > max(24, bounds.width - 8)
    }

    private func measuredWidth(for text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let measured = (text as NSString).size(withAttributes: [.font: font]).width
        guard measured.isFinite else { return 0 }
        return ceil(measured)
    }
}

enum SteamWorkshopDownloadProgressPalette {
    enum Tone {
        case neutral
        case transfer
        case queued
        case waiting
        case failure
    }

    static func color(for tone: Tone, darkMode: Bool) -> NSColor {
        switch tone {
        case .neutral:
            return darkMode
                ? NSColor.white.withAlphaComponent(0.18)
                : NSColor.black.withAlphaComponent(0.10)
        case .transfer:
            return .systemGreen
        case .queued:
            return .systemBlue
        case .waiting:
            return .systemOrange
        case .failure:
            return .systemRed
        }
    }
}

final class SteamWorkshopGlassBarView: NSGlassEffectView {
    enum AccentStyle {
        case neutral
        case downloading
        case queued
        case waiting
        case failed
        case ready
    }

    private let glossLayer = CAGradientLayer()
    private let fillClipLayer = CALayer()
    private let fillLayer = CAGradientLayer()
    private var accentStyle: AccentStyle = .neutral
    private var progressFraction: CGFloat?
    private var showsIndeterminateProgress = false
    private var progressAnimationVisible = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor.clear.cgColor
        fillClipLayer.masksToBounds = true
        fillLayer.startPoint = CGPoint(x: 0, y: 0.5)
        fillLayer.endPoint = CGPoint(x: 1, y: 0.5)
        fillClipLayer.addSublayer(fillLayer)
        layer?.addSublayer(fillClipLayer)
        glossLayer.colors = [
            NSColor.white.withAlphaComponent(0.14).cgColor,
            NSColor.white.withAlphaComponent(0.04).cgColor,
            NSColor.clear.cgColor
        ]
        glossLayer.locations = [0.0, 0.12, 0.46]
        glossLayer.startPoint = CGPoint(x: 0.18, y: 0.98)
        glossLayer.endPoint = CGPoint(x: 0.82, y: 0.08)
        layer?.addSublayer(glossLayer)
        updateMaterial()
    }

    override func layout() {
        super.layout()
        glossLayer.frame = bounds
        updateProgressFrames(animated: false)
        updateProgressAnimation()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateMaterial()
    }

    private func updateMaterial() {
        let isDarkMode = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let tone: SteamWorkshopDownloadProgressPalette.Tone = {
            switch accentStyle {
            case .neutral, .ready: return .neutral
            case .downloading: return .transfer
            case .queued: return .queued
            case .waiting: return .waiting
            case .failed: return .failure
            }
        }()
        let accentBaseColor = SteamWorkshopDownloadProgressPalette.color(for: tone, darkMode: isDarkMode)
        let usesStatusFill = accentStyle != .neutral && accentStyle != .ready

        style = .regular
        tintColor = isDarkMode
            ? NSColor(calibratedWhite: 0.10, alpha: 0.82)
            : NSColor(calibratedWhite: 1.0, alpha: 0.72)

        layer?.backgroundColor = NSColor.clear.cgColor
        let neutral = SteamWorkshopDownloadProgressPalette.color(for: .neutral, darkMode: isDarkMode)
        layer?.borderColor = neutral.withAlphaComponent(isDarkMode ? 0.34 : 0.22).cgColor

        fillLayer.colors = [
            accentBaseColor.withAlphaComponent(usesStatusFill ? 0.88 : 0.34).cgColor,
            accentBaseColor.withAlphaComponent(usesStatusFill ? 0.72 : 0.18).cgColor,
            accentBaseColor.withAlphaComponent(usesStatusFill ? 0.84 : 0.08).cgColor
        ]
        fillLayer.locations = [0, 0.55, 1]

        glossLayer.isHidden = false
        updateProgressFrames(animated: false)
        updateProgressAnimation()
    }

    func applyProgress(
        style: AccentStyle,
        fraction: Double?,
        indeterminate: Bool,
        animated: Bool
    ) {
        accentStyle = style
        progressFraction = fraction.map { CGFloat(min(1, max(0, $0))) }
        showsIndeterminateProgress = indeterminate
        updateMaterial()
        updateProgressFrames(animated: animated)
        updateProgressAnimation()
    }

    func setProgressAnimationVisible(_ visible: Bool) {
        progressAnimationVisible = visible
        updateProgressAnimation()
    }

    private func updateProgressFrames(animated: Bool) {
        let width: CGFloat
        if let progressFraction {
            width = bounds.width * progressFraction
        } else if showsIndeterminateProgress {
            width = max(24, bounds.width * 0.24)
        } else if accentStyle == .queued || accentStyle == .waiting || accentStyle == .failed {
            width = min(10, bounds.width)
        } else {
            width = 0
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.18 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        fillClipLayer.frame = CGRect(x: 0, y: 0, width: max(0, width), height: bounds.height)
        fillClipLayer.cornerRadius = layer?.cornerRadius ?? 0
        fillLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        CATransaction.commit()
    }

    private func updateProgressAnimation() {
        fillClipLayer.removeAnimation(forKey: "steam.bar.indeterminate")
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard showsIndeterminateProgress,
              progressAnimationVisible,
              !reduceMotion,
              bounds.width > fillClipLayer.bounds.width else { return }
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = -fillClipLayer.bounds.width
        animation.toValue = bounds.width
        animation.duration = 1.45
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = false
        fillClipLayer.add(animation, forKey: "steam.bar.indeterminate")
    }
}
