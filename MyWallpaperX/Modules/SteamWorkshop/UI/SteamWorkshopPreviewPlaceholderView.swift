import AppKit

final class SteamWorkshopPreviewPlaceholderView: NSView {
    enum State {
        case hidden
        case loading
        case retrying
        case unavailable
    }

    private let backgroundView = NSView()
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

        titleLabel.frame = NSRect(x: 12, y: floor((bounds.height - 16) * 0.5),
            width: max(0, bounds.width - 24), height: 16)
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
            titleLabel.stringValue = ""
        case .loading:
            isHidden = false
            titleLabel.stringValue = "加载中"
        case .retrying:
            isHidden = false
            titleLabel.stringValue = "加载中"
        case .unavailable:
            isHidden = false
            titleLabel.stringValue = "暂无缩略图"
        }
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        backgroundView.wantsLayer = true
        refreshBackgroundColor()
        addSubview(backgroundView)

        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.backgroundColor = .clear
        addSubview(titleLabel)

        setState(.hidden)
    }
}
