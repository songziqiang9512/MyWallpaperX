import Foundation
import simd

/// 官方 `effects/pulse` exact stock 单 pass 的执行计划。
///
/// 常量语义来自官方 pulse.frag `AUDIOPROCESSING == 0` 分支：
/// `pulse = pow(smoothstep(bounds.x, bounds.y, sin(t*speed + phase - π/2)*0.5+0.5)*amount + noise, power)`，
/// `PULSECOLOR` 用 `ApplyBlending(BLENDMODE, albedo*tintLow, albedo*tintHigh, pulse)`，
/// `PULSEALPHA` 乘 alpha（premultiplied 下四通道同乘），`MASK` 按 `mix(sample, albedo, mask.r)`。
nonisolated struct ScenePulseExecutionPlan {
    /// 官方 shader 声明的九个 material 常量。rawValue 即 authored JSON 键。
    nonisolated enum Constant: String, CaseIterable {
        case speed
        case phase
        case amount
        case bounds
        case noiseSpeed = "noisespeed"
        case noiseAmount = "noiseamount"
        case power
        case tintLow = "tintlow"
        case tintHigh = "tinthigh"

        nonisolated var valueType: SceneDynamicValueType {
            switch self {
            case .bounds: .vector2
            case .tintLow, .tintHigh: .vector3
            default: .scalar
            }
        }

        /// shader 注解的 range（vec 常量按分量同界）；`noisespeed` 的界随 profile 变。
        nonisolated func range(for profile: ScenePulseShaderProfile) -> ClosedRange<Double> {
            switch self {
            case .speed: 0 ... 10
            case .phase: 0 ... 6.282
            case .amount, .noiseAmount: 0 ... 2
            case .bounds, .tintLow, .tintHigh: 0 ... 1
            case .noiseSpeed: profile.noiseSpeedRange
            case .power: 0 ... 4
            }
        }

        /// shader 注解的 default；`noisespeed` 的默认值随 profile 变。
        nonisolated func defaultComponents(
            for profile: ScenePulseShaderProfile
        ) -> [Double] {
            switch self {
            case .speed: [3]
            case .phase: [0]
            case .amount: [1]
            case .bounds: [0, 1]
            case .noiseSpeed: [profile.noiseSpeedDefault]
            case .noiseAmount: [0]
            case .power: [1]
            case .tintLow, .tintHigh: [1, 1, 1]
            }
        }
    }

    nonisolated struct ConstantBinding: Equatable {
        let propertyKey: String
        let layerID: Int
        let effectIndex: Int
        let constant: Constant

        nonisolated var dynamicTarget: SceneDynamicTarget {
            .effectConstant(
                layerID: layerID,
                effectIndex: effectIndex,
                passIndex: 0,
                name: constant.rawValue
            )
        }
    }

    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    /// 逐指纹 shader 语义（相位偏移、noise UV 系数、输出 clamp）。
    let shaderProfile: ScenePulseShaderProfile
    /// `BLENDMODE` combo，官方 `[COMBO]` 默认 9。
    let blendMode: Int
    /// `PULSECOLOR` combo，官方默认 1。
    let pulseColor: Bool
    /// `PULSEALPHA` combo，官方默认 0。
    let pulseAlpha: Bool
    /// 静态或绑定 fallback 值，按 `Constant` 全量填充（缺省用官方默认）。
    let staticOrFallbackValues: [Constant: SIMD3<Double>]
    let bindings: [Constant: ConstantBinding]
    /// slot 2（`g_Texture2`）遮罩；nil 表示实例未绑图。
    let maskTexturePath: String?
    /// slot 1（`g_Texture1`）显式声明的 noise 覆盖；v1 只接受缺省或 `util/noise`。
    let noiseTexturePath: String?
    /// 启用 `AUDIOPROCESSING` 时的求值参数；`nil` 表示时间驱动路径。
    let audio: SceneAudioResponse.Parameters?

    nonisolated var liveConsumerTargets: Set<SceneDynamicTarget> {
        Set(bindings.values.map(\.dynamicTarget))
    }

    /// noise 项只有 `noiseAmount` 可能非 0（静态非 0，或存在绑定可在运行期变非 0）时才参与采样。
    nonisolated var requiresNoiseTexture: Bool {
        bindings[.noiseAmount] != nil
            || staticOrFallbackValues[.noiseAmount, default: .zero].x != 0
    }

    nonisolated func resolvedComponents(
        _ constant: Constant,
        in snapshot: SceneDynamicSnapshot
    ) -> SIMD3<Double> {
        let defaults = constant.defaultComponents(for: shaderProfile)
        let fallback = staticOrFallbackValues[
            constant,
            default: SIMD3(defaults, fill: 0)
        ]
        guard let target = bindings[constant]?.dynamicTarget,
              let value = snapshot[target]?.value
        else {
            return fallback
        }
        let components: [Double]
        switch value {
        case let .scalar(x): components = [x]
        case let .vector2(x, y): components = [x, y]
        case let .vector3(x, y, z): components = [x, y, z]
        default: return fallback
        }
        let range = constant.range(for: shaderProfile)
        guard components.count == defaults.count,
              components.allSatisfy({ $0.isFinite && range.contains($0) })
        else {
            return fallback
        }
        return SIMD3(components, fill: 0)
    }
}

extension SIMD3<Double> {
    nonisolated init(_ components: [Double], fill: Double) {
        self.init(
            components.count > 0 ? components[0] : fill,
            components.count > 1 ? components[1] : fill,
            components.count > 2 ? components[2] : fill
        )
    }
}
