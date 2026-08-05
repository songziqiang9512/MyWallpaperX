import Foundation

extension ScenePropertyBindingCompiler {
    nonisolated static func map(
        _ binding: SceneUserPropertyBinding,
        propertyKind: SceneUserPropertyKind?
    ) -> (
        target: SceneDynamicTarget,
        valueType: SceneDynamicValueType,
        propertyKind: SceneUserPropertyKind
    )? {
        guard case let .shaderValue(
            layerID, effectIndex, passIndex, name, _
        ) = binding.target else {
            return map(binding.target)
        }
        guard layerID >= 0, effectIndex >= 0, passIndex >= 0,
              !name.isEmpty,
              name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              let shape = shaderValueShape(
                  fallback: binding.fallbackValue,
                  propertyKind: propertyKind
              ) else { return nil }
        return (
            .effectConstant(
                layerID: layerID,
                effectIndex: effectIndex,
                passIndex: passIndex,
                name: name
            ),
            shape.valueType,
            shape.propertyKind
        )
    }

    nonisolated static func map(
        _ target: SceneUserPropertyBindingTarget
    ) -> (
        target: SceneDynamicTarget,
        valueType: SceneDynamicValueType,
        propertyKind: SceneUserPropertyKind
    )? {
        switch target {
        case let .layerAlpha(layerID):
            (.layer(layerID: layerID, field: .alpha), .scalar, .slider)
        case let .puppetAnimationVisibility(layerID, animationLayerID):
            (
                ScenePuppetAnimationPropertyTarget.visibility(
                    layerID: layerID,
                    animationLayerID: animationLayerID
                ),
                .bool,
                .bool
            )
        case let .layerColor(layerID):
            (.layer(layerID: layerID, field: .color), .vector3, .color)
        case let .text(layerID, field):
            switch field {
            case .content:
                (.text(layerID: layerID, field: .content), .string, .textInput)
            case .pointSize:
                (.text(layerID: layerID, field: .pointSize), .scalar, .slider)
            case .color:
                (.text(layerID: layerID, field: .color), .vector3, .color)
            }
        case let .particle(layerID, field):
            switch field {
            case .alpha: particleScalar(layerID, .alpha)
            case .size: particleScalar(layerID, .size)
            case .lifetime: particleScalar(layerID, .lifetime)
            case .rate: particleScalar(layerID, .rate)
            case .speed: particleScalar(layerID, .speed)
            case .count: particleScalar(layerID, .count)
            case .brightness: particleScalar(layerID, .brightness)
            case .normalizedColor:
                (.particle(layerID: layerID, field: .normalizedColor), .vector3, .color)
            case .color: nil
            }
        case let .effectVisibility(layerID, effectIndex, effectPath)
            where normalized(effectPath) == "effects/xray/effect.json":
            (
                .effectVisibility(layerID: layerID, effectIndex: effectIndex),
                .bool,
                .bool
            )
        default:
            nil
        }
    }

    private nonisolated static func normalized(_ path: String?) -> String? {
        path?.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static func shaderValueShape(
        fallback: SceneUserPropertyValue?,
        propertyKind: SceneUserPropertyKind?
    ) -> (
        valueType: SceneDynamicValueType,
        propertyKind: SceneUserPropertyKind
    )? {
        switch (propertyKind, fallback) {
        case (.slider, _):
            (.scalar, .slider)
        case (.color, _):
            (.vector3, .color)
        case (nil, .number):
            (.scalar, .slider)
        case (nil, .string):
            (.vector3, .color)
        default:
            nil
        }
    }

    private nonisolated static func particleScalar(
        _ layerID: Int,
        _ field: SceneDynamicParticleField
    ) -> (SceneDynamicTarget, SceneDynamicValueType, SceneUserPropertyKind) {
        (.particle(layerID: layerID, field: field), .scalar, .slider)
    }
}
