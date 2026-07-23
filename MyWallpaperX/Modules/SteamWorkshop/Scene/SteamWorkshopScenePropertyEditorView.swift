import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SteamWorkshopScenePropertyEditorView: View {
    let record: SteamWorkshopDownloadRecord
    let context: SteamWorkshopScenePropertyContext

    @ObservedObject private var service: SteamWorkshopService
    @State private var values: [String: SceneUserPropertyValue]

    init(
        record: SteamWorkshopDownloadRecord,
        context: SteamWorkshopScenePropertyContext
    ) {
        self.record = record
        self.context = context
        _service = ObservedObject(wrappedValue: .shared)
        _values = State(initialValue: context.effectiveValues)
    }

    private var visibleDefinitions: [SceneUserPropertyDefinition] {
        context.definitions.filter {
            service.shouldDisplaySceneProperty($0, values: values, catalog: context.catalog)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("属性调节")
                    .font(.headline)
                Spacer(minLength: 0)
                Button("恢复默认", systemImage: "arrow.counterclockwise") {
                    values = context.catalog.defaultValues
                    service.resetScenePropertyValues(
                        for: record,
                        defaultValues: context.catalog.defaultValues
                    )
                }
                .help("恢复这个 Scene 壁纸的默认属性")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(visibleDefinitions) { definition in
                        propertyRow(definition)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 440, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func propertyRow(_ definition: SceneUserPropertyDefinition) -> some View {
        switch definition.kind {
        case .bool:
            Toggle(title(for: definition), isOn: boolBinding(for: definition))
                .toggleStyle(.switch)
        case .slider:
            sliderRow(definition)
        case .color:
            ColorPicker(
                title(for: definition),
                selection: colorBinding(for: definition),
                supportsOpacity: false
            )
        case .combo:
            comboRow(definition)
        case .textInput:
            TextField(title(for: definition), text: textBinding(for: definition))
                .textFieldStyle(.roundedBorder)
        case .group:
            if let text = displayText(for: definition) {
                Text(text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        case .text:
            if let text = displayText(for: definition) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .sceneTexture:
            sceneTextureRow(definition)
        case .unsupported:
            EmptyView()
        }
    }

    private func sceneTextureRow(_ definition: SceneUserPropertyDefinition) -> some View {
        let selectedURL = service.resolvedSceneTexturePropertyURL(
            forKey: definition.key,
            record: record
        )
        return VStack(alignment: .leading, spacing: 7) {
            Text(title(for: definition))
            HStack(spacing: 8) {
                Text(selectedURL?.lastPathComponent ?? "使用作者默认纹理")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if selectedURL != nil {
                    Button {
                        values[definition.key] = definition.defaultValue ?? .string("")
                        service.updateSceneTexturePropertyURL(
                            nil,
                            definition: definition,
                            record: record
                        )
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("恢复作者提供的默认纹理")
                }
                Button("选择图像", systemImage: "photo.badge.plus") {
                    selectSceneTexture(for: definition)
                }
                .help("选择 PNG 或 JPEG 图像")
            }
        }
    }

    private func selectSceneTexture(for definition: SceneUserPropertyDefinition) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg]
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard service.updateSceneTexturePropertyURL(
            url,
            definition: definition,
            record: record
        ) else { return }
        values[definition.key] = .string(url.path)
    }

    private func sliderRow(_ definition: SceneUserPropertyDefinition) -> some View {
        let range = sliderRange(for: definition)
        let step = sliderStep(for: definition, range: range)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title(for: definition))
                Spacer(minLength: 12)
                Text(formattedSliderValue(definition))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: sliderBinding(for: definition, range: range),
                in: range,
                step: step
            )
        }
    }

    @ViewBuilder
    private func comboRow(_ definition: SceneUserPropertyDefinition) -> some View {
        let options = service.visibleScenePropertyOptions(
            for: definition,
            values: values,
            catalog: context.catalog
        )
        if !options.isEmpty {
            Picker(title(for: definition), selection: valueBinding(for: definition)) {
                ForEach(options) { option in
                    Text(displayText(option.label) ?? option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func boolBinding(for definition: SceneUserPropertyDefinition) -> Binding<Bool> {
        Binding(
            get: { values[definition.key]?.boolValue ?? false },
            set: { commit(.bool($0), definition: definition) }
        )
    }

    private func sliderBinding(
        for definition: SceneUserPropertyDefinition,
        range: ClosedRange<Double>
    ) -> Binding<Double> {
        Binding(
            get: {
                let value = values[definition.key]?.numberValue
                    ?? definition.defaultValue?.numberValue
                    ?? range.lowerBound
                return min(max(value, range.lowerBound), range.upperBound)
            },
            set: { commit(.number($0), definition: definition) }
        )
    }

    private func colorBinding(for definition: SceneUserPropertyDefinition) -> Binding<Color> {
        Binding(
            get: {
                guard case let .string(raw) = values[definition.key],
                      let components = SteamWorkshopService.parseWebColorComponents(from: raw) else {
                    return .white
                }
                return Color(red: components.red, green: components.green, blue: components.blue)
            },
            set: { color in
                guard let converted = NSColor(color).usingColorSpace(.deviceRGB) else { return }
                let value = String(
                    format: "%.6f %.6f %.6f",
                    converted.redComponent,
                    converted.greenComponent,
                    converted.blueComponent
                )
                commit(.string(value), definition: definition)
            }
        )
    }

    private func textBinding(for definition: SceneUserPropertyDefinition) -> Binding<String> {
        Binding(
            get: { values[definition.key]?.stringValue ?? "" },
            set: { commit(.string($0), definition: definition) }
        )
    }

    private func valueBinding(
        for definition: SceneUserPropertyDefinition
    ) -> Binding<SceneUserPropertyValue> {
        Binding(
            get: { values[definition.key] ?? definition.defaultValue ?? .string("") },
            set: { commit($0, definition: definition) }
        )
    }

    private func commit(
        _ value: SceneUserPropertyValue,
        definition: SceneUserPropertyDefinition
    ) {
        values[definition.key] = value
        service.updateScenePropertyValue(value, definition: definition, record: record)
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

    private func title(for definition: SceneUserPropertyDefinition) -> String {
        let title = displayText(for: definition) ?? ""
        return title.isEmpty ? definition.key : title
    }

    private func displayText(for definition: SceneUserPropertyDefinition) -> String? {
        if definition.kind == .text || definition.kind == .group,
           definition.title.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().hasPrefix("ui_editor_") {
            return nil
        }
        return displayText(definition.title)
    }

    private func displayText(_ rawText: String) -> String? {
        let withLineBreaks = rawText.replacingOccurrences(
            of: "(?i)<br(?:\\s|/|&nbsp;)*?>",
            with: "\n",
            options: .regularExpression
        )
        let withoutTags = withLineBreaks.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        var text = SteamWorkshopService.normalizedWebPropertyTitleText(withoutTags)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.lowercased().hasPrefix("ui_editor_") {
            text = humanizedEditorKey(text)
        }
        return text.isEmpty ? nil : text
    }

    private func humanizedEditorKey(_ rawKey: String) -> String {
        var key = String(rawKey.dropFirst("ui_editor_".count))
        for prefix in [
            "script_insert_property_",
            "character_separation_",
            "properties_",
            "property_",
            "effect_",
            "preset_"
        ] where key.hasPrefix(prefix) {
            key.removeFirst(prefix.count)
            break
        }
        if key.hasSuffix("_title") {
            key.removeLast("_title".count)
        }
        return key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
