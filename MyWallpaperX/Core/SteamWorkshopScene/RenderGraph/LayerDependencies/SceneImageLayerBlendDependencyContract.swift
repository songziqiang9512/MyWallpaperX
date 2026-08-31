import Foundation

nonisolated struct SceneImageLayerBlendDependencyDeclaration: Hashable {
    let effectID: String
    let passIndex: Int
    let providerLayerID: Int
    let slotIndex: Int
    let blendMode: Int
    let requiresResolvedMaterialProgram: Bool
}

/// The smallest stock Blend form whose external image-layer input is exact:
/// one primary named target with no mask, user/system override, or secondary
/// texture. Authored blending, strength, alpha and UV transform stay inside
/// the resolved MaterialProgram; this contract only grants the referenced
/// texture a named-target binding.
nonisolated enum SceneImageLayerBlendDependencyContract {
    private struct ConstantContract {
        let requiresResolvedMaterialProgram: Bool
    }

    private static let maximumBlendMode = 32

    static func supports(blendMode: Int) -> Bool {
        (0...maximumBlendMode).contains(blendMode)
    }

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
              let combos = normalizedCombos(pass.combos),
              let constantContract = supportedConstants(
                  pass.constantShaderValues,
                  transformUV: combos["TRANSFORMUV", default: 0] == 1
              ) else {
            return nil
        }
        let declaration = SceneImageLayerBlendDependencyDeclaration(
            effectID: effect.id,
            passIndex: 0,
            providerLayerID: reference.providerLayerID,
            slotIndex: 1,
            blendMode: combos["BLENDMODE", default: 0],
            requiresResolvedMaterialProgram:
                constantContract.requiresResolvedMaterialProgram
                    || combos["BLENDMODE", default: 0] != 0
                    || combos["TRANSFORMUV", default: 0] == 1
                    || combos["WRITEALPHA", default: 0] != 0
        )
        return declaration
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
        let transformUV = result["TRANSFORMUV", default: 0]
        let transformRepeat = result["TRANSFORMREPEAT", default: 0]
        guard supports(blendMode: result["BLENDMODE", default: 0]),
              (0...1).contains(transformUV),
              (0...2).contains(transformRepeat),
              transformUV == 1 || transformRepeat == 0,
              (0...1).contains(result["WRITEALPHA", default: 0]),
              result["NUMBLENDTEXTURES", default: 1] == 1,
              result["OPACITYMASK", default: 0] == 0 else {
            return nil
        }
        return result
    }

    private static func supportedConstants(
        _ constants: [String: SceneDocument.ShaderValue],
        transformUV: Bool
    ) -> ConstantContract? {
        var values: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in constants {
            guard values.updateValue(value, forKey: key.lowercased()) == nil else {
                return nil
            }
        }
        let allowed = Set(["multiply", "alpha", "blendangle", "blendoffset", "blendscale"])
        guard values.keys.allSatisfy(allowed.contains),
              let multiply = scalar(values["multiply"], default: 1),
              let alpha = scalar(values["alpha"], default: 1),
              let angle = scalar(values["blendangle"], default: 0),
              let scale = scalar(values["blendscale"], default: 1),
              multiply.isFinite,
              alpha.isFinite,
              angle.isFinite,
              scale.isFinite,
              scale > 0 else {
            return nil
        }
        let offset = values["blendoffset"]
        let offsetComponents = offset?.components ?? [0, 0]
        guard offset?.userBinding == nil,
              offsetComponents.count == 2,
              offsetComponents.allSatisfy(\.isFinite) else {
            return nil
        }
        guard transformUV
            || (angle == 0 && scale == 1 && offsetComponents == [0, 0]) else {
            return nil
        }
        return ConstantContract(
            requiresResolvedMaterialProgram: multiply != 1 || alpha != 1
        )
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
