//
//  SceneDesktopWallpaperHost+AudioDemand.swift
//  MyWallpaperX
//

import Foundation

extension SceneDesktopWallpaperHost {
    /// 按 consumer 存在性声明频谱采集需求。
    ///
    /// 判据是「已进入执行目录的 strict backend 里是否有启用 audio 的 plan」，
    /// 而不是 project 的 `supportsaudioprocessing`——后者是作者在编辑器里勾的
    /// 声明，45 样本中它为 true 的 12 个与真正带 audio 声明的样本互有出入，
    /// 会让没有任何 consumer 的壁纸也去占用系统音频权限。
    ///
    /// 当前 consumer 包括 stock Shake/Pulse 的 `AUDIOPROCESSING` 分支，以及
    /// 严格准入的 Workshop Audio Bars 和受限 SceneScript Audio Bars；
    /// 新增 consumer 时必须同批扩充这里，否则采集不会启动。
    nonisolated static func requiresAudioSpectrum(
        in catalog: SceneAuthoredEffectExecutionCatalog,
        sceneScriptAudioBarsProgram: SceneScriptAudioBarsProgram = .empty
    ) -> Bool {
        sceneScriptAudioBarsProgram.hasAudioConsumer
            || catalog.chainsByLayerID.values.contains { chain in
            chain.stages.contains {
                $0.shake?.audio != nil
                    || $0.pulse?.audio != nil
                    || $0.workshopAudioBars != nil
                    || $0.workshopAudioHueShift != nil
            }
        }
    }
}
