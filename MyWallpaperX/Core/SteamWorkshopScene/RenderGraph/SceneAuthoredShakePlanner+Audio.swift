//
//  SceneAuthoredShakePlanner+Audio.swift
//  MyWallpaperX
//

import Foundation

extension SceneAuthoredShakePlanner {
    /// 作者启用 AUDIOPROCESSING 时与 motion 四键并存的 audio 常量。
    /// 官方取值 1/2/3 分别是 left、right 与左右平均。
    nonisolated static let audioConstantKeys = Set([
        "frequencymin", "frequencymax", "audioexponent",
        "audiobounds", "audioamount",
    ])

    /// audio 求值参数的提取结果。`parameters == nil` 表示作者未启用，
    /// 走既有时间驱动路径；提取失败时 `audioParameters` 整体返回 nil 由调用方拒绝。
    nonisolated struct AudioAdmission {
        let parameters: SceneAudioResponse.Parameters?
    }

    /// `AUDIOPROCESSING` 只在已随 audio 验证过指纹的 profile 上放开。
    /// `legacyUnconditionalPhase` 的老编辑器包尚无 audio 正反例，保持整段拒绝。
    nonisolated static func audioCapable(_ profile: SceneShakeShaderProfile) -> Bool {
        switch profile {
        case .whitePhaseFallback, .timeOffsetCombo:
            return true
        case .legacyUnconditionalPhase:
            return false
        }
    }

    /// 官方 `shake.vert` 的 audio uniform 默认值（annotation 逐条给出）：
    /// `frequencymin` 0、`frequencymax` 1、`audioexponent` 1.0、
    /// `audiobounds` "0.0 1.2"、`audioamount` 1。
    ///
    /// 语料中这五个常量是**部分可选**的：`2419444134` 缺 frequencymin/max，
    /// `1937925563` 缺 frequencymin 与 audioexponent，因此缺省必须按 annotation
    /// 填充，不能要求作者写全。
    /// `SceneShakeExecutionPlan.audio` 为 `nil` 时表示作者未启用，走时间驱动路径。
    nonisolated static func audioParameters(
        _ pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor,
        profile: SceneShakeShaderProfile
    ) -> AudioAdmission? {
        // 就地取值而不放宽主文件里同名 helper 的访问级别。
        let comboValue = pass.combos.first { $0.key.uppercased() == "AUDIOPROCESSING" }?.value
        guard let comboValue, comboValue != 0 else {
            return AudioAdmission(parameters: nil)
        }
        guard audioCapable(profile),
              let channel = SceneAudioResponse.Channel(comboValue: comboValue)
        else {
            return nil
        }

        var values: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in pass.constantShaderValues {
            guard values.updateValue(value, forKey: key.lowercased()) == nil else {
                return nil
            }
        }
        // 作者只能写这五个 audio 常量；出现其他未知 audio 键说明是本 profile
        // 未覆盖的变体，整段拒绝而不是忽略。
        let known = audioConstantKeys.union(["bounds", "friction", "speed", "strength"])
        guard Set(values.keys).isSubset(of: known),
              let frequencyMin = audioScalar(
                  values["frequencymin"], range: 0 ... 15, fallback: 0
              ),
              let frequencyMax = audioScalar(
                  values["frequencymax"], range: 0 ... 15, fallback: 1
              ),
              let exponent = audioScalar(
                  values["audioexponent"], range: 0 ... 4, fallback: 1
              ),
              let multiply = audioScalar(
                  values["audioamount"], range: 0 ... 2, fallback: 1
              ),
              let bounds = audioVector(values["audiobounds"], fallback: SIMD2(0, 1.2))
        else {
            return nil
        }

        return AudioAdmission(
            parameters: SceneAudioResponse.Parameters(
                channel: channel,
                frequencyMin: frequencyMin,
                frequencyMax: frequencyMax,
                boundsLower: bounds.x,
                boundsUpper: bounds.y,
                exponent: exponent,
                multiply: multiply
            )
        )
    }

    /// 与非 audio 常量相同的准入口径：拒绝 user binding、非 number、非有限值。
    /// 未声明时使用 annotation 默认值。
    private nonisolated static func audioScalar(
        _ value: SceneDocument.ShaderValue?,
        range: ClosedRange<Double>,
        fallback: Float
    ) -> Float? {
        guard let value else { return fallback }
        guard value.userBinding == nil,
              value.valueKind.lowercased() == "number",
              let components = value.components,
              components.count == 1,
              let component = components.first,
              component.isFinite,
              range.contains(component)
        else {
            return nil
        }
        return Float(component)
    }

    private nonisolated static func audioVector(
        _ value: SceneDocument.ShaderValue?,
        fallback: SIMD2<Float>
    ) -> SIMD2<Float>? {
        guard let value else { return fallback }
        guard value.userBinding == nil,
              let components = value.components,
              components.count == 2,
              components.allSatisfy(\.isFinite)
        else {
            return nil
        }
        // bounds 进入 smoothstep 的两端。官方对 audiobounds 没有声明 range，
        // 语料实测为 0...1.2；这里只要求有限且下沿不大于上沿，
        // 反序交由 SceneAudioResponse 的 UB 兜底处理。
        return SIMD2(Float(components[0]), Float(components[1]))
    }
}
