import AppKit
import Combine
import UniformTypeIdentifiers

/// Projects the prepared catalog; persistence and runtime updates stay in the service.
@MainActor
final class SteamWorkshopScenePropertyEditorView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout, WorkshopPropertyKeyTraversal {
    private let service = SteamWorkshopService.shared
    private let record: SteamWorkshopDownloadRecord
    private let context: SteamWorkshopScenePropertyContext
    private var values: [String: SceneUserPropertyValue]
    private var overrides: [String: SceneUserPropertyValue]
    private var shortcutConfiguration: ScenePlaybackShortcutConfiguration = .empty
    private let list = NSCollectionView()
    private let flowLayout = NSCollectionViewFlowLayout()
    private let scrollView = WorkshopPropertyScrollView()
    private let reset = NSButton(title: String(localized: "Restore Defaults"), target: nil, action: nil)
    private lazy var commonRows = SteamWorkshopSceneCommonPropertyRows(reset: reset)
    private lazy var schemeIndex = context.definitions.firstIndex {
        $0.key == "schemecolor" && $0.kind == .color && context.actionableKeys.contains($0.key)
    }
    private var subscriptions: Set<AnyCancellable> = []
    private var titles: [Int: String] = [:]
    private var titleContents: [Int: WorkshopPropertyTextContent] = [:]
    private var optionLabels: [Int: [String]] = [:]
    private var dependentRows: [String: Set<Int>] = [:]
    private var valueRows: [String: Set<Int>] = [:]
    private var visibleRows: [Int] = []
    private var displayed: Set<Int> = []
    private var visibleOptions: [Int: [SceneUserPropertyOption]] = [:]
    private var heights: [Int: CGFloat] = [:]
    private var measuredWidth: CGFloat = 0
    private var textureSelection: (id: UUID, index: Int, panel: NSOpenPanel)?
    private var shortcutSelection: (id: UUID, index: Int, sheet: NSWindow)?
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
        shortcutConfiguration = SteamWorkshopService.shared.storedSceneShortcutConfiguration(for: record)
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
            cancelShortcutSelection()
            invalidateTextureFeedback()
            cancelEditing()
            subscriptions.removeAll()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && subscriptions.isEmpty {
            service.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
                self?.refreshAcceptedValues()
            }.store(in: &subscriptions)
            Publishers.Merge(
                WallpaperManager.shared.$settings.map { _ in () },
                NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).map { _ in () }
            ).receive(on: RunLoop.main).sink { [weak self] _ in
                self?.refreshPresentation()
            }.store(in: &subscriptions)
            refreshAcceptedValues(forceRows: Set(titles.keys))
        }
    }

    override func viewDidHide() {
        super.viewDidHide()
        cancelTextureSelection()
        cancelShortcutSelection()
        invalidateTextureFeedback()
    }

    override func layout() {
        super.layout()
        textureStatus.preferredMaxLayoutWidth = max(1, bounds.width)
        let width = scrollView.contentSize.width
        guard width > 0, abs(width - measuredWidth) > 0.5 else { return }
        measuredWidth = width
        for (index, title) in titles {
            heights[index] = WorkshopPropertyRowView.height(
                style: Self.rowStyle(for: context.definitions[index].kind), content: titleContents[index] ?? .init(text: title), rowWidth: width)
        }
        updateHeaderHeight()
        flowLayout.invalidateLayout()
    }

    private static func rowStyle(for kind: SceneUserPropertyKind) -> WorkshopPropertyRowView.Style {
        switch kind {
        case .text, .unsupported: .note
        case .group: .group
        case .bool, .color: .inline
        case .combo: .choice
        case .sceneTexture, .userShortcut: .resource
        case .slider, .textInput: .stacked
        }
    }

    private func setupList() {
        reset.target = self
        reset.action = #selector(resetProperties)
        reset.toolTip = String(localized: "Restore Default Properties for This Scene Wallpaper")
        commonRows.onDisclosureChanged = { [weak self] in self?.toggleCommon() }
        commonRows.onEdit = { [weak self] edit in
            guard let self else { return }
            refreshPresentation(service.updateScenePresentation(for: record, edit: edit))
        }
        textureStatus.font = .systemFont(ofSize: 11)
        textureStatus.textColor = .secondaryLabelColor
        textureStatus.setAccessibilityIdentifier("scene-texture-update-status")
        textureStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textureStatus.isHidden = true
        flowLayout.minimumLineSpacing = WorkshopPropertyPanelLayout.rowSpacing
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.scrollDirection = .vertical
        refreshPresentation()
        list.collectionViewLayout = flowLayout
        list.backgroundColors = [.clear]
        list.isSelectable = false
        list.dataSource = self
        list.delegate = self
        list.register(NSView.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader, withIdentifier: .init("reset"))
        for kind in Set(context.definitions.map { $0.kind.rawValue }) {
            list.register(PropertyItem.self, forItemWithIdentifier: .init(kind))
        }
        scrollView.documentView = list
        WorkshopPropertyPanelLayout.install(in: self, status: textureStatus, scrollView: scrollView)
    }

    private func refreshPresentation(_ accepted: ScenePlaybackPresentation? = nil) {
        let value = accepted ?? service.scenePresentation(for: record)
        let settings = WallpaperManager.shared.settings
        let screens = settings.multiDisplayEnabled ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        reset.isEnabled = context.hasEditorControls || value != ScenePlaybackPresentation()
        let hasCrop = context.canvasAspect.map { aspect in
            screens.contains { abs($0.frame.width - $0.frame.height * aspect) > 1 }
        } ?? false
        let showsCrop = hasCrop && value.resolvedAlignment(systemFit: settings.videoFillMode == .aspectFit) == .cover
        let layoutChanged = commonRows.configure(value, hasCanvas: context.canvasAspect != nil, showsCrop: showsCrop,
            hasParallax: context.supportsMouseParallax, hasAudio: context.supportsAudioProcessing,
            hasSound: context.hasSound)
        if layoutChanged { updateHeaderHeight() }
    }

    private func updateHeaderHeight() {
        let height = commonRows.height(for: measuredWidth > 0 ? measuredWidth : 324)
        if flowLayout.headerReferenceSize.height != height {
            flowLayout.headerReferenceSize = NSSize(width: 1, height: height)
            flowLayout.invalidateLayout()
        }
    }

    private func toggleCommon() {
        if let schemeIndex {
            if !commonRows.isExpanded, let row = visibleRows.firstIndex(of: schemeIndex) {
                ((list.item(at: IndexPath(item: row, section: 0)) as? PropertyItem)?.cell)?.cancelEditing()
            }
            project(indices: [schemeIndex])
            list.reloadData()
        }
        refreshPresentation()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func prepareRows() {
        let displayResolver = WorkshopPropertyDisplayResolver(localization: context.propertyDisplayLocalization)
        for (index, definition) in context.definitions.enumerated() {
            var content = index == schemeIndex
                ? WorkshopPropertyTextContent(text: String(localized: "Theme Color"))
                : WorkshopPropertyTextContent(markup: displayResolver.string(definition.title))
            if definition.kind == .unsupported {
                let status = definition.runtimeType.isEmpty ? String(localized: "Missing Type") : String(localized: "Unsupported type: \(definition.runtimeType)")
                if content.isEmpty { content = .init(text: String(localized: "Unnamed Property")) }
                content = content.appendingLine(status)
            } else if definition.kind == .group || definition.kind == .text {
                guard !content.isEmpty else { continue }
            } else if content.isEmpty {
                content = .init(text: String(localized: "Unnamed Property"))
            }
            titles[index] = content.text
            titleContents[index] = content
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
            if index == schemeIndex { show = show && commonRows.isExpanded }
            if definition.kind == .combo {
                let options = service.visibleScenePropertyOptions(for: definition, inputs: inputs,
                    programs: context.conditionPrograms)
                visibleOptions[index] = options
                show = show && !options.isEmpty
            }
            if show { displayed.insert(index) } else { displayed.remove(index) }
        }
        visibleRows = context.definitions.indices.filter { displayed.contains($0) }
        if let schemeIndex, let row = visibleRows.firstIndex(of: schemeIndex), row > 0 {
            visibleRows.remove(at: row)
            visibleRows.insert(schemeIndex, at: 0)
        }
    }

    private func refreshAcceptedValues(forceRows: Set<Int> = []) {
        let current = service.scenePropertyOverrides(for: record)
        let shortcuts = service.storedSceneShortcutConfiguration(for: record)
        var changedRows = forceRows
        if shortcuts != shortcutConfiguration {
            changedRows.formUnion(context.definitions.indices.filter { context.definitions[$0].kind == .userShortcut })
        }
        guard current != overrides || !changedRows.isEmpty else { return }
        overrides = current
        shortcutConfiguration = shortcuts
        let accepted = context.catalog.effectiveValues(overrides: current)
        for (row, index) in visibleRows.enumerated()
        where values[context.definitions[index].key] != accepted[context.definitions[index].key] {
            ((list.item(at: IndexPath(item: row, section: 0)) as? PropertyItem)?.cell)?.cancelEditing()
        }
        updateValues(accepted, forceRows: changedRows)
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
        if let selection = shortcutSelection, !newIDs.contains(selection.index) { cancelShortcutSelection() }
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

    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                        at indexPath: IndexPath) -> NSView {
        let header = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: .init("reset"), for: indexPath)
        if commonRows.superview !== header {
            header.addSubview(commonRows)
            NSLayoutConstraint.activate([
                commonRows.leadingAnchor.constraint(equalTo: header.leadingAnchor), commonRows.trailingAnchor.constraint(equalTo: header.trailingAnchor),
                commonRows.topAnchor.constraint(equalTo: header.topAnchor)
            ])
        }
        return header
    }

    func focusNextPropertyControl(from responder: NSResponder?, reverse: Bool) -> Bool {
        guard let view = (responder as? NSTextView)?.delegate as? NSView ?? responder as? NSView else { return false }
        let fullAccess = NSApp.isFullKeyboardAccessEnabled
        let direction = reverse ? -1 : 1
        var targetRow: Int
        if fullAccess, view.isDescendant(of: commonRows) {
            let controls = commonRows.keyboardControls
            if let current = controls.firstIndex(where: { $0 === view }), controls.indices.contains(current + direction) {
                let target = controls[current + direction]
                target.scrollToVisible(target.bounds)
                return window?.makeFirstResponder(target) == true
            }
            guard !reverse else { return false }
            targetRow = 0
        } else {
            var ancestor: NSView? = view
            while let current = ancestor, !(current is PropertyCell) { ancestor = current.superview }
            guard let cell = ancestor as? PropertyCell, cell.isDescendant(of: self),
                  let index = cell.definitionIndex, let row = visibleRows.firstIndex(of: index) else { return false }
            let controls = cell.keyboardControls(fullAccess: fullAccess)
            if let current = controls.firstIndex(where: { $0 === view }), controls.indices.contains(current + direction) {
                return window?.makeFirstResponder(controls[current + direction]) == true
            }
            targetRow = row + direction
        }
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
        guard reverse, fullAccess else { return false }
        let header = NSRect(x: 0, y: 0, width: list.bounds.width, height: flowLayout.headerReferenceSize.height)
        let bottom = NSRect(x: header.minX, y: header.maxY - 1, width: 1, height: 1)
        list.scrollToVisible(bottom)
        list.layoutSubtreeIfNeeded()
        window?.displayIfNeeded()
        guard let target = commonRows.keyboardControls.last else { return false }
        target.scrollToVisible(target.bounds)
        return window?.makeFirstResponder(target) == true
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
        cancelShortcutSelection()
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
                self.showTextureStatus(String(localized: "Some properties couldn’t be reset to defaults, so your original choices were kept."), index: nil)
            case .superseded:
                break
            }
        }
        refreshPresentation()
    }

    private func selectSceneTexture(index: Int) {
        guard let window else { return }
        cancelTextureSelection()
        cancelShortcutSelection()
        let panel = NSOpenPanel()
        let requestID = UUID()
        textureSelection = (requestID, index, panel)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .mpeg4Movie, .quickTimeMovie]
            + [UTType(filenameExtension: "m4v")].compactMap { $0 }
        panel.prompt = String(localized: "Select")
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

    private func cancelShortcutSelection() {
        let pending = shortcutSelection
        shortcutSelection = nil
        if let panel = pending?.sheet as? NSOpenPanel { panel.cancel(nil) }
        else if let sheet = pending?.sheet {
            sheet.sheetParent?.endSheet(sheet, returnCode: .cancel)
            sheet.orderOut(nil)
        }
    }

    private func selectShortcut(index: Int, web: Bool) {
        guard let window, displayed.contains(index) else { return }
        cancelTextureSelection()
        cancelShortcutSelection()
        let requestID = UUID()
        let finish: (NSApplication.ModalResponse, URL?) -> Void = { [weak self, weak window] response, url in
            guard let self, let window, self.window === window,
                  self.shortcutSelection?.id == requestID else { return }
            self.shortcutSelection = nil
            guard response == .OK, let url, window.isVisible,
                  !self.isHiddenOrHasHiddenAncestor, self.displayed.contains(index) else { return }
            self.updateShortcut(url, index: index)
        }
        if web {
            let alert = NSAlert()
            alert.messageText = String(localized: "Configure URL Shortcut")
            alert.informativeText = String(localized: "Only HTTP and HTTPS URLs are supported. Commands and other protocols aren’t.")
            alert.addButton(withTitle: String(localized: "Save"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            let field = WallpaperFormTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
            let reference = service.sceneShortcutReference(forKey: context.definitions[index].key, record: record)
            field.stringValue = reference?.kind == .webURL ? reference!.url.absoluteString : "https://"
            field.setAccessibilityLabel(String(localized: "HTTP or HTTPS URL"))
            let surface = WallpaperFormFieldStyle.wrapping(field)
            surface.widthAnchor.constraint(equalToConstant: 360).isActive = true
            alert.accessoryView = surface
            alert.window.initialFirstResponder = field
            let presentedWindow = presentAppAlert(alert, in: window) { [weak self, weak window] response in
                guard response == .alertFirstButtonReturn else { finish(.cancel, nil); return }
                guard let self, let window, self.window === window,
                      self.shortcutSelection?.id == requestID,
                      self.canPresentTextureFeedback(in: window), self.displayed.contains(index) else { return }
                let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: text), ScenePlaybackShortcutReference(
                    kind: .webURL, url: url, bookmarkData: nil).isValid else {
                    self.shortcutSelection = nil
                    self.showTextureStatus(String(localized: "Enter an HTTP(S) URL without account information."), index: index)
                    return
                }
                finish(.OK, url)
            }
            shortcutSelection = (requestID, index, presentedWindow)
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = String(localized: "Select")
            shortcutSelection = (requestID, index, panel)
            panel.beginSheetModal(for: window) { [weak panel] response in finish(response, panel?.url) }
        }
    }

    private func updateShortcut(_ url: URL?, index: Int) {
        cancelShortcutSelection()
        let definition = context.definitions[index], requestID = UUID()
        textureFeedbackRequests[definition.key] = (requestID, index)
        resetFeedbackRequestID = nil
        clearTextureStatus()
        let initiatingWindow = window
        service.updateSceneShortcutPropertyURL(url, definition: definition, record: record) { [weak self, weak initiatingWindow] outcome in
            guard let self, let initiatingWindow,
                  self.textureFeedbackRequests[definition.key]?.id == requestID,
                  self.canPresentTextureFeedback(in: initiatingWindow), self.displayed.contains(index) else { return }
            self.textureFeedbackRequests.removeValue(forKey: definition.key)
            switch outcome {
            case .applied:
                self.clearTextureStatus()
                self.refreshAcceptedValues(forceRows: [index])
            case let .failed(message): self.showTextureStatus(message, index: index)
            case .unavailable: self.showTextureStatus(String(localized: "The current playback session didn’t accept the shortcut configuration; the previous choice was kept."), index: index)
            case .superseded: break
            }
        }
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
                self.showTextureStatus(String(localized: "“\(self.titles[index] ?? definition.key)” image or video couldn’t be updated; your previous selection was kept. Choose a readable PNG/JPEG image or MP4/MOV/M4V video."), index: index)
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

    private final class PropertyCell: WorkshopPropertyRowView, NSTextFieldDelegate {
        private weak var editor: SteamWorkshopScenePropertyEditorView?
        private var index: Int?
        private var generation: UInt64 = 0
        private struct Session { let index: Int; let generation: UInt64 }
        private var textSession: Session?
        private var sliderSession: Session?
        private var colorSession: Session?
        private let kind: SceneUserPropertyKind
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
        private var chooseWeb: NSButton?
        var definitionIndex: Int? { index }

        func keyboardControls(fullAccess: Bool) -> [NSView] {
            if !fullAccess { return field.map { [$0] } ?? [] }
            return [toggle, slider, field, colorWell, popup, clear?.isHidden == false ? clear : nil, choose, chooseWeb]
                .compactMap { $0 }
        }

        init(kind: SceneUserPropertyKind) {
            self.kind = kind
            super.init(style: SteamWorkshopScenePropertyEditorView.rowStyle(for: kind))
            if kind != .text && kind != .group && kind != .unsupported { setupControl() }
        }
        required init?(coder: NSCoder) { nil }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if window != nil && newWindow == nil { cancelEditing() }
            super.viewWillMove(toWindow: newWindow)
        }

        private func setupControl() {
            switch kind {
            case .bool:
                let button = NSButton(checkboxWithTitle: "", target: nil, action: nil)
                button.target = self
                button.action = #selector(boolChanged)
                addTrailingControl(button)
                toggle = button
            case .slider:
                let control = WorkshopPropertySlider(value: 0, minValue: 0, maxValue: 1,
                    target: self, action: #selector(sliderChanged))
                control.onTrackingBegan = { [weak self] _ in
                    guard let self, let index = self.index else { return }
                    self.sliderSession = Session(index: index, generation: self.generation)
                }
                control.onTrackingEnded = { [weak self] _ in self?.sliderSession = nil }
                let label = NSTextField(labelWithString: "")
                addSlider(control, summary: label)
                slider = control; summary = label
            case .textInput:
                let control = WallpaperFormTextField(string: "")
                control.delegate = self
                control.target = self
                control.action = #selector(textChanged)
                content.addArrangedSubview(WallpaperFormFieldStyle.wrapping(control))
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
            case .sceneTexture, .userShortcut:
                content.orientation = .vertical
                content.alignment = .trailing
                let label = NSTextField(labelWithString: "")
                label.lineBreakMode = .byTruncatingMiddle
                label.textColor = .secondaryLabelColor
                let buttons = NSStackView()
                buttons.orientation = .horizontal
                buttons.spacing = 8
                let shortcut = kind == .userShortcut
                let choose = NSButton(title: shortcut ? String(localized: "File or Folder") : String(localized: "Choose File"), target: self,
                    action: shortcut ? #selector(chooseShortcut) : #selector(chooseTexture))
                choose.bezelStyle = .rounded; choose.controlSize = .small
                choose.image = NSImage(systemSymbolName: shortcut ? "folder.badge.plus" : "photo.badge.plus", accessibilityDescription: nil)
                choose.imagePosition = .imageLeading
                choose.toolTip = shortcut ? String(localized: "Choose a local file or folder, then open it from the wallpaper button once configured") : String(localized: "Choose a PNG/JPEG image or an MP4/MOV/M4V video")
                let restore = NSButton(title: "", target: self, action: shortcut ? #selector(clearShortcut) : #selector(clearTexture))
                restore.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: shortcut ? String(localized: "Remove Shortcuts") : String(localized: "Restore Default Textures"))
                restore.isBordered = false; restore.toolTip = shortcut ? String(localized: "Remove Shortcut Configuration for This Device") : String(localized: "Restore Author’s Default Textures")
                buttons.addArrangedSubview(restore); buttons.addArrangedSubview(choose)
                if shortcut {
                    let web = NSButton(title: String(localized: "URL"), target: self, action: #selector(chooseShortcutWeb))
                    web.bezelStyle = .rounded; web.controlSize = .small
                    buttons.addArrangedSubview(web); chooseWeb = web
                }
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
            self.title.setPresentation(editor.titleContents[index] ?? .init(text: title))
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
                    popup.addItem(withTitle: String(localized: "Current value: \(current) (not selectable)"))
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
                if kind == .userShortcut {
                    let reference = editor.shortcutConfiguration.references[definition.key]
                    resourceName.stringValue = reference?.displayName ?? String(localized: "Not configured (stored on this device only)")
                    resourceName.toolTip = reference?.url.absoluteString
                    clear?.isHidden = reference == nil
                } else {
                    let url = editor.service.resolvedSceneTexturePropertyURL(forKey: definition.key, record: editor.record)
                    let hasSelection = url != nil || editor.overrides[definition.key] != nil
                    resourceName.stringValue = url?.lastPathComponent
                        ?? (hasSelection ? String(localized: "The selected image isn’t available right now") : String(localized: "Use Author’s Default Texture"))
                    clear?.isHidden = !hasSelection
                }
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
            guard editor.values[definition.key] != .number(value) else { return }
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
        @objc private func chooseShortcut(_ sender: NSButton) {
            guard let index else { return }; editor?.selectShortcut(index: index, web: false)
        }
        @objc private func chooseShortcutWeb(_ sender: NSButton) {
            guard let index else { return }; editor?.selectShortcut(index: index, web: true)
        }
        @objc private func clearShortcut(_ sender: NSButton) {
            guard let index else { return }; editor?.updateShortcut(nil, index: index)
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

}
