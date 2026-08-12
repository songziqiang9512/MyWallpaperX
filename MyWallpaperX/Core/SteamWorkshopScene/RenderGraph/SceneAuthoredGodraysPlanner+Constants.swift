import Foundation
import simd

/// definition、material、combo 与常量的逐项校验。stock 与 v1 profile 分别锁定
/// 自己的 CASTER、RT format、定义元数据与 gaussian 核；未知组合继续整条拒绝。
extension SceneAuthoredGodraysPlanner {
    nonisolated struct DownsampleConstants {
        let threshold: Float
        let noiseAmount: Float
        let noiseScale: Float
        let noiseSpeed: Float
        let noiseSmoothness: Float
    }

    nonisolated struct CastConstants {
        let center: SIMD2<Float>
        let direction: Float?
        let color: SIMD3<Float>
        let length: Float
        let intensity: Float
    }

    nonisolated static func validDefinition(
        in descriptor: SceneRenderDescriptor,
        path: String,
        profile: SceneGodraysShaderProfile
    ) -> Bool {
        let matches = descriptor.effectDefinitions.filter {
            normalized($0.relativePath) == normalized(path)
        }
        guard matches.count == 1, let definition = matches.first,
              definition.version == 1,
              definition.name == "ui_editor_effect_godrays_title",
              definition.description == "ui_editor_effect_godrays_description",
              definition.group == "enhance",
              definition.previewPath == "preview/project.json",
              definition.editable == nil,
              definition.framebuffers.count == 2,
              definition.functions == nil,
              definition.gizmos == nil,
              definition.extraFields.isEmpty,
              definition.unknownFieldPaths.isEmpty,
              definition.passes.count == 5
        else {
            return false
        }
        switch profile {
        case .stock2842:
            return definition.replacementKey == "godrays"
                && definition.performance == "expensive"
        case .directionalV1:
            return definition.replacementKey == nil && definition.performance == nil
        }
    }

    nonisolated static func validMaterial(
        _ material: SceneResolvedMaterialNode,
        ordinal: Int,
        bindings: [(Int, String, Graph.TextureIdentity)],
        profile: SceneGodraysShaderProfile
    ) -> Bool {
        let shaders = [
            "effects/godrays_downsample2",
            "effects/godrays_cast",
            "effects/godrays_gaussian",
            "effects/godrays_gaussian",
            "effects/godrays_combine",
        ]
        guard normalized(material.shaderPath) == shaders[ordinal],
              material.renderState.blending?.lowercased() == "normal",
              material.renderState.depthTest?.lowercased() == "disabled",
              material.renderState.depthWrite?.lowercased() == "disabled",
              material.renderState.cullMode?.lowercased() == "nocull",
              validCombos(material.combos, ordinal: ordinal, profile: profile)
        else {
            return false
        }
        let expectedBySlot = Dictionary(uniqueKeysWithValues: bindings.map { ($0.0, $0.2) })
        for index in material.textureSlots.indices {
            if let expected = expectedBySlot[index] {
                if profile == .directionalV1, ordinal == 4, index == 1 {
                    let capture = "_rt_imagelayercomposite_\(expected.layerID)_a"
                    guard let slot = material.textureSlots[index],
                          slot.candidates.count == 2,
                          slot.candidates[0].provenance == .instance,
                          case let .asset(path) = slot.candidates[0].source,
                          normalized(path) == capture,
                          slot.provenance == .explicitBinding,
                          case let .graph(actual) = slot.source,
                          actual == expected
                    else {
                        return false
                    }
                    continue
                }
                guard let slot = material.textureSlots[index],
                      slot.candidates.count == 1,
                      slot.provenance == .explicitBinding,
                      case let .graph(actual) = slot.source,
                      actual == expected
                else {
                    return false
                }
                continue
            }
            guard let slot = material.textureSlots[index] else { continue }
            // pass 0 的 slot 1（遮罩）与 slot 2（noise）允许实例资产；其余槽必须为空。
            guard ordinal == 0, [1, 2].contains(index),
                  slot.provenance == .instance,
                  case let .asset(assetPath) = slot.source
            else {
                return false
            }
            if index == 2 {
                guard normalized(assetPath) == noiseAssetPath else { return false }
            } else {
                guard !assetPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    return false
                }
            }
        }
        return true
    }

    /// 官方 combos：downsample2 `NOISE` 缺省 1（0 无语料且改变 alpha 语义，拒绝）；
    /// cast `CASTER` 缺省 0（Radial），`SAMPLES` 0/1；gaussian `KERNEL` 缺省 1、
    /// 显式 0（`VERTICAL` 按 pass 序固定）；combine `BLENDMODE` 缺省 9，`COPYBG` 拒绝。
    private nonisolated static func validCombos(
        _ authored: [String: Int],
        ordinal: Int,
        profile: SceneGodraysShaderProfile
    ) -> Bool {
        guard let combos = normalizedCombos(authored) else { return false }
        switch ordinal {
        case 0:
            return combos.keys.allSatisfy { ["NOISE", "MASK"].contains($0) }
                && combos["NOISE", default: 1] == 1
                && combos["MASK", default: 0] == 0
        case 1:
            return combos.keys.allSatisfy { ["CASTER", "SAMPLES"].contains($0) }
                && combos["CASTER", default: 0]
                    == (profile == .directionalV1 ? 1 : 0)
                && [0, 1].contains(combos["SAMPLES", default: 0])
        case 2, 3:
            return combos.keys.allSatisfy { ["KERNEL", "VERTICAL"].contains($0) }
                && (profile == .directionalV1
                    ? combos["KERNEL", default: 0] == 0
                    : [0, 1].contains(combos["KERNEL", default: 1]))
                && combos["VERTICAL", default: 0] == (ordinal == 3 ? 1 : 0)
        case 4:
            return combos.keys.allSatisfy { ["BLENDMODE", "COPYBG"].contains($0) }
                && combos["COPYBG", default: 0] == 0
                && (0 ... SceneBlendModeShaderSource.maximumMode)
                .contains(combos["BLENDMODE", default: defaultBlendMode])
        default:
            return false
        }
    }

    nonisolated static func downsampleConstants(
        _ constants: [String: SceneDocument.ShaderValue]
    ) -> DownsampleConstants? {
        guard let values = staticScalars(
            constants,
            allowed: [
                "raythreshold": (0 ... 1, 0.5),
                "noiseamount": (0.01 ... 1, 0.4),
                "noisescale": (0.01 ... 10, 3),
                "noisespeed": (0.01 ... 1, 0.15),
                "noisesmoothness": (0.01 ... 0.5, 0.2),
            ]
        ) else {
            return nil
        }
        return DownsampleConstants(
            threshold: values["raythreshold"]!,
            noiseAmount: values["noiseamount"]!,
            noiseScale: values["noisescale"]!,
            noiseSpeed: values["noisespeed"]!,
            noiseSmoothness: values["noisesmoothness"]!
        )
    }

    nonisolated static func castConstants(
        _ constants: [String: SceneDocument.ShaderValue],
        profile: SceneGodraysShaderProfile
    ) -> CastConstants? {
        var scalars: [String: SceneDocument.ShaderValue] = [:]
        var center = SIMD2<Float>(0.5, 0.5)
        var direction: Float?
        var color = SIMD3<Float>(1, 1, 1)
        for (key, value) in constants {
            switch key.lowercased() {
            case "center":
                guard profile == .stock2842 else { return nil }
                guard let components = staticVector(value, count: 2, range: -1 ... 2) else {
                    return nil
                }
                center = SIMD2(components[0], components[1])
            case "direction":
                guard profile == .directionalV1,
                      let components = staticVector(value, count: 1, range: 0 ... 6.28)
                else {
                    return nil
                }
                direction = components[0]
            case "color":
                guard let components = staticVector(value, count: 3, range: 0 ... 1) else {
                    return nil
                }
                color = SIMD3(components[0], components[1], components[2])
            default:
                guard scalars.updateValue(value, forKey: key.lowercased()) == nil else {
                    return nil
                }
            }
        }
        guard let values = staticScalars(
            scalars,
            allowed: [
                "raylength": (0.01 ... 1, 0.5),
                "rayintensity": (0.01 ... 2, 1),
            ]
        ) else {
            return nil
        }
        return CastConstants(
            center: center,
            direction: profile == .directionalV1 ? direction ?? 0 : nil,
            color: color,
            length: values["raylength"]!,
            intensity: values["rayintensity"]!
        )
    }

    nonisolated static func blurScale(
        _ constants: [String: SceneDocument.ShaderValue]
    ) -> SIMD2<Float>? {
        if constants.isEmpty { return SIMD2(1, 1) }
        guard constants.count == 1,
              let value = constants.first(where: { $0.key.lowercased() == "blurscale" })?.value,
              let components = staticVector(value, count: 2, range: 0.01 ... 2)
        else {
            return nil
        }
        return SIMD2(components[0], components[1])
    }

    nonisolated static func combineBlendMode(_ authored: [String: Int]) -> Int? {
        guard let combos = normalizedCombos(authored) else { return nil }
        let mode = combos["BLENDMODE", default: defaultBlendMode]
        return (0 ... SceneBlendModeShaderSource.maximumMode).contains(mode) ? mode : nil
    }

    nonisolated static func castSamples(_ authored: [String: Int]) -> Bool? {
        guard let combos = normalizedCombos(authored) else { return nil }
        return combos["SAMPLES", default: 0] == 1
    }

    nonisolated static func gaussianKernel(
        _ horizontal: [String: Int],
        vertical: [String: Int],
        profile: SceneGodraysShaderProfile
    ) -> Bool? {
        let defaultKernel = profile == .directionalV1 ? 0 : 1
        guard let x = normalizedCombos(horizontal),
              let y = normalizedCombos(vertical),
              x["KERNEL", default: defaultKernel] == y["KERNEL", default: defaultKernel]
        else {
            return nil
        }
        return x["KERNEL", default: defaultKernel] == 0
    }

    /// 区分「拒绝」（nil）与「合法无遮罩」（`.path == nil`）。pass 0 实例槽只接受
    /// 空、`[nil, mask]`、`[nil, mask, nil|clouds]`、`[nil, nil, clouds]` 形态；
    /// directional-v1 combine 只接受与当前 layer capture 名称精确一致的冗余实例引用。
    nonisolated struct MaskResolution {
        let path: String?
    }

    nonisolated static func maskTexturePath(
        effect: Graph.Effect,
        layer: SceneRenderDescriptor.Layer,
        resolvedDownsample _: SceneResolvedMaterialNode,
        profile: SceneGodraysShaderProfile
    ) -> MaskResolution? {
        guard layer.effects.indices.contains(effect.key.effectIndex) else { return nil }
        let descriptor = layer.effects[effect.key.effectIndex]
        guard descriptor.id == effect.key.descriptorID,
              descriptor.visible != false,
              descriptor.passes.count == 5
        else {
            return nil
        }
        for (index, pass) in descriptor.passes.enumerated() {
            guard pass.userTextureInputs.isEmpty else { return nil }
            if index == 0 { continue }
            if index == 4, profile == .directionalV1 {
                let capture = "_rt_imagelayercomposite_\(layer.id)_a"
                guard pass.textureSlots.count == 2,
                      pass.textureSlots[0] == nil,
                      pass.textureSlots[1].map(normalized) == capture,
                      pass.texturePaths.map(normalized) == [capture]
                else {
                    return nil
                }
                continue
            }
            guard pass.texturePaths.isEmpty, pass.textureSlots.isEmpty else { return nil }
        }
        let pass = descriptor.passes[0]
        if pass.texturePaths.isEmpty && pass.textureSlots.isEmpty {
            return MaskResolution(path: nil)
        }
        guard (2 ... 3).contains(pass.textureSlots.count),
              pass.textureSlots[0] == nil
        else {
            return nil
        }
        let mask = pass.textureSlots[1]
        let noise = pass.textureSlots.count == 3 ? pass.textureSlots[2] : nil
        if let mask {
            guard !mask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
        }
        if let noise {
            guard normalized(noise) == noiseAssetPath else { return nil }
        }
        guard mask != nil || noise != nil else { return nil }
        let expectedPaths = [mask, noise].compactMap { $0 }
        guard pass.texturePaths == expectedPaths else { return nil }
        return MaskResolution(path: mask)
    }

    private nonisolated static func staticScalars(
        _ constants: [String: SceneDocument.ShaderValue],
        allowed: [String: (ClosedRange<Double>, Float)]
    ) -> [String: Float]? {
        var values: [String: Float] = [:]
        for (key, value) in constants {
            let lower = key.lowercased()
            guard let (range, _) = allowed[lower],
                  values[lower] == nil,
                  let components = staticVector(value, count: 1, range: range)
            else {
                return nil
            }
            values[lower] = components[0]
        }
        for (key, (_, fallback)) in allowed where values[key] == nil {
            values[key] = fallback
        }
        return values
    }

    /// range 按 Float 精度比较（作者值是编辑器 float32 序列化）。
    private nonisolated static func staticVector(
        _ value: SceneDocument.ShaderValue,
        count: Int,
        range: ClosedRange<Double>
    ) -> [Float]? {
        guard value.userBinding == nil,
              value.valueKind.lowercased() == (count == 1 ? "number" : "vector"),
              let components = value.components,
              components.count == count
        else {
            return nil
        }
        let floatRange = ClosedRange(
            uncheckedBounds: (Float(range.lowerBound), Float(range.upperBound))
        )
        var result: [Float] = []
        for component in components {
            let float = Float(component)
            guard float.isFinite, floatRange.contains(float) else { return nil }
            result.append(float)
        }
        return result
    }

    private nonisolated static func normalizedCombos(
        _ authored: [String: Int]
    ) -> [String: Int]? {
        var result: [String: Int] = [:]
        for (key, value) in authored {
            guard result.updateValue(value, forKey: key.uppercased()) == nil else {
                return nil
            }
        }
        return result
    }

    /// combine 的 `[COMBO]` 注解默认 9。
    nonisolated static let defaultBlendMode = 9
    /// downsample2 的 `g_Texture2` 注解默认。
    nonisolated static let noiseAssetPath = "util/clouds_256"
}
