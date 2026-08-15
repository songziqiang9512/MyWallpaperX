import Foundation

/// Typed output of the bounded SceneScript family that copies slider-backed
/// script properties into an authored Vec3 layer transform.
///
/// The program is data only. It does not grant authority to arbitrary
/// JavaScript, object mutation, events, or targets outside layer origin/scale.
nonisolated struct ScenePropertyVectorScriptProgram: Equatable, Sendable {
    let bindings: [ScenePropertyVectorScriptBinding]

    nonisolated static let empty = ScenePropertyVectorScriptProgram(bindings: [])

    nonisolated var definitions: [SceneDynamicTargetDefinition] {
        bindings.map(\.definition)
    }

    nonisolated var admittedScaleLayerIDs: Set<Int> {
        Set(bindings.compactMap { binding in
            guard case let .layer(layerID, .scale) = binding.definition.target else {
                return nil
            }
            return layerID
        })
    }

    nonisolated static func validated(
        bindings: [ScenePropertyVectorScriptBinding]
    ) -> Self? {
        let targets = bindings.map(\.definition.target)
        guard Set(targets).count == targets.count,
              bindings.allSatisfy(\.isValid) else { return nil }
        return Self(bindings: bindings.sorted {
            $0.definition.target.propertyVectorSortKey
                < $1.definition.target.propertyVectorSortKey
        })
    }
}

nonisolated struct ScenePropertyVectorScriptBinding: Equatable, Sendable {
    let definition: SceneDynamicTargetDefinition
    let operation: ScenePropertyVectorScriptOperation

    fileprivate nonisolated var isValid: Bool {
        guard definition.valueType == .vector3,
              case .vector3 = definition.authoredValue else { return false }
        switch definition.target {
        case .layer(_, .origin):
            guard case .components = operation else { return false }
        case .layer(_, .scale):
            break
        default:
            return false
        }
        return operation.isValid
    }
}

nonisolated enum ScenePropertyVectorScriptOperation: Equatable, Sendable {
    case scalarSplat(ScenePropertyVectorScriptScalarInput)
    case components([ScenePropertyVectorScriptComponentBinding])

    fileprivate nonisolated var isValid: Bool {
        switch self {
        case let .scalarSplat(input):
            input.isValid
        case let .components(components):
            !components.isEmpty
                && components.count <= 3
                && Set(components.map(\.component)).count == components.count
                && components.allSatisfy { $0.input.isValid }
        }
    }
}

nonisolated struct ScenePropertyVectorScriptComponentBinding: Equatable, Sendable {
    let component: Int
    let input: ScenePropertyVectorScriptScalarInput
}

nonisolated struct ScenePropertyVectorScriptScalarInput: Equatable, Sendable {
    let fallback: Double
    let userPropertyKey: String?

    fileprivate nonisolated var isValid: Bool {
        fallback.isFinite
            && (userPropertyKey == nil
                || !(userPropertyKey?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty ?? true))
    }
}

private nonisolated extension SceneDynamicTarget {
    var propertyVectorSortKey: String {
        switch self {
        case let .layer(layerID, field):
            let fieldKey: String
            switch field {
            case .origin: fieldKey = "origin"
            case .scale: fieldKey = "scale"
            default: fieldKey = "~"
            }
            return String(format: "%020d:%@", layerID, fieldKey)
        default:
            return "~"
        }
    }
}
