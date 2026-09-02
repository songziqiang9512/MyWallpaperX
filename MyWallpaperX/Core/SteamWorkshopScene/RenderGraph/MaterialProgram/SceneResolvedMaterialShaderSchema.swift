import Foundation

/// Projects active Wallpaper Engine shader metadata into the typed facts used
/// by material finalization. Editor labels and project-private fields never
/// become execution policy here.
nonisolated enum SceneResolvedMaterialShaderSchema {
    typealias Template = SceneResolvedMaterialTemplate
    typealias ChannelUse = SceneAuthoredShaderProgram.TextureBinding.ChannelUse

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
        /// Source-derived use for one prepared variant. Bootstrap schemas have
        /// no active syntax proof and therefore retain the conservative default.
        let channelUse: ChannelUse
        /// A role proven from complete active shader dataflow. This may type an
        /// otherwise ambiguous authored asset/property slot, but it may never
        /// override a conflicting explicit or registered resource contract.
        let sourceProvenPurpose: SceneTextureLoadPurpose?

        init(
            name: String,
            slot: Int,
            mode: TextureMode,
            materialKey: String?,
            isHidden: Bool,
            defaultTexture: DefaultTexture?,
            readinessCombo: String?,
            channelUse: ChannelUse = .unproven,
            sourceProvenPurpose: SceneTextureLoadPurpose? = nil
        ) {
            self.name = name
            self.slot = slot
            self.mode = mode
            self.materialKey = materialKey
            self.isHidden = isHidden
            self.defaultTexture = defaultTexture
            self.readinessCombo = readinessCombo
            self.channelUse = channelUse
            self.sourceProvenPurpose = sourceProvenPurpose
        }

        func withChannelUse(_ value: ChannelUse) -> Self {
            .init(
                name: name,
                slot: slot,
                mode: mode,
                materialKey: materialKey,
                isHidden: isHidden,
                defaultTexture: defaultTexture,
                readinessCombo: readinessCombo,
                channelUse: value,
                sourceProvenPurpose: sourceProvenPurpose
            )
        }

        func withSourceProvenPurpose(
            _ value: SceneTextureLoadPurpose
        ) -> Self {
            .init(
                name: name,
                slot: slot,
                mode: mode,
                materialKey: materialKey,
                isHidden: isHidden,
                defaultTexture: defaultTexture,
                readinessCombo: readinessCombo,
                channelUse: channelUse,
                sourceProvenPurpose: value
            )
        }

        func mergingVariantFacts(from active: Self) -> Self? {
            guard name == active.name,
                  slot == active.slot,
                  mode == active.mode,
                  materialKey == active.materialKey,
                  isHidden == active.isHidden,
                  defaultTexture == active.defaultTexture,
                  readinessCombo == active.readinessCombo else { return nil }
            return .init(
                name: name,
                slot: slot,
                mode: mode,
                materialKey: materialKey,
                isHidden: isHidden,
                defaultTexture: defaultTexture,
                readinessCombo: readinessCombo,
                channelUse: active.channelUse,
                sourceProvenPurpose: active.sourceProvenPurpose
            )
        }
    }

    struct Uniform: Hashable {
        let name: String
        let materialKeys: [String]
        let defaultValue: Template.StaticUniformValue?
        /// Author-declared numeric domain, including the normalized domain of
        /// a typed color editor. It is not a general clamp policy; owner
        /// transfers may require it to preserve an incumbent's runtime contract.
        let authoredRange: ClosedRange<Double>?
    }

    enum Issue: Error {
        case sampler(String)
        case uniform(String)
    }

    /// Resolves combo-default conditional declarations before texture
    /// readiness starts the normal fixed-point iteration.
    nonisolated static func bootstrapSamplers(
        _ template: Template,
        textureFormats: [Int: SceneShaderTextureFormat] = [:]
    ) throws -> [Int: Sampler] {
        let readiness = Dictionary(uniqueKeysWithValues: (0 ..< 8).map {
            ($0, false)
        })
        switch SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: template.shaderContract,
            compatibilityTarget: template.compatibilityTarget,
            combos: template.comboValues,
            inactiveComboProviders: Set(template.inheritedInactiveCombos),
            textureReadiness: readiness,
            textureFormats: textureFormats
        ) {
        case let .accepted(prepared):
            let sources = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
                vertex: prepared.vertex.source,
                fragment: prepared.fragment.source
            )
            let loopBounds = SceneResolvedMaterialRuntimeLoopBoundResolver.resolve(
                template: template,
                prepared: prepared
            )
            guard let names = SceneAuthoredShaderDeadBindingAnalyzer
                    .activeSamplerNames(
                        vertexSource: sources.vertex,
                        fragmentSource: sources.fragment,
                        runtimeLoopBounds: loopBounds
                    ), let resolvedCombos =
                    SceneAuthoredShaderPreparation.resolvedIntegerCombos(
                        contract: template.shaderContract,
                        prepared: prepared,
                        combos: template.comboValues,
                        inactiveComboProviders: Set(
                            template.inheritedInactiveCombos
                        ),
                        textureReadiness: readiness,
                        textureFormats: textureFormats
                    ) else {
                throw Issue.sampler("bootstrap-frontend")
            }
            return try activeSamplers(
                prepared,
                activeNames: names,
                analysisVertexSource: sources.vertex,
                analysisFragmentSource: sources.fragment,
                normalBlendModeIdentifiers: Set(
                    resolvedCombos.compactMap { name, value in
                        value == 0 ? name : nil
                    }
                )
            )
        case .rejected, .notApplicable:
            throw Issue.sampler("bootstrap-variant")
        }
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
        var result = try samplerSchemas(records(sources))
        if let bootstrap = try? bootstrapSamplers(template) {
            for (slot, active) in bootstrap {
                guard let seed = result[slot],
                      let merged = seed.mergingVariantFacts(from: active) else {
                    continue
                }
                result[slot] = merged
            }
        }
        return result
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
        activeNames: Set<String>,
        analysisVertexSource: String? = nil,
        analysisFragmentSource: String? = nil,
        normalBlendModeIdentifiers: Set<String> = []
    ) throws -> [Int: Sampler] {
        guard activeNames.allSatisfy({ name in
            name.hasPrefix("g_Texture") && Int(name.dropFirst(9)) != nil
        }) else { throw Issue.sampler("active-reflection") }
        let schemas = try samplerSchemas(records(prepared).filter {
            $0.declaration.kind != .uniform
                || !isSampler2D($0.declaration.type)
                || activeNames.contains($0.declaration.name)
        })
        let vertexSource = analysisVertexSource ?? prepared.vertex.source
        let fragmentSource = analysisFragmentSource ?? prepared.fragment.source
        let projected = schemas.mapValues { sampler in
            sampler.withChannelUse(
                SceneAuthoredShaderTextureChannelAnalyzer.analyze(
                    samplerName: sampler.name,
                    vertexSource: vertexSource,
                    fragmentSource: fragmentSource
                )
            )
        }
        let sourceTyped = sourceTypedAuxiliarySamplers(
            projected,
            vertexSource: vertexSource,
            fragmentSource: fragmentSource
        )
        return sourceTypedSpatialWeightedColorBlendSamplers(
            sourceTyped,
            fragmentSource: fragmentSource,
            normalBlendModeIdentifiers: normalBlendModeIdentifiers
        )
    }

    private static func sourceTypedAuxiliarySamplers(
        _ samplers: [Int: Sampler],
        vertexSource: String,
        fragmentSource: String
    ) -> [Int: Sampler] {
        let facts = SceneAuthoredShaderAuxiliaryTexturePurposeAnalyzer.analyze(
            vertexSource: vertexSource,
            fragmentSource: fragmentSource
        )
        guard !facts.isEmpty, facts.allSatisfy({ fact in
            guard let sampler = samplers[fact.slot],
                  sampler.mode == .regular,
                  sampler.materialKey == nil,
                  !sampler.isHidden,
                  sampler.defaultTexture == nil,
                  sampler.sourceProvenPurpose == nil else { return false }
            if fact.role == .phase { return sampler.channelUse == .redOnly }
            return true
        }) else { return samplers }

        var result = samplers
        for fact in facts {
            let purpose: SceneTextureLoadPurpose = fact.role == .phase
                ? .phase : .normal
            result[fact.slot] = result[fact.slot]?
                .withSourceProvenPurpose(purpose)
        }
        return result
    }

    private static func sourceTypedSpatialWeightedColorBlendSamplers(
        _ samplers: [Int: Sampler],
        fragmentSource: String,
        normalBlendModeIdentifiers: Set<String>
    ) -> [Int: Sampler] {
        guard let fact = SceneAuthoredShaderSpatialWeightedColorBlendAnalyzer
                .analyze(
                    fragmentSource: fragmentSource,
                    normalBlendModeIdentifiers: normalBlendModeIdentifiers
                ),
              Set(samplers.keys) == fact.activeSlots,
              samplers[fact.sourceSlot]?.mode == .regular,
              samplers[fact.sourceSlot]?.channelUse == .wholeVector,
              samplers[fact.straightColorSlot]?.mode == .regular,
              samplers[fact.straightColorSlot]?.channelUse == .wholeVector,
              samplers[fact.preservedRedAlphaSlot]?.mode == .regular,
              fact.optionalMaskSlot.map({
                  samplers[$0]?.mode == .opacityMask
                      && samplers[$0]?.channelUse == .redOnly
              }) ?? true else { return samplers }
        var result = samplers
        result[fact.straightColorSlot] = result[fact.straightColorSlot]?
            .withSourceProvenPurpose(.straightAlbedo)
        result[fact.preservedRedAlphaSlot] = result[fact.preservedRedAlphaSlot]?
            .withSourceProvenPurpose(.preservedChannels)
        if let maskSlot = fact.optionalMaskSlot {
            result[maskSlot] = result[maskSlot]?
                .withSourceProvenPurpose(.mask)
        }
        return result
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
              matches[0].declaration.arraySuffix == nil,
              matches[0].declaration.arraySize == nil,
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

    /// Resolves the exact active scalar/vector consumers for one authored
    /// material key. The declaration name is author-controlled, so owner
    /// admission must prove the annotation mapping, stage set, and exact ABI.
    static func exactActiveUniforms(
        materialKey: String,
        type: SceneAuthoredShaderValueType,
        stages: [SceneShaderContract.StageKind],
        prepared: SceneShaderPreparedProgram
    ) -> [Uniform]? {
        guard !stages.isEmpty,
              Set(stages.map(\.rawValue)).count == stages.count else {
            return nil
        }
        let allRecords = records(prepared)
        var identities: [String: (
            stage: SceneShaderContract.StageKind, name: String
        )] = [:]
        for record in allRecords {
            guard let recordStage = record.stage,
                  record.declaration.kind == .uniform,
                  !isSampler2D(record.declaration.type) else { continue }
            let identity = [
                recordStage.rawValue, record.declaration.name,
            ].joined(separator: "\u{1f}")
            identities[identity] = (recordStage, record.declaration.name)
        }
        let matches = identities.values.compactMap { identity -> (
            stage: SceneShaderContract.StageKind, name: String, schema: Uniform
        )? in
            let field = SceneAuthoredShaderUniformLayout.Field(
                name: identity.name,
                stage: identity.stage,
                type: type,
                offset: 0
            )
            guard let schema = try? uniformSchema(field, records: allRecords),
                  schema.materialKeys.contains(materialKey) else { return nil }
            return (identity.stage, identity.name, schema)
        }
        guard matches.count == stages.count else { return nil }
        var result: [Uniform] = []
        for stage in stages {
            let stageMatches = matches.filter { $0.stage == stage }
            guard stageMatches.count == 1, let match = stageMatches.first else {
                return nil
            }
            let declarations = allRecords.filter {
                $0.stage == match.stage
                    && $0.declaration.kind == .uniform
                    && !isSampler2D($0.declaration.type)
                    && $0.declaration.name == match.name
            }
            guard declarations.count == 1,
                  declarations[0].declaration.arraySuffix == nil,
                  declarations[0].declaration.arraySize == nil,
                  SceneAuthoredShaderValueType(
                      authoredName: declarations[0].declaration.type
                  ) == type else { return nil }
            result.append(match.schema)
        }
        return result
    }

    static func uniqueActiveUniform(
        materialKey: String,
        type: SceneAuthoredShaderValueType,
        stage: SceneShaderContract.StageKind,
        prepared: SceneShaderPreparedProgram
    ) -> Uniform? {
        exactActiveUniforms(
            materialKey: materialKey,
            type: type,
            stages: [stage],
            prepared: prepared
        )?.first
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
            let authoredRange = try uniformRange(
                value("range", in: objects),
                editorType: value("type", in: objects),
                field: field,
                name: name
            )
            return .init(
                name: field.name,
                materialKeys: [name] + (material.map { [$0] } ?? []),
                defaultValue: fallback,
                authoredRange: authoredRange
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

    private static func uniformRange(
        _ value: SceneShaderAnnotationValue?,
        editorType: SceneShaderAnnotationValue?,
        field: SceneAuthoredShaderUniformLayout.Field,
        name: String
    ) throws -> ClosedRange<Double>? {
        if let value {
            let components = try defaultComponents(value, name: name)
            guard components.count == 2,
                  components[0] <= components[1] else {
                throw Issue.uniform(name)
            }
            return components[0] ... components[1]
        }
        guard field.type == .float3,
              field.arrayCount == nil,
              let rawType = editorType?.stringValue,
              rawType == rawType.trimmingCharacters(in: .whitespacesAndNewlines),
              rawType.caseInsensitiveCompare("color") == .orderedSame else {
            return nil
        }
        return 0 ... 1
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
