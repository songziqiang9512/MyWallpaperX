import AppKit

final class SteamWorkshopPreviewPlaceholderView: NSView {
    enum State {
        case hidden
        case loading
        case retrying
        case unavailable
    }

    private let backgroundView = NSView()
    private let spinner = NSProgressIndicator()
    private let titleLabel = NSTextField(labelWithString: "")
    private var currentState: State?

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
        backgroundView.frame = bounds

        let spinnerSize: CGFloat = 18
        let spacing: CGFloat = 8
        let titleHeight: CGFloat = 16
        let totalHeight = spinnerSize + spacing + titleHeight
        let originY = floor((bounds.height - totalHeight) * 0.5)

        spinner.frame = CGRect(
            x: floor((bounds.width - spinnerSize) * 0.5),
            y: max(0, originY),
            width: spinnerSize,
            height: spinnerSize
        )
        titleLabel.frame = CGRect(
            x: 12,
            y: spinner.frame.maxY + spacing,
            width: max(0, bounds.width - 24),
            height: titleHeight
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshBackgroundColor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshBackgroundColor()
    }

    private func refreshBackgroundColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            backgroundView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.72).cgColor
        }
    }

    func setState(_ state: State) {
        guard state != currentState else { return }
        currentState = state

        switch state {
        case .hidden:
            isHidden = true
            spinner.stopAnimation(nil)
            titleLabel.stringValue = ""
        case .loading:
            isHidden = false
            spinner.isHidden = false
            spinner.startAnimation(nil)
            titleLabel.stringValue = "缩略图加载中"
        case .retrying:
            isHidden = false
            spinner.isHidden = false
            spinner.startAnimation(nil)
            titleLabel.stringValue = "正在重试加载"
        case .unavailable:
            isHidden = false
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            titleLabel.stringValue = "暂无缩略图"
        }
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        backgroundView.wantsLayer = true
        refreshBackgroundColor()
        addSubview(backgroundView)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        addSubview(spinner)

        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.backgroundColor = .clear
        addSubview(titleLabel)

        setState(.hidden)
    }
}
