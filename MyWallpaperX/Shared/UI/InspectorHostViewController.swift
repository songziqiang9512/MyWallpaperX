//
//  InspectorHostViewController.swift
//  MyWallpaperX
//

import AppKit

final class InspectorHostViewController: NSViewController {
    /// Total vertical space around the detail card within its host's safe area.
    static let cardVerticalInset: CGFloat = 36
    private let store: InspectorHostStore
    private let cardView = InspectorHostCardView()
    private var cardWidthConstraint: NSLayoutConstraint?
    private var cardHeightConstraint: NSLayoutConstraint?

    init(store: InspectorHostStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
        store.onChange = { [weak self] in
            self?.applyStoreState()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = InspectorHostRootView(cardView: cardView)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        let widthConstraint = cardView.widthAnchor.constraint(
            equalToConstant: InspectorHostRequest.defaultPreferredWidth
        )
        cardWidthConstraint = widthConstraint
        let safeArea = view.safeAreaLayoutGuide
        let heightConstraint = cardView.heightAnchor.constraint(equalTo: safeArea.heightAnchor, constant: -Self.cardVerticalInset)
        heightConstraint.priority = .defaultHigh
        cardHeightConstraint = heightConstraint

        let centerYConstraint = cardView.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor)
        centerYConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(greaterThanOrEqualTo: safeArea.topAnchor),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            cardView.bottomAnchor.constraint(lessThanOrEqualTo: safeArea.bottomAnchor, constant: -18),
            centerYConstraint,
            heightConstraint,
            widthConstraint
        ])

        applyStoreState()
    }

    private func applyStoreState() {
        guard isViewLoaded else { return }
        guard let request = store.currentRequest else {
            cardView.isHidden = true
            cardView.configure(request: nil, hostedContentView: nil)
            return
        }

        cardWidthConstraint?.constant = request.preferredWidth
        cardHeightConstraint?.constant = -Self.cardVerticalInset
        cardView.isHidden = false
        cardView.configure(request: request, hostedContentView: store.hostedContentView)
    }
}

private final class InspectorHostRootView: NSView {
    private weak var cardView: NSView?

    init(cardView: NSView) {
        self.cardView = cardView
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        if let cardView {
            let point = convert(event.locationInWindow, from: nil)
            if cardView.frame.contains(point) {
                return
            }
        }
        NotificationCenter.default.post(name: .inspectorHostCloseRequested, object: nil)
    }
}

final class InspectorHostCardView: NSView {
    var stretchesHostedContent = false {
        didSet { stackView.distribution = stretchesHostedContent ? .fill : .gravityAreas }
    }
    var onClose: (() -> Void)?
    var headerTitleOverride: String?
    /// Standalone windows use AppKit's shadow; embedded cards draw their own.
    var drawsShadow = true
    private let clippedContent = WallpaperPanelSurface(cornerRadius: 22)
    var compactHeader = false
    private var centeredHeaderConstraint: NSLayoutConstraint?
    private var iconWidthConstraint: NSLayoutConstraint?
    private let headerSpacer = NSView()
    private let stackView = NSStackView()
    private let headerRow = NSStackView()
    private let titleContainer = NSStackView()
    private let iconView = NSImageView()
    private let infoTitleLabel = NSTextField(labelWithString: "详情")
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let closeButton = WallpaperPanelCloseButton()
    private let contentContainer = InspectorHostedContentContainerView()
    private let progressIndicator = NSProgressIndicator()
    private var request: InspectorHostRequest?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(request: InspectorHostRequest?, hostedContentView: NSView?) {
        self.request = request
        guard let request else {
            contentContainer.hostedContentView = nil
            progressIndicator.stopAnimation(nil)
            return
        }

        let isInfoPanel = request.chromeStyle == .infoPanel
        stackView.spacing = compactHeader ? 8 : 14
        stackView.edgeInsets.top = 18
        infoTitleLabel.stringValue = headerTitleOverride ?? "详情"
        centeredHeaderConstraint?.isActive = headerTitleOverride != nil
        iconWidthConstraint?.constant = headerTitleOverride == nil ? 18 : 32
        headerSpacer.isHidden = headerTitleOverride != nil
        infoTitleLabel.alignment = headerTitleOverride == nil ? .left : .center
        titleLabel.stringValue = request.title
        subtitleLabel.stringValue = request.subtitle ?? ""
        subtitleLabel.isHidden = subtitleLabel.stringValue.isEmpty
        iconView.isHidden = !isInfoPanel
        infoTitleLabel.isHidden = !isInfoPanel
        titleContainer.isHidden = isInfoPanel

        let closeSymbolName = isInfoPanel ? "xmark" : "xmark.circle.fill"
        closeButton.image = NSImage(systemSymbolName: closeSymbolName, accessibilityDescription: "关闭详情")
        closeButton.toolTip = "关闭详情"

        contentContainer.hostedContentView = hostedContentView
        progressIndicator.isHidden = hostedContentView != nil
        hostedContentView == nil ? progressIndicator.startAnimation(nil) : progressIndicator.stopAnimation(nil)
        refreshAppearance()
        // New source children enter the already visible card at its actual
        // width, rather than painting once with their zero-size initial frame.
        superview?.layoutSubtreeIfNeeded()
        layoutSubtreeIfNeeded()
    }

    func refreshAppearance() {
        guard isViewLoadedInWindow || window != nil || superview != nil else { return }
        layer?.shadowColor = NSColor.black.cgColor
        // Embedded inspectors cannot receive a WindowServer shadow. Approximate
        // its neutral, compact falloff without changing density between themes.
        layer?.shadowOpacity = drawsShadow ? 0.24 : 0
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -9)

        infoTitleLabel.textColor = .labelColor
        titleLabel.textColor = .labelColor
        subtitleLabel.textColor = .secondaryLabelColor
        iconView.contentTintColor = .labelColor

        let infoPanel = request?.chromeStyle == .infoPanel
        closeButton.showsBackground = infoPanel
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    private var isViewLoadedInWindow: Bool {
        window != nil
    }

    private func setup() {
        wantsLayer = true
        // The outer layer casts the shadow; only the glass/background layers clip.
        clipsToBounds = false
        layer?.cornerRadius = 22
        layer?.masksToBounds = false

        clippedContent.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clippedContent)
        NSLayoutConstraint.activate([
            clippedContent.leadingAnchor.constraint(equalTo: leadingAnchor),
            clippedContent.trailingAnchor.constraint(equalTo: trailingAnchor),
            clippedContent.topAnchor.constraint(equalTo: topAnchor),
            clippedContent.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        setupHeader()
        setupContent()
        refreshAppearance()
    }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 22, cornerHeight: 22, transform: nil)
    }

    private func setupHeader() {
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 14
        stackView.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 12
        headerRow.detachesHiddenViews = true
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        // Keep the header compact so the body receives spare height. Packing
        // remains optional so mixed-height controls and text stay centered.
        let headerHugging = NSLayoutConstraint.Priority(
            rawValue: NSLayoutConstraint.Priority.defaultLow.rawValue + 1
        )
        headerRow.setHuggingPriority(headerHugging, for: .vertical)

        iconView.image = NSImage(systemSymbolName: "info.circle.fill", accessibilityDescription: "详情")
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: 18)
        NSLayoutConstraint.activate([
            iconWidthConstraint!,
            iconView.heightAnchor.constraint(equalToConstant: 18)
        ])

        infoTitleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        infoTitleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.lineBreakMode = .byTruncatingTail

        titleContainer.orientation = .vertical
        titleContainer.alignment = .leading
        titleContainer.spacing = 4
        titleContainer.detachesHiddenViews = true
        titleContainer.addArrangedSubview(titleLabel)
        titleContainer.addArrangedSubview(subtitleLabel)

        closeButton.target = self
        closeButton.action = #selector(closeInspector)

        let spacer = headerSpacer
        spacer.translatesAutoresizingMaskIntoConstraints = false

        headerRow.addArrangedSubview(iconView)
        headerRow.addArrangedSubview(infoTitleLabel)
        headerRow.addArrangedSubview(titleContainer)
        headerRow.addArrangedSubview(spacer)
        headerRow.addArrangedSubview(closeButton)
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let centered = infoTitleLabel.centerXAnchor.constraint(equalTo: headerRow.centerXAnchor)
        centered.priority = .defaultHigh
        centeredHeaderConstraint = centered

        stackView.addArrangedSubview(headerRow)
        clippedContent.bodyView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            headerRow.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -36)
        ])
    }

    private func setupContent() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        let contentHost = NSView()
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(contentContainer)
        contentHost.addSubview(progressIndicator)
        stackView.addArrangedSubview(contentHost)

        NSLayoutConstraint.activate([
            contentHost.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -36),
            contentContainer.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: contentHost.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
            progressIndicator.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            progressIndicator.topAnchor.constraint(equalTo: contentHost.topAnchor, constant: 4),
            contentHost.heightAnchor.constraint(greaterThanOrEqualToConstant: 24)
        ])
    }

    @objc private func closeInspector() {
        if let onClose { onClose(); return }
        guard let request else { return }
        InspectorHostActions.postClose(module: request.token.module, cardID: request.token.cardID)
    }

    override func mouseDown(with event: NSEvent) {
        // Blank panel areas should not bubble to the transparent overlay and dismiss the inspector.
    }
}

private final class InspectorHostedContentContainerView: NSView {
    var hostedContentView: NSView? {
        didSet {
            guard hostedContentView !== oldValue else { return }
            oldValue?.removeFromSuperview()
            guard let hostedContentView else { return }
            hostedContentView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hostedContentView)
            NSLayoutConstraint.activate([
                hostedContentView.leadingAnchor.constraint(equalTo: leadingAnchor),
                hostedContentView.trailingAnchor.constraint(equalTo: trailingAnchor),
                hostedContentView.topAnchor.constraint(equalTo: topAnchor),
                hostedContentView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }
}
