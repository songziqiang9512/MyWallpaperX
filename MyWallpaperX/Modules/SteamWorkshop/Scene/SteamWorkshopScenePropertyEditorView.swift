import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
protocol WorkshopPropertyKeyTraversal: AnyObject {
    func focusNextPropertyControl(from responder: NSResponder?, reverse: Bool) -> Bool
}

/// Projects the prepared catalog; persistence and runtime updates stay in the service.
@MainActor
final class SteamWorkshopScenePropertyEditorView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout, WorkshopPropertyKeyTraversal {
    private let service = SteamWorkshopService.shared
    private let record: SteamWorkshopDownloadRecord
    private let context: SteamWorkshopScenePropertyContext
    private var values: [String: SceneUserPropertyValue]
    private var overrides: [String: SceneUserPropertyValue]
    private let list = NSCollectionView()
    private let flowLayout = NSCollectionViewFlowLayout()
    private let scrollView = InspectorFadingScrollView(fadeRatio: 0)
    private var subscription: AnyCancellable?
    private var titles: [Int: String] = [:]
    private var optionLabels: [Int: [String]] = [:]
    private var dependentRows: [String: Set<Int>] = [:]
    private var valueRows: [String: Set<Int>] = [:]
    private var visibleRows: [Int] = []
    private var displayed: Set<Int> = []
    private var visibleOptions: [Int: [SceneUserPropertyOption]] = [:]
    private var heights: [Int: CGFloat] = [:]
    private var measuredWidth: CGFloat = 0
    private var textureSelection: (id: UUID, index: Int, panel: NSOpenPanel)?
    private let textureStatus = NSTextField(wrappingLabelWithString: "")
    // These tokens scope feedback to this presentation; the service owns submission revisions.
    private var textureFeedbackRequests: [String: (id: UUID, index: Int)] = [:]
    private var resetFeedbackRequestID: UUID?
    private var textureStatusIndex: Int?

    init(record: SteamWorkshopDownloadRecord, context: SteamWorkshopScenePropertyContext) {
        self.record = record
        self.context = context
        values = context.effectiveValues
        overrides = SteamWorkshopService.shared.scenePropertyOverrides(for: record)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .vertical)
        prepareRows()
        setupList()
        project(indices: Set(titles.keys))
        list.reloadData()
    }
    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 400) }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window != nil && newWindow !== window {
            cancelTextureSelection()
            invalidateTextureFeedback()
            cancelEditing()
            subscription?.cancel()
            subscription = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && subscription == nil {
            subscription = service.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
                self?.refreshAcceptedValues()
            }
            refreshAcceptedValues(forceRows: Set(titles.keys))
        }
    }

    override func viewDidHide() {
        super.viewDidHide()
        cancelTextureSelection()
        invalidateTextureFeedback()
    }

    override func layout() {
        super.layout()
        textureStatus.preferredMaxLayoutWidth = max(1, bounds.width)
        let width = scrollView.contentSize.width
        guard width > 0, abs(width - measuredWidth) > 0.5 else { return }
        measuredWidth = width
        for (index, title) in titles {
            let kind = context.definitions[index].kind
            let isLabel = kind == .text || kind == .group || kind == .unsupported
            let font = NSFont.systemFont(ofSize: isLabel ? 12 : 13,
                weight: kind == .group ? .semibold : .regular)
            let rect = (title as NSString).boundingRect(
                with: NSSize(width: Self.titleWidth(for: kind, rowWidth: width), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
            let controlsHeight: CGFloat = switch kind {
            case .slider, .textInput, .combo: 34
            case .sceneTexture: 62
            default: 0
            }
            heights[index] = max(isLabel ? 30 : 40, ceil(rect.height) + 18 + controlsHeight)
        }
        flowLayout.invalidateLayout()
    }

    private static func titleWidth(for kind: SceneUserPropertyKind, rowWidth: CGFloat) -> CGFloat {
        max(1, rowWidth - ((kind == .bool || kind == .color) ? 68 : 8))
    }

    private func setupList() {
        let reset = NSButton(title: "恢复默认", target: self, action: #selector(resetProperties))
        reset.bezelStyle = .rounded
        reset.controlSize = .small
        reset.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil)
        reset.imagePosition = .imageLeading
        reset.toolTip = "恢复这个 Scene 壁纸的默认属性"
        reset.isHidden = !context.hasEditorControls
        reset.translatesAutoresizingMaskIntoConstraints = false
        textureStatus.font = .systemFont(ofSize: 11)
        textureStatus.textColor = .secondaryLabelColor
        textureStatus.setAccessibilityIdentifier("scene-texture-update-status")
        textureStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textureStatus.isHidden = true
        let header = NSStackView(views: [reset, textureStatus])
        header.orientation = .vertical
        header.alignment = .trailing
        header.spacing = 4
        header.detachesHiddenViews = true
        header.translatesAutoresizingMaskIntoConstraints = false
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        let scroller = PropertyScroller()
        scroller.isHidden = true
        scrollView.verticalScroller = scroller
        scrollView.hasHorizontalScroller = false
        flowLayout.minimumLineSpacing = 6
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.scrollDirection = .vertical
        list.collectionViewLayout = flowLayout
        list.backgroundColors = [.clear]
        list.isSelectable = false
        list.dataSource = self
        list.delegate = self
        for kind in Set(context.definitions.map { $0.kind.rawValue }) {
            list.register(PropertyItem.self, forItemWithIdentifier: .init(kind))
        }
        scrollView.documentView = list
        addSubview(header)
        addSubview(separator)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func prepareRows() {
        let displayResolver = WorkshopPropertyDisplayResolver(localization: context.propertyDisplayLocalization)
        for (index, definition) in context.definitions.enumerated() {
            if definition.kind == .unsupported {
                let status = definition.runtimeType.isEmpty ? "缺少类型" : "不支持的类型：\(definition.runtimeType)"
                titles[index] = "\(displayText(displayResolver.string(definition.title)) ?? "未命名属性")\n\(status)"
            } else if definition.kind == .group || definition.kind == .text {
                guard let text = displayText(displayResolver.string(definition.title)) else { continue }
                titles[index] = text
            } else {
                titles[index] = displayText(displayResolver.string(definition.title)) ?? "未命名属性"
            }
            optionLabels[index] = definition.options.map {
                displayText(displayResolver.string($0.label)) ?? $0.label
            }
            valueRows[definition.key, default: []].insert(index)
            let conditions = [definition.displayCondition] + definition.options.map(\.displayCondition)
            for condition in conditions.compactMap({ $0 }) {
                for key in context.conditionPrograms[condition]?.referencedPropertyKeys ?? [] {
                    dependentRows[key, default: []].insert(index)
                }
            }
        }
    }

    /// Only condition dependants are evaluated after a value change; hidden values remain in inputs.
    private func project(indices: Set<Int>) {
        let inputs = context.conditionInputs(values: values)
        for index in indices where titles[index] != nil {
            let definition = context.definitions[index]
            var show = service.shouldDisplaySceneProperty(definition, inputs: inputs,
                programs: context.conditionPrograms)
            if definition.kind == .combo {
                let options = service.visibleScenePropertyOptions(for: definition, inputs: inputs,
                    programs: context.conditionPrograms)
                visibleOptions[index] = options
                show = show && !options.isEmpty
            }
            if show { displayed.insert(index) } else { displayed.remove(index) }
        }
        visibleRows = context.definitions.indices.filter { displayed.contains($0) }
    }

    private func refreshAcceptedValues(forceRows: Set<Int> = []) {
        let current = service.scenePropertyOverrides(for: record)
        guard current != overrides || !forceRows.isEmpty else { return }
        overrides = current
        let accepted = context.catalog.effectiveValues(overrides: current)
        for (row, index) in visibleRows.enumerated()
        where values[context.definitions[index].key] != accepted[context.definitions[index].key] {
            ((list.item(at: IndexPath(item: row, section: 0)) as? PropertyItem)?.cell)?.cancelEditing()
        }
        updateValues(accepted, forceRows: forceRows)
    }

    private func updateValues(_ accepted: [String: SceneUserPropertyValue], forceRows: Set<Int> = []) {
        let keys = Set(values.keys).union(accepted.keys).filter { values[$0] != accepted[$0] }
        values = accepted
        var affected = forceRows
        for key in keys {
            affected.formUnion(dependentRows[key] ?? [])
            affected.formUnion(valueRows[key] ?? [])
        }
        guard !affected.isEmpty else { return }
        let old = visibleRows
        let origin = scrollView.contentView.bounds.origin
        let anchor = list.indexPathsForVisibleItems().min { $0.item < $1.item }?.item ?? -1
        var editingView = ((window?.firstResponder as? NSTextView)?.delegate as? NSTextField) as NSView?
        while editingView != nil && !(editingView is PropertyCell) { editingView = editingView?.superview }
        let editingIndex = (editingView as? PropertyCell)?.definitionIndex
        let anchorID = editingIndex ?? (old.indices.contains(anchor) ? old[anchor] : nil)
        let anchorRow = anchorID.flatMap { old.firstIndex(of: $0) }
        let offset = anchorRow.map { origin.y - (flowLayout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame.minY ?? origin.y) } ?? 0
        project(indices: affected)
        let oldIDs = Set(old), newIDs = Set(visibleRows)
        let removed = IndexSet(old.indices.filter { !newIDs.contains(old[$0]) })
        let inserted = IndexSet(visibleRows.indices.filter { !oldIDs.contains(visibleRows[$0]) })
        if let selection = textureSelection, !newIDs.contains(selection.index) { cancelTextureSelection() }
        if !textureFeedbackRequests.isEmpty {
            textureFeedbackRequests = textureFeedbackRequests.filter { newIDs.contains($0.value.index) }
        }
        if let index = textureStatusIndex, !newIDs.contains(index) { clearTextureStatus() }
        for row in removed {
            ((list.item(at: IndexPath(item: row, section: 0)) as? PropertyItem)?.cell)?.cancelEditing()
        }
        if !removed.isEmpty || !inserted.isEmpty {
            if let editingIndex, let oldRow = old.firstIndex(of: editingIndex),
               let newRow = visibleRows.firstIndex(of: editingIndex) {
                let height: (Int) -> CGFloat = { (self.heights[$0] ?? 40) + self.flowLayout.minimumLineSpacing }
                let delta = visibleRows.prefix(newRow).reduce(CGFloat(0)) { $0 + height($1) }
                    - old.prefix(oldRow).reduce(CGFloat(0)) { $0 + height($1) }
                // Move the viewport with an insertion before AppKit realizes
                // its new cells, so a focused field never temporarily falls out.
                if delta > 0 { scrollView.contentView.setBoundsOrigin(NSPoint(x: origin.x, y: origin.y + delta)) }
            }
            list.performBatchUpdates({
                list.deleteItems(at: Set(removed.map { IndexPath(item: $0, section: 0) }))
                list.insertItems(at: Set(inserted.map { IndexPath(item: $0, section: 0) }))
            })
            list.layoutSubtreeIfNeeded()
            if let anchorID, let row = visibleRows.firstIndex(of: anchorID),
               let frame = flowLayout.layoutAttributesForItem(at: IndexPath(item: row, section: 0))?.frame {
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: frame.minY + offset))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
        for (row, index) in visibleRows.enumerated() where affected.contains(index) {
            if let cell = (list.item(at: IndexPath(item: row, section: 0)) as? PropertyItem)?.cell {
                configure(cell, index: index)
            }
        }
    }

    private func configure(_ cell: PropertyCell, index: Int) {
        cell.configure(editor: self, index: index, definition: context.definitions[index],
            title: titles[index]!, value: values[context.definitions[index].key],
            options: visibleOptions[index] ?? [])
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { visibleRows.count }

    func focusNextPropertyControl(from responder: NSResponder?, reverse: Bool) -> Bool {
        let view = (responder as? NSTextView)?.delegate as? NSView ?? responder as? NSView
        var ancestor = view
        while let current = ancestor, !(current is PropertyCell) { ancestor = current.superview }
        guard let cell = ancestor as? PropertyCell, cell.isDescendant(of: self),
              let index = cell.definitionIndex, let row = visibleRows.firstIndex(of: index) else { return false }
        let fullAccess = NSApp.isFullKeyboardAccessEnabled
        let controls = cell.keyboardControls(fullAccess: fullAccess)
        let direction = reverse ? -1 : 1
        if let current = controls.firstIndex(where: { $0 === view }), controls.indices.contains(current + direction) {
            return window?.makeFirstResponder(controls[current + direction]) == true
        }
        var targetRow = row + direction
        while visibleRows.indices.contains(targetRow) {
            defer { targetRow += direction }
            let kind = context.definitions[visibleRows[targetRow]].kind
            guard kind == .textInput || (fullAccess && kind != .text && kind != .group && kind != .unsupported) else { continue }
            let path = IndexPath(item: targetRow, section: 0)
            list.scrollToItems(at: [path], scrollPosition: .nearestHorizontalEdge)
            list.layoutSubtreeIfNeeded()
            window?.displayIfNeeded()
            guard let target = (list.item(at: path) as? PropertyItem)?.cell else { return false }
            let candidates = target.keyboardControls(fullAccess: fullAccess)
            if let control = reverse ? candidates.last : candidates.first {
                return window?.makeFirstResponder(control) == true
            }
        }
        return false
    }
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> NSSize {
        NSSize(width: max(1, scrollView.contentSize.width), height: heights[visibleRows[indexPath.item]] ?? 40)
    }
    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let index = visibleRows[indexPath.item], definition = context.definitions[index]
        let identifier = NSUserInterfaceItemIdentifier(definition.kind.rawValue)
        let item = collectionView.makeItem(withIdentifier: identifier, for: indexPath) as! PropertyItem
        let cell = item.cell(for: definition.kind)
        configure(cell, index: index)
        return item
    }
    func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem,
                        forRepresentedObjectAt indexPath: IndexPath) {
        (item as? PropertyItem)?.cell?.cancelEditing()
    }

    private final class PropertyItem: NSCollectionViewItem {
        var cell: PropertyCell? { view.subviews.first as? PropertyCell }
        override func loadView() { view = NSView() }
        func cell(for kind: SceneUserPropertyKind) -> PropertyCell {
            let identifier = NSUserInterfaceItemIdentifier(kind.rawValue)
            if let cell, cell.identifier == identifier { return cell }
            cell?.removeFromSuperview()
            let cell = PropertyCell(kind: kind)
            cell.identifier = identifier
            cell.frame = view.bounds
            cell.autoresizingMask = [.width, .height]
            view.addSubview(cell)
            return cell
        }
        override func prepareForReuse() {
            cell?.cancelEditing()
            super.prepareForReuse()
        }
    }

    private func commit(_ value: SceneUserPropertyValue, index: Int) {
        let definition = context.definitions[index]
        var changed = values
        changed[definition.key] = value
        updateValues(changed)
        service.updateScenePropertyValue(value, definition: definition, record: record)
        overrides = service.scenePropertyOverrides(for: record)
    }

    private func cancelEditing() {
        for row in 0..<visibleRows.count {
            ((list.item(at: IndexPath(item: row, section: 0)) as? PropertyItem)?.cell)?.cancelEditing()
        }
    }

    @objc private func resetProperties() {
        cancelTextureSelection()
        cancelEditing()
        invalidateTextureFeedback()
        let requestID = UUID()
        resetFeedbackRequestID = requestID
        let initiatingWindow = window
        service.resetScenePropertyValues(for: record, defaultValues: context.catalog.defaultValues) { [weak self, weak initiatingWindow] outcome in
            guard let self, let initiatingWindow, self.resetFeedbackRequestID == requestID,
                  self.canPresentTextureFeedback(in: initiatingWindow) else { return }
            self.resetFeedbackRequestID = nil
            switch outcome {
            case .applied:
                self.clearTextureStatus()
                self.refreshAcceptedValues(forceRows: Set(self.titles.keys))
            case .failed(_), .unavailable:
                self.showTextureStatus("部分图像或视频未能恢复默认，已保留原选择。", index: nil)
            case .superseded:
                break
            }
        }
    }

    private func selectSceneTexture(index: Int) {
        guard let window else { return }
        cancelTextureSelection()
        let panel = NSOpenPanel()
        let requestID = UUID()
        textureSelection = (requestID, index, panel)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .mpeg4Movie, .quickTimeMovie]
            + [UTType(filenameExtension: "m4v")].compactMap { $0 }
        panel.prompt = "选择"
        panel.beginSheetModal(for: window) { [weak self, weak window, weak panel] response in
            guard let self, let window, let panel, self.window === window,
                  self.textureSelection?.id == requestID else { return }
            self.textureSelection = nil
            guard response == .OK, let url = panel.url, window.isVisible,
                  !self.isHiddenOrHasHiddenAncestor, self.displayed.contains(index) else { return }
            self.updateTexture(url, index: index)
        }
    }

    private func cancelTextureSelection() {
        let pending = textureSelection
        textureSelection = nil
        pending?.panel.cancel(nil)
    }

    private func updateTexture(_ url: URL?, index: Int) {
        let definition = context.definitions[index]
        let requestID = UUID()
        textureFeedbackRequests[definition.key] = (requestID, index)
        resetFeedbackRequestID = nil
        if textureStatusIndex == nil || textureStatusIndex.map({ context.definitions[$0].key }) == definition.key {
            clearTextureStatus()
        }
        let initiatingWindow = window
        service.updateSceneTexturePropertyURL(url, definition: definition, record: record) { [weak self, weak initiatingWindow] outcome in
            guard let self, let initiatingWindow,
                  self.textureFeedbackRequests[definition.key]?.id == requestID,
                  self.canPresentTextureFeedback(in: initiatingWindow), self.displayed.contains(index) else { return }
            self.textureFeedbackRequests.removeValue(forKey: definition.key)
            switch outcome {
            case .applied:
                if self.textureStatusIndex.map({ self.context.definitions[$0].key }) == definition.key {
                    self.clearTextureStatus()
                }
                self.refreshAcceptedValues(forceRows: [index])
            case .failed(_), .unavailable:
                self.showTextureStatus("“\(self.titles[index] ?? definition.key)”图像或视频无法更新，已保留原选择。请选择可读取的 PNG/JPEG 图像或 MP4/MOV/M4V 视频。", index: index)
            case .superseded:
                break
            }
        }
    }

    private func canPresentTextureFeedback(in initiatingWindow: NSWindow) -> Bool {
        window === initiatingWindow && initiatingWindow.isVisible && !isHiddenOrHasHiddenAncestor
    }

    private func clearTextureStatus() {
        textureStatus.stringValue = ""
        textureStatus.isHidden = true
        textureStatusIndex = nil
    }

    private func showTextureStatus(_ message: String, index: Int?) {
        textureStatus.stringValue = message
        textureStatusIndex = index
        textureStatus.isHidden = false
    }

    private func invalidateTextureFeedback() {
        textureFeedbackRequests.removeAll()
        resetFeedbackRequestID = nil
        clearTextureStatus()
    }

    private final class PropertyCell: NSView, NSTextFieldDelegate {
        private weak var editor: SteamWorkshopScenePropertyEditorView?
        private var index: Int?
        private var generation: UInt64 = 0
        private struct Session { let index: Int; let generation: UInt64 }
        private var textSession: Session?
        private var sliderSession: Session?
        private var colorSession: Session?
        private let kind: SceneUserPropertyKind
        private let title = NSTextField(wrappingLabelWithString: "")
        private let content = NSStackView()
        private var slider: WorkshopPropertySlider?
        private var summary: NSTextField?
        private var toggle: NSButton?
        private var field: NSTextField?
        private var colorWell: PropertyColorWell?
        private var popup: NSPopUpButton?
        private var options: [SceneUserPropertyOption] = []
        private var resourceName: NSTextField?
        private var clear: NSButton?
        private var choose: NSButton?
        var definitionIndex: Int? { index }

        func keyboardControls(fullAccess: Bool) -> [NSView] {
            if !fullAccess { return field.map { [$0] } ?? [] }
            return [toggle, slider, field, colorWell, popup, clear?.isHidden == false ? clear : nil, choose]
                .compactMap { $0 }
        }

        init(kind: SceneUserPropertyKind) {
            self.kind = kind
            super.init(frame: .zero)
            let isLabel = kind == .text || kind == .group || kind == .unsupported
            title.font = .systemFont(ofSize: isLabel ? 12 : 13,
                weight: kind == .group ? .semibold : .regular)
            title.textColor = isLabel ? .secondaryLabelColor : .labelColor
            title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            title.translatesAutoresizingMaskIntoConstraints = false
            content.orientation = .horizontal
            content.alignment = .centerY
            content.spacing = 8
            content.translatesAutoresizingMaskIntoConstraints = false
            addSubview(title)
            if isLabel {
                NSLayoutConstraint.activate([
                    title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                    title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                    title.centerYAnchor.constraint(equalTo: centerYAnchor)])
            } else {
                addSubview(content)
                let inline = kind == .bool || kind == .color
                NSLayoutConstraint.activate([
                    title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                    content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)])
                if inline {
                    NSLayoutConstraint.activate([
                        title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -64),
                        title.centerYAnchor.constraint(equalTo: centerYAnchor),
                        content.widthAnchor.constraint(equalToConstant: 44),
                        content.centerYAnchor.constraint(equalTo: centerYAnchor)])
                } else {
                    NSLayoutConstraint.activate([
                        title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                        title.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                        content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                        content.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
                        content.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8)])
                }
                setupControl()
            }
        }
        required init?(coder: NSCoder) { nil }

        override func layout() {
            title.preferredMaxLayoutWidth = SteamWorkshopScenePropertyEditorView.titleWidth(for: kind, rowWidth: bounds.width)
            super.layout()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if window != nil && newWindow == nil { cancelEditing() }
            super.viewWillMove(toWindow: newWindow)
        }

        private func setupControl() {
            switch kind {
            case .bool:
                let spacer = NSView()
                spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
                let button = NSButton(checkboxWithTitle: "", target: nil, action: nil)
                button.target = self
                button.action = #selector(boolChanged)
                content.addArrangedSubview(spacer)
                content.addArrangedSubview(button)
                toggle = button
            case .slider:
                let control = WorkshopPropertySlider(value: 0, minValue: 0, maxValue: 1,
                    target: self, action: #selector(sliderChanged))
                control.isContinuous = true
                control.setContentHuggingPriority(.defaultLow, for: .horizontal)
                control.onTrackingBegan = { [weak self] _ in
                    guard let self, let index = self.index else { return }
                    self.sliderSession = Session(index: index, generation: self.generation)
                }
                control.onTrackingEnded = { [weak self] _ in self?.sliderSession = nil }
                let label = NSTextField(labelWithString: "")
                label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                label.textColor = .secondaryLabelColor
                label.widthAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
                content.addArrangedSubview(control)
                content.addArrangedSubview(label)
                slider = control; summary = label
            case .textInput:
                let control = NSTextField(string: "")
                control.delegate = self
                control.target = self
                control.action = #selector(textChanged)
                content.addArrangedSubview(control)
                field = control
            case .color:
                let well = PropertyColorWell(frame: NSRect(x: 0, y: 0, width: 42, height: 26))
                well.supportsAlpha = false
                well.target = self
                well.action = #selector(colorChanged)
                well.onActivation = { [weak self] in
                    guard let self, let index = self.index else { return }
                    self.colorSession = Session(index: index, generation: self.generation)
                }
                well.onDeactivation = { [weak self] in self?.colorSession = nil }
                content.addArrangedSubview(well)
                well.widthAnchor.constraint(equalToConstant: 42).isActive = true
                well.heightAnchor.constraint(equalToConstant: 26).isActive = true
                colorWell = well
            case .combo:
                let control = NSPopUpButton()
                control.lineBreakMode = .byTruncatingTail
                control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                control.target = self
                control.action = #selector(comboChanged)
                content.addArrangedSubview(control)
                popup = control
            case .sceneTexture:
                content.orientation = .vertical
                content.alignment = .trailing
                let label = NSTextField(labelWithString: "")
                label.lineBreakMode = .byTruncatingMiddle
                label.textColor = .secondaryLabelColor
                let buttons = NSStackView()
                buttons.orientation = .horizontal
                buttons.spacing = 8
                let choose = NSButton(title: "选择文件", target: self, action: #selector(chooseTexture))
                choose.bezelStyle = .rounded; choose.controlSize = .small
                choose.image = NSImage(systemSymbolName: "photo.badge.plus", accessibilityDescription: nil)
                choose.imagePosition = .imageLeading; choose.toolTip = "选择 PNG/JPEG 图像或 MP4/MOV/M4V 视频"
                let restore = NSButton(title: "", target: self, action: #selector(clearTexture))
                restore.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "恢复默认纹理")
                restore.isBordered = false; restore.toolTip = "恢复作者提供的默认纹理"
                buttons.addArrangedSubview(restore); buttons.addArrangedSubview(choose)
                content.addArrangedSubview(label); content.addArrangedSubview(buttons)
                label.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor).isActive = true
                resourceName = label; clear = restore
                self.choose = choose
            case .group, .text, .unsupported: break
            }
            for view in content.arrangedSubviews { view.translatesAutoresizingMaskIntoConstraints = false }
        }

        func configure(editor: SteamWorkshopScenePropertyEditorView, index: Int,
                       definition: SceneUserPropertyDefinition, title: String,
                       value: SceneUserPropertyValue?, options: [SceneUserPropertyOption]) {
            if self.editor !== editor || self.index != index {
                cancelEditing()
                self.editor = editor
                self.index = index
            }
            self.title.stringValue = title
            toggle?.setAccessibilityLabel(title)
            toggle?.state = value?.boolValue == true ? .on : .off
            slider?.setAccessibilityLabel(title)
            if let slider, !slider.isTrackingMouse {
                let range = editor.sliderRange(for: definition)
                slider.minValue = range.lowerBound; slider.maxValue = range.upperBound
                slider.doubleValue = min(max(value?.numberValue ?? range.lowerBound, range.lowerBound), range.upperBound)
            }
            summary?.stringValue = editor.formattedSliderValue(definition)
            field?.setAccessibilityLabel(title)
            if textSession == nil { field?.stringValue = value?.stringValue ?? "" }
            colorWell?.setAccessibilityLabel(title)
            if colorSession == nil, let colorWell {
                if let raw = value?.stringValue, let color = SteamWorkshopService.parseWebColorComponents(from: raw) {
                    colorWell.color = NSColor(deviceRed: color.red, green: color.green, blue: color.blue, alpha: 1)
                } else {
                    colorWell.color = .white
                }
            }
            if let popup {
                popup.setAccessibilityLabel(title)
                self.options = options
                popup.removeAllItems()
                if !options.contains(where: { $0.value == value }) {
                    let current = definition.options.firstIndex(where: { $0.value == value })
                        .map { editor.optionLabels[index]![$0] }
                        ?? String(describing: value?.foundationValue ?? "")
                    popup.addItem(withTitle: "当前值：\(current)（不可选）")
                    popup.lastItem?.isEnabled = false
                }
                for (offset, option) in options.enumerated() {
                    let original = definition.options.firstIndex(of: option)!
                    let item = NSMenuItem(title: editor.optionLabels[index]![original], action: nil, keyEquivalent: "")
                    item.representedObject = offset
                    popup.menu?.addItem(item)
                    if option.value == value { popup.select(item) }
                }
            }
            if let resourceName {
                let url = editor.service.resolvedSceneTexturePropertyURL(forKey: definition.key, record: editor.record)
                let hasSelection = url != nil || editor.overrides[definition.key] != nil
                resourceName.stringValue = url?.lastPathComponent
                    ?? (hasSelection ? "已选图像暂不可用" : "使用作者默认纹理")
                clear?.isHidden = !hasSelection
            }
        }

        func cancelEditing() {
            generation &+= 1
            textSession = nil; sliderSession = nil; colorSession = nil
            if let field, field.currentEditor() != nil { window?.makeFirstResponder(nil) }
            colorWell?.deactivate()
        }
        private func active(_ session: Session?) -> Int? {
            guard let session, session.generation == generation, session.index == index else { return nil }
            return session.index
        }
        @objc private func boolChanged(_ sender: NSButton) {
            guard let index else { return }
            editor?.commit(.bool(sender.state == .on), index: index)
        }
        @objc private func sliderChanged(_ sender: WorkshopPropertySlider) {
            guard let index = sender.isTrackingMouse ? active(sliderSession) : index, let editor else { return }
            let definition = editor.context.definitions[index], range = editor.sliderRange(for: definition)
            let step = editor.sliderStep(for: definition, range: range)
            let value = min(max(range.lowerBound + ((sender.doubleValue - range.lowerBound) / step).rounded() * step,
                                range.lowerBound), range.upperBound)
            sender.doubleValue = value
            editor.commit(.number(value), index: index)
        }
        @objc private func textChanged(_ sender: NSTextField) {
            guard let index = active(textSession), let editor,
                  editor.values[editor.context.definitions[index].key] != .string(sender.stringValue) else { return }
            editor.commit(.string(sender.stringValue), index: index)
        }
        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let index else { return }
            textSession = Session(index: index, generation: generation)
        }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
            textChanged(field)
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            if let field = notification.object as? NSTextField { textChanged(field) }
            textSession = nil
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                return editor?.focusNextPropertyControl(from: control, reverse: false) == true
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                return editor?.focusNextPropertyControl(from: control, reverse: true) == true
            }
            return false
        }
        @objc private func comboChanged(_ sender: NSPopUpButton) {
            guard let index, let option = sender.selectedItem?.representedObject as? Int,
                  options.indices.contains(option) else { return }
            editor?.commit(options[option].value, index: index)
        }
        @objc private func colorChanged(_ sender: PropertyColorWell) {
            guard let index = active(colorSession), let color = sender.color.usingColorSpace(.deviceRGB) else { return }
            editor?.commit(.string(String(format: "%.6f %.6f %.6f", color.redComponent,
                color.greenComponent, color.blueComponent)), index: index)
        }
        @objc private func chooseTexture(_ sender: NSButton) {
            guard let index else { return }; editor?.selectSceneTexture(index: index)
        }
        @objc private func clearTexture(_ sender: NSButton) {
            guard let index else { return }; editor?.updateTexture(nil, index: index)
        }
    }

    private final class PropertyColorWell: NSColorWell {
        var onActivation: (() -> Void)?
        var onDeactivation: (() -> Void)?
        override func activate(_ exclusive: Bool) {
            onActivation?()
            super.activate(exclusive)
        }
        override func deactivate() {
            onDeactivation?()
            super.deactivate()
        }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            guard window != nil else { return false }
            let wasActive = isActive
            if !wasActive { onActivation?() }
            defer { if !wasActive && !isActive { onDeactivation?() } }
            return super.performDragOperation(sender)
        }
    }
    private func sliderRange(for definition: SceneUserPropertyDefinition) -> ClosedRange<Double> {
        let current = values[definition.key]?.numberValue ?? definition.defaultValue?.numberValue ?? 0
        let lower = min(definition.minimumValue ?? min(0, current), current)
        var upper = max(definition.maximumValue ?? max(1, current), current)
        if upper <= lower {
            upper = lower + 1
        }
        return lower...upper
    }

    private func sliderStep(
        for definition: SceneUserPropertyDefinition,
        range: ClosedRange<Double>
    ) -> Double {
        let inferred = definition.allowsFractionalValues
            ? pow(10, -Double(max(definition.fractionalPrecision ?? 2, 0)))
            : 1
        return min(max(definition.stepValue ?? inferred, 0.000_001), range.upperBound - range.lowerBound)
    }

    private func formattedSliderValue(_ definition: SceneUserPropertyDefinition) -> String {
        let value = values[definition.key]?.numberValue ?? definition.defaultValue?.numberValue ?? 0
        let precision = definition.allowsFractionalValues
            ? max(definition.fractionalPrecision ?? 2, 0)
            : 0
        return String(format: "%.\(precision)f", value)
    }

    private func displayText(_ rawText: String) -> String? {
        WorkshopPropertyDisplayResolver.plainText(rawText)
    }

    private final class PropertyScroller: NSScroller {
        override class var isCompatibleWithOverlayScrollers: Bool { true }
        override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat { 0 }
        // Keep vertical scrolling enabled for NSCollectionView's content sizing,
        // but never let its scrollbar cover the trailing property controls.
        override var isHidden: Bool {
            get { super.isHidden }
            set { super.isHidden = true }
        }
    }
}
