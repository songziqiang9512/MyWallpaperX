import AppKit
import UniformTypeIdentifiers
import ObjectiveC

/// Author controls reuse the existing Web property persistence and preview owners.
final class SteamWorkshopWebPropertyEditorView: NSView {
    private let service = SteamWorkshopService.shared
    private let record: SteamWorkshopDownloadRecord
    private let contentStack = NSStackView()
    private let scrollView = InspectorFadingScrollView(fadeRatio: 0)

    init(record: SteamWorkshopDownloadRecord) {
        self.record = record
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        let document = PropertyDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(contentStack)
        scrollView.documentView = document
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            contentStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: document.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        rebuild()
    }
    required init?(coder: NSCoder) { nil }

    private func rebuild(preservingScrollPosition: Bool = true) {
        let origin = scrollView.contentView.bounds.origin
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let descriptor = service.resolvedWebProjectDescriptor(for: record) else {
            contentStack.addArrangedSubview(label("当前壁纸的属性暂不可用，请先完成依赖下载。", font: .systemFont(ofSize: 13), color: .secondaryLabelColor, lines: 0))
            return
        }
        let values = service.effectiveWebPropertyValues(for: record, descriptor: descriptor)
        let definitions = descriptor.propertyDefinitions.filter {
            service.shouldRenderWebPropertyControl($0, staticContentSummary: descriptor.staticContentSummary)
                && service.shouldDisplayWebProperty($0, values: values, definitions: descriptor.propertyDefinitions)
        }
        let reset = NSButton(title: "恢复默认", target: self, action: #selector(resetProperties))
        reset.bezelStyle = .rounded
        let resetRow = NSStackView(views: [spacer(), reset])
        resetRow.orientation = .horizontal
        contentStack.addArrangedSubview(resetRow)
        resetRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        if definitions.isEmpty {
            contentStack.addArrangedSubview(label("作者没有提供可调节的属性。", font: .systemFont(ofSize: 13), color: .secondaryLabelColor, lines: 0))
        }
        for definition in definitions {
            let row = webPropertyControl(definition: definition, value: values[definition.key] ?? definition.defaultValue,
                visibleOptions: service.visibleWebPropertyOptions(for: definition, values: values, definitions: descriptor.propertyDefinitions), record: record)
            contentStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }
        layoutSubtreeIfNeeded()
        if preservingScrollPosition { scrollView.contentView.scroll(to: origin) }
    }
    @objc private func resetProperties() { service.resetWebPropertyValues(for: record); rebuild() }
    private func label(_ text: String, font: NSFont, color: NSColor, lines: Int) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font; label.textColor = color; label.maximumNumberOfLines = lines
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
    private func spacer() -> NSView {
        let view = NSView(); view.setContentHuggingPriority(.defaultLow, for: .horizontal); return view
    }
    private func webPropertyControl(
        definition: SteamWorkshopWebPropertyDefinition,
        value: SteamWorkshopWebPropertyValue,
        visibleOptions: [SteamWorkshopWebPropertyOption],
        record: SteamWorkshopDownloadRecord
    ) -> NSView {
        if definition.kind == .group || definition.kind == .label {
            return controlView(definition: definition, value: value, visibleOptions: visibleOptions, record: record, summaryLabel: nil)
        }
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false
        let title = label(definition.title, font: .systemFont(ofSize: 13), color: .labelColor, lines: 0)
        let summary = definition.kind == .slider ? label(valueSummary(value, definition: definition), font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor, lines: 1) : nil
        let control = controlView(definition: definition, value: value, visibleOptions: visibleOptions, record: record, summaryLabel: summary)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setAccessibilityLabel(definition.title)
        row.addArrangedSubview(title)
        if definition.kind == .toggle { row.addArrangedSubview(spacer()) }
        row.addArrangedSubview(control)
        if let summary { row.addArrangedSubview(summary) }
        title.widthAnchor.constraint(equalToConstant: 112).isActive = true
        if summary == nil && definition.kind != .toggle {
            control.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -128).isActive = true
        }
        return row
    }

    private func controlView(
        definition: SteamWorkshopWebPropertyDefinition,
        value: SteamWorkshopWebPropertyValue,
        visibleOptions: [SteamWorkshopWebPropertyOption],
        record: SteamWorkshopDownloadRecord,
        summaryLabel: NSTextField?
    ) -> NSView {
        switch definition.kind {
        case .slider:
            let target = WebPropertyActionTarget(view: self, record: record, definition: definition, summaryLabel: summaryLabel)
            let slider = WebPropertySlider(value: value.numberValue ?? definition.defaultValue.numberValue ?? definition.minimumValue ?? 0,
                                           minValue: definition.minimumValue ?? 0,
                                           maxValue: definition.maximumValue ?? max((definition.minimumValue ?? 0) + 1, value.numberValue ?? 1),
                                           target: target,
                                           action: #selector(WebPropertyActionTarget.sliderChanged(_:)))
            slider.isContinuous = true
            slider.identifier = NSUserInterfaceItemIdentifier(definition.key)
            slider.translatesAutoresizingMaskIntoConstraints = false
            slider.onTrackingEnded = { [weak target] slider in
                target?.sliderTrackingEnded(slider)
            }
            retainActionTarget(target, for: slider)
            return slider
        case .toggle:
            let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
            checkbox.state = (value.boolValue ?? definition.defaultValue.boolValue ?? false) ? .on : .off
            let target = WebPropertyActionTarget(view: self, record: record, definition: definition)
            checkbox.target = target
            checkbox.action = #selector(WebPropertyActionTarget.toggleChanged(_:))
            retainActionTarget(target, for: checkbox)
            return checkbox
        case .combo:
            let popup = NSPopUpButton()
            if visibleOptions.isEmpty {
                popup.addItem(withTitle: "当前没有可选项")
                popup.isEnabled = false
            } else {
                var selectedValueID: String?
                if visibleOptions.contains(where: { $0.value == value }) == false {
                    popup.addItem(withTitle: "当前值：\(valueSummary(value, definition: definition))（不可选）")
                    popup.lastItem?.isEnabled = false
                    popup.selectItem(at: 0)
                }
                visibleOptions.forEach { option in
                    popup.addItem(withTitle: option.label)
                    popup.lastItem?.representedObject = option.id as NSString
                    if option.value == value {
                        selectedValueID = option.id
                    }
                }
                if let selectedIndex = visibleOptions.firstIndex(where: { $0.value == value }) {
                    popup.selectItem(withTitle: visibleOptions[selectedIndex].label)
                }
                if let selectedValueID,
                   let item = popup.itemArray.first(where: { ($0.representedObject as? String) == selectedValueID }) {
                    popup.select(item)
                }
            }
            let target = WebPropertyActionTarget(view: self, record: record, definition: definition, visibleOptions: visibleOptions)
            popup.target = target
            popup.action = #selector(WebPropertyActionTarget.popupChanged(_:))
            retainActionTarget(target, for: popup)
            return popup
        case .file, .directory:
            let row = NSStackView()
            row.orientation = .vertical
            row.alignment = .trailing
            row.spacing = 8
            let buttonRow = NSStackView()
            buttonRow.orientation = .horizontal
            buttonRow.spacing = 10
            let choose = NSButton(title: definition.kind == .directory ? "选择文件夹" : "选择文件", target: nil, action: nil)
            choose.bezelStyle = .rounded
            choose.controlSize = .small
            let target = WebPropertyActionTarget(view: self, record: record, definition: definition, summaryLabel: summaryLabel)
            choose.target = target
            choose.action = #selector(WebPropertyActionTarget.choosePath(_:))
            retainActionTarget(target, for: choose)
            buttonRow.addArrangedSubview(spacer())
            buttonRow.addArrangedSubview(choose)
            if !(value.stringValue ?? "").isEmpty {
                let clear = NSButton(title: "清空", target: target, action: #selector(WebPropertyActionTarget.clearPath(_:)))
                clear.bezelStyle = .rounded
                clear.controlSize = .small
                buttonRow.addArrangedSubview(clear)
            }
            row.addArrangedSubview(buttonRow)
            row.addArrangedSubview(textField(textValue(value, definition: definition), placeholder: definition.kind == .directory ? "选择目录路径" : "选择文件路径", target: target, action: #selector(WebPropertyActionTarget.textChanged(_:))))
            for child in row.arrangedSubviews {
                child.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
            }
            return row
        case .label, .group:
            return label(definition.title, font: definition.kind == .group ? .systemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 12), color: .labelColor, lines: 0)
        case .color:
            return colorControl(value: value, definition: definition, record: record, summaryLabel: summaryLabel)
        case .text, .unknown:
            let target = WebPropertyActionTarget(view: self, record: record, definition: definition, summaryLabel: summaryLabel)
            return textField(textValue(value, definition: definition), placeholder: definition.title, target: target, action: #selector(WebPropertyActionTarget.textChanged(_:)))
        }
    }

    private func colorControl(
        value: SteamWorkshopWebPropertyValue,
        definition: SteamWorkshopWebPropertyDefinition,
        record: SteamWorkshopDownloadRecord,
        summaryLabel: NSTextField?
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let target = WebPropertyActionTarget(view: self, record: record, definition: definition, summaryLabel: summaryLabel)
        let colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 42, height: 26))
        colorWell.color = color(from: value.stringValue ?? definition.defaultValue.stringValue ?? "0 0 0")
        colorWell.target = target
        colorWell.action = #selector(WebPropertyActionTarget.colorChanged(_:))
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        retainActionTarget(target, for: colorWell)
        row.addArrangedSubview(colorWell)

        let field = textField(
            textValue(value, definition: definition),
            placeholder: "R G B",
            target: target,
            action: #selector(WebPropertyActionTarget.textChanged(_:))
        )
        target.textField = field
        row.addArrangedSubview(field)

        NSLayoutConstraint.activate([
            colorWell.widthAnchor.constraint(equalToConstant: 42),
            colorWell.heightAnchor.constraint(equalToConstant: 26)
        ])
        return row
    }

    private func retainActionTarget(_ target: WebPropertyActionTarget, for control: NSControl) {
        objc_setAssociatedObject(control, "[\(Unmanaged.passUnretained(control).toOpaque())].target", target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private func updateWebProperty(_ value: SteamWorkshopWebPropertyValue, definition: SteamWorkshopWebPropertyDefinition, record: SteamWorkshopDownloadRecord, preview: Bool = false) {
        if preview {
            service.previewWebPropertyValue(value, for: definition, record: record)
            return
        } else {
            service.updateWebPropertyValue(value, for: definition, record: record)
        }
        DispatchQueue.main.async { [weak self] in self?.rebuild(preservingScrollPosition: true) }
    }

    private func textField(_ value: String, placeholder: String, target: AnyObject, action: Selector) -> NSTextField {
        let field = NSTextField(string: value)
        field.placeholderString = placeholder
        field.target = target
        field.action = action
        field.delegate = target as? NSTextFieldDelegate
        field.translatesAutoresizingMaskIntoConstraints = false
        retainActionTarget(target as! WebPropertyActionTarget, for: field)
        return field
    }

    private func textValue(_ value: SteamWorkshopWebPropertyValue, definition: SteamWorkshopWebPropertyDefinition) -> String {
        if let stringValue = value.stringValue { return stringValue }
        if let numberValue = value.numberValue { return formattedNumber(numberValue, allowsFractional: true, precision: definition.fractionalPrecision) }
        if let boolValue = value.boolValue { return boolValue ? "true" : "false" }
        return ""
    }

    private func color(from raw: String) -> NSColor {
        guard let components = SteamWorkshopService.parseWebColorComponents(from: raw) else {
            return .black
        }
        return NSColor(
            deviceRed: components.red,
            green: components.green,
            blue: components.blue,
            alpha: 1
        )
    }

    private func colorString(from color: NSColor) -> String {
        let resolved = color.usingColorSpace(.deviceRGB) ?? .black
        return String(
            format: "%.6f %.6f %.6f",
            resolved.redComponent,
            resolved.greenComponent,
            resolved.blueComponent
        )
    }

    private func valueSummary(_ value: SteamWorkshopWebPropertyValue, definition: SteamWorkshopWebPropertyDefinition) -> String {
        if let stringValue = value.stringValue { return SteamWorkshopService.normalizedWebDisplayText(stringValue) }
        if let numberValue = value.numberValue { return formattedNumber(numberValue, allowsFractional: definition.allowsFractionalValues, precision: definition.fractionalPrecision) }
        if let boolValue = value.boolValue { return boolValue ? "开" : "关" }
        return "-"
    }

    private func formattedNumber(_ value: Double, allowsFractional: Bool, precision: Int?) -> String {
        if !allowsFractional {
            return String(Int(value.rounded()))
        }
        let digits = max(precision ?? 2, 0)
        return String(format: "%.\(digits)f", value)
    }

    private func normalizedSliderValue(_ value: Double, definition: SteamWorkshopWebPropertyDefinition) -> Double {
        if definition.allowsFractionalValues {
            let precision = SteamWorkshopService.effectiveWebSliderPrecision(for: definition) ?? 2
            guard precision >= 0 else { return value }
            let scale = pow(10.0, Double(precision))
            return (value * scale).rounded() / scale
        }
        return value.rounded()
    }

    private func allowedContentTypes(for fileType: String?) -> [UTType] {
        guard let normalized = fileType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else { return [] }
        switch normalized {
        case "image": return [.image]
        case "video": return [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        case "audio", "music": return [.audio, .mp3, .mpeg4Audio]
        case "font": return [.font]
        default: return []
        }
    }

    private final class WebPropertySlider: NSSlider {
        var isTrackingMouse = false
        var onTrackingEnded: ((NSSlider) -> Void)?

        override func mouseDown(with event: NSEvent) {
            isTrackingMouse = true
            super.mouseDown(with: event)
            isTrackingMouse = false
            onTrackingEnded?(self)
        }
    }

    private final class WebPropertyActionTarget: NSObject, NSTextFieldDelegate {
        weak var view: SteamWorkshopWebPropertyEditorView?
        let record: SteamWorkshopDownloadRecord
        let definition: SteamWorkshopWebPropertyDefinition
        let visibleOptions: [SteamWorkshopWebPropertyOption]
        weak var summaryLabel: NSTextField?
        weak var textField: NSTextField?
        private var pendingColorString: String?
        private var colorPanelCloseObserver: NSObjectProtocol?

        init(
            view: SteamWorkshopWebPropertyEditorView,
            record: SteamWorkshopDownloadRecord,
            definition: SteamWorkshopWebPropertyDefinition,
            visibleOptions: [SteamWorkshopWebPropertyOption] = [],
            summaryLabel: NSTextField? = nil
        ) {
            self.view = view
            self.record = record
            self.definition = definition
            self.visibleOptions = visibleOptions
            self.summaryLabel = summaryLabel
        }

        deinit {
            if let colorPanelCloseObserver {
                NotificationCenter.default.removeObserver(colorPanelCloseObserver)
            }
        }

        @objc func toggleChanged(_ sender: NSButton) {
            view?.updateWebProperty(.bool(sender.state == .on), definition: definition, record: record)
        }

        @objc func popupChanged(_ sender: NSPopUpButton) {
            guard let selectedID = sender.selectedItem?.representedObject as? String,
                  let option = visibleOptions.first(where: { $0.id == selectedID }) else { return }
            view?.updateWebProperty(option.value, definition: definition, record: record)
        }

        @objc func sliderChanged(_ sender: NSSlider) {
            let normalized = view?.normalizedSliderValue(sender.doubleValue, definition: definition) ?? sender.doubleValue
            sender.doubleValue = normalized
            summaryLabel?.stringValue = view?.valueSummary(.number(normalized), definition: definition) ?? String(normalized)
            view?.updateWebProperty(.number(normalized), definition: definition, record: record, preview: true)
            if let slider = sender as? WebPropertySlider {
                if !slider.isTrackingMouse {
                    commitSliderValue(sender)
                }
            } else if !sender.isHighlighted {
                commitSliderValue(sender)
            }
        }

        @objc func textChanged(_ sender: NSTextField) {
            commitTextFieldValue(sender.stringValue)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            previewTextFieldValue(field.stringValue)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            commitTextFieldValue(field.stringValue)
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            guard let colorString = view?.colorString(from: sender.color) else { return }
            observeColorPanelCloseIfNeeded()
            pendingColorString = colorString
            summaryLabel?.stringValue = view?.valueSummary(.string(colorString), definition: definition) ?? colorString
            textField?.stringValue = colorString
            view?.updateWebProperty(.string(colorString), definition: definition, record: record, preview: true)
        }

        @objc func choosePath(_ sender: NSButton) {
            let panel = NSOpenPanel()
            let selectsDirectories = definition.kind == .directory
            panel.canChooseFiles = !selectsDirectories
            panel.canChooseDirectories = selectsDirectories
            panel.allowsMultipleSelection = false
            panel.resolvesAliases = true
            panel.canCreateDirectories = selectsDirectories
            panel.prompt = selectsDirectories ? "选择目录" : "选择文件"
            if !selectsDirectories {
                panel.allowedContentTypes = view?.allowedContentTypes(for: definition.fileType) ?? []
            }
            if panel.runModal() == .OK, let url = panel.url {
                view?.updateWebProperty(.string(url.path), definition: definition, record: record)
            }
        }

        @objc func clearPath(_ sender: NSButton) {
            view?.updateWebProperty(.string(""), definition: definition, record: record)
        }

        private func observeColorPanelCloseIfNeeded() {
            guard colorPanelCloseObserver == nil else { return }
            colorPanelCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: NSColorPanel.shared,
                queue: .main
            ) { [weak self] _ in
                self?.commitPendingColor()
            }
        }

        private func commitSliderValue(_ sender: NSSlider) {
            let normalized = view?.normalizedSliderValue(sender.doubleValue, definition: definition) ?? sender.doubleValue
            sender.doubleValue = normalized
            summaryLabel?.stringValue = view?.valueSummary(.number(normalized), definition: definition) ?? String(normalized)
            view?.updateWebProperty(.number(normalized), definition: definition, record: record)
        }

        func sliderTrackingEnded(_ sender: NSSlider) {
            commitSliderValue(sender)
        }

        private func previewTextFieldValue(_ rawValue: String) {
            pendingColorString = nil
            let value = webPropertyValue(from: rawValue)
            summaryLabel?.stringValue = view?.valueSummary(value, definition: definition) ?? rawValue
            view?.updateWebProperty(value, definition: definition, record: record, preview: true)
        }

        private func commitTextFieldValue(_ rawValue: String) {
            pendingColorString = nil
            view?.updateWebProperty(webPropertyValue(from: rawValue), definition: definition, record: record)
        }

        private func commitPendingColor() {
            guard let pendingColorString else { return }
            self.pendingColorString = nil
            view?.updateWebProperty(.string(pendingColorString), definition: definition, record: record)
        }

        private func webPropertyValue(from rawValue: String) -> SteamWorkshopWebPropertyValue {
            if definition.kind == .slider, let value = Double(rawValue) {
                return .number(value)
            }
            return .string(rawValue)
        }
    }
}

private final class PropertyDocumentView: NSView {
    override var isFlipped: Bool { true }
}
