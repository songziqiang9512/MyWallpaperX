//
//  SidebarComponents.swift
//  MyWallpaperX
//

import AppKit

final class SidebarOutlineView: NSOutlineView {
    var rowContextMenuProvider: ((Int) -> NSMenu?)?
    var blankAreaMenuProvider: (() -> NSMenu?)?
    var sameSelectionClickHandler: ((Int) -> Void)?

    private var mouseDownRow: Int = -1
    private var preselectedRow: Int = -1
    private var didBeginDragGesture = false
    private var didTriggerSameSelectionClick = false
    private var pendingSameSelectionClickWorkItem: DispatchWorkItem?
    private var leftMouseUpMonitor: Any?

    override var acceptsFirstResponder: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        draggingDestinationFeedbackStyle = .none
        target = self
        action = #selector(handleOutlineAction(_:))
    }



    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        // 右键菜单由命中行决定，空白区和行内菜单分开处理，避免误触发创建标签菜单。
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        if row >= 0 {
            return rowContextMenuProvider?(row)
        }
        return blankAreaMenuProvider?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMouseMonitorIfNeeded()
    }

    deinit {
        if let leftMouseUpMonitor {
            NSEvent.removeMonitor(leftMouseUpMonitor)
        }
    }

    override func draggingSession(
        _ session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint
    ) {
        // NSOutlineView may consume the tracking loop itself, without calling
        // mouseDragged. A native drag must revoke the same-selection click.
        didBeginDragGesture = true
        pendingSameSelectionClickWorkItem?.cancel()
        pendingSameSelectionClickWorkItem = nil
        super.draggingSession(session, willBeginAt: screenPoint)
    }

    override func mouseDown(with event: NSEvent) {
        pendingSameSelectionClickWorkItem?.cancel()
        pendingSameSelectionClickWorkItem = nil
        didBeginDragGesture = false
        didTriggerSameSelectionClick = false
        mouseDownRow = row(at: convert(event.locationInWindow, from: nil))
        preselectedRow = selectedRow
        super.mouseDown(with: event)
        scheduleSameSelectionClickCheck()
    }

    override func mouseDragged(with event: NSEvent) {
        if !didBeginDragGesture, mouseDownRow >= 0 {
            let point = convert(event.locationInWindow, from: nil)
            let downRowRect = rect(ofRow: mouseDownRow)
            let expandedRect = downRowRect.insetBy(dx: -4, dy: -4)
            if !expandedRect.contains(point) {
                didBeginDragGesture = true
                pendingSameSelectionClickWorkItem?.cancel()
                pendingSameSelectionClickWorkItem = nil
            }
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        // defer 在作用域末尾执行等同于直接写在此处，改用 do 消除警告。
        do {
            mouseDownRow = -1
            preselectedRow = -1
            didBeginDragGesture = false
            didTriggerSameSelectionClick = false
            pendingSameSelectionClickWorkItem?.cancel()
            pendingSameSelectionClickWorkItem = nil
        }
    }

    @objc private func handleOutlineAction(_ sender: Any?) {
        triggerSameSelectionClickIfNeeded(source: "action")
    }

    private func triggerSameSelectionClickIfNeeded(source: String) {
        guard !didBeginDragGesture,
              !didTriggerSameSelectionClick,
              mouseDownRow >= 0,
              mouseDownRow == preselectedRow,
              mouseDownRow == selectedRow else {
            return
        }
        didTriggerSameSelectionClick = true
        sameSelectionClickHandler?(mouseDownRow)
    }

    private func scheduleSameSelectionClickCheck() {
        guard mouseDownRow >= 0, mouseDownRow == preselectedRow else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.triggerSameSelectionClickIfNeeded(source: "deferred")
        }
        pendingSameSelectionClickWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func installMouseMonitorIfNeeded() {
        guard leftMouseUpMonitor == nil else { return }
        leftMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else {
                return event
            }
            guard self.mouseDownRow >= 0, self.mouseDownRow == self.preselectedRow else {
                return event
            }
            DispatchQueue.main.async { [weak self] in
                self?.triggerSameSelectionClickIfNeeded(source: "monitor")
            }
            return event
        }
    }
}

final class SidebarRowView: NSTableRowView {
    // Keep the native neutral selection while focus moves into the new page.
    override var isEmphasized: Bool {
        get { false }
        set { super.isEmphasized = false }
    }
}

final class SidebarRowCellView: NSTableCellView {
    private static let iconSide: CGFloat = 22
    private let iconSlot = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let container = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(title: String, symbolName: String?, count: Int?, coverImage: NSImage? = nil,
                   symbolTint: NSColor? = nil) {
        // 行视图只吃纯数据快照，不保留额外派生状态，便于 outlineView 重建时直接复用。
        titleLabel.stringValue = title
        iconView.contentTintColor = coverImage == nil ? (symbolTint ?? .secondaryLabelColor) : nil
        iconView.wantsLayer = coverImage != nil
        iconView.layer?.cornerRadius = coverImage == nil ? 0 : 3
        iconView.layer?.masksToBounds = coverImage != nil
        if let coverImage {
            iconView.image = coverImage
            iconView.isHidden = false
        } else if let symbolName, let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            iconView.image = image
            iconView.isHidden = false
        } else {
            iconView.image = nil
            iconView.isHidden = true
        }

        if let count {
            countLabel.stringValue = "\(count)"
            countLabel.isHidden = false
        } else {
            countLabel.stringValue = ""
            countLabel.isHidden = true
        }
    }

    private func setup() {
        // 这个 cell 只负责图标、标题、计数三段式布局，样式尽量保持原生 source list 的直觉。
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        textField = titleLabel
        imageView = iconView
        iconView.contentTintColor = .secondaryLabelColor
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconSlot.translatesAutoresizingMaskIntoConstraints = false
        iconSlot.addSubview(iconView)

        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .systemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false

        addSubview(container)
        container.addArrangedSubview(iconSlot)
        container.addArrangedSubview(titleLabel)
        container.addArrangedSubview(NSView())
        container.addArrangedSubview(countLabel)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSide),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSide),
            iconSlot.widthAnchor.constraint(equalToConstant: Self.iconSide),
            iconSlot.heightAnchor.constraint(equalToConstant: Self.iconSide),
            iconView.centerXAnchor.constraint(equalTo: iconSlot.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconSlot.centerYAnchor),
            countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
