import Foundation

/// Shared, identity-free projections between authored numeric producer shapes
/// and a strictly reflected uniform consumer ABI.
nonisolated enum SceneResolvedMaterialUniformProjection {
    typealias Template = SceneResolvedMaterialTemplate

    static func encodeAuthoredStatic(
        _ value: Template.StaticUniformValue,
        schema: SceneResolvedMaterialShaderSchema.Uniform,
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

    static func isIsotropicFloat2Consumer(
        schema: SceneResolvedMaterialShaderSchema.Uniform,
        field: SceneAuthoredShaderUniformLayout.Field
    ) -> Bool {
        field.type == .float2
            && field.arrayCount == nil
            && hasIsotropicFloat2Default(schema)
    }

    static func hasIsotropicFloat2Default(
        _ schema: SceneResolvedMaterialShaderSchema.Uniform
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
