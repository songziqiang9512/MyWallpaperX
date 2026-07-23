import Foundation

struct SceneFoliageSwayPlan {
    let strength: Float
    let speed: Float
    let phase: Float
    let power: Float
    let noiseScale: Float
    let ratio: Float
    let direction: Float
}

enum SceneFoliageSwayRuntimePlanner {
    static func plan(
        for layer: SceneRenderDescriptor.Layer,
        hasMask: Bool
    ) -> SceneFoliageSwayPlan? {
        let effects = layer.effects.filter {
            $0.visible != false
                && $0.file.localizedLowercase == "effects/foliagesway/effect.json"
        }
        guard effects.count == 1,
              let effect = effects.first,
              let pass = effect.passes.first,
              combo("MODE", in: pass) ?? 0 == 0,
              !SceneEffectMaskSemantics.declaresMask(in: effect) || hasMask else {
            return nil
        }
        let values = pass.constantShaderValues
        return SceneFoliageSwayPlan(
            strength: clamped(value("strength", in: values, fallback: 0.4), 0...1),
            speed: clamped(value("speeduv", in: values, fallback: 5), 0.01...20),
            phase: clamped(value("phase", in: values, fallback: 0.5), 0...2),
            power: clamped(value("power", in: values, fallback: 1), 0.01...2),
            noiseScale: clamped(value("scale", in: values, fallback: 0.05), 0...1),
            ratio: clamped(value("ratio", in: values, fallback: 0.3), 0.01...10),
            direction: wrappedAngle(value("scrolldirection", in: values, fallback: 0))
        )
    }

    private static func value(
        _ key: String,
        in values: [String: SceneDocument.ShaderValue],
        fallback: Float
    ) -> Float {
        guard let raw = values.first(where: {
            $0.key.caseInsensitiveCompare(key) == .orderedSame
        })?.value.components?.first,
        raw.isFinite else {
            return fallback
        }
        return Float(raw)
    }

    private static func combo(
        _ key: String,
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> Int? {
        pass.combos.first {
            $0.key.caseInsensitiveCompare(key) == .orderedSame
        }?.value
    }

    private static func clamped(
        _ value: Float,
        _ range: ClosedRange<Float>
    ) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func wrappedAngle(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return value.truncatingRemainder(dividingBy: 2 * .pi)
    }
}
