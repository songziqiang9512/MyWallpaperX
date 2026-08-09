import Foundation

nonisolated struct SceneShaderVariantSchemaSource: Codable, Equatable, Sendable {
    let relativePath: String
    let annotations: [SceneShaderContract.Annotation]
    let declarations: [SceneShaderContract.Declaration]

    init(stage: SceneShaderContract.Stage) {
        relativePath = stage.relativePath
        annotations = stage.annotations
        declarations = stage.declarations
    }

    init(
        relativePath: String,
        annotations: [SceneShaderContract.Annotation],
        declarations: [SceneShaderContract.Declaration]
    ) {
        self.relativePath = relativePath
        self.annotations = annotations
        self.declarations = declarations
    }
}

extension SceneShaderVariantResolver {
    nonisolated struct Schema: Equatable {
        nonisolated enum Origin: Equatable {
            case authoredCombo
            case disabledCombo
            case textureReadiness(slot: Int)
            case textureFormat(slot: Int)
        }

        let combo: String
        let defaultValue: Int64?
        let options: Set<Int64>?
        let requirements: [String: Int64]
        let requireAny: Bool
        let origin: Origin

        var samplerSlot: Int? {
            guard case let .textureReadiness(slot) = origin else { return nil }
            return slot
        }

        var textureFormatSlot: Int? {
            guard case let .textureFormat(slot) = origin else { return nil }
            return slot
        }

        var isAuthoredComboMarker: Bool {
            origin == .authoredCombo || origin == .disabledCombo
        }

        var isDisabledCombo: Bool { origin == .disabledCombo }
    }

    nonisolated static func schemas(
        in source: SceneShaderVariantSchemaSource
    ) throws -> [Schema] {
        let declarations = Dictionary(grouping: source.declarations, by: \.line)
        return try source.annotations.flatMap { annotation -> [Schema] in
            let markerRequiresCombo = annotation.marker != nil
                && annotation.marker != "[PASS]"
            guard case .object(let object) = annotation.variantValue else {
                if markerRequiresCombo {
                    throw Failure(
                        code: .invalidAnnotation,
                        combo: nil,
                        message: "Shader combo marker requires an object payload."
                    )
                }
                return []
            }
            let requireAny: Bool
            if let rawRequireAny = object["requireany"] {
                guard let value = rawRequireAny.boolValue else {
                    throw Failure(
                        code: .invalidAnnotation,
                        combo: object["combo"]?.stringValue,
                        message: "Shader combo requireany must be a boolean."
                    )
                }
                requireAny = value
            } else {
                requireAny = false
            }
            let rawCombo = object["combo"]
            let combo: String?
            if let rawCombo {
                guard let value = rawCombo.stringValue, !value.isEmpty else {
                    throw Failure(
                        code: .invalidAnnotation,
                        combo: rawCombo.stringValue,
                        message: "Shader combo annotation has no valid identifier."
                    )
                }
                combo = value
            } else {
                combo = nil
            }
            if markerRequiresCombo, combo == nil {
                throw Failure(
                    code: .invalidAnnotation,
                    combo: nil,
                    message: "Shader combo marker requires a combo identifier."
                )
            }
            let requirementOwner = combo ?? "<texture-format>"
            let requirements = try requirements(
                object["require"],
                combo: requirementOwner
            )
            if let combo,
               let disabled = try disabledComboSchema(
                   annotation: annotation,
                   object: object,
                   combo: combo
               ) {
                return [disabled]
            }
            if annotation.marker == "[COMBO]" {
                guard let combo else {
                    throw Failure(
                        code: .invalidAnnotation,
                        combo: nil,
                        message: "Shader combo marker requires a combo identifier."
                    )
                }
                return [Schema(
                    combo: combo,
                    defaultValue: try integer(object["default"], combo: combo),
                    options: try options(object["options"], combo: combo),
                    requirements: requirements,
                    requireAny: requireAny,
                    origin: .authoredCombo
                )]
            }
            guard annotation.marker == nil else {
                throw Failure(
                    code: .invalidAnnotation,
                    combo: combo,
                    message: "Unsupported shader combo marker."
                )
            }
            let rawFormatCombo = object["formatcombo"]
            let hasFormatCombo: Bool
            if let rawFormatCombo {
                guard let value = rawFormatCombo.boolValue else {
                    throw Failure(
                        code: .invalidAnnotation,
                        combo: combo,
                        message: "Shader texture formatcombo must be a boolean."
                    )
                }
                hasFormatCombo = value
            } else {
                hasFormatCombo = false
            }
            guard combo != nil || hasFormatCombo else { return [] }
            guard let slot = declarations[annotation.line]?
                    .compactMap(samplerSlot).first else {
                throw Failure(
                    code: .invalidAnnotation,
                    combo: combo,
                    message: "Unmarked shader combo metadata must belong to a texture sampler."
                )
            }
            var result: [Schema] = []
            if let combo {
                result.append(Schema(
                    combo: combo,
                    defaultValue: nil,
                    options: nil,
                    requirements: requirements,
                    requireAny: requireAny,
                    origin: .textureReadiness(slot: slot)
                ))
            }
            if hasFormatCombo {
                result.append(Schema(
                    combo: "TEX\(slot)FORMAT",
                    defaultValue: nil,
                    options: nil,
                    requirements: requirements,
                    requireAny: requireAny,
                    origin: .textureFormat(slot: slot)
                ))
            }
            return result
        }
    }

    nonisolated static func integer(
        _ value: SceneShaderAnnotationValue?,
        combo: String
    ) throws -> Int64? {
        guard let value else { return nil }
        if let bool = value.boolValue { return bool ? 1 : 0 }
        guard let integer = value.integerValue else {
            throw Failure(
                code: .invalidAnnotation,
                combo: combo,
                message: "Shader combo value must be an integer or boolean."
            )
        }
        return integer
    }

    nonisolated static func options(
        _ value: SceneShaderAnnotationValue?,
        combo: String
    ) throws -> Set<Int64>? {
        guard let value else { return nil }
        let values: [SceneShaderAnnotationValue]
        switch value {
        case .array(let array): values = array
        case .object(let object): values = Array(object.values)
        default:
            throw Failure(
                code: .invalidAnnotation,
                combo: combo,
                message: "Shader combo options must be an array or object."
            )
        }
        let parsed = try values.map { try integer($0, combo: combo)! }
        return Set(parsed)
    }

    nonisolated static func requirements(
        _ value: SceneShaderAnnotationValue?,
        combo: String
    ) throws -> [String: Int64] {
        guard let value else { return [:] }
        guard case .object(let object) = value else {
            throw Failure(
                code: .invalidAnnotation,
                combo: combo,
                message: "Shader combo requirements must be an object."
            )
        }
        var result: [String: Int64] = [:]
        for (name, raw) in object {
            guard let parsed = try integer(raw, combo: combo) else {
                throw Failure(
                    code: .invalidAnnotation,
                    combo: combo,
                    message: "Shader combo requirement has no value."
                )
            }
            result[name] = parsed
        }
        return result
    }

    private nonisolated static func samplerSlot(
        _ declaration: SceneShaderContract.Declaration
    ) -> Int? {
        guard declaration.kind == .uniform,
              declaration.type.caseInsensitiveCompare("sampler2D") == .orderedSame,
              declaration.name.hasPrefix("g_Texture"),
              let slot = Int(declaration.name.dropFirst("g_Texture".count)),
              (0 ... 7).contains(slot) else { return nil }
        return slot
    }
}
