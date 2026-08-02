import Foundation

nonisolated enum SceneUserPropertyPathComponent: Codable, Equatable, Hashable {
    case key(String)
    case index(Int)
}

nonisolated struct SceneUserPropertyPath: Codable, Equatable, Hashable, CustomStringConvertible {
    let components: [SceneUserPropertyPathComponent]

    nonisolated var description: String {
        components.reduce("$") { path, component in
            switch component {
            case let .key(key): return path + "." + key
            case let .index(index): return path + "[\(index)]"
            }
        }
    }
}

nonisolated enum SceneUserPropertyBindingTarget: Codable, Equatable, Hashable {
    enum TextField: String, Codable {
        case content
        case pointSize
        case color
    }

    enum ParticleField: String, Codable {
        case alpha, size, lifetime, rate, speed, count, brightness, color, normalizedColor
    }

    case layerVisibility(layerID: Int)
    case layerAlpha(layerID: Int)
    case layerColor(layerID: Int)
    case effectVisibility(layerID: Int, effectIndex: Int, effectPath: String?)
    case camera(field: String)
    case text(layerID: Int, field: TextField)
    case particle(layerID: Int, field: ParticleField)
    case shaderValue(
        layerID: Int,
        effectIndex: Int,
        passIndex: Int,
        name: String,
        effectPath: String?
    )
    case unsupported(reason: String)

    nonisolated var acceptsConditionalBoolean: Bool {
        switch self {
        case .layerVisibility, .effectVisibility:
            return true
        case let .camera(field):
            return field == "cameraparallax" || field == "camerashake"
        case .layerAlpha, .layerColor, .text, .particle, .shaderValue, .unsupported:
            return false
        }
    }

    nonisolated var isUnsupported: Bool {
        if case .unsupported = self { return true }
        return false
    }
}

nonisolated struct SceneUserPropertyBindingReference: Codable, Equatable, Hashable {
    let key: String
    let condition: SceneUserPropertyValue?

    nonisolated var isConditional: Bool { condition != nil }
}

nonisolated struct SceneUserPropertyBinding: Codable, Equatable, Hashable {
    let reference: SceneUserPropertyBindingReference
    let fallbackValue: SceneUserPropertyValue?
    let path: SceneUserPropertyPath
    let target: SceneUserPropertyBindingTarget
}

nonisolated struct SceneUserPropertyBindingDiagnostic: Codable, Equatable, Hashable {
    enum Kind: String, Codable {
        case malformedUserReference
        case unsupportedTarget
        case unsupportedConditionalTarget
        case missingEffectiveValue
    }

    let kind: Kind
    let path: SceneUserPropertyPath
    let propertyKey: String?
    let message: String
}

nonisolated struct SceneUserPropertyBindingReport {
    let bindings: [SceneUserPropertyBinding]
    let diagnostics: [SceneUserPropertyBindingDiagnostic]

    nonisolated var conditionalBindingCount: Int {
        bindings.filter(\.reference.isConditional).count
    }

    nonisolated var unsupportedBindings: [SceneUserPropertyBinding] {
        bindings.filter(\.target.isUnsupported)
    }
}

nonisolated struct SceneUserPropertyResolution {
    let root: [String: Any]
    let bindingReport: SceneUserPropertyBindingReport
    let diagnostics: [SceneUserPropertyBindingDiagnostic]
    let resolvedBindingCount: Int

    nonisolated var unresolvedBindingCount: Int {
        bindingReport.bindings.count - resolvedBindingCount
    }
}

nonisolated struct SceneUserPropertyBindingParser {
    nonisolated func parse(root: [String: Any]) -> SceneUserPropertyBindingReport {
        var bindings: [SceneUserPropertyBinding] = []
        var diagnostics: [SceneUserPropertyBindingDiagnostic] = []
        visit(
            root,
            path: [],
            root: root,
            bindings: &bindings,
            diagnostics: &diagnostics
        )
        return SceneUserPropertyBindingReport(bindings: bindings, diagnostics: diagnostics)
    }

    nonisolated func reference(
        in dictionary: [String: Any]
    ) -> Result<SceneUserPropertyBindingReference?, ReferenceError> {
        guard let rawUser = dictionary["user"] else { return .success(nil) }
        if rawUser is NSNull { return .success(nil) }
        if let key = Self.trimmedString(rawUser as? String) {
            return .success(SceneUserPropertyBindingReference(key: key, condition: nil))
        }
        guard let object = rawUser as? [String: Any],
              let key = Self.trimmedString(object["name"] as? String) else {
            return .failure(.invalidShape)
        }
        guard let rawCondition = object["condition"], !(rawCondition is NSNull) else {
            return .success(SceneUserPropertyBindingReference(key: key, condition: nil))
        }
        guard let condition = SceneUserPropertyValue.parse(rawCondition) else {
            return .failure(.invalidCondition)
        }
        return .success(SceneUserPropertyBindingReference(key: key, condition: condition))
    }

    nonisolated func target(
        for components: [SceneUserPropertyPathComponent],
        root: [String: Any]
    ) -> SceneUserPropertyBindingTarget {
        if components.count == 2,
           Self.key(components[0]) == "general",
           let field = Self.key(components[1]),
           field.hasPrefix("camera") {
            return .camera(field: field)
        }
        if components.count == 2,
           Self.key(components[0]) == "camera",
           let field = Self.key(components[1]) {
            return .camera(field: field)
        }
        guard components.count >= 3,
              Self.key(components[0]) == "objects",
              let objectIndex = Self.index(components[1]),
              let object = Self.object(at: objectIndex, root: root),
              let layerID = Self.integer(object["id"]) else {
            return .unsupported(reason: "未识别的绑定路径")
        }
        if components.count == 3, Self.key(components[2]) == "visible" {
            return .layerVisibility(layerID: layerID)
        }
        if components.count == 3, Self.key(components[2]) == "alpha" {
            return .layerAlpha(layerID: layerID)
        }
        if components.count == 3,
           Self.key(components[2]) == "color",
           object["text"] == nil {
            return .layerColor(layerID: layerID)
        }
        if components.count == 4,
           Self.key(components[2]) == "instanceoverride",
           let field = Self.key(components[3]),
           let override = object["instanceoverride"] as? [String: Any],
           let wrapper = override[field] as? [String: Any] {
            guard wrapper["script"] == nil || wrapper["script"] is NSNull,
                  wrapper["animation"] == nil || wrapper["animation"] is NSNull else {
                return .unsupported(reason: "粒子 instance override 存在冲突动态来源")
            }
            switch field {
            case "alpha": return .particle(layerID: layerID, field: .alpha)
            case "size": return .particle(layerID: layerID, field: .size)
            case "lifetime": return .particle(layerID: layerID, field: .lifetime)
            case "rate": return .particle(layerID: layerID, field: .rate)
            case "speed": return .particle(layerID: layerID, field: .speed)
            case "count": return .particle(layerID: layerID, field: .count)
            case "brightness": return .particle(layerID: layerID, field: .brightness)
            case "color": return .particle(layerID: layerID, field: .color)
            case "colorn": return .particle(layerID: layerID, field: .normalizedColor)
            default: break
            }
        }
        if components.count == 5,
           Self.key(components[2]) == "effects",
           let effectIndex = Self.index(components[3]),
           Self.key(components[4]) == "visible" {
            return .effectVisibility(
                layerID: layerID,
                effectIndex: effectIndex,
                effectPath: Self.effect(at: effectIndex, object: object)?["file"] as? String
            )
        }
        if components.count == 8,
           Self.key(components[2]) == "effects",
           let effectIndex = Self.index(components[3]),
           Self.key(components[4]) == "passes",
           let passIndex = Self.index(components[5]),
           Self.key(components[6]) == "constantshadervalues",
           let name = Self.key(components[7]) {
            return .shaderValue(
                layerID: layerID,
                effectIndex: effectIndex,
                passIndex: passIndex,
                name: name,
                effectPath: Self.effect(at: effectIndex, object: object)?["file"] as? String
            )
        }
        if components.count == 3, object["text"] != nil {
            switch Self.key(components[2]) {
            case "text": return .text(layerID: layerID, field: .content)
            case "pointsize": return .text(layerID: layerID, field: .pointSize)
            case "color": return .text(layerID: layerID, field: .color)
            default: break
            }
        }
        return .unsupported(reason: "当前核心层未分类该绑定目标")
    }

    enum ReferenceError: Error {
        case invalidShape
        case invalidCondition
    }

    private nonisolated func visit(
        _ value: Any,
        path: [SceneUserPropertyPathComponent],
        root: [String: Any],
        bindings: inout [SceneUserPropertyBinding],
        diagnostics: inout [SceneUserPropertyBindingDiagnostic]
    ) {
        if let dictionary = value as? [String: Any] {
            if dictionary.keys.contains("user") {
                appendBinding(
                    dictionary,
                    path: path,
                    root: root,
                    bindings: &bindings,
                    diagnostics: &diagnostics
                )
            }
            for key in dictionary.keys.sorted() {
                guard let child = dictionary[key] else { continue }
                visit(
                    child,
                    path: path + [.key(key)],
                    root: root,
                    bindings: &bindings,
                    diagnostics: &diagnostics
                )
            }
        } else if let array = value as? [Any] {
            for (index, child) in array.enumerated() {
                visit(
                    child,
                    path: path + [.index(index)],
                    root: root,
                    bindings: &bindings,
                    diagnostics: &diagnostics
                )
            }
        }
    }

    private nonisolated func appendBinding(
        _ dictionary: [String: Any],
        path: [SceneUserPropertyPathComponent],
        root: [String: Any],
        bindings: inout [SceneUserPropertyBinding],
        diagnostics: inout [SceneUserPropertyBindingDiagnostic]
    ) {
        let propertyPath = SceneUserPropertyPath(components: path)
        switch reference(in: dictionary) {
        case .success(nil):
            return
        case let .failure(error):
            diagnostics.append(.init(
                kind: .malformedUserReference,
                path: propertyPath,
                propertyKey: nil,
                message: error == .invalidCondition ? "条件绑定值无法解析。" : "user 绑定缺少有效 key。"
            ))
        case let .success(reference?):
            let target = target(for: path, root: root)
            let binding = SceneUserPropertyBinding(
                reference: reference,
                fallbackValue: SceneUserPropertyValue.parse(dictionary["value"]),
                path: propertyPath,
                target: target
            )
            bindings.append(binding)
            if case let .unsupported(reason) = target {
                diagnostics.append(.init(
                    kind: .unsupportedTarget,
                    path: propertyPath,
                    propertyKey: reference.key,
                    message: reason
                ))
            }
            if reference.isConditional, !target.acceptsConditionalBoolean {
                diagnostics.append(.init(
                    kind: .unsupportedConditionalTarget,
                    path: propertyPath,
                    propertyKey: reference.key,
                    message: "条件绑定仅对 visibility 等布尔目标求值。"
                ))
            }
        }
    }

    private nonisolated static func object(
        at index: Int,
        root: [String: Any]
    ) -> [String: Any]? {
        guard let objects = root["objects"] as? [Any], objects.indices.contains(index) else { return nil }
        return objects[index] as? [String: Any]
    }

    private nonisolated static func effect(
        at index: Int,
        object: [String: Any]
    ) -> [String: Any]? {
        guard let effects = object["effects"] as? [Any], effects.indices.contains(index) else { return nil }
        return effects[index] as? [String: Any]
    }

    private nonisolated static func key(_ component: SceneUserPropertyPathComponent) -> String? {
        guard case let .key(value) = component else { return nil }
        return value
    }

    private nonisolated static func index(_ component: SceneUserPropertyPathComponent) -> Int? {
        guard case let .index(value) = component else { return nil }
        return value
    }

    private nonisolated static func integer(_ rawValue: Any?) -> Int? {
        SceneUserPropertyValue.parse(rawValue)?.numberValue.map(Int.init)
    }

    private nonisolated static func trimmedString(_ rawValue: String?) -> String? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
