import Foundation
import simd

// Shared current-snapshot numeric resolution for shader finalization and
// prepared geometry, preserving source, range, fallback and ABI validation.
nonisolated extension SceneResolvedMaterialProgram {
    private typealias Template = SceneResolvedMaterialTemplate
    private typealias DynamicBinding = SceneResolvedMaterialPreparedUniformBinding.Dynamic

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
            return .init(encodedValue: encoded)
        case let .dynamic(prepared):
            let dynamic = prepared.declaration
            let fallback = prepared.fallback
            guard let resolved = snapshot[dynamic.target],
                  valid(
                      resolved.source,
                      contributors: dynamic.valueContributors,
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
                splatsScalarToFloat2: prepared.splatsScalarToFloat2,
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
                prepared: prepared,
                source: resolved.source,
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
                          splatsScalarToFloat2: prepared.splatsScalarToFloat2,
                          field: field
                      ) == encoded else {
                    throw SceneResolvedMaterialFailure(
                        phase: .uniform,
                        code: .dynamicUniformBindingInvalid,
                        details: [field.name]
                    )
                }
            }
            return .init(encodedValue: encoded, resolvedSource: resolved.source)
        default:
            throw SceneResolvedMaterialFailure(
                phase: .uniform, code: .staticUniformBindingInvalid, details: [field.name]
            )
        }
    }

    private static func valid(
        _ source: SceneDynamicSource,
        contributors: [Template.DynamicUniformSource],
        fallback: Template.StaticUniformValue?
    ) -> Bool {
        if source == .authored { return fallback != nil }
        return contributors.contains { contributor in
            switch (contributor, source) {
            case (.userProperty, .userProperty), (.timeline, .timeline),
                 (.sceneScript, .sceneScript): true
            default: false
            }
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
        prepared: DynamicBinding,
        source: SceneDynamicSource,
        field: SceneAuthoredShaderUniformLayout.Field
    ) -> Data? {
        guard let liveEncoded else { return nil }
        guard source == .userProperty,
              let range = prepared.directUserPropertyRange else {
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
            splatsScalarToFloat2: prepared.splatsScalarToFloat2,
            field: field
        ) else { return nil }
        if value(authoredValue, isWithin: range) { return authoredEncoded }

        // A direct property wrapper may author an equal-lane float2 sentinel
        // outside shader editor metadata (for example zero to disable blur).
        // Preserve only an exact fallback projection; arbitrary live values
        // and every other ABI/source shape stay range-gated.
        guard prepared.splatsScalarToFloat2,
              let fallback = prepared.fallback,
              let fallbackEncoded = encodeDynamicFallback(
                  fallback, splatsScalarToFloat2: true, field: field
              ), authoredEncoded == fallbackEncoded else { return nil }
        return authoredEncoded
    }

    private static func encodeDynamicUniform(
        _ value: SceneDynamicValue,
        splatsScalarToFloat2: Bool,
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
              splatsScalarToFloat2 else {
            return nil
        }
        return SceneResolvedMaterialUniformEncoder.encodeComponents(
            [component, component],
            as: field.type
        )
    }

    private static func encodeDynamicFallback(
        _ fallback: Template.StaticUniformValue,
        splatsScalarToFloat2: Bool,
        field: SceneAuthoredShaderUniformLayout.Field
    ) -> Data? {
        if let exact = SceneResolvedMaterialUniformEncoder.encode(
            fallback,
            as: field.type
        ) {
            return exact
        }
        guard splatsScalarToFloat2, fallback.componentBitPatterns.count == 1 else { return nil }
        let component = Double(bitPattern: fallback.componentBitPatterns[0])
        return SceneResolvedMaterialUniformEncoder.encodeComponents(
            [component, component],
            as: field.type
        )
    }

}
