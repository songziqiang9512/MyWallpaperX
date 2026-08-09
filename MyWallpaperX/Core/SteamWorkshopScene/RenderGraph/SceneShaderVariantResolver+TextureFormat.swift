import Foundation

nonisolated extension SceneShaderVariantResolver {
    static func applyTextureFormats(
        _ schemas: [Schema],
        explicit: [String: Int64],
        textureFormats: [Int: SceneShaderTextureFormat],
        schemaProviders: Set<String>,
        requirementDefinitions: [String: SceneShaderMacroDefinition],
        definitions: inout [String: SceneShaderMacroDefinition],
        provenance: inout [String: SceneShaderComboProvenance],
        validatedSlots: inout [String: Set<Int>]
    ) throws {
        let active = schemas.filter {
            $0.textureFormatSlot != nil && requirementsSatisfied(
                $0,
                definitions: requirementDefinitions,
                schemaProviders: schemaProviders
            )
        }
        let groupedSchemas = Dictionary(grouping: active, by: \.combo)
        for combo in groupedSchemas.keys.sorted() {
            guard let comboSchemas = groupedSchemas[combo] else { continue }
            let slots = Set(comboSchemas.compactMap(\.textureFormatSlot))
            let missingSlots = slots.filter { textureFormats[$0] == nil }.sorted()
            guard missingSlots.isEmpty else {
                throw Failure(
                    code: .textureFormatUnavailable,
                    combo: combo,
                    message: "Shader texture format combo requires authored formats for slots \(missingSlots)."
                )
            }
            let values = Set(slots.compactMap { textureFormats[$0]?.macroValue })
            guard values.count == 1, let value = values.first else {
                throw Failure(
                    code: .conflictingTextureFormat,
                    combo: combo,
                    message: "One shader format combo is attached to texture slots with conflicting formats."
                )
            }
            let expected = SceneShaderMacroDefinition.defined(
                .integer(Int64(value))
            )
            if explicit[combo] != nil {
                throw Failure(
                    code: .explicitTextureFormatConflict,
                    combo: combo,
                    message: "Texture format macros are host-owned and cannot come from material combos."
                )
            }
            if definitions[combo] != .undefined,
               definitions[combo] != expected {
                throw Failure(
                    code: .conflictingTextureFormat,
                    combo: combo,
                    message: "Shader texture format facts conflict."
                )
            }
            definitions[combo] = expected
            provenance[combo] = .textureFormat
            validatedSlots[combo, default: []].formUnion(slots)
        }
    }

    static func validateHostRequirements(
        _ schemas: [Schema],
        providerNames: Set<String>
    ) throws {
        for name in Set(schemas.flatMap { $0.requirements.keys }).sorted() {
            guard let requirement = SceneShaderVariantEnvironment.unresolvedRequirement(for: name) else {
                continue
            }
            if requirement == .textureFormat,
               providerNames.contains(name) {
                continue
            }
            throw Failure(
                code: .invalidEnvironment,
                combo: name,
                message: "Shader requirement '\(name)' has no trusted \(requirement.rawValue) provider."
            )
        }
    }

}
