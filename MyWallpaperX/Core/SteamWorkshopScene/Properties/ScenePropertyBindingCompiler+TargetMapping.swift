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
        case let .shaderValue(layerID, effectIndex, passIndex, name, effectPath)
            where normalized(effectPath) == "effects/tint/effect.json"
                && passIndex == 0 && name.lowercased() == "alpha":
            effectConstant(
                layerID: layerID,
                effectIndex: effectIndex,
                passIndex: passIndex,
                name: "alpha"
            )
        case let .shaderValue(layerID, effectIndex, passIndex, name, effectPath)
            where normalized(effectPath) == "effects/tint/effect.json"
                && passIndex == 0 && name.lowercased() == "color":
            (
                .effectConstant(
                    layerID: layerID,
                    effectIndex: effectIndex,
                    passIndex: passIndex,
                    name: "color"
                ),
                .vector3,
                .color
            )
        case let .shaderValue(layerID, effectIndex, passIndex, name, effectPath)
            where isSimpleAudioBars(effectPath)
                && passIndex == 0 && name.lowercased() == "bar color":
            (
                .effectConstant(
                    layerID: layerID,
                    effectIndex: effectIndex,
                    passIndex: passIndex,
                    name: "bar color"
                ),
                .vector3,
                .color
            )
        case let .shaderValue(layerID, effectIndex, passIndex, name, effectPath)
            where isSimpleAudioBars(effectPath)
                && passIndex == 0
                && name.lowercased() == "ui_editor_properties_opacity":
            effectConstant(
                layerID: layerID,
                effectIndex: effectIndex,
                passIndex: passIndex,
                name: "ui_editor_properties_opacity"
            )
        default:
            nil
        }
    }

    private nonisolated static func normalized(_ path: String?) -> String? {
        path?.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static func isSimpleAudioBars(_ path: String?) -> Bool {
        guard let path = normalized(path),
              path.hasPrefix("effects/") else {
            return false
        }
        let tail = "workshop/2084198056/simple_audio_bars/effect.json"
        let relative = String(path.dropFirst("effects/".count))
        guard relative.hasSuffix(tail) else { return false }
        let namespace = String(relative.dropLast(tail.count))
        if namespace.isEmpty { return true }
        let components = namespace.split(
            separator: "/",
            omittingEmptySubsequences: true
        )
        return components.count == 2
            && components[0] == "workshop"
            && !components[1].isEmpty
            && components[1].allSatisfy(\.isNumber)
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

    private nonisolated static func particleScalar(
        _ layerID: Int,
        _ field: SceneDynamicParticleField
    ) -> (SceneDynamicTarget, SceneDynamicValueType, SceneUserPropertyKind) {
        (.particle(layerID: layerID, field: field), .scalar, .slider)
    }
}
