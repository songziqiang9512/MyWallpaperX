import Foundation

extension SteamWorkshopService {
    func resolvedWebRuntimePropertyPayload(
        for definition: SteamWorkshopWebPropertyDefinition,
        runtimeValue: SteamWorkshopWebPropertyValue,
        binding: ResolvedWebResourceBinding?,
        visibleOptions: [SteamWorkshopWebPropertyOption]
    ) -> [String: Any] {
        if binding?.kind == .pathlikePreset {
            var payload = Self.webRuntimeFallbackPropertyPayload(forKey: definition.key, value: runtimeValue)
            if !visibleOptions.isEmpty {
                payload["options"] = visibleOptions.map { option in
                    [
                        "label": option.label,
                        "value": Self.webRuntimeJSONValue(from: option.value, forKind: definition.kind)
                    ]
                }
            }
            return payload
        }

        return Self.webRuntimePropertyPayload(
            for: definition,
            value: runtimeValue,
            visibleOptions: visibleOptions
        )
    }

    func resolvedWebRuntimePropertyPayloadJSON(
        for definition: SteamWorkshopWebPropertyDefinition,
        runtimeValue: SteamWorkshopWebPropertyValue,
        binding: ResolvedWebResourceBinding?,
        visibleOptions: [SteamWorkshopWebPropertyOption]
    ) -> String? {
        let payload = [
            definition.key: resolvedWebRuntimePropertyPayload(
                for: definition,
                runtimeValue: runtimeValue,
                binding: binding,
                visibleOptions: visibleOptions
            )
        ]

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    func effectiveWebPropertiesJSONString(
        for record: SteamWorkshopDownloadRecord,
        definitions: [SteamWorkshopWebPropertyDefinition]? = nil,
        valuesOverride: [String: SteamWorkshopWebPropertyValue]? = nil,
        bindingContext: WebAuthorBindingContext? = nil
    ) -> String? {
        let resolvedDefinitions = definitions ?? webPropertyDefinitions(for: record)
        let effectiveValues = valuesOverride ?? effectiveWebPropertyValues(for: record, definitions: resolvedDefinitions)
        var runtimeProperties = Dictionary(uniqueKeysWithValues: resolvedDefinitions.map { definition in
            let rawValue = effectiveValues[definition.key] ?? definition.defaultValue
            return (
                definition.key,
                resolvedWebRuntimeProperty(
                    forKey: definition.key,
                    definition: definition,
                    rawValue: rawValue,
                    record: record, bindingContext: bindingContext
                )
            )
        })

        let pathlikePresetValues = bindingContext?.pathlikePresetValues ?? webShellResourcePathLikePresetValues(for: record)
        let pathlikePresetKeys = Set(pathlikePresetValues.keys)
        let missingPathlikePresetKeys = pathlikePresetKeys.filter { runtimeProperties[$0] == nil }
        for key in missingPathlikePresetKeys {
            guard let rawValue = effectiveValues[key] ?? pathlikePresetValues[key] else { continue }
            let binding = resolvedWebResourceBinding(
                forKey: key,
                definition: nil,
                rawValue: rawValue,
                record: record, bindingContext: bindingContext
            )
            let value = binding.flatMap { $0.resolvedPath }.map(SteamWorkshopWebPropertyValue.string) ?? rawValue
            runtimeProperties[key] = (value, binding)
        }

        guard !resolvedDefinitions.isEmpty || !runtimeProperties.isEmpty else {
            return Self.webRuntimePropertyPayloadJSON(definitions: [], values: runtimeProperties.mapValues { $0.value })
        }

        let visibleOptionsByKey = Dictionary(uniqueKeysWithValues: resolvedDefinitions.map { definition in
            (
                definition.key,
                visibleWebPropertyOptions(
                    for: definition,
                    values: effectiveValues,
                    definitions: resolvedDefinitions
                )
            )
        })

        var normalizedProperties: [String: [String: Any]] = [:]
        for definition in resolvedDefinitions where definition.kind != .label && definition.kind != .group {
            let property = runtimeProperties[definition.key]
            normalizedProperties[definition.key] = resolvedWebRuntimePropertyPayload(
                for: definition,
                runtimeValue: property?.value ?? definition.defaultValue,
                binding: property?.binding,
                visibleOptions: visibleOptionsByKey[definition.key] ?? []
            )
        }

        for key in missingPathlikePresetKeys {
            guard normalizedProperties[key] == nil,
                  let runtimeValue = runtimeProperties[key]?.value else {
                continue
            }
            normalizedProperties[key] = Self.webRuntimeFallbackPropertyPayload(forKey: key, value: runtimeValue)
        }

        if normalizedProperties.isEmpty {
            return Self.webRuntimePropertyPayloadJSON(definitions: [], values: runtimeProperties.mapValues { $0.value })
        }
        guard JSONSerialization.isValidJSONObject(normalizedProperties),
              let normalizedData = try? JSONSerialization.data(withJSONObject: normalizedProperties),
              let json = String(data: normalizedData, encoding: .utf8) else {
            return Self.webRuntimePropertyPayloadJSON(definitions: [], values: runtimeProperties.mapValues { $0.value })
        }
        return json
    }

    static func webRuntimePropertyPayload(
        for definition: SteamWorkshopWebPropertyDefinition,
        value: SteamWorkshopWebPropertyValue,
        visibleOptions: [SteamWorkshopWebPropertyOption]
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "type": definition.runtimeType,
            "value": webRuntimeJSONValue(from: value, forKind: definition.kind)
        ]
        mergeWebRuntimePropertyMetadata(into: &payload, definition: definition)
        if let text = webRuntimeSelectedOptionText(for: definition, value: value) {
            payload["text"] = text
        }
        if !visibleOptions.isEmpty {
            payload["options"] = visibleOptions.map { option in
                [
                    "label": option.label,
                    "value": webRuntimeJSONValue(from: option.value, forKind: definition.kind)
                ]
            }
        }
        return payload
    }

    static func webRuntimeFallbackPropertyPayload(
        forKey key: String,
        value: SteamWorkshopWebPropertyValue
    ) -> [String: Any] {
        let rawPath = value.stringValue ?? ""
        var payload: [String: Any] = [
            "type": "text",
            "value": webRuntimeJSONValue(from: value)
        ]

        guard let semantic = fallbackResourceSemantic(forKey: key, rawPath: rawPath) else {
            return payload
        }

        switch semantic {
        case .directory:
            payload["type"] = "directory"
        case let .file(fileType):
            payload["type"] = "file"
            if let fileType {
                payload["filetype"] = fileType
            }
        }

        return payload
    }

    static func webRuntimePropertyPayloadJSON(
        definitions: [SteamWorkshopWebPropertyDefinition],
        values: [String: SteamWorkshopWebPropertyValue],
        visibleOptionsByKey: [String: [SteamWorkshopWebPropertyOption]] = [:]
    ) -> String? {
        let keys = Set(definitions.map(\.key)).union(values.keys)
        var payload: [String: [String: Any]] = [:]
        for key in keys {
            let definition = definitions.first(where: { $0.key == key })
            let value = values[key] ?? definition?.defaultValue ?? .string("")
            var propertyPayload: [String: Any] = [
                "type": definition?.runtimeType ?? "text",
                "value": webRuntimeJSONValue(from: value, forKind: definition?.kind),
                "options": (visibleOptionsByKey[key] ?? []).map { option in
                    [
                        "label": option.label,
                        "value": webRuntimeJSONValue(from: option.value, forKind: definition?.kind)
                    ]
                }
            ]
            if let definition {
                mergeWebRuntimePropertyMetadata(into: &propertyPayload, definition: definition)
                if let text = webRuntimeSelectedOptionText(for: definition, value: value) {
                    propertyPayload["text"] = text
                }
            }
            payload[key] = propertyPayload
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private static func webRuntimeSelectedOptionText(
        for definition: SteamWorkshopWebPropertyDefinition,
        value: SteamWorkshopWebPropertyValue
    ) -> String? {
        guard definition.kind == .combo else { return nil }
        return definition.options.first(where: { $0.value == value })?.label
    }

    private static func mergeWebRuntimePropertyMetadata(
        into payload: inout [String: Any],
        definition: SteamWorkshopWebPropertyDefinition
    ) {
        if let minimumValue = definition.minimumValue {
            payload["min"] = minimumValue
        }
        if let maximumValue = definition.maximumValue {
            payload["max"] = maximumValue
        }
        if let fractionalPrecision = effectiveWebSliderPrecision(for: definition) {
            payload["precision"] = fractionalPrecision
        }
        if definition.kind == .slider {
            payload["fraction"] = definition.allowsFractionalValues
        }
        if let directoryMode = definition.directoryMode {
            payload["mode"] = directoryMode
        }
        if let fileType = definition.fileType {
            payload["filetype"] = fileType
        }
    }

    private static func webRuntimeJSONValue(from value: SteamWorkshopWebPropertyValue) -> Any {
        webRuntimeJSONValue(from: value, forKind: nil)
    }

    private static func webRuntimeJSONValue(
        from value: SteamWorkshopWebPropertyValue,
        forKind _: SteamWorkshopWebPropertyKind?
    ) -> Any {
        switch value {
        case let .string(string):
            return string
        case let .number(number):
            return number
        case let .bool(bool):
            return bool
        }
    }
}
