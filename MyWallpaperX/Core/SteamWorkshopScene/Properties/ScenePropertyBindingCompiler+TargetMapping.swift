import Foundation

extension ScenePropertyBindingCompiler {
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
        case let .shaderValue(layerID, effectIndex, passIndex, name, effectPath)
            where normalized(effectPath) == "effects/localcontrast/effect.json"
                && passIndex == 3 && name.lowercased() == "strength":
            effectConstant(
                layerID: layerID,
                effectIndex: effectIndex,
                passIndex: passIndex,
                name: "strength"
            )
        case let .shaderValue(layerID, effectIndex, passIndex, name, effectPath)
            where normalized(effectPath) == "effects/opacity/effect.json"
                && passIndex == 0 && name.lowercased() == "alpha":
            effectConstant(
                layerID: layerID,
                effectIndex: effectIndex,
                passIndex: passIndex,
                name: "alpha"
            )
        case let .effectVisibility(layerID, effectIndex, effectPath)
            where normalized(effectPath) == "effects/xray/effect.json":
            (
                .effectVisibility(layerID: layerID, effectIndex: effectIndex),
                .bool,
                .bool
            )
        case let .shaderValue(layerID, effectIndex, passIndex, name, effectPath)
            where normalized(effectPath) == "effects/xray/effect.json"
                && passIndex == 0
                && (name.lowercased() == "size" || name.lowercased() == "multiply"):
            effectConstant(
                layerID: layerID,
                effectIndex: effectIndex,
                passIndex: passIndex,
                name: name.lowercased()
            )
        default:
            nil
        }
    }

    private nonisolated static func normalized(_ path: String?) -> String? {
        path?.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static func effectConstant(
        layerID: Int,
        effectIndex: Int,
        passIndex: Int,
        name: String
    ) -> (SceneDynamicTarget, SceneDynamicValueType, SceneUserPropertyKind) {
        (
            .effectConstant(
                layerID: layerID,
                effectIndex: effectIndex,
                passIndex: passIndex,
                name: name
            ),
            .scalar,
            .slider
        )
    }
}
