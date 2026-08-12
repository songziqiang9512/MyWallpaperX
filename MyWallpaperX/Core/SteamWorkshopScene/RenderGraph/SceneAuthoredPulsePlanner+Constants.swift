import Foundation
import simd

/// combo、常量与纹理槽的逐项提取：任何未知键、越界值、SceneScript 绑定或
/// 非 `util/noise` 的 slot 1 覆盖都整条拒绝。
extension SceneAuthoredPulsePlanner {
    nonisolated struct ResolvedCombos {
        let blendMode: Int
        let pulseColor: Bool
        let pulseAlpha: Bool
        /// `.off` 表示作者未启用 audio，走时间驱动路径。
        let audioChannel: SceneAudioResponse.Channel
    }

    nonisolated struct ResolvedConstants {
        let values: [Constant: SIMD3<Double>]
        let bindings: [Constant: ScenePulseExecutionPlan.ConstantBinding]
    }

    nonisolated struct ResolvedTextureSlots {
        let noise: String?
        let mask: String?
    }

    /// `AUDIOPROCESSING` 取值 1/2/3 分别是 left、right 与左右平均，只在 stock 指纹上
    /// 放开：两个 v1 profile 的 audio 行为尚无正反例，继续 fail closed。
    /// `MASK` 由编辑器按槽位绑图在编译期自动设置（E-MASK-SLOT-COMBO），语料 0 次显式声明。
    /// `allowsAudio` 只对 effect 实例 pass 为真：语料中 audio 声明全部落在实例层，
    /// material 层是经 SHA 校验的 stock 文件，出现非 0 值即视为异常。
    nonisolated static func validAuthoredCombos(
        _ authored: [String: Int],
        allowsAudio: Bool
    ) -> Bool {
        guard let combos = normalizedCombos(authored) else { return false }
        let audio = combos["AUDIOPROCESSING", default: 0]
        guard combos.keys.allSatisfy({
            ["AUDIOPROCESSING", "BLENDMODE", "PULSEALPHA", "PULSECOLOR"].contains($0)
        }),
            audio == 0 || (allowsAudio && (1 ... 3).contains(audio)),
            [0, 1].contains(combos["PULSEALPHA", default: 0]),
            [0, 1].contains(combos["PULSECOLOR", default: 1])
        else {
            return false
        }
        return (0 ... SceneBlendModeShaderSource.maximumMode)
            .contains(combos["BLENDMODE", default: defaultBlendMode])
    }

    nonisolated static func resolvedCombos(
        _ authored: [String: Int],
        profile: ScenePulseShaderProfile
    ) -> ResolvedCombos? {
        guard validAuthoredCombos(authored, allowsAudio: profile == .stock2842),
              let combos = normalizedCombos(authored)
        else {
            return nil
        }
        return ResolvedCombos(
            blendMode: combos["BLENDMODE", default: defaultBlendMode],
            pulseColor: combos["PULSECOLOR", default: 1] == 1,
            pulseAlpha: combos["PULSEALPHA", default: 0] == 1,
            audioChannel: SceneAudioResponse.Channel(
                comboValue: combos["AUDIOPROCESSING", default: 0]
            ) ?? .off
        )
    }

    /// 全部键必须是官方九个 material 常量之一；静态值按 shader 注解 range 准入
    /// （`noisespeed` 的界随 profile 变），user binding 记录动态目标并保留 authored
    /// fallback，SceneScript 形态拒绝。
    /// stock `pulse.vert` 的 `audiobounds` annotation 默认值是 `0.5 1.0`，
    /// 与 shake 的 `0.0 1.2` 不同，因此默认值在这里给出而不是由共享层内置。
    nonisolated static func audioParameters(
        combos: [String: Int],
        constants: [String: SceneDocument.ShaderValue],
        profile: ScenePulseShaderProfile
    ) -> SceneAudioResponseAdmission.Result? {
        let comboValue = combos.first { $0.key.uppercased() == "AUDIOPROCESSING" }?.value
        return SceneAudioResponseAdmission.resolve(
            comboValue: comboValue ?? 0,
            constants: constants,
            defaultBounds: SIMD2(0.5, 1),
            isAudioCapableProfile: profile == .stock2842
        )
    }

    nonisolated static func resolvedConstants(
        from constants: [String: SceneDocument.ShaderValue],
        effect: Graph.EffectKey,
        profile: ScenePulseShaderProfile,
        audioEnabled: Bool
    ) -> ResolvedConstants? {
        var values: [Constant: SIMD3<Double>] = [:]
        var bindings: [Constant: ScenePulseExecutionPlan.ConstantBinding] = [:]
        for (key, value) in constants {
            // 启用 audio 时这五个常量由 SceneAudioResponseAdmission 准入；
            // 未启用时官方 shader 根本不声明对应 uniform，出现即视为声明不一致。
            if audioEnabled,
               SceneAudioResponseAdmission.constantKeys.contains(key.lowercased()) {
                continue
            }
            guard let constant = Constant(rawValue: key.lowercased()),
                  values[constant] == nil
            else {
                return nil
            }
            let expectedCount = constant.defaultComponents(for: profile).count
            let range = constant.range(for: profile)
            guard let components = value.components,
                  components.count == expectedCount,
                  components.allSatisfy({ $0.isFinite && range.contains($0) })
            else {
                return nil
            }
            if let propertyKey = value.userBinding?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            {
                guard !propertyKey.isEmpty,
                      value.valueKind.lowercased() == "binding"
                else {
                    return nil
                }
                bindings[constant] = .init(
                    propertyKey: propertyKey,
                    layerID: effect.layerID,
                    effectIndex: effect.effectIndex,
                    constant: constant
                )
            } else {
                let staticKind = expectedCount == 1 ? "number" : "vector"
                guard value.valueKind.lowercased() == staticKind else { return nil }
            }
            values[constant] = SIMD3(components, fill: 0)
        }
        guard validBounds(values[.bounds]) else { return nil }
        for constant in Constant.allCases where values[constant] == nil {
            values[constant] = SIMD3(constant.defaultComponents(for: profile), fill: 0)
        }
        return ResolvedConstants(values: values, bindings: bindings)
    }

    /// 官方 default "0 1"。smoothstep 在 x >= y 时未定义，fail closed。
    private nonisolated static func validBounds(_ bounds: SIMD3<Double>?) -> Bool {
        guard let bounds else { return true }
        return bounds.x < bounds.y
    }

    /// 实例槽形态只接受：空、`[nil, noise]`、`[nil, noise, mask]`、`[nil, nil, mask]`。
    /// slot 0 是 `g_Texture0`（hidden 上游输入），作者绑图即拒绝。
    nonisolated static func validInstanceTextureSlots(
        paths: [String],
        slots: [String?]
    ) -> Bool {
        if paths.isEmpty && slots.isEmpty { return true }
        guard (2 ... 3).contains(slots.count), slots[0] == nil else { return false }
        let noise = slots[1]
        let mask = slots.count == 3 ? slots[2] : nil
        if let noise {
            guard normalized(noise) == noiseAssetPath else { return false }
        }
        if let mask {
            guard !mask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
        }
        guard noise != nil || mask != nil else { return false }
        let expectedPaths = [noise, mask].compactMap { $0 }
        return paths == expectedPaths
    }

    nonisolated static func textureSlots(
        in passes: [SceneRenderDescriptor.EffectDescriptor.PassDescriptor]
    ) -> ResolvedTextureSlots? {
        guard let pass = passes.first else { return nil }
        let slots = pass.textureSlots
        guard validInstanceTextureSlots(paths: pass.texturePaths, slots: slots) else {
            return nil
        }
        return ResolvedTextureSlots(
            noise: slots.count >= 2 ? slots[1] : nil,
            mask: slots.count >= 3 ? slots[2] : nil
        )
    }

    /// resolved material 槽位（resolver 固定 8 槽）与实例同构：只允许 slot 1 绑
    /// stock noise、slot 2 绑 instance 遮罩资产，其余槽位必须为空。
    nonisolated static func validResolvedTextureSlots(
        _ slots: [SceneResolvedMaterialNode.TextureSlot?]
    ) -> Bool {
        for (index, slot) in slots.enumerated() {
            guard let slot else { continue }
            guard [1, 2].contains(index),
                  slot.provenance == .instance,
                  case let .asset(path) = slot.source
            else {
                return false
            }
            if index == 1 {
                guard normalized(path) == noiseAssetPath else { return false }
            } else {
                guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return false
                }
            }
        }
        return true
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

    /// 官方 pulse.frag 的 `[COMBO]` 注解声明 `BLENDMODE` 默认 9。
    nonisolated static let defaultBlendMode = 9
    /// `g_Texture1` 注解的 default；语料 19 个显式覆盖全部仍是该值。
    nonisolated static let noiseAssetPath = "util/noise"
}
