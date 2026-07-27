//
//  SceneAuthoredShakePlanner+Audio.swift
//  MyWallpaperX
//

import Foundation

extension SceneAuthoredShakePlanner {
    /// 作者启用 AUDIOPROCESSING 时与 motion 四键并存的 audio 常量。
    /// 官方取值 1/2/3 分别是 left、right 与左右平均。
    nonisolated static var audioConstantKeys: Set<String> {
        SceneAudioResponseAdmission.constantKeys
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

    /// `SceneShakeExecutionPlan.audio` 为 `nil` 时表示作者未启用，走时间驱动路径。
    /// stock `shake.vert` 的 `audiobounds` annotation 默认值是 `0.0 1.2`。
    nonisolated static func audioParameters(
        _ pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor,
        profile: SceneShakeShaderProfile
    ) -> SceneAudioResponseAdmission.Result? {
        // 就地取值而不放宽主文件里同名 helper 的访问级别。
        let comboValue = pass.combos.first { $0.key.uppercased() == "AUDIOPROCESSING" }?.value
        // 作者只能写这五个 audio 常量与 motion 四键；出现其他键说明是本 profile
        // 未覆盖的变体，整段拒绝而不是忽略。
        let known = audioConstantKeys.union(["bounds", "friction", "speed", "strength"])
        guard Set(pass.constantShaderValues.keys.map { $0.lowercased() })
            .isSubset(of: known)
        else {
            return nil
        }
        return SceneAudioResponseAdmission.resolve(
            comboValue: comboValue ?? 0,
            constants: pass.constantShaderValues,
            defaultBounds: SIMD2(0, 1.2),
            isAudioCapableProfile: audioCapable(profile)
        )
    }
}
