import Foundation

/// Projects active Wallpaper Engine shader metadata into the typed facts used
/// by material finalization. Editor labels and project-private fields never
/// become execution policy here.
nonisolated enum SceneResolvedMaterialShaderSchema {
    typealias Template = SceneResolvedMaterialTemplate

    enum TextureMode: Hashable {
        case regular
        case opacityMask
        case rgbMask
        case flowMask
        case depth
    }

    enum DefaultTexture: Hashable {
        case asset(SceneVFSAssetPath)
        case internalTarget(String)
    }

    struct Sampler: Hashable {
        let name: String
        let slot: Int
        let mode: TextureMode
        let materialKey: String?
        let isHidden: Bool
        let defaultTexture: DefaultTexture?
        /// An unmarked sampler combo describes whether an authored texture is
        /// actually bound. Its annotation default must not manufacture that
        /// presence fact, although an active combo-off sampler may consume the
        /// typed default as a separate resource fallback.
        let readinessCombo: String?
    }

    struct Uniform: Hashable {
        let name: String
        let materialKeys: [String]
        let defaultValue: Template.StaticUniformValue?
    }

    enum Issue: Error {
        case sampler(String)
        case uniform(String)
    }

    static func unconditionalSamplers(
        _ template: Template
    ) throws -> [Int: Sampler] {
        guard let graph = template.shaderContract.sourceGraph else {
            throw Issue.sampler("source-graph-missing")
        }
        let sources = SceneShaderVariantSchemaSeed.unconditional(
            contract: template.shaderContract,
            graph: graph
        )
        return try samplerSchemas(records(sources))
    }

    static func activeSamplers(
        _ prepared: SceneShaderPreparedProgram,
        runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds = .none
    ) throws -> [Int: Sampler] {
        guard let activeNames = SceneAuthoredShaderDeadBindingAnalyzer.activeSamplerNames(
            vertexSource: prepared.vertex.source,
            fragmentSource: prepared.fragment.source,
            runtimeLoopBounds: runtimeLoopBounds
        ) else { throw Issue.sampler("prepared-frontend") }
        return try activeSamplers(prepared, activeNames: activeNames)
    }

    /// A validated compiler artifact already publishes its active reflection.
    /// Reuse the same metadata projection without asking the bounded Swift
    /// language frontend to parse the source a second time.
    static func activeSamplers(
        _ prepared: SceneShaderPreparedProgram,
        activeNames: Set<String>
    ) throws -> [Int: Sampler] {
        guard activeNames.allSatisfy({ name in
            name.hasPrefix("g_Texture") && Int(name.dropFirst(9)) != nil
        }) else { throw Issue.sampler("active-reflection") }
        return try samplerSchemas(records(prepared).filter {
            $0.declaration.kind != .uniform
                || !isSampler2D($0.declaration.type)
                || activeNames.contains($0.declaration.name)
        })
    }

    static func activeUniforms(
        _ fields: [SceneAuthoredShaderUniformLayout.Field],
        prepared: SceneShaderPreparedProgram
    ) throws -> [String: Uniform] {
        let allRecords = records(prepared)
        var result: [String: Uniform] = [:]
        var keyOwners: [String: String] = [:]
        for field in fields {
            let schema = try uniformSchema(field, records: allRecords)
            guard result.updateValue(schema, forKey: field.name) == nil else {
                throw Issue.uniform(field.name)
            }
            for key in schema.materialKeys {
                if let owner = keyOwners[key], owner != field.authoredName {
                    throw Issue.uniform(key)
                }
                keyOwners[key] = field.authoredName
            }
        }
        return result
    }

    /// Resolves one exact active authored uniform before backend reflection is
    /// available. The expected type is part of the proof; callers may not use
    /// annotation defaults from a duplicate or differently typed declaration.
    static func uniqueActiveUniform(
        named name: String,
        type: SceneAuthoredShaderValueType,
        stage: SceneShaderContract.StageKind,
        prepared: SceneShaderPreparedProgram
    ) -> Uniform? {
        let allRecords = records(prepared)
        let matches = allRecords.filter {
            $0.stage == stage
                && $0.declaration.kind == .uniform
                && !isSampler2D($0.declaration.type)
                && $0.declaration.name == name
        }
        guard matches.count == 1,
              SceneAuthoredShaderValueType(
                  authoredName: matches[0].declaration.type
              ) == type else { return nil }
        let field = SceneAuthoredShaderUniformLayout.Field(
            name: name,
            stage: stage,
            type: type,
            offset: 0
        )
        return try? uniformSchema(field, records: allRecords)
    }

    private struct Record {
        let stage: SceneShaderContract.StageKind?
        let sourcePath: String
        let declaration: SceneShaderContract.Declaration
        let annotations: [SceneShaderContract.Annotation]
    }

    private static func records(
        _ sources: [SceneShaderVariantSchemaSource]
    ) -> [Record] {
        sources.flatMap { source in
            source.declarations.map { declaration in
                .init(
                    stage: nil,
                    sourcePath: source.relativePath,
                    declaration: declaration,
                    annotations: source.annotations.filter {
                        $0.line == declaration.line
                    }
                )
            }
        }
    }

    private static func records(
        _ prepared: SceneShaderPreparedProgram
    ) -> [Record] {
        let annotations = prepared.all.flatMap(\.activeAnnotations)
        var seen: Set<String> = []
        return prepared.all.flatMap { source in
            source.activeDeclarations.compactMap { active in
                let declaration = active.declaration
                let identity = [
                    source.stage.rawValue, active.sourcePath, String(declaration.line),
                    declaration.kind.rawValue, declaration.type, declaration.name,
                ].joined(separator: "\u{1f}")
                guard seen.insert(identity).inserted else { return nil }
                return .init(
                    stage: source.stage,
                    sourcePath: active.sourcePath,
                    declaration: declaration,
                    annotations: annotations.compactMap { annotation in
                        guard annotation.sourcePath == active.sourcePath,
                              annotation.annotation.line == declaration.line else {
                            return nil
                        }
                        return annotation.annotation
                    }
                )
            }
        }
    }

    private static func samplerSchemas(
        _ records: [Record]
    ) throws -> [Int: Sampler] {
        let samplerRecords = records.filter {
            $0.declaration.kind == .uniform && isSampler2D($0.declaration.type)
        }
        var result: [Int: Sampler] = [:]
        for name in Set(samplerRecords.map(\.declaration.name)).sorted() {
            let declarations = samplerRecords.filter { $0.declaration.name == name }
            guard let slot = textureSlot(name) else { throw Issue.sampler(name) }
            let objects = declarations.flatMap { record in
                record.annotations.compactMap { annotation -> [String: SceneShaderAnnotationValue]? in
                    guard annotation.marker == nil,
                          case let .object(object) = annotation.variantValue else {
                        return nil
                    }
                    return object
                }
            }
            let mode = try textureMode(value("mode", in: objects), name: name)
            try validateTextureFormat(
                value("format", in: objects),
                mode: mode,
                name: name
            )
            let material = try normalizedString(value("material", in: objects), name: name)
            let hidden = try value("hidden", in: objects)
            guard hidden == nil || hidden?.boolValue != nil else {
                throw Issue.sampler(name)
            }
            let isHidden = hidden?.boolValue == true
            let defaultTexture = try textureDefault(value("default", in: objects), name: name)
            let readinessCombo = try normalizedString(
                value("combo", in: objects),
                name: name
            )
            let schema = Sampler(
                name: name,
                slot: slot,
                mode: mode,
                materialKey: material,
                isHidden: isHidden,
                defaultTexture: defaultTexture,
                readinessCombo: readinessCombo
            )
            if let existing = result[slot], existing != schema {
                throw Issue.sampler(name)
            }
            result[slot] = schema
        }
        return result
    }

    private static func uniformSchema(
        _ field: SceneAuthoredShaderUniformLayout.Field,
        records: [Record]
    ) throws -> Uniform {
        let name = field.authoredName
        do {
            let declarations = records.filter {
                $0.declaration.kind == .uniform
                    && !isSampler2D($0.declaration.type)
                    && $0.declaration.name == name
                    && (field.stage == nil || $0.stage == field.stage)
            }
            guard !declarations.isEmpty else { throw Issue.uniform(name) }
            let objects = declarations.flatMap { record in
                record.annotations.compactMap {
                    annotation -> [String: SceneShaderAnnotationValue]? in
                    guard !isCompileTime(annotation),
                          case let .object(object) = annotation.variantValue else {
                        return nil
                    }
                    return object
                }
            }
            let material = try authoredBindingKey(
                value("material", in: objects),
                name: name
            )
            let rawDefault = try value("default", in: objects)
            let fallback = try rawDefault.map {
                Template.StaticUniformValue(
                    valueKind: "shader-default",
                    componentBitPatterns: try defaultComponents($0, name: name).map(\.bitPattern),
                    authoredBindingKeys: []
                )
            }
            return .init(
                name: field.name,
                materialKeys: [name] + (material.map { [$0] } ?? []),
                defaultValue: fallback
            )
        } catch {
            throw Issue.uniform(name)
        }
    }

    private static func value(
        _ key: String,
        in objects: [[String: SceneShaderAnnotationValue]]
    ) throws -> SceneShaderAnnotationValue? {
        let values = objects.compactMap { $0[key] }
        guard let first = values.first else { return nil }
        guard values.dropFirst().allSatisfy({ $0 == first }) else {
            throw Issue.sampler(key)
        }
        return first
    }

    private static func textureMode(
        _ value: SceneShaderAnnotationValue?,
        name: String
    ) throws -> TextureMode {
        guard let value else { return .regular }
        guard let raw = value.stringValue,
              raw == raw.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw Issue.sampler(name)
        }
        return switch raw.lowercased() {
        case "opacitymask": .opacityMask
        case "rgbmask": .rgbMask
        case "flowmask": .flowMask
        case "depth": .depth
        default: throw Issue.sampler(name)
        }
    }

    private static func validateTextureFormat(
        _ value: SceneShaderAnnotationValue?,
        mode: TextureMode,
        name: String
    ) throws {
        guard let value else { return }
        guard mode == .depth,
              let raw = value.stringValue,
              raw.caseInsensitiveCompare("r8") == .orderedSame else {
            throw Issue.sampler(name)
        }
    }

    private static func normalizedString(
        _ value: SceneShaderAnnotationValue?,
        name: String
    ) throws -> String? {
        guard let value else { return nil }
        guard let raw = value.stringValue,
              !raw.isEmpty,
              raw == raw.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.unicodeScalars.contains(where: {
                  $0.value < 32 || $0.value == 127
              }) else {
            throw Issue.sampler(name)
        }
        return raw
    }

    /// Material binding keys are authored identities, not display strings.
    /// Preserve significant leading/trailing whitespace so the shader-side
    /// key can match the instance constant exactly, while still rejecting
    /// empty, whitespace-only, or control-character identities.
    private static func authoredBindingKey(
        _ value: SceneShaderAnnotationValue?,
        name: String
    ) throws -> String? {
        guard let value else { return nil }
        guard let raw = value.stringValue,
              !raw.isEmpty,
              raw.contains(where: { !$0.isWhitespace }),
              !raw.unicodeScalars.contains(where: {
                  $0.value < 32 || $0.value == 127
              }) else {
            throw Issue.uniform(name)
        }
        return raw
    }

    private static func textureDefault(
        _ value: SceneShaderAnnotationValue?,
        name: String
    ) throws -> DefaultTexture? {
        guard let value else { return nil }
        guard let raw = value.stringValue,
              raw == raw.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.unicodeScalars.contains(where: {
                  $0.value < 32 || $0.value == 127
              }) else {
            throw Issue.sampler(name)
        }
        if raw.isEmpty { return nil }
        let normalized = raw.replacingOccurrences(of: "\\", with: "/").lowercased()
        if normalized.hasPrefix("_rt_") { return .internalTarget(normalized) }
        guard let path = SceneVFSAssetPath(raw) else { throw Issue.sampler(name) }
        return .asset(path)
    }

    private static func defaultComponents(
        _ value: SceneShaderAnnotationValue,
        name: String
    ) throws -> [Double] {
        let components: [Double]?
        switch value {
        case let .integer(number): components = Double(exactly: number).map { [$0] }
        case let .number(number): components = number.isFinite ? [number] : nil
        case let .string(raw):
            let values: [String]
            if raw.contains(",") {
                values = raw.split(
                    separator: ",",
                    omittingEmptySubsequences: false
                ).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if values.contains(where: { $0.isEmpty || $0.contains(where: \.isWhitespace) }) {
                    throw Issue.uniform(name)
                }
            } else {
                values = raw.split(whereSeparator: \.isWhitespace).map(String.init)
            }
            components = values.isEmpty ? nil : values.compactMap(Double.init)
            if components?.count != values.count { throw Issue.uniform(name) }
        case let .array(values):
            var numbers: [Double] = []
            for item in values {
                let scalar = try defaultComponents(item, name: name)
                guard scalar.count == 1 else { throw Issue.uniform(name) }
                numbers.append(scalar[0])
            }
            components = numbers.isEmpty ? nil : numbers
        default: components = nil
        }
        guard let components, components.allSatisfy(\.isFinite) else {
            throw Issue.uniform(name)
        }
        return components
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0 ..< 8).contains(slot) else { return nil }
        return slot
    }

    private static func isSampler2D(_ type: String) -> Bool {
        type.split(whereSeparator: \.isWhitespace).last?
            .caseInsensitiveCompare("sampler2D") == .orderedSame
    }

    private static func isCompileTime(
        _ annotation: SceneShaderContract.Annotation
    ) -> Bool {
        if annotation.marker?.uppercased().contains("COMBO") == true { return true }
        guard case let .object(object) = annotation.variantValue else { return false }
        return object["combo"] != nil
    }
}
