import AppKit

/// One passive last-row status; continuation belongs to the grid's scroll path.
final class AppKitSteamWorkshopBrowserFooterItem: NSCollectionViewItem {
    override func loadView() { view = AppKitSteamWorkshopBrowserFooterView(frame: .zero) }
    func configure(text: String) { (view as? AppKitSteamWorkshopBrowserFooterView)?.configure(text: text) }
}

final class AppKitSteamWorkshopBrowserFooterView: NSView {
    private let textField = NSTextField(labelWithString: "")
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }
    func configure(text: String) { textField.stringValue = text }
    private func setup() {
        identifier = NSUserInterfaceItemIdentifier("SteamWorkshopBrowserFooterView")
        textField.font = .systemFont(ofSize: 12)
        textField.textColor = .secondaryLabelColor
        textField.alignment = .center
        textField.lineBreakMode = .byTruncatingTail
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)
        NSLayoutConstraint.activate([
            textField.centerXAnchor.constraint(equalTo: centerXAnchor), textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            textField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ])
    }
}
