import Foundation

nonisolated enum SceneParticleRemapTransform: String, Equatable, Sendable {
    case simplexNoise = "simplexnoise"
    case fbmNoise = "fbmnoise"
    case unsupported
}

nonisolated enum SceneParticleRemapOutput: String, Equatable, Sendable {
    case velocity
    case speed
    case unsupported
}

/// Loss-preserving typed declaration for the per-step Remap Value component.
///
/// Execution admits the existing vector profile and a bounded scalar Multiply
/// profile. Explicit input channels and lifecycle blends remain unsupported.
nonisolated struct SceneParticleRemapValue: Equatable, Sendable {
    let operation: String?
    let hasExplicitOperation: Bool
    let hasExplicitFlags: Bool
    let output: SceneParticleRemapOutput
    let outputRangeMinimum: SceneParticleNumericValue?
    let outputRangeMaximum: SceneParticleNumericValue?
    let transform: SceneParticleRemapTransform
    let transformInputScale: Double?
    let hasExplicitInput: Bool
    let hasMalformedFields: Bool
    let hasMalformedScalarShape: Bool
    let unsupportedFieldNames: [String]

    nonisolated init(root: [String: Any]) {
        let supportedFields = Set([
            "id", "name", "flags", "operation", "output", "outputrangemin",
            "outputrangemax", "transformfunction", "transforminputscale",
        ])
        let rawOperation = Self.string(root["operation"])
        let rawOutput = Self.string(root["output"])
        let rawTransform = Self.string(root["transformfunction"])
        let minimum = SceneParticleDefinitionParser.numericValue(root["outputrangemin"])
        let maximum = SceneParticleDefinitionParser.numericValue(root["outputrangemax"])
        let scale = SceneParticleDefinitionParser.number(root["transforminputscale"])

        operation = rawOperation
        hasExplicitOperation = root["operation"] != nil
        hasExplicitFlags = root["flags"] != nil
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
            root[key] != nil && !parsed
        } || (root["flags"] != nil && SceneParticleDefinitionParser.integer(root["flags"]) == nil)
        hasMalformedScalarShape = [
            "flags", "outputrangemin", "outputrangemax", "transforminputscale",
        ].contains { root[$0] != nil && !Self.isCompleteScalarShape(root[$0]) }
        unsupportedFieldNames = root.keys.filter { !supportedFields.contains($0) }.sorted()
    }

    private nonisolated static func string(_ rawValue: Any?) -> String? {
        guard let value = rawValue as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The shared numeric decoder accepts author wrappers. A scalar array must
    /// retain its one authored leaf rather than collapse after filtering or
    /// recursively decoding nested containers. This guard only gates speed.
    private nonisolated static func isCompleteScalarShape(_ rawValue: Any?) -> Bool {
        if let wrapper = rawValue as? [String: Any], let value = wrapper["value"] {
            return isCompleteScalarShape(value)
        }
        if let values = rawValue as? [Any] {
            guard values.count == 1, !(values[0] is [Any]),
                  !(values[0] is [String: Any]) else { return false }
            return SceneParticleDefinitionParser.number(values[0]) != nil
        }
        return SceneParticleDefinitionParser.number(rawValue) != nil
    }
}

nonisolated struct SceneParticleVelocityRemapPlan: Equatable, Sendable {
    let minimum: SIMD3<Double>
    let maximum: SIMD3<Double>
    let inputScale: Double
}

nonisolated struct SceneParticleScalarSpeedRemapPlan: Equatable, Sendable {
    let minimum: Double
    let maximum: Double
    let inputScale: Double
}

extension SceneParticleOperator {
    nonisolated var boundedVelocityRemapPlan: SceneParticleVelocityRemapPlan? {
        guard rawFlags == 0, case let .remapValue(value) = kind, !value.hasExplicitFlags,
              value.operation == "remap", value.output == .velocity,
              value.transform == .simplexNoise, !value.hasExplicitInput,
              !value.hasMalformedFields, value.unsupportedFieldNames.isEmpty,
              let minimum = Self.vector3(value.outputRangeMinimum),
              let maximum = Self.vector3(value.outputRangeMaximum),
              let scale = value.transformInputScale,
              scale.isFinite, scale > 0, scale <= 1_000_000 else { return nil }
        return .init(minimum: minimum, maximum: maximum, inputScale: scale)
    }

    nonisolated var boundedScalarSpeedRemapPlan: SceneParticleScalarSpeedRemapPlan? {
        guard rawFlags == 3, case let .remapValue(value) = kind,
              !value.hasExplicitOperation || value.operation == "multiply",
              value.output == .speed, value.transform == .fbmNoise,
              !value.hasExplicitInput, !value.hasMalformedFields,
              !value.hasMalformedScalarShape,
              value.unsupportedFieldNames.isEmpty,
              case let .scalar(minimum) = value.outputRangeMinimum,
              case let .scalar(maximum) = value.outputRangeMaximum,
              minimum.isFinite, maximum.isFinite,
              abs(minimum) <= 1_000_000, abs(maximum) <= 1_000_000,
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
