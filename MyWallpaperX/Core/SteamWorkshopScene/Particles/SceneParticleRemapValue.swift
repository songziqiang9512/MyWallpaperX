import Foundation

nonisolated enum SceneParticleRemapTransform: String, Equatable, Sendable {
    case simplexNoise = "simplexnoise"
    case unsupported
}

nonisolated enum SceneParticleRemapOutput: String, Equatable, Sendable {
    case velocity
    case unsupported
}

/// Loss-preserving typed declaration for the per-step Remap Value component.
///
/// Execution remains narrower than parsing. The first V3 cohort only admits the
/// stock Rain vector-velocity shape; scalar FBM, explicit input channels and
/// lifecycle blends keep a typed unsupported plan instead of being approximated
/// by the velocity operation.
nonisolated struct SceneParticleRemapValue: Equatable, Sendable {
    let operation: String?
    let output: SceneParticleRemapOutput
    let outputRangeMinimum: SceneParticleNumericValue?
    let outputRangeMaximum: SceneParticleNumericValue?
    let transform: SceneParticleRemapTransform
    let transformInputScale: Double?
    let hasExplicitInput: Bool
    let hasMalformedFields: Bool
    let unsupportedFieldNames: [String]

    nonisolated init(root: [String: Any]) {
        let supportedFields = Set([
            "id", "name", "operation", "output", "outputrangemin",
            "outputrangemax", "transformfunction", "transforminputscale",
        ])
        let rawOperation = Self.string(root["operation"])
        let rawOutput = Self.string(root["output"])
        let rawTransform = Self.string(root["transformfunction"])
        let minimum = SceneParticleDefinitionParser.numericValue(root["outputrangemin"])
        let maximum = SceneParticleDefinitionParser.numericValue(root["outputrangemax"])
        let scale = SceneParticleDefinitionParser.number(root["transforminputscale"])

        operation = rawOperation
        output = SceneParticleRemapOutput(rawValue: rawOutput ?? "") ?? .unsupported
        outputRangeMinimum = minimum
        outputRangeMaximum = maximum
        transform = SceneParticleRemapTransform(rawValue: rawTransform ?? "") ?? .unsupported
        transformInputScale = scale
        hasExplicitInput = root["input"] != nil || root["inputcontrolpoint0"] != nil
        hasMalformedFields = [
            ("operation", rawOperation != nil),
            ("output", rawOutput != nil),
            ("outputrangemin", minimum != nil),
            ("outputrangemax", maximum != nil),
            ("transformfunction", rawTransform != nil),
            ("transforminputscale", scale != nil),
        ].contains { key, parsed in
            root[key] != nil && !(root[key] is NSNull) && !parsed
        }
        unsupportedFieldNames = root.keys.filter { !supportedFields.contains($0) }.sorted()
    }

    private nonisolated static func string(_ rawValue: Any?) -> String? {
        guard let value = rawValue as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated struct SceneParticleVelocityRemapPlan: Equatable, Sendable {
    let minimum: SIMD3<Double>
    let maximum: SIMD3<Double>
    let inputScale: Double
}

extension SceneParticleOperator {
    nonisolated var boundedVelocityRemapPlan: SceneParticleVelocityRemapPlan? {
        guard rawFlags == 0, case let .remapValue(value) = kind,
              value.operation == "remap", value.output == .velocity,
              value.transform == .simplexNoise, !value.hasExplicitInput,
              !value.hasMalformedFields, value.unsupportedFieldNames.isEmpty,
              let minimum = Self.vector3(value.outputRangeMinimum),
              let maximum = Self.vector3(value.outputRangeMaximum),
              let scale = value.transformInputScale,
              scale.isFinite, scale > 0, scale <= 1_000_000 else { return nil }
        return .init(minimum: minimum, maximum: maximum, inputScale: scale)
    }

    private nonisolated static func vector3(
        _ value: SceneParticleNumericValue?
    ) -> SIMD3<Double>? {
        guard case let .vector(values) = value, values.count == 3,
              values.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else {
            return nil
        }
        return SIMD3(values[0], values[1], values[2])
    }
}
