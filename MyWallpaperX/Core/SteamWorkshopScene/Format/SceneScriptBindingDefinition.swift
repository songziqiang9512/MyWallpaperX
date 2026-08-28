import Foundation

/// Authored layer display fields whose value is owned by an inline SceneScript.
///
/// This is only a provenance fact. The parser does not interpret or execute the
/// script, and malformed script payloads remain owned because their static
/// fallback cannot safely authorize composition.
nonisolated struct SceneLayerDisplayScriptOwnership: Codable, Equatable, Sendable {
    let visible: Bool
    let alpha: Bool

    nonisolated var fields: [String] {
        var result: [String] = []
        if visible { result.append("visible") }
        if alpha { result.append("alpha") }
        return result
    }

    nonisolated var isEmpty: Bool { !visible && !alpha }

    nonisolated static func parse(
        authoredObject root: [String: Any]
    ) -> SceneLayerDisplayScriptOwnership {
        SceneLayerDisplayScriptOwnership(
            visible: containsScriptMarker(root["visible"]),
            alpha: containsScriptMarker(root["alpha"])
        )
    }

    private nonisolated static func containsScriptMarker(_ value: Any?) -> Bool {
        (value as? [String: Any])?.keys.contains("script") == true
    }
}

/// Layer wrapper that may drive an authored texture animation.
///
/// Parsing preserves the complete wrapper shape. No generic texture-animation
/// SceneScript executor is authorized, so unsupported scripts remain inert while
/// ordinary authored TEX sprite playback continues independently.
nonisolated struct SceneTextureAnimationScriptDefinition: Codable, Equatable, Sendable {
    let host: String
    let source: String
    let properties: [String: SceneJSONValue]
    let user: SceneJSONValue?
    let authoredValue: SceneJSONValue?
    let wrapperKeys: [String]

    nonisolated static func parseLayerProperties(
        in root: [String: Any]
    ) -> [SceneTextureAnimationScriptDefinition] {
        root.keys.sorted().compactMap { host in
            guard let wrapper = root[host] as? [String: Any],
                  let source = wrapper["script"] as? String,
                  let properties = parseProperties(wrapper["scriptproperties"]) else {
                return nil
            }
            return SceneTextureAnimationScriptDefinition(
                host: host,
                source: source,
                properties: properties,
                user: wrapper["user"].flatMap(SceneJSONValue.init(jsonObject:)),
                authoredValue: wrapper["value"].flatMap(SceneJSONValue.init(jsonObject:)),
                wrapperKeys: wrapper.keys.sorted()
            )
        }
    }

    nonisolated private static func parseProperties(
        _ rawValue: Any?
    ) -> [String: SceneJSONValue]? {
        guard let rawValue else { return [:] }
        guard let object = rawValue as? [String: Any] else { return nil }

        var properties: [String: SceneJSONValue] = [:]
        for (key, value) in object {
            guard let parsed = SceneJSONValue(jsonObject: value) else { return nil }
            properties[key] = parsed
        }
        return properties
    }
}

/// 作者挂在 layer 顶层属性上的 SceneScript 声明。
///
/// 解析阶段只保留原始脚本及其输入，不判断脚本语义，也不执行未知脚本。
nonisolated struct SceneScriptBindingDefinition: Codable, Equatable, Sendable {
    let host: String
    let source: String
    let properties: [String: SceneJSONValue]
    let authoredValue: SceneJSONValue?

    nonisolated static func parseLayerProperties(
        in root: [String: Any]
    ) -> [SceneScriptBindingDefinition] {
        root.keys.sorted().compactMap { host in
            guard let wrapper = root[host] as? [String: Any],
                  !wrapper.keys.contains("user"),
                  let source = wrapper["script"] as? String,
                  let properties = parseProperties(wrapper["scriptproperties"]) else {
                return nil
            }
            return SceneScriptBindingDefinition(
                host: host,
                source: source,
                properties: properties,
                authoredValue: wrapper["value"].flatMap(SceneJSONValue.init(jsonObject:))
            )
        }
    }

    nonisolated private static func parseProperties(
        _ rawValue: Any?
    ) -> [String: SceneJSONValue]? {
        guard let rawValue else { return [:] }
        guard let object = rawValue as? [String: Any] else { return nil }

        var properties: [String: SceneJSONValue] = [:]
        for (key, value) in object {
            guard let parsed = SceneJSONValue(jsonObject: value) else { return nil }
            properties[key] = parsed
        }
        return properties
    }
}

/// Property-bound SceneScript 的文档级无损 IR。
///
/// 它只描述作者输入的 source、owner、完整 JSON target path、properties 与 fallback；
/// 不执行 JavaScript，也不把未知 nested wrapper 提升成已支持 target。
nonisolated struct SceneScriptBindingIR: Codable, Equatable, Sendable {
    let source: String
    let owner: SceneScriptBindingOwner
    let targetPath: [SceneScriptBindingPathComponent]
    let properties: [String: SceneJSONValue]
    let authoredValue: SceneJSONValue?
    let valueType: SceneScriptBindingValueType
    let wrapperKeys: [String]?

    nonisolated init(
        source: String,
        owner: SceneScriptBindingOwner,
        targetPath: [SceneScriptBindingPathComponent],
        properties: [String: SceneJSONValue],
        authoredValue: SceneJSONValue?,
        valueType: SceneScriptBindingValueType,
        wrapperKeys: [String]? = nil
    ) {
        self.source = source
        self.owner = owner
        self.targetPath = targetPath
        self.properties = properties
        self.authoredValue = authoredValue
        self.valueType = valueType
        self.wrapperKeys = wrapperKeys
    }

    nonisolated var targetKey: String {
        guard case let .key(key) = targetPath.last else { return "" }
        return key
    }
}

nonisolated struct SceneScriptBindingOwner: Codable, Equatable, Sendable {
    nonisolated enum Kind: String, Codable, Equatable, Sendable {
        case scene
        case object
        case effect
        case pass
    }

    let kind: Kind
    let objectIndex: Int?
    let objectID: Int?
    let effectIndex: Int?
    let effectID: Int?
    let passIndex: Int?
    let passID: Int?
}

nonisolated enum SceneScriptBindingPathComponent: Codable, Equatable, Sendable {
    case key(String)
    case index(Int)
}

nonisolated enum SceneScriptBindingValueType: String, Codable, Equatable, Sendable {
    case absent
    case null
    case boolean
    case number
    case string
    case array
    case object

    nonisolated init(authoredValue: SceneJSONValue?) {
        switch authoredValue {
        case nil:
            self = .absent
        case .null:
            self = .null
        case .bool:
            self = .boolean
        case .number:
            self = .number
        case .string:
            self = .string
        case .array:
            self = .array
        case .object:
            self = .object
        }
    }
}

nonisolated struct SceneScriptBindingDiagnostic: Codable, Equatable, Sendable {
    nonisolated enum Code: String, Codable, Equatable, Sendable {
        case conflictingSources
        case invalidSource
        case invalidProperties
        case invalidAuthoredValue
    }

    let code: Code
    let targetPath: [SceneScriptBindingPathComponent]
}

nonisolated struct SceneScriptBindingParseResult: Equatable, Sendable {
    let bindings: [SceneScriptBindingIR]
    let diagnostics: [SceneScriptBindingDiagnostic]
}

nonisolated enum SceneScriptBindingIRParser {
    /// 只遍历正式静态取证已确认的 owner/target 形态：
    /// scene `general.*`、object 顶层 property、effect `visible` 与 pass constants。
    /// `instanceoverride` 等 nested wrapper 不会因递归 presence 被误挂到 object owner。
    nonisolated static func parse(
        document root: [String: Any]
    ) -> SceneScriptBindingParseResult {
        var bindings: [SceneScriptBindingIR] = []
        var diagnostics: [SceneScriptBindingDiagnostic] = []

        if let general = root["general"] as? [String: Any] {
            let owner = SceneScriptBindingOwner(
                kind: .scene,
                objectIndex: nil,
                objectID: nil,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            )
            for key in general.keys.sorted() {
                append(
                    general[key],
                    owner: owner,
                    path: [.key("general"), .key(key)],
                    bindings: &bindings,
                    diagnostics: &diagnostics
                )
            }
        }

        for (objectIndex, object) in (
            root["objects"] as? [[String: Any]] ?? []
        ).enumerated() {
            let objectOwner = SceneScriptBindingOwner(
                kind: .object,
                objectIndex: objectIndex,
                objectID: object["id"] as? Int,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            )
            for key in object.keys.sorted() where key != "effects" {
                append(
                    object[key],
                    owner: objectOwner,
                    path: [.key("objects"), .index(objectIndex), .key(key)],
                    bindings: &bindings,
                    diagnostics: &diagnostics
                )
            }

            let effects = object["effects"] as? [[String: Any]] ?? []
            for (effectIndex, effect) in effects.enumerated() {
                let effectPath: [SceneScriptBindingPathComponent] = [
                    .key("objects"), .index(objectIndex),
                    .key("effects"), .index(effectIndex),
                ]
                let effectOwner = SceneScriptBindingOwner(
                    kind: .effect,
                    objectIndex: objectIndex,
                    objectID: object["id"] as? Int,
                    effectIndex: effectIndex,
                    effectID: effect["id"] as? Int,
                    passIndex: nil,
                    passID: nil
                )
                append(
                    effect["visible"],
                    owner: effectOwner,
                    path: effectPath + [.key("visible")],
                    bindings: &bindings,
                    diagnostics: &diagnostics
                )

                let passes = effect["passes"] as? [[String: Any]] ?? []
                for (passIndex, pass) in passes.enumerated() {
                    guard let constants = pass["constantshadervalues"]
                        as? [String: Any] else { continue }
                    let passOwner = SceneScriptBindingOwner(
                        kind: .pass,
                        objectIndex: objectIndex,
                        objectID: object["id"] as? Int,
                        effectIndex: effectIndex,
                        effectID: effect["id"] as? Int,
                        passIndex: passIndex,
                        passID: pass["id"] as? Int
                    )
                    let constantPath = effectPath + [
                        .key("passes"), .index(passIndex),
                        .key("constantshadervalues"),
                    ]
                    for key in constants.keys.sorted() {
                        append(
                            constants[key],
                            owner: passOwner,
                            path: constantPath + [.key(key)],
                            bindings: &bindings,
                            diagnostics: &diagnostics
                        )
                    }
                }
            }
        }
        return SceneScriptBindingParseResult(
            bindings: bindings,
            diagnostics: diagnostics
        )
    }

    private nonisolated static func append(
        _ rawValue: Any?,
        owner: SceneScriptBindingOwner,
        path: [SceneScriptBindingPathComponent],
        bindings: inout [SceneScriptBindingIR],
        diagnostics: inout [SceneScriptBindingDiagnostic]
    ) {
        guard let wrapper = rawValue as? [String: Any],
              wrapper.keys.contains("script") else { return }
        if let userValue = wrapper["user"], !(userValue is NSNull) {
            diagnostics.append(.init(code: .conflictingSources, targetPath: path))
            return
        }
        guard let source = wrapper["script"] as? String else {
            diagnostics.append(.init(code: .invalidSource, targetPath: path))
            return
        }
        guard let properties = parseProperties(wrapper["scriptproperties"]) else {
            diagnostics.append(.init(code: .invalidProperties, targetPath: path))
            return
        }
        let authoredValue: SceneJSONValue?
        if let rawAuthoredValue = wrapper["value"] {
            guard let parsed = SceneJSONValue(jsonObject: rawAuthoredValue) else {
                diagnostics.append(.init(code: .invalidAuthoredValue, targetPath: path))
                return
            }
            authoredValue = parsed
        } else {
            authoredValue = nil
        }
        bindings.append(SceneScriptBindingIR(
            source: source,
            owner: owner,
            targetPath: path,
            properties: properties,
            authoredValue: authoredValue,
            valueType: .init(authoredValue: authoredValue),
            wrapperKeys: wrapper.keys.sorted()
        ))
    }

    private nonisolated static func parseProperties(
        _ rawValue: Any?
    ) -> [String: SceneJSONValue]? {
        guard let rawValue else { return [:] }
        guard let object = rawValue as? [String: Any] else { return nil }
        var properties: [String: SceneJSONValue] = [:]
        for (key, value) in object {
            guard let parsed = SceneJSONValue(jsonObject: value) else { return nil }
            properties[key] = parsed
        }
        return properties
    }
}
