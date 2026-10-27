import AppKit

/// Shared, noninteractive metadata badge. AppKit owns its fill and border drawing.
final class InspectorBadgeView: NSBox {
    init(text: String, truncatesText: Bool = false) {
        super.init(frame: .zero)
        boxType = .custom
        titlePosition = .noTitle
        cornerRadius = 13
        fillColor = NSColor.black.withAlphaComponent(0.12)
        borderColor = .separatorColor
        borderWidth = 0.6
        contentViewMargins = .zero
        translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        if truncatesText {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
        }
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView!.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            widthAnchor.constraint(lessThanOrEqualToConstant: 180),
            heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
