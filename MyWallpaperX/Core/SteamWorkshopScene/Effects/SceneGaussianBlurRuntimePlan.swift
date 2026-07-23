import Foundation

struct SceneGaussianBlurPlan {
    let horizontalStep: Float
    let verticalStep: Float
    let sampleResolutionScale: Float
    let isPrecise: Bool
}

enum SceneGaussianBlurRuntimePlanner {
    static func plan(for layer: SceneRenderDescriptor.Layer) -> SceneGaussianBlurPlan? {
        if let effect = layer.effects.first(where: {
            $0.visible != false && $0.file.localizedLowercase.contains("/blurprecise/")
        }) {
            return SceneGaussianBlurPlan(
                horizontalStep: preciseScale(in: effect.passes.first, component: 0),
                verticalStep: preciseScale(
                    in: effect.passes.dropFirst().first ?? effect.passes.first,
                    component: 1
                ),
                sampleResolutionScale: 1,
                isPrecise: true
            )
        }
        guard let effect = layer.effects.first(where: {
            $0.visible != false && $0.file.localizedLowercase.contains("/blur/effect.json")
        }) else {
            return nil
        }
        let verticalPass = effect.passes.count > 2
            ? effect.passes[2]
            : effect.passes.dropFirst().first
        return SceneGaussianBlurPlan(
            horizontalStep: coarseScale(in: effect.passes.dropFirst().first, component: 0),
            verticalStep: coarseScale(in: verticalPass, component: 1),
            sampleResolutionScale: 4,
            isPrecise: false
        )
    }

    private static func coarseScale(
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor?,
        component: Int
    ) -> Float {
        clampedScale(in: pass, component: component, fallback: 0.01, range: 0.01...2)
    }

    private static func preciseScale(
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor?,
        component: Int
    ) -> Float {
        clampedScale(in: pass, component: component, fallback: 1, range: 0.1...16)
    }

    private static func clampedScale(
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor?,
        component: Int,
        fallback: Float,
        range: ClosedRange<Float>
    ) -> Float {
        let components = pass?.constantShaderValues.first(where: {
            $0.key.localizedLowercase == "scale"
        })?.value.components ?? []
        let raw = components.indices.contains(component)
            ? Float(components[component])
            : Float(components.first ?? Double(fallback))
        return min(max(abs(raw), range.lowerBound), range.upperBound)
    }
}
