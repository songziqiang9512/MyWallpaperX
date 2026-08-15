import Foundation

nonisolated struct SceneImageLayerBlendDependencyDeclaration: Hashable {
    let effectID: String
    let passIndex: Int
    let providerLayerID: Int
    let slotIndex: Int
    let blendMode: Int
}

/// The smallest stock Blend form whose external image-layer input is exact:
/// one primary named target, normal mode, full strength, no transform, mask,
/// user/system override, or secondary texture.
nonisolated enum SceneImageLayerBlendDependencyContract {
    static func declaration(
        for effect: SceneRenderDescriptor.EffectDescriptor
    ) -> SceneImageLayerBlendDependencyDeclaration? {
        guard effect.visible != false,
              normalized(effect.file) == "effects/blend/effect.json",
              effect.passes.count == 1,
              let pass = effect.passes.first,
              pass.passIndex == 0,
              pass.textureSlots.count == 2,
              pass.textureSlots[0] == nil,
              let path = pass.textureSlots[1],
              pass.texturePaths == [path],
              pass.userTextureInputs.isEmpty,
              let reference = SceneNamedTextureReference.parse(path),
              reference.variant == .primary,
              normalizedCombos(pass.combos) != nil,
              fullStrength(pass.constantShaderValues) else {
            return nil
        }
        return .init(
            effectID: effect.id,
            passIndex: 0,
            providerLayerID: reference.providerLayerID,
            slotIndex: 1,
            blendMode: 0
        )
    }

    private static func normalizedCombos(_ authored: [String: Int]) -> [String: Int]? {
        let allowed = Set([
            "BLENDMODE", "TRANSFORMUV", "TRANSFORMREPEAT", "WRITEALPHA",
            "NUMBLENDTEXTURES", "OPACITYMASK",
        ])
        var result: [String: Int] = [:]
        for (key, value) in authored {
            let normalizedKey = key.uppercased()
            guard allowed.contains(normalizedKey),
                  result.updateValue(value, forKey: normalizedKey) == nil else {
                return nil
            }
        }
        guard result["BLENDMODE"] == 0,
              result["TRANSFORMUV", default: 0] == 0,
              result["TRANSFORMREPEAT", default: 0] == 0,
              (0...1).contains(result["WRITEALPHA", default: 0]),
              result["NUMBLENDTEXTURES", default: 1] == 1,
              result["OPACITYMASK", default: 0] == 0 else {
            return nil
        }
        return result
    }

    private static func fullStrength(
        _ constants: [String: SceneDocument.ShaderValue]
    ) -> Bool {
        var values: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in constants {
            guard values.updateValue(value, forKey: key.lowercased()) == nil else {
                return false
            }
        }
        let allowed = Set(["multiply", "alpha", "blendangle", "blendoffset", "blendscale"])
        guard values.keys.allSatisfy(allowed.contains),
              scalar(values["multiply"], default: 1) == 1,
              scalar(values["alpha"], default: 1) == 1,
              scalar(values["blendangle"], default: 0) == 0,
              scalar(values["blendscale"], default: 1) == 1 else {
            return false
        }
        guard let offset = values["blendoffset"] else { return true }
        return offset.userBinding == nil
            && offset.components == [0, 0]
    }

    private static func scalar(
        _ value: SceneDocument.ShaderValue?,
        default fallback: Double
    ) -> Double? {
        guard let value else { return fallback }
        guard value.userBinding == nil,
              let components = value.components,
              components.count == 1,
              let component = components.first,
              component.isFinite else {
            return nil
        }
        return component
    }

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}
