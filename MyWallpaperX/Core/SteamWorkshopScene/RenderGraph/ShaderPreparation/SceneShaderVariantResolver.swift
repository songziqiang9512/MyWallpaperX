import Foundation

/// Compiles author annotations, resolved material combos and texture readiness
/// into one deterministic macro environment. Macro spelling remains case
/// sensitive because authored shaders use distinct `VERSION` and `version` keys.
nonisolated enum SceneShaderVariantResolver {
    enum FailureCode: String, Codable, Equatable, Sendable {
        case invalidAnnotation = "invalid-annotation"
        case disabledComboAnnotation = "disabled-combo-annotation"
        case missingDefault = "missing-default"
        case conflictingDefault = "conflicting-default"
        case invalidOption = "invalid-option"
        case invalidEnvironment = "invalid-environment"
        case unresolvedRequirement = "unresolved-requirement"
        case conflictingTextureReadiness = "conflicting-texture-readiness"
        case explicitTextureReadinessConflict = "explicit-texture-readiness-conflict"
        case textureReadinessUnavailable = "texture-readiness-unavailable"
        case conflictingTextureFormat = "conflicting-texture-format"
        case explicitTextureFormatConflict = "explicit-texture-format-conflict"
        case textureFormatUnavailable = "texture-format-unavailable"
        case resolutionDidNotConverge = "resolution-did-not-converge"
    }

    struct Failure: Error, Codable, Equatable, Sendable {
        let code: FailureCode
        let combo: String?
        let message: String
    }

    static func resolve(
        stage: SceneShaderContract.StageKind,
        stages: [SceneShaderContract.Stage],
        explicitCombos: [String: Int],
        inactiveComboProviders: Set<String> = [],
        textureReadiness: [Int: Bool] = [:],
        textureFormats: [Int: SceneShaderTextureFormat] = [:]
    ) -> Result<SceneShaderVariantEnvironment, Failure> {
        resolve(
            stage: stage,
            schemaSources: stages.map(SceneShaderVariantSchemaSource.init),
            explicitCombos: explicitCombos,
            inactiveComboProviders: inactiveComboProviders,
            textureReadiness: textureReadiness,
            textureFormats: textureFormats
        )
    }

    static func resolve(
        stage: SceneShaderContract.StageKind,
        schemaSources: [SceneShaderVariantSchemaSource],
        explicitCombos: [String: Int],
        inactiveComboProviders: Set<String> = [],
        textureReadiness: [Int: Bool] = [:],
        textureFormats: [Int: SceneShaderTextureFormat] = [:]
    ) -> Result<SceneShaderVariantEnvironment, Failure> {
        let schemas: [Schema]
        do {
            schemas = try schemaSources.flatMap(schemas(in:))
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            preconditionFailure("Unexpected shader variant schema failure: \(error)")
        }

        let explicit = explicitCombos.mapValues(Int64.init)
        let inactiveProviders = inactiveComboProviders.subtracting(explicit.keys)
        if let disabled = schemas.first(where: {
            $0.isDisabledCombo && explicit[$0.combo] != nil
        }) {
            return .failure(.init(
                code: .disabledComboAnnotation,
                combo: disabled.combo,
                message: "Disabled shader combo cannot be overridden by authored material data."
            ))
        }
        let schemaNames = Set(schemas.map(\.combo))
        let providerNames = schemaNames
            .union(explicit.keys)
            .union(inactiveProviders)
        var baseDefinitions = Dictionary(
            uniqueKeysWithValues: schemaNames.union(inactiveProviders).map {
                ($0, SceneShaderMacroDefinition.undefined)
            }
        )
        var baseProvenance = Dictionary(
            uniqueKeysWithValues: schemaNames.map {
                ($0, SceneShaderComboProvenance.annotationUndefined)
            }
        )
        for name in inactiveProviders where baseProvenance[name] == nil {
            baseProvenance[name] = .authoredEffectInactive
        }
        for (name, value) in explicit {
            baseDefinitions[name] = .defined(.integer(value))
            baseProvenance[name] = .explicitResolvedMaterial
        }

        do {
            try validateRequirementProviders(
                schemas,
                providerNames: providerNames
            )
            try validateHostRequirements(
                schemas,
                providerNames: providerNames
            )
            try resolveAuthoredCombos(
                schemas.filter(\.isAuthoredComboMarker),
                explicit: explicit,
                definitions: &baseDefinitions,
                provenance: &baseProvenance
            )
            let baseState = ResolutionState(
                definitions: baseDefinitions,
                provenance: baseProvenance,
                validatedSlots: [:]
            )
            var state = baseState
            var visitedStates = [state]
            var converged = false
            let passBudget = max(1, schemas.count + providerNames.count + 1)
            for _ in 0 ..< passBudget {
                var next = baseState
                try applyTextureReadiness(
                    schemas,
                    explicit: explicit,
                    textureReadiness: textureReadiness,
                    schemaProviders: providerNames,
                    requirementDefinitions: state.definitions,
                    definitions: &next.definitions,
                    provenance: &next.provenance,
                    validatedSlots: &next.validatedSlots
                )
                try applyTextureFormats(
                    schemas,
                    explicit: explicit,
                    textureFormats: textureFormats,
                    schemaProviders: providerNames,
                    requirementDefinitions: state.definitions,
                    definitions: &next.definitions,
                    provenance: &next.provenance,
                    validatedSlots: &next.validatedSlots
                )
                if next == state {
                    state = next
                    converged = true
                    break
                }
                guard !visitedStates.contains(next) else {
                    throw Failure(
                        code: .resolutionDidNotConverge,
                        combo: nil,
                        message: "Shader combo requirements entered a repeating resolution state."
                    )
                }
                visitedStates.append(next)
                state = next
            }
            guard converged else {
                throw Failure(
                    code: .resolutionDidNotConverge,
                    combo: nil,
                    message: "Shader combo requirements exceeded their bounded resolution budget."
                )
            }
            var finalProvenance = state.provenance
            for combo in Set(schemas.filter {
                $0.hasRuntimeRequirements && !$0.requirements.isEmpty
            }.map(\.combo)).sorted()
            where explicit[combo] == nil && state.definitions[combo] == .undefined {
                let hasActiveSchema = schemas.contains {
                    $0.combo == combo && requirementsSatisfied(
                        $0,
                        definitions: state.definitions,
                        schemaProviders: providerNames
                    )
                }
                if !hasActiveSchema {
                    finalProvenance[combo] = .requirementInactive
                }
            }
            try validateOptions(
                schemas,
                definitions: state.definitions
            )
            let resolutions = state.definitions.keys.sorted().map { name in
                SceneShaderComboResolution(
                    binding: .init(name: name, definition: state.definitions[name]!),
                    provenance: finalProvenance[name] ?? .annotationUndefined,
                    schemaDeclared: schemas.contains {
                        $0.combo == name && $0.isAuthoredComboMarker
                    },
                    validatedTextureSlots: Array(state.validatedSlots[name] ?? []).sorted()
                )
            }
            return .success(try SceneShaderVariantEnvironment(
                stage: stage,
                comboResolutions: resolutions
            ))
        } catch let failure as Failure {
            return .failure(failure)
        } catch let failure as SceneShaderVariantFailure {
            return .failure(.init(
                code: .invalidEnvironment,
                combo: failure.identifier,
                message: failure.message
            ))
        } catch {
            preconditionFailure("Unexpected shader variant resolution failure: \(error)")
        }
    }

    private static func resolveAuthoredCombos(
        _ schemas: [Schema],
        explicit: [String: Int64],
        definitions: inout [String: SceneShaderMacroDefinition],
        provenance: inout [String: SceneShaderComboProvenance]
    ) throws {
        let grouped = Dictionary(grouping: schemas, by: \.combo)
        for combo in grouped.keys.sorted() {
            guard let comboSchemas = grouped[combo] else { continue }
            let defaults = comboSchemas.compactMap(\.defaultValue)
            let uniqueDefaults = Set(defaults)
            guard uniqueDefaults.count <= 1 else {
                throw Failure(
                    code: .conflictingDefault,
                    combo: combo,
                    message: "Shader combo annotations declare conflicting defaults."
                )
            }
            if explicit[combo] != nil { continue }
            guard defaults.count == comboSchemas.count,
                  let value = uniqueDefaults.first else {
                throw Failure(
                    code: .missingDefault,
                    combo: combo,
                    message: "Shader combo requires an annotation default when the material has no explicit value."
                )
            }
            definitions[combo] = .defined(.integer(value))
            provenance[combo] = .annotationDefault
        }
    }

    private static func applyTextureReadiness(
        _ schemas: [Schema],
        explicit: [String: Int64],
        textureReadiness: [Int: Bool],
        schemaProviders: Set<String>,
        requirementDefinitions: [String: SceneShaderMacroDefinition],
        definitions: inout [String: SceneShaderMacroDefinition],
        provenance: inout [String: SceneShaderComboProvenance],
        validatedSlots: inout [String: Set<Int>]
    ) throws {
        let active = schemas.filter {
            $0.samplerSlot != nil && requirementsSatisfied(
                $0,
                definitions: requirementDefinitions,
                schemaProviders: schemaProviders
            )
        }
        let groupedSchemas = Dictionary(grouping: active, by: \.combo)
        for combo in groupedSchemas.keys.sorted() {
            guard let comboSchemas = groupedSchemas[combo] else { continue }
            let slots = Set(comboSchemas.compactMap(\.samplerSlot))
            let missingSlots = slots.filter { textureReadiness[$0] == nil }.sorted()
            guard missingSlots.isEmpty else {
                throw Failure(
                    code: .textureReadinessUnavailable,
                    combo: combo,
                    message: "Shader sampler combo requires explicit readiness for slots \(missingSlots)."
                )
            }
            let readiness = Set(slots.compactMap { textureReadiness[$0] })
            guard readiness.count == 1, let isReady = readiness.first else {
                throw Failure(
                    code: .conflictingTextureReadiness,
                    combo: combo,
                    message: "One shader combo is attached to texture slots with conflicting readiness."
                )
            }
            let expected: SceneShaderMacroDefinition = isReady
                ? .defined(.integer(1))
                : .undefined
            if explicit[combo] != nil {
                guard definitions[combo] == expected else {
                    throw Failure(
                        code: .explicitTextureReadinessConflict,
                        combo: combo,
                        message: "Explicit material combo conflicts with its texture readiness fact."
                    )
                }
            } else {
                if definitions[combo] != .undefined,
                   definitions[combo] != expected {
                    guard authoredZeroDefaultCanYieldToReadiness(
                        combo,
                        schemas: schemas,
                        definition: definitions[combo],
                        provenance: provenance[combo]
                    ) else {
                        throw Failure(
                            code: .conflictingTextureReadiness,
                            combo: combo,
                            message: "Shader annotation default conflicts with texture readiness."
                        )
                    }
                }
                definitions[combo] = expected
                provenance[combo] = .textureReadiness
            }
            validatedSlots[combo, default: []].formUnion(slots)
        }
    }

    private static func authoredZeroDefaultCanYieldToReadiness(
        _ combo: String,
        schemas: [Schema],
        definition: SceneShaderMacroDefinition?,
        provenance: SceneShaderComboProvenance?
    ) -> Bool {
        let authored = schemas.filter {
            $0.combo == combo && $0.origin == .authoredCombo
        }
        return authored.count == 1
            && authored[0].defaultValue == 0
            && authored[0].requirements.isEmpty
            && !authored[0].requireAny
            && definition == .defined(.integer(0))
            && provenance == .annotationDefault
    }

    private static func validateOptions(
        _ schemas: [Schema],
        definitions: [String: SceneShaderMacroDefinition]
    ) throws {
        for schema in schemas {
            guard let options = schema.options,
                  case .defined(.integer(let value)) = definitions[schema.combo],
                  !options.contains(value) else { continue }
            throw Failure(
                code: .invalidOption,
                combo: schema.combo,
                message: "Shader combo value is outside its authored option set."
            )
        }
    }

    static func requirementsSatisfied(
        _ schema: Schema,
        definitions: [String: SceneShaderMacroDefinition],
        schemaProviders: Set<String>
    ) -> Bool {
        guard schema.hasRuntimeRequirements,
              !schema.requirements.isEmpty else { return true }
        let matches = schema.requirements.map { name, expected in
            if let requirement = SceneShaderVariantEnvironment.unresolvedRequirement(for: name) {
                if requirement == .backendLanguage || requirement == .platform {
                    return false
                }
                guard schemaProviders.contains(name),
                      case .defined? = definitions[name] else { return false }
            }
            return value(definitions[name]) == expected
        }
        return schema.requireAny ? matches.contains(true) : matches.allSatisfy { $0 }
    }

    private static func validateRequirementProviders(
        _ schemas: [Schema],
        providerNames: Set<String>
    ) throws {
        for name in Set(schemas.filter(\.hasRuntimeRequirements)
            .flatMap { $0.requirements.keys }).sorted() {
            guard SceneShaderVariantEnvironment.unresolvedRequirement(for: name) == nil else {
                continue
            }
            guard providerNames.contains(name) else {
                throw Failure(
                    code: .unresolvedRequirement,
                    combo: name,
                    message: "Shader combo requirement '\(name)' has no declared [COMBO] provider."
                )
            }
        }
    }

    private static func value(_ definition: SceneShaderMacroDefinition?) -> Int64 {
        guard case .defined(let macro)? = definition else { return 0 }
        return macro.expressionValue ?? 0
    }

    private struct ResolutionState: Equatable {
        var definitions: [String: SceneShaderMacroDefinition]
        var provenance: [String: SceneShaderComboProvenance]
        var validatedSlots: [String: Set<Int>]
    }

}
