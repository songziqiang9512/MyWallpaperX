import Foundation
import simd

nonisolated struct SceneGradientColorPlan {
    let color1: SIMD3<Float>
    let color2: SIMD3<Float>
    let amount: Float
    let hueSpeed: Float
    let oscillate: Float
    let opacity: Float
    let axis: Int
}

nonisolated enum SceneGradientColorRuntimePlanner {
    nonisolated static func plan(
        for layer: SceneRenderDescriptor.Layer
    ) -> SceneGradientColorPlan? {
        let visibleEffects = layer.effects.filter { $0.visible != false }
        guard visibleEffects.count == 1 || visibleEffects.count == 2,
              let first = visibleEffects.first,
              let plan = plan(for: first) else {
            return nil
        }
        if visibleEffects.count == 2 {
            guard visibleEffects[1].file.localizedLowercase.contains("clipping_mask") else {
                return nil
            }
        }
        return plan
    }

    nonisolated static func plan(
        for effect: SceneRenderDescriptor.EffectDescriptor
    ) -> SceneGradientColorPlan? {
        let path = effect.file.localizedLowercase
        guard path.hasSuffix("/gradient_color/effect.json"),
              effect.passes.count == 1,
              let pass = effect.passes.first,
              pass.texturePaths.isEmpty,
              pass.textureSlots.allSatisfy({ $0 == nil }),
              pass.userTextureInputs.allSatisfy({ $0 == nil }),
              pass.combos.keys.allSatisfy({
                  $0.caseInsensitiveCompare("AXIS") == .orderedSame
                      || $0.caseInsensitiveCompare("BLENDMODE") == .orderedSame
              }),
              combo("BLENDMODE", in: pass) == 0 else {
            return nil
        }
        let axis = combo("AXIS", in: pass) ?? 0
        let expectedKeys = Set([
            "amount", "color 1", "color 2", "hue speed", "opacity", "oscillate",
        ])
        guard axis == 0 || axis == 1,
              Set(pass.constantShaderValues.keys.map { $0.localizedLowercase }) == expectedKeys,
              let color1 = vector("Color 1", in: pass, count: 3, range: 0...1),
              let color2 = vector("Color 2", in: pass, count: 3, range: 0...1),
              let amount = scalar("Amount", in: pass, range: 0...100),
              let hueSpeed = scalar("Hue Speed", in: pass, range: 0...1),
              let oscillate = scalar("Oscillate", in: pass, range: 0...1),
              let opacity = scalar("Opacity", in: pass, range: 0...1) else {
            return nil
        }
        return SceneGradientColorPlan(
            color1: SIMD3(color1[0], color1[1], color1[2]),
            color2: SIMD3(color2[0], color2[1], color2[2]),
            amount: amount,
            hueSpeed: hueSpeed,
            oscillate: oscillate,
            opacity: opacity,
            axis: axis
        )
    }

    private nonisolated static func scalar(
        _ key: String,
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor,
        range: ClosedRange<Float>
    ) -> Float? {
        guard let values = components(key, in: pass), values.count == 1,
              range.contains(values[0]) else {
            return nil
        }
        return values[0]
    }

    private nonisolated static func vector(
        _ key: String,
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor,
        count: Int,
        range: ClosedRange<Float>
    ) -> [Float]? {
        guard let values = components(key, in: pass), values.count == count,
              values.allSatisfy(range.contains) else {
            return nil
        }
        return values
    }

    private nonisolated static func components(
        _ key: String,
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> [Float]? {
        guard let value = pass.constantShaderValues.first(where: {
            $0.key.caseInsensitiveCompare(key) == .orderedSame
        })?.value, let components = value.components?.map(Float.init),
        components.allSatisfy(\.isFinite) else {
            return nil
        }
        return components
    }

    private nonisolated static func combo(
        _ key: String,
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> Int? {
        pass.combos.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }
}
