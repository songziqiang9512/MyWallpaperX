import Foundation

struct SceneWaterRippleNormalPlan {
    let animationSpeed: Float
    let scale: Float
    let scrollSpeed: Float
    let direction: Float
    let ratio: Float
    let strength: Float
}

enum SceneWaterRippleRuntimePlanner {
    static func plan(
        for layer: SceneRenderDescriptor.Layer,
        hasNormalTexture: Bool
    ) -> SceneWaterRippleNormalPlan? {
        guard hasNormalTexture,
              let effect = layer.effects.first(where: {
                  $0.visible != false && $0.file.localizedLowercase.contains("waterripple")
              }), let pass = effect.passes.first,
              pass.textureSlots.indices.contains(2), pass.textureSlots[2] != nil,
              maskIsDisabled(in: pass),
              combo("SPECULAR", in: pass) != 1 else {
            return nil
        }
        let values = pass.constantShaderValues
        return SceneWaterRippleNormalPlan(
            animationSpeed: clampedFloat("animationspeed", in: values, default: 0.15, range: 0...0.5),
            scale: clampedFloat("scale", in: values, default: 1, range: 0...10),
            scrollSpeed: clampedFloat("scrollspeed", in: values, default: 0, range: 0...0.5),
            direction: float("scrolldirection", in: values, default: 0),
            ratio: clampedFloat("ratio", in: values, default: 1, range: 0...10),
            strength: clampedFloat("ripplestrength", in: values, default: 0.1, range: 0...1)
        )
    }

    private static func maskIsDisabled(
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> Bool {
        !SceneEffectMaskSemantics.declaresMask(in: pass)
    }

    private static func combo(
        _ name: String,
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> Int? {
        pass.combos.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private static func clampedFloat(
        _ key: String,
        in values: [String: SceneDocument.ShaderValue],
        default defaultValue: Float,
        range: ClosedRange<Float>
    ) -> Float {
        min(max(float(key, in: values, default: defaultValue), range.lowerBound), range.upperBound)
    }

    private static func float(
        _ key: String,
        in values: [String: SceneDocument.ShaderValue],
        default defaultValue: Float
    ) -> Float {
        guard let component = values.first(where: {
            $0.key.caseInsensitiveCompare(key) == .orderedSame
        })?.value.components?.first else {
            return defaultValue
        }
        return Float(component)
    }
}
