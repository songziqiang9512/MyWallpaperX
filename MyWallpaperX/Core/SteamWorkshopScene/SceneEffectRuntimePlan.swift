import Foundation
import simd

struct SceneLayerEffectInputs {
    let flags: SceneEffectFlags
    let params0: SIMD4<Float>
    let params1: SIMD4<Float>
    let params2: SIMD4<Float>
    let params3: SIMD4<Float>
}

struct SceneGaussianBlurPlan {
    let horizontalStep: Float
    let verticalStep: Float
}

struct SceneEffectRuntimePlan {
    let inputs: SceneLayerEffectInputs
    let gaussianBlur: SceneGaussianBlurPlan?
    let offscreenPassCount: Int
    let skipDirectRender: Bool
}

enum SceneEffectRuntimePlanner {
    static func plan(
        for layer: SceneRenderDescriptor.Layer,
        hasIrisMask: Bool,
        hasOpacityMask: Bool,
        hasWaterMask: Bool,
        hasFoliageMask: Bool
    ) -> SceneEffectRuntimePlan {
        SceneEffectRuntimePlan(
            inputs: effectInputs(
                for: layer,
                hasIrisMask: hasIrisMask,
                hasOpacityMask: hasOpacityMask,
                hasWaterMask: hasWaterMask,
                hasFoliageMask: hasFoliageMask
            ),
            gaussianBlur: gaussianBlurPlan(for: layer),
            offscreenPassCount: offscreenPassCount(for: layer),
            skipDirectRender: shouldSkipDirectRender(for: layer)
        )
    }

    static func offscreenPassCount(for layer: SceneRenderDescriptor.Layer) -> Int {
        layer.effects.reduce(into: 0) { total, effect in
            guard effect.visible != false else { return }
            let lower = effect.file.localizedLowercase
            guard shouldRouteEffectOffscreen(path: lower, passCount: effect.passes.count) else { return }
            total += max(1, effect.passes.count)
        }
    }

    static func runtimeSummary(for layer: SceneRenderDescriptor.Layer) -> String? {
        let passCount = offscreenPassCount(for: layer)
        guard passCount > 0 else { return nil }
        if gaussianBlurPlan(for: layer) != nil {
            return "effect runtime gaussian-blur; \(passCount) declared pass(es)"
        }
        return "offscreen route-only; \(passCount) declared pass(es)"
    }

    private static func gaussianBlurPlan(
        for layer: SceneRenderDescriptor.Layer
    ) -> SceneGaussianBlurPlan? {
        guard let effect = layer.effects.first(where: {
            $0.visible != false && $0.file.localizedLowercase.contains("/blur/effect.json")
        }) else {
            return nil
        }
        let horizontal = blurScale(in: effect.passes.dropFirst().first, component: 0)
        let verticalPass = effect.passes.count > 2 ? effect.passes[2] : effect.passes.dropFirst().first
        let vertical = blurScale(in: verticalPass, component: 1)
        return SceneGaussianBlurPlan(horizontalStep: horizontal, verticalStep: vertical)
    }

    private static func blurScale(
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor?,
        component: Int
    ) -> Float {
        let components = pass?.constantShaderValues.first(where: {
            $0.key.localizedLowercase == "scale"
        })?.value.components ?? []
        let raw = components.indices.contains(component)
            ? Float(components[component])
            : Float(components.first ?? 0.002)
        return min(max(abs(raw), 0.00025), 0.02)
    }

    private static func effectInputs(
        for layer: SceneRenderDescriptor.Layer,
        hasIrisMask: Bool,
        hasOpacityMask: Bool,
        hasWaterMask: Bool,
        hasFoliageMask: Bool
    ) -> SceneLayerEffectInputs {
        var flags: SceneEffectFlags = []
        var params0 = SIMD4<Float>(0, 0, 0, 0)
        var params1 = SIMD4<Float>(0, 0, 0, 0)
        var params2 = SIMD4<Float>(12, 1, 0.08, 0)
        let params3 = SIMD4<Float>(1, 0, 1, 0)
        for path in layer.effectFiles {
            let lower = path.localizedLowercase
            if lower.contains("foliagesway") { flags.insert(.foliagesway) }
            if lower.contains("waterwaves") || lower.contains("waterripple") {
                flags.insert(.waterwaves)
            }
            if lower.contains("cursorripple") { flags.insert(.cursorripple) }
            if lower.contains("chromaticaberration") { flags.insert(.chromaticaberration) }
        }

        for effect in layer.effects where effect.visible != false {
            let lower = effect.file.localizedLowercase
            guard let firstPass = effect.passes.first else { continue }
            if hasWaterMask && (lower.contains("waterwaves") || lower.contains("waterripple")) {
                flags.insert(.hasWaterMask)
            }
            if hasFoliageMask && (lower.contains("foliagesway") || lower.contains("cursorripple")) {
                flags.insert(.hasFoliageMask)
            }
            if hasIrisMask && lower.contains("iris") {
                flags.insert(.irisMask)
                let scale = floatComponents(forKey: "scale", in: firstPass.constantShaderValues)
                params0.x = scale.count > 0 ? scale[0] : 1
                params0.y = scale.count > 1 ? scale[1] : params0.x
                params0.z = firstFloat(forKeys: ["speed"], in: firstPass.constantShaderValues, default: 1)
                params0.w = firstFloat(forKeys: ["phase"], in: firstPass.constantShaderValues, default: 0)
                params1.x = firstFloat(forKeys: ["rough"], in: firstPass.constantShaderValues, default: 0.2)
                params1.y = firstFloat(forKeys: ["noiseamount"], in: firstPass.constantShaderValues, default: 0)
            }
            if hasOpacityMask && lower.contains("opacity") {
                flags.insert(.opacityMask)
                params1.z = firstFloat(forKeys: ["alpha"], in: firstPass.constantShaderValues, default: 1)
            }
            if lower.contains("waterwaves") || lower.contains("waterripple") {
                params2.x = firstFloat(forKeys: ["scale"], in: firstPass.constantShaderValues, default: params2.x)
                params2.y = firstFloat(
                    forKeys: ["speed", "animationspeed", "scrollspeed"],
                    in: firstPass.constantShaderValues,
                    default: params2.y
                )
                params2.z = firstFloat(
                    forKeys: ["strength", "ripplestrength"],
                    in: firstPass.constantShaderValues,
                    default: params2.z
                )
                params2.w = firstFloat(
                    forKeys: ["direction", "scrolldirection"],
                    in: firstPass.constantShaderValues,
                    default: params2.w
                )
            }
        }
        return SceneLayerEffectInputs(
            flags: flags,
            params0: params0,
            params1: params1,
            params2: params2,
            params3: params3
        )
    }

    private static func firstFloat(
        forKeys keys: [String],
        in values: [String: SceneDocument.ShaderValue],
        default defaultValue: Float
    ) -> Float {
        for key in keys {
            let lowerKey = key.localizedLowercase
            if let first = values.first(where: { $0.key.localizedLowercase == lowerKey })?.value.components?.first {
                return Float(first)
            }
        }
        return defaultValue
    }

    private static func floatComponents(
        forKey key: String,
        in values: [String: SceneDocument.ShaderValue]
    ) -> [Float] {
        let lowerKey = key.localizedLowercase
        return values.first(where: { $0.key.localizedLowercase == lowerKey })?.value.components?.map(Float.init) ?? []
    }

    private static func shouldSkipDirectRender(for layer: SceneRenderDescriptor.Layer) -> Bool {
        guard layer.name?.localizedLowercase.contains("ripple") == true else { return false }
        let effectSet = Set(layer.effectFiles.map(\.localizedLowercase))
        return effectSet.contains(where: { $0.contains("opacity") })
            && effectSet.contains(where: { $0.contains("perspective") })
            && effectSet.contains(where: { $0.contains("pulse") })
            && effectSet.contains(where: { $0.contains("waterflow") })
            && effectSet.contains(where: { $0.contains("waterripple") })
    }

    private static func shouldRouteEffectOffscreen(path: String, passCount: Int) -> Bool {
        if isInlineEffectPath(path) { return false }
        if passCount > 1 { return true }
        return isSinglePassOffscreenEffectPath(path)
    }

    private static func isInlineEffectPath(_ path: String) -> Bool {
        path.contains("foliagesway")
            || path.contains("waterwaves")
            || path.contains("waterripple")
            || path.contains("cursorripple")
            || path.contains("chromaticaberration")
            || path.contains("iris")
    }

    private static func isSinglePassOffscreenEffectPath(_ path: String) -> Bool {
        path.contains("blurprecise")
            || path.contains("/blur/")
            || path.contains("bloom")
            || path.contains("motionblur")
            || path.contains("godrays")
            || path.contains("glitter")
            || path.contains("opacity")
            || path.contains("shadow")
    }
}
