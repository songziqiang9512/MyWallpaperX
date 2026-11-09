import Foundation

/// Shared, identity-free projections between authored numeric producer shapes
/// and a strictly reflected uniform consumer ABI.
nonisolated enum SceneResolvedMaterialUniformProjection {
    typealias Template = SceneResolvedMaterialTemplate

    static func encodeAuthoredStatic(
        _ value: Template.StaticUniformValue,
        schema: SceneResolvedMaterialPreparedUniformSchema,
        field: SceneAuthoredShaderUniformLayout.Field
    ) -> Data? {
        if let exact = SceneResolvedMaterialUniformEncoder.encode(
            value,
            as: field.type
        ) {
            return exact
        }
        let components = value.componentBitPatterns.map {
            Double(bitPattern: $0)
        }
        guard value.authoredScalarProjectionProven,
              components.count == 1,
              let component = components.first,
              component.isFinite,
              isIsotropicFloat2Consumer(schema: schema, field: field) else {
            return nil
        }
        return SceneResolvedMaterialUniformEncoder.encodeComponents(
            [component, component],
            as: field.type
        )
    }

    static func prepareDynamic(
        _ declaration: Template.DynamicUniform,
        contributor: Template.DynamicUniformSource,
        schema: SceneResolvedMaterialPreparedUniformSchema,
        field: SceneAuthoredShaderUniformLayout.Field
    ) -> SceneResolvedMaterialPreparedUniformBinding.Dynamic {
        let fallback = declaration.authoredFallback ?? schema.defaultValue
        var directRange: ClosedRange<Double>?
        var splatsScalarToFloat2 = false
        if case .userProperty = contributor,
           declaration.scriptAttachments.isEmpty,
           field.arrayCount == nil,
           let fallback,
           fallback.valueKind.localizedLowercase == "binding",
           SceneResolvedMaterialDirectUserBindingContract.matches(
               dynamic: declaration,
               fallback: fallback
           ) {
            if [.float, .float2, .float3].contains(field.type) {
                directRange = schema.authoredRange
            }
            if declaration.authoredFallback != nil,
               isIsotropicFloat2Consumer(schema: schema, field: field) {
                let components = fallback.componentBitPatterns.map { Double(bitPattern: $0) }
                splatsScalarToFloat2 = components.allSatisfy(\.isFinite)
                    && (components.count == 1
                        || (components.count == 2 && components[0] == components[1]))
            }
        }
        return .init(
            declaration: declaration,
            contributor: contributor,
            fallback: fallback,
            directUserPropertyRange: directRange,
            splatsScalarToFloat2: splatsScalarToFloat2
        )
    }

    static func isIsotropicFloat2Consumer(
        schema: SceneResolvedMaterialPreparedUniformSchema,
        field: SceneAuthoredShaderUniformLayout.Field
    ) -> Bool {
        field.type == .float2
            && field.arrayCount == nil
            && hasIsotropicFloat2Default(schema)
    }

    static func hasIsotropicFloat2Default(
        _ schema: SceneResolvedMaterialPreparedUniformSchema
    ) -> Bool {
        guard let consumerDefault = schema.defaultValue else { return false }
        let components = consumerDefault.componentBitPatterns.map {
            Double(bitPattern: $0)
        }
        return components.count == 2
            && components.allSatisfy(\.isFinite)
            && components[0] == components[1]
    }
}
