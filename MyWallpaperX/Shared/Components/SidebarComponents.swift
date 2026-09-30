//
//  SidebarComponents.swift
//  MyWallpaperX
//

import AppKit

final class SidebarOutlineView: NSOutlineView {
    var rowContextMenuProvider: ((Int) -> NSMenu?)?
    var blankAreaMenuProvider: (() -> NSMenu?)?
    var draggingUpdatedHandler: ((NSPoint) -> Void)?
    var draggingSessionEndedHandler: ((NSDragOperation) -> Void)?
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
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        super.draggingSession(session, endedAt: screenPoint, operation: operation)
        draggingSessionEndedHandler?(operation)
    }

    override func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdatedHandler?(sender.draggingLocation)
        return .move
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
    var suppressSelectionDuringDrag = false

    /// 始终以强调色（蓝色）显示选中态，不随窗口焦点变化切换为灰色。
    override var isEmphasized: Bool {
        get { true }
        set { }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard !suppressSelectionDuringDrag else { return }
        // 始终用强调色绘制选中背景，避免焦点转移到内容区后选中行变灰。
        guard isSelected else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 2), xRadius: 6, yRadius: 6)
        NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
        path.fill()
    }
}

final class SidebarRowCellView: NSTableCellView {
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

    func configure(title: String, symbolName: String?, count: Int?) {
        // 行视图只吃纯数据快照，不保留额外派生状态，便于 outlineView 重建时直接复用。
        // 复用池可能携带上一任行被拖拽置 0 的腾空态（alphaValue 唯一写点在
        // setDraggingPresentation），重新装配内容时一并复位，避免整行不可见；
        // 拖拽源行在拖拽期间不会走 configure，腾空呈现不受影响。
        alphaValue = 1
        titleLabel.stringValue = title
        if let symbolName, let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
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

    func setDraggingPresentation(_ isDragging: Bool) {
        // 拖拽中的源行在视觉上临时腾空，避免与拖拽图像形成“双影”。
        alphaValue = isDragging ? 0 : 1
    }

    private func setup() {
        // 这个 cell 只负责图标、标题、计数三段式布局，样式尽量保持原生 source list 的直觉。
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        iconView.contentTintColor = .secondaryLabelColor
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 13, weight: .regular)
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
        container.addArrangedSubview(iconView)
        container.addArrangedSubview(titleLabel)
        container.addArrangedSubview(NSView())
        container.addArrangedSubview(countLabel)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
