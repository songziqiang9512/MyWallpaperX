import Foundation
import simd

// Shared current-snapshot numeric resolution for shader finalization and
// prepared geometry, preserving source, range, fallback and ABI validation.
nonisolated extension SceneResolvedMaterialProgram {
    private typealias Template = SceneResolvedMaterialTemplate

    static func resolvePreparedPoint(
        _ binding: SceneResolvedMaterialPreparedUniformBinding,
        snapshot: SceneDynamicSnapshot
    ) -> SIMD2<Float>? {
        guard binding.field.type == .float2, binding.field.arrayCount == nil,
              let uniform = try? resolvedAuthoredUniform(binding, snapshot: snapshot),
              uniform.encodedValue.count == 8 else { return nil }
        let point = uniform.encodedValue.withUnsafeBytes {
            SIMD2($0.loadUnaligned(as: Float.self),
                  $0.loadUnaligned(fromByteOffset: 4, as: Float.self))
        }
        return point.x.isFinite && point.y.isFinite ? point : nil
    }

    static func resolvedAuthoredUniform(
        _ binding: SceneResolvedMaterialPreparedUniformBinding,
        snapshot: SceneDynamicSnapshot
    ) throws -> ResolvedUniform {
        let field = binding.field
        switch binding.source {
        case let .staticValue(encoded):
            guard encoded.count == field.storageByteSize else {
                throw SceneResolvedMaterialFailure(
                    phase: .invariant,
                    code: .programAssemblyIdentityInvariant,
                    details: [field.name, "prepared-static-byte-count"]
                )
            }
            return .init(
                field: field,
                source: .staticValue,
                encodedValue: encoded
            )
        case let .dynamic(prepared):
            let dynamic = prepared.declaration
            let contributor = prepared.contributor
            let fallback = prepared.fallback
            let schema = prepared.schema
            guard let resolved = snapshot[dynamic.target],
                  valid(
                      resolved.source,
                      contributor: contributor,
                      fallback: fallback
                  ) else {
                throw SceneResolvedMaterialFailure(
                    phase: .uniform,
                    code: .dynamicUniformBindingInvalid,
                    details: [field.name]
                )
            }
            let liveEncoded = encodeDynamicUniform(
                resolved.value,
                contributor: contributor,
                declaration: dynamic,
                schema: schema,
                field: field
            )
            guard let encoded = directUserPropertyRangedValue(
                liveEncoded,
                liveValue: resolved.value,
                authoredValue: snapshot.authoredValue(
                    for: dynamic.target
                ),
                userPropertyNumericRange:
                    snapshot.userPropertyNumericRange(
                        for: dynamic.target
                    ),
                fallback,
                source: resolved.source,
                contributor: contributor,
                declaration: dynamic,
                schema: schema,
                field: field
            ) else {
                throw SceneResolvedMaterialFailure(
                    phase: .uniform,
                    code: .dynamicUniformBindingInvalid,
                    details: [field.name]
                )
            }
            if resolved.source == .authored {
                guard let fallback,
                      encodeDynamicFallback(
                          fallback,
                          contributor: contributor,
                          declaration: dynamic,
                          schema: schema,
                          field: field
                      ) == encoded else {
                    throw SceneResolvedMaterialFailure(
                        phase: .uniform,
                        code: .dynamicUniformBindingInvalid,
                        details: [field.name]
                    )
                }
            }
            return .init(
                field: field,
                source: .dynamic(
                    declared: contributor,
                    target: dynamic.target,
                    resolvedSource: resolved.source,
                    scriptAttachments: dynamic.scriptAttachments
                ),
                encodedValue: encoded
            )
        default:
            throw SceneResolvedMaterialFailure(
                phase: .uniform, code: .staticUniformBindingInvalid, details: [field.name]
            )
        }
    }

    private static func valid(
        _ source: SceneDynamicSource,
        contributor: Template.DynamicUniformSource,
        fallback: Template.StaticUniformValue?
    ) -> Bool {
        if source == .authored { return fallback != nil }
        return switch (contributor, source) {
        case (.userProperty, .userProperty), (.timeline, .timeline),
             (.sceneScript, .sceneScript): true
        default: false
        }
    }

    private static func value(
        _ value: SceneDynamicValue,
        isWithin range: ClosedRange<Double>?
    ) -> Bool {
        guard let range else { return true }
        let components: [Double]
        switch value {
        case let .scalar(x): components = [x]
        case let .vector2(x, y): components = [x, y]
        case let .vector3(x, y, z): components = [x, y, z]
        case let .vector4(x, y, z, w): components = [x, y, z, w]
        case .bool, .string: return false
        }
        return components.allSatisfy { $0.isFinite && range.contains($0) }
    }

    private static func directUserPropertyRangedValue(
        _ liveEncoded: Data?,
        liveValue: SceneDynamicValue,
        authoredValue: SceneDynamicValue?,
        userPropertyNumericRange: ClosedRange<Double>?,
        _ fallback: Template.StaticUniformValue?,
        source: SceneDynamicSource,
        contributor: Template.DynamicUniformSource,
        declaration: Template.DynamicUniform,
        schema: SceneResolvedMaterialPreparedUniformSchema,
        field: SceneAuthoredShaderUniformLayout.Field
    ) -> Data? {
        guard let liveEncoded else { return nil }
        guard source == .userProperty,
              case .userProperty = contributor,
              [.float, .float2, .float3].contains(field.type),
              field.arrayCount == nil,
              declaration.scriptAttachments.isEmpty,
              let fallback,
              fallback.valueKind.localizedLowercase == "binding",
              SceneResolvedMaterialDirectUserBindingContract.matches(
                  dynamic: declaration,
                  fallback: fallback
              ),
              let range = schema.authoredRange else {
            return liveEncoded
        }
        if value(liveValue, isWithin: range) { return liveEncoded }
        if field.type == .float,
           let userPropertyNumericRange,
           value(liveValue, isWithin: userPropertyNumericRange) {
            // A direct user property owns its authored UI domain. Shader
            // range annotations describe the unbound material editor value
            // and may intentionally exclude a UI sentinel such as zero.
            return liveEncoded
        }
        guard let authoredValue,
              let authoredEncoded = encodeDynamicUniform(
            authoredValue,
            contributor: contributor,
            declaration: declaration,
            schema: schema,
            field: field
        ) else { return nil }
        if value(authoredValue, isWithin: range) { return authoredEncoded }

        // A direct property wrapper may author an equal-lane float2 sentinel
        // outside shader editor metadata (for example zero to disable blur).
        // Preserve only an exact fallback projection; arbitrary live values
        // and every other ABI/source shape stay range-gated.
        guard scalarSplatEligible(
                  contributor: contributor, declaration: declaration,
                  schema: schema, field: field
              ), let fallbackEncoded = encodeDynamicFallback(
                  fallback, contributor: contributor,
                  declaration: declaration, schema: schema, field: field
              ), authoredEncoded == fallbackEncoded else { return nil }
        return authoredEncoded
    }

    /// Slider properties are scalar producers. A float2 shader consumer with
    /// an equal-lane typed default may explicitly bind that scalar through the
    /// direct user/value wrapper. Keep the producer scalar and perform only
    /// that isotropic consumer projection; all other lane/type/source shapes
    /// retain the existing exact encoder failure.
    private static func encodeDynamicUniform(
        _ value: SceneDynamicValue,
        contributor: Template.DynamicUniformSource,
        declaration: Template.DynamicUniform,
        schema: SceneResolvedMaterialPreparedUniformSchema,
        field: SceneAuthoredShaderUniformLayout.Field
    ) -> Data? {
        if let exact = SceneResolvedMaterialUniformEncoder.encode(
            value,
            as: field.type
        ) {
            return exact
        }
        guard case let .scalar(component) = value,
              component.isFinite,
              scalarSplatEligible(
                  contributor: contributor,
                  declaration: declaration,
                  schema: schema,
                  field: field
              ) else {
            return nil
        }
        return SceneResolvedMaterialUniformEncoder.encodeComponents(
            [component, component],
            as: field.type
        )
    }

    private static func encodeDynamicFallback(
        _ fallback: Template.StaticUniformValue,
        contributor: Template.DynamicUniformSource,
        declaration: Template.DynamicUniform,
        schema: SceneResolvedMaterialPreparedUniformSchema,
        field: SceneAuthoredShaderUniformLayout.Field
    ) -> Data? {
        if let exact = SceneResolvedMaterialUniformEncoder.encode(
            fallback,
            as: field.type
        ) {
            return exact
        }
        let components = fallback.componentBitPatterns.map {
            Double(bitPattern: $0)
        }
        guard components.count == 1,
              let component = components.first,
              component.isFinite,
              scalarSplatEligible(
                  contributor: contributor,
                  declaration: declaration,
                  schema: schema,
                  field: field
              ) else {
            return nil
        }
        return SceneResolvedMaterialUniformEncoder.encodeComponents(
            [component, component],
            as: field.type
        )
    }

    private static func scalarSplatEligible(
        contributor: Template.DynamicUniformSource,
        declaration: Template.DynamicUniform,
        schema: SceneResolvedMaterialPreparedUniformSchema,
        field: SceneAuthoredShaderUniformLayout.Field
    ) -> Bool {
        guard case .userProperty = contributor,
              declaration.scriptAttachments.isEmpty,
              let fallback = declaration.authoredFallback,
              fallback.valueKind.localizedLowercase == "binding",
              SceneResolvedMaterialDirectUserBindingContract.matches(
                  dynamic: declaration,
                  fallback: fallback
              ),
              SceneResolvedMaterialUniformProjection.isIsotropicFloat2Consumer(
                  schema: schema,
                  field: field
              ) else {
            return false
        }
        let fallbackComponents = fallback.componentBitPatterns.map {
            Double(bitPattern: $0)
        }
        let fallbackIsScalarOrEqualPair = fallbackComponents.count == 1
            || (fallbackComponents.count == 2
                && fallbackComponents[0] == fallbackComponents[1])
        return fallbackIsScalarOrEqualPair
            && fallbackComponents.allSatisfy(\.isFinite)
    }

}
