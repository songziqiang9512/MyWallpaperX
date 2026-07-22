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
    let usesPixelSteps: Bool
}

struct SceneBloomPlan {
    let threshold: Float
    let gamma: Float
    let radius: Float
    let intensity: Float
    let tint: SIMD3<Float>
}

struct SceneEffectRuntimePlan {
    let inputs: SceneLayerEffectInputs
    let gaussianBlur: SceneGaussianBlurPlan?
    let bloom: SceneBloomPlan?
    let waterRippleNormal: SceneWaterRippleNormalPlan?
    let perspectiveOpacity: ScenePerspectiveOpacityPlan?
    let offscreenPassCount: Int
    let skipsUnsupportedComposite: Bool
}

enum SceneEffectRuntimePlanner {
    static func plan(
        for layer: SceneRenderDescriptor.Layer,
        hasIrisMask: Bool,
        hasOpacityMask: Bool,
        hasWaterMask: Bool,
        hasFoliageMask: Bool,
        hasWaterRippleNormal: Bool
    ) -> SceneEffectRuntimePlan {
        let waterRippleNormal = SceneWaterRippleRuntimePlanner.plan(
            for: layer,
            hasNormalTexture: hasWaterRippleNormal
        )
        let perspectiveOpacity = perspectiveOpacityPlan(
            for: layer,
            hasOpacityMask: hasOpacityMask
        )
        return SceneEffectRuntimePlan(
            inputs: effectInputs(
                for: layer,
                hasIrisMask: hasIrisMask,
                hasOpacityMask: hasOpacityMask && perspectiveOpacity == nil,
                hasWaterMask: hasWaterMask,
                hasFoliageMask: hasFoliageMask,
                usesNormalWaterRipple: waterRippleNormal != nil
            ),
            gaussianBlur: gaussianBlurPlan(for: layer),
            bloom: bloomPlan(for: layer),
            waterRippleNormal: waterRippleNormal,
            perspectiveOpacity: perspectiveOpacity,
            offscreenPassCount: max(offscreenPassCount(for: layer), waterRippleNormal == nil ? 0 : 1),
            skipsUnsupportedComposite: skipsUnsupportedComposite(for: layer) && perspectiveOpacity == nil
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

    static func runtimeSummary(
        for layer: SceneRenderDescriptor.Layer,
        hasWaterRippleNormal: Bool = false,
        hasOpacityMask: Bool = false
    ) -> String? {
        let waterRippleNormal = SceneWaterRippleRuntimePlanner.plan(
            for: layer,
            hasNormalTexture: hasWaterRippleNormal
        )
        let hasDeclaredWaterRipple = layer.effects.contains {
            $0.visible != false && $0.file.localizedLowercase.contains("waterripple")
        }
        let legacyRipple = hasDeclaredWaterRipple && waterRippleNormal == nil
            ? "effect runtime waterripple-legacy; "
            : ""
        if perspectiveOpacityPlan(for: layer, hasOpacityMask: hasOpacityMask) != nil {
            let ripple = waterRippleNormal == nil ? "" : "effect runtime waterripple-normal; "
            return "\(ripple)\(legacyRipple)effect runtime perspective-opacity; layer color blend mode=\(layer.colorBlendMode ?? 0)"
        }
        if skipsUnsupportedComposite(for: layer) {
            return "unsupported composite skipped; waterflow+waterripple+perspective+opacity"
        }
        if waterRippleNormal != nil {
            return "effect runtime waterripple-normal; 1 declared pass(es)"
        }
        if legacyRipple.isEmpty == false {
            return "\(legacyRipple)inline approximation"
        }
        let passCount = offscreenPassCount(for: layer)
        guard passCount > 0 else { return nil }
        if gaussianBlurPlan(for: layer)?.usesPixelSteps == true {
            return "effect runtime gaussian-blur-precise; \(passCount) declared pass(es)"
        }
        if gaussianBlurPlan(for: layer) != nil {
            return "effect runtime gaussian-blur; \(passCount) declared pass(es)"
        }
        if bloomPlan(for: layer) != nil {
            return "effect runtime bloom; \(passCount) declared pass(es)"
        }
        return "offscreen route-only; \(passCount) declared pass(es)"
    }

    private static func gaussianBlurPlan(
        for layer: SceneRenderDescriptor.Layer
    ) -> SceneGaussianBlurPlan? {
        if let effect = layer.effects.first(where: {
            $0.visible != false && $0.file.localizedLowercase.contains("/blurprecise/")
        }) {
            let horizontal = preciseBlurScale(in: effect.passes.first, component: 0)
            let vertical = preciseBlurScale(
                in: effect.passes.dropFirst().first ?? effect.passes.first,
                component: 1
            )
            return SceneGaussianBlurPlan(
                horizontalStep: horizontal,
                verticalStep: vertical,
                usesPixelSteps: true
            )
        }
        guard let effect = layer.effects.first(where: {
            $0.visible != false && $0.file.localizedLowercase.contains("/blur/effect.json")
        }) else {
            return nil
        }
        let horizontal = blurScale(in: effect.passes.dropFirst().first, component: 0)
        let verticalPass = effect.passes.count > 2 ? effect.passes[2] : effect.passes.dropFirst().first
        let vertical = blurScale(in: verticalPass, component: 1)
        return SceneGaussianBlurPlan(
            horizontalStep: horizontal,
            verticalStep: vertical,
            usesPixelSteps: false
        )
    }

    private static func bloomPlan(for layer: SceneRenderDescriptor.Layer) -> SceneBloomPlan? {
        guard let effect = layer.effects.first(where: {
            $0.visible != false && $0.file.localizedLowercase.contains("/bloom/")
        }), let firstPass = effect.passes.first else {
            return nil
        }
        let values = firstPass.constantShaderValues
        let opacity = firstFloat(forKeys: ["opacity"], in: values, default: 1)
        let strength = firstFloat(forKeys: ["strength"], in: values, default: 1)
        let tintValues = effect.passes.reversed().lazy
            .map { floatComponents(forKey: "tint", in: $0.constantShaderValues) }
            .first(where: { !$0.isEmpty }) ?? [1, 1, 1]
        return SceneBloomPlan(
            threshold: min(max(firstFloat(forKeys: ["threshold"], in: values, default: 0.5), 0), 0.999),
            gamma: min(max(firstFloat(forKeys: ["gamma"], in: values, default: 1), 0.1), 4),
            radius: min(max(firstFloat(forKeys: ["radius"], in: values, default: 2), 0.5), 12),
            intensity: min(max(opacity * strength, 0), 2),
            tint: SIMD3(tintValues, fill: 1)
        )
    }

    private static func perspectiveOpacityPlan(
        for layer: SceneRenderDescriptor.Layer,
        hasOpacityMask: Bool
    ) -> ScenePerspectiveOpacityPlan? {
        guard hasOpacityMask else { return nil }
        let visibleEffects = layer.effects.filter { $0.visible != false }
        guard let perspectiveIndex = visibleEffects.firstIndex(where: {
            $0.file.localizedLowercase.contains("perspective")
        }), let opacityIndex = visibleEffects.firstIndex(where: {
            $0.file.localizedLowercase.contains("opacity")
        }), perspectiveIndex < opacityIndex,
        let perspectivePass = visibleEffects[perspectiveIndex].passes.first,
        let opacityPass = visibleEffects[opacityIndex].passes.first else {
            return nil
        }

        let values = perspectivePass.constantShaderValues
        let edges = SIMD4<Float>(
            clampedPerspectiveEdge(firstFloat(forKeys: ["top"], in: values, default: 0)),
            clampedPerspectiveEdge(firstFloat(forKeys: ["bottom"], in: values, default: 0)),
            clampedPerspectiveEdge(firstFloat(forKeys: ["left"], in: values, default: 0)),
            clampedPerspectiveEdge(firstFloat(forKeys: ["right"], in: values, default: 0))
        )
        guard let weights = perspectiveWeights(edges: edges) else { return nil }
        let opacity = min(max(
            firstFloat(forKeys: ["alpha"], in: opacityPass.constantShaderValues, default: 1),
            0
        ), 1)
        return ScenePerspectiveOpacityPlan(edges: edges, weights: weights, opacity: opacity)
    }

    private static func clampedPerspectiveEdge(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, -0.49), 0.49)
    }

    private static func perspectiveWeights(edges: SIMD4<Float>) -> SIMD4<Float>? {
        let top = edges.x
        let bottom = edges.y
        let left = edges.z
        let right = edges.w
        let p3 = SIMD2(top, left)
        let p2 = SIMD2(1 - top, right)
        let p1 = SIMD2(1 - bottom, 1 - right)
        let p0 = SIMD2(bottom, 1 - left)
        let a = p2 - p0
        let b = p3 - p1
        let c = p0 - p1
        let cross = a.x * b.y - a.y * b.x
        guard cross.isFinite, abs(cross) >= 0.00001 else { return nil }
        let s = (a.x * c.y - a.y * c.x) / cross
        let t = (b.x * c.y - b.y * c.x) / cross
        guard s.isFinite, t.isFinite,
              s > 0.00001, s < 0.99999,
              t > 0.00001, t < 0.99999 else {
            return nil
        }
        return SIMD4(1 / (1 - t), 1 / (1 - s), 1 / t, 1 / s)
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

    private static func preciseBlurScale(
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor?,
        component: Int
    ) -> Float {
        let components = pass?.constantShaderValues.first(where: {
            $0.key.localizedLowercase == "scale"
        })?.value.components ?? []
        let raw = components.indices.contains(component)
            ? Float(components[component])
            : Float(components.first ?? 1)
        return min(max(abs(raw), 0.1), 16)
    }

    private static func effectInputs(
        for layer: SceneRenderDescriptor.Layer,
        hasIrisMask: Bool,
        hasOpacityMask: Bool,
        hasWaterMask: Bool,
        hasFoliageMask: Bool,
        usesNormalWaterRipple: Bool
    ) -> SceneLayerEffectInputs {
        var flags = SceneInlineEffectRuntime.flags(
            for: layer,
            usesNormalWaterRipple: usesNormalWaterRipple
        )
        var params0 = SIMD4<Float>(0, 0, 0, 0)
        var params1 = SIMD4<Float>(0, 0, 0, 0)
        var params2 = SIMD4<Float>(12, 1, 0.08, 0)
        let params3 = SIMD4<Float>(1, 0, 1, 0)
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

    private static func skipsUnsupportedComposite(for layer: SceneRenderDescriptor.Layer) -> Bool {
        let visiblePaths = layer.effects.compactMap { effect -> String? in
            guard effect.visible != false else { return nil }
            return effect.file.localizedLowercase
        }
        return ["waterflow", "waterripple", "perspective", "opacity"].allSatisfy { fragment in
            visiblePaths.contains(where: { $0.contains(fragment) })
        }
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
