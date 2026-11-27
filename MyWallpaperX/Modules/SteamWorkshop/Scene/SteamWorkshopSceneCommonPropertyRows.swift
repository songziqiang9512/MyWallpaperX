import AppKit

@MainActor
final class SteamWorkshopSceneCommonPropertyRows: NSStackView {
    var onDisclosureChanged: (() -> Void)?
    var onEdit: (((inout ScenePlaybackPresentation) -> Void) -> Void)?
    var isExpanded: Bool { disclosure.state == .on }

    private let disclosure = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let alignmentMenu = NSPopUpButton()
    private let listen = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let flip = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let parallax = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private lazy var alignmentRow = WorkshopPropertyRowView(
        style: .choice, title: String(localized: "Scene Framing"), control: alignmentMenu)
    private lazy var crop = SliderRow(String(localized: "Crop Position"), range: 0...100,
        target: self, action: #selector(changeCrop))
    private lazy var horizontal = SliderRow(String(localized: "Horizontal Position"), range: 0...100,
        target: self, action: #selector(changeHorizontal))
    private lazy var vertical = SliderRow(String(localized: "Vertical Position"), range: 0...100,
        target: self, action: #selector(changeVertical))
    private lazy var zoom = SliderRow(String(localized: "Camera Zoom"), range: 50...200,
        target: self, action: #selector(changeZoom), displaysPercentage: true)
    private lazy var rate = SliderRow(String(localized: "Playback Speed"), range: 10...200,
        target: self, action: #selector(changeRate), displaysPercentage: true)
    private lazy var listenRow = WorkshopPropertyRowView(
        style: .inline, title: String(localized: "Audio Listening"), control: listen)
    private lazy var flipRow = WorkshopPropertyRowView(
        style: .inline, title: String(localized: "Flip Horizontally"), control: flip)
    private lazy var parallaxRow = WorkshopPropertyRowView(
        style: .inline, title: String(localized: "Mouse Parallax"), control: parallax)
    private lazy var volume = SliderRow(String(localized: "Volume"), range: 0...100,
        target: self, action: #selector(changeVolume), displaysPercentage: true)

    init(reset: NSButton) {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = WorkshopPropertyPanelLayout.rowSpacing
        detachesHiddenViews = true
        translatesAutoresizingMaskIntoConstraints = false

        let disclosureRow = WorkshopPropertyRowView(
            style: .inline, title: String(localized: "Show Common Adjustments"), control: disclosure)
        for row in [WorkshopPropertyPanelLayout.resetRow(reset), disclosureRow, alignmentRow, crop,
                    horizontal, vertical, zoom, rate, flipRow, parallaxRow, listenRow, volume] {
            addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }

        for option in ScenePlaybackPresentation.Alignment.allCases {
            let title = switch option {
            case .system: String(localized: "Follow System Setting")
            case .cover: String(localized: "Cover Screen")
            case .fit: String(localized: "Show Entire Scene")
            case .center: String(localized: "Center")
            case .stretch: String(localized: "Stretch")
            case .free: String(localized: "Free")
            }
            alignmentMenu.addItem(withTitle: title)
        }
        alignmentMenu.lineBreakMode = .byTruncatingTail
        alignmentMenu.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for (control, action) in [(disclosure as NSControl, #selector(changeDisclosure)),
                                  (alignmentMenu, #selector(changeAlignment)),
                                  (flip, #selector(changeFlip)), (parallax, #selector(changeParallax)),
                                  (listen, #selector(changeListen))] {
            control.target = self
            control.action = action
        }
    }

    required init?(coder: NSCoder) { nil }

    func configure(_ value: ScenePlaybackPresentation, hasCanvas: Bool, showsCrop: Bool,
                   hasParallax: Bool, hasAudio: Bool, hasSound: Bool) -> Bool {
        let mode = ScenePlaybackPresentation.Alignment.allCases.firstIndex(of: value.alignment)!
        if alignmentMenu.indexOfSelectedItem != mode { alignmentMenu.selectItem(at: mode) }
        crop.setValue(value.position)
        horizontal.setValue(value.horizontalPosition)
        vertical.setValue(value.verticalPosition)
        zoom.setValue(value.zoom)
        rate.setValue(value.rate)
        volume.setValue(value.volume)
        listen.state = value.listensToAudio ? .on : .off
        flip.state = value.flippedHorizontally ? .on : .off
        parallax.state = value.allowsMouseParallax ? .on : .off

        let expanded = isExpanded
        let showsFree = expanded && hasCanvas && value.alignment == .free
        var layoutChanged = false
        func show(_ row: NSView, when visible: Bool) {
            guard row.isHidden == visible else { return }
            row.isHidden = !visible
            layoutChanged = true
        }
        show(alignmentRow, when: expanded && hasCanvas)
        show(crop, when: expanded && showsCrop)
        show(horizontal, when: showsFree)
        show(vertical, when: showsFree)
        show(zoom, when: expanded)
        show(rate, when: expanded)
        show(flipRow, when: expanded)
        show(parallaxRow, when: expanded && hasParallax)
        show(listenRow, when: expanded && hasAudio)
        show(volume, when: expanded && hasSound)
        return layoutChanged
    }

    func height(for width: CGFloat) -> CGFloat {
        arrangedSubviews.filter { !$0.isHidden }.reduce(0) { total, row in
            let height = (row as? WorkshopPropertyRowView).map {
                WorkshopPropertyRowView.height(style: $0.style, content: $0.title.presentation, rowWidth: width)
            } ?? row.fittingSize.height
            return total + height + spacing
        }
    }

    var keyboardControls: [NSControl] {
        arrangedSubviews.filter { !$0.isHidden }.flatMap { row in
            let views = (row as? WorkshopPropertyRowView)?.content.arrangedSubviews ?? row.subviews
            return views.compactMap { $0 as? NSControl }.filter {
                ($0 is NSButton || $0 is NSSlider) && $0.isEnabled && !$0.isHiddenOrHasHiddenAncestor
            }
        }
    }

    @objc private func changeDisclosure() { onDisclosureChanged?() }
    @objc private func changeAlignment() {
        edit(\.alignment, ScenePlaybackPresentation.Alignment.allCases[alignmentMenu.indexOfSelectedItem])
    }
    @objc private func changeCrop(_ slider: NSSlider) { edit(\.position, slider.integerValue) }
    @objc private func changeHorizontal(_ slider: NSSlider) { edit(\.horizontalPosition, slider.integerValue) }
    @objc private func changeVertical(_ slider: NSSlider) { edit(\.verticalPosition, slider.integerValue) }
    @objc private func changeZoom(_ slider: NSSlider) { edit(\.zoom, slider.integerValue) }
    @objc private func changeRate(_ slider: NSSlider) { edit(\.rate, slider.integerValue) }
    @objc private func changeVolume(_ slider: NSSlider) { edit(\.volume, slider.integerValue) }
    @objc private func changeFlip() { edit(\.flippedHorizontally, flip.state == .on) }
    @objc private func changeParallax() { edit(\.allowsMouseParallax, parallax.state == .on) }
    @objc private func changeListen() { edit(\.listensToAudio, listen.state == .on) }

    private func edit<T>(_ key: WritableKeyPath<ScenePlaybackPresentation, T>, _ value: T) {
        onEdit? { $0[keyPath: key] = value }
    }

    private final class SliderRow: WorkshopPropertyRowView {
        private let slider: WorkshopPropertySlider
        private let summary = NSTextField(labelWithString: "")
        private let displaysPercentage: Bool

        init(_ title: String, range: ClosedRange<Int>, target: AnyObject, action: Selector,
             displaysPercentage: Bool = false) {
            slider = WorkshopPropertySlider(value: Double(range.lowerBound), minValue: Double(range.lowerBound),
                maxValue: Double(range.upperBound), target: target, action: action)
            self.displaysPercentage = displaysPercentage
            super.init(style: .choice)
            self.title.stringValue = title
            slider.setAccessibilityLabel(title)
            addSlider(slider, summary: summary)
        }

        required init?(coder: NSCoder) { nil }

        func setValue(_ value: Int) {
            if !slider.isTrackingMouse { slider.integerValue = value }
            summary.stringValue = displaysPercentage ? (Double(value) / 100).formatted(.percent) : value.formatted()
        }
    }
}
