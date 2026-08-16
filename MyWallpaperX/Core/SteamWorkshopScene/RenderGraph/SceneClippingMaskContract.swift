import Foundation

nonisolated enum SceneClippingMaskProfile: String {
    case classic
    case weightedNeutral
}

nonisolated struct SceneClippingMaskDeclaration {
    let effectID: String
    let passIndex: Int
    let providerLayerID: Int
    let variant: SceneNamedTextureReference.Variant
    let blendMode: Int
    let profile: SceneClippingMaskProfile
}

enum SceneClippingMaskContract {
    nonisolated static func declaration(
        for effect: SceneRenderDescriptor.EffectDescriptor
    ) -> SceneClippingMaskDeclaration? {
        guard let declaration = dependencyDeclaration(for: effect),
              declaration.variant == .primary else {
            return nil
        }
        return declaration
    }

    nonisolated static func dependencyDeclaration(
        for effect: SceneRenderDescriptor.EffectDescriptor
    ) -> SceneClippingMaskDeclaration? {
        guard effect.visible != false,
              normalized(effect.file) == definitionPath,
              effect.passes.count == 1,
              let pass = effect.passes.first,
              pass.passIndex == 0,
              pass.userTextureInputs.allSatisfy({ $0 == nil }),
              let referencePath = pass.textureSlots[safe: 1] ?? nil,
              let reference = SceneNamedTextureReference.parse(referencePath),
              pass.texturePaths == [referencePath],
              pass.textureSlots.enumerated().allSatisfy({
                  $0.offset == 1 || $0.element == nil
              }),
              let instance = instanceProfile(pass) else {
            return nil
        }
        return SceneClippingMaskDeclaration(
            effectID: effect.id,
            passIndex: pass.passIndex,
            providerLayerID: reference.providerLayerID,
            variant: reference.variant,
            blendMode: instance.blendMode,
            profile: instance.profile
        )
    }

    private nonisolated static func instanceProfile(
        _ pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> (profile: SceneClippingMaskProfile, blendMode: Int)? {
        guard let combos = normalizedCombos(pass.combos) else { return nil }
        if pass.textureSlots.count == 2,
           combos == ["BLENDMODE": 5],
           pass.constantShaderValues.isEmpty {
            return (.classic, 5)
        }
        if pass.textureSlots.count == 3,
           combos.isEmpty,
           exactConstants(
               pass.constantShaderValues,
               expected: ["opacity": [1]]
           ) {
            return (.classic, 0)
        }
        if pass.textureSlots.count == 4,
           combos.isEmpty,
           exactConstants(
               pass.constantShaderValues,
               expected: [
                   "0opacity": [1],
                   "1texoffset": [0],
                   "color": [0, 0, 0],
                   "threshold": [1],
                   "weight": [1],
               ]
           ) {
            return (.weightedNeutral, 0)
        }
        return nil
    }

    private nonisolated static func normalizedCombos(
        _ combos: [String: Int]
    ) -> [String: Int]? {
        var result: [String: Int] = [:]
        for (key, value) in combos {
            guard result.updateValue(value, forKey: key.uppercased()) == nil else {
                return nil
            }
        }
        return result
    }

    private nonisolated static func exactConstants(
        _ values: [String: SceneDocument.ShaderValue],
        expected: [String: [Double]]
    ) -> Bool {
        var normalized: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in values {
            guard normalized.updateValue(value, forKey: key.lowercased()) == nil else {
                return false
            }
        }
        guard Set(normalized.keys) == Set(expected.keys) else { return false }
        return expected.allSatisfy { key, components in
            guard let value = normalized[key],
                  value.userBinding == nil,
                  let actual = value.components,
                  actual.count == components.count else {
                return false
            }
            return zip(actual, components).allSatisfy {
                $0.isFinite && abs($0 - $1) < 0.000_001
            }
        }
    }

    nonisolated static let definitionPath =
        "effects/workshop/2800594362/clipping_mask/effect.json"

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

private extension Array {
    nonisolated subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
