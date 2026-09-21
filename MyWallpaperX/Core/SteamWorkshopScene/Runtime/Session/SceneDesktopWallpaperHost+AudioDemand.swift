//
//  SceneDesktopWallpaperHost+AudioDemand.swift
//  MyWallpaperX
//

import Foundation

extension SceneDesktopWallpaperHost {
    /// Owns the demand lifecycle around a surface rebuild.  Particle demand is
    /// unknown until the new surfaces have loaded, so the current exact demand
    /// is preserved first and only reconciled by `rebuildSurfaces` after the
    /// particle plans are available.  A failed rebuild is a terminal host
    /// state: `stop()` revokes the demand and all other launch-scoped owners.
    @discardableResult
    func rebuildSurfacesReconcilingAudioDemand(
        _ context: SceneDesktopWallpaperLaunchContext,
        rebuild: () -> Bool,
        revokeLaunch: () -> Void
    ) -> Bool {
        updateAudioSpectrumDemand(context, hasParticleAudioConsumer: nil)
        guard rebuild() else {
            revokeLaunch()
            return false
        }
        return true
    }

    func updateAudioSpectrumDemand(
        _ context: SceneDesktopWallpaperLaunchContext,
        hasParticleAudioConsumer: Bool?
    ) {
        let demandsSpectrum = Self.requiresAudioSpectrum(
            resolvedMaterialExecutionCapabilities:
                context.resolvedMaterialExecutionCapabilities,
            hasParticleAudioConsumer: hasParticleAudioConsumer == true
                || context.propertyVectorScriptProgram.hasAudioConsumers
                || context.sceneScriptScalarProgram.hasAudioConsumers
                || context.sceneScriptStringProgram.hasAudioConsumers
                || context.sceneScriptCursorProgram.hasAudioConsumers
        )
        // Particle plans are known only after the new surfaces load.  When no
        // other prepared consumer proves demand, preserve the previous scene's
        // exact demand until rebuild resolves the particle result.  Converting
        // this unknown to false would clear the shared snapshot and retire the
        // system tap during an audio -> particle-only scene switch.
        guard demandsSpectrum || hasParticleAudioConsumer != nil else { return }
        SceneAudioSpectrumInbox.shared.setDemand(
            demandsSpectrum,
            requiresCurrentProcessAudioCapture:
                !context.soundPlaybackProgram.bindings.isEmpty
        )
    }

    /// 按 consumer 存在性声明频谱采集需求。
    ///
    /// 判据是「已进入统一执行目录的 backend 里是否有启用 audio 的 plan」，
    /// 而不是 project 的 `supportsaudioprocessing`——后者是作者在编辑器里勾的
    /// 声明；它与真正带 audio 声明的样本集合并不相等，按它采集会让没有任何
    /// consumer 的壁纸也去占用系统音频权限。
    ///
    /// 当前 consumer 包括 stock Shake/Pulse 的 `AUDIOPROCESSING` 分支、
    /// 统一 Program 的 active audio host uniforms、surface 资源装载后确认
    /// 可执行的 bounded particle audio plan，以及通用 SceneScript audio host；
    /// 新增 consumer 时必须同批扩充这里，否则采集不会启动。
    static func requiresAudioSpectrum(
        resolvedMaterialExecutionCapabilities:
            SceneResolvedMaterialExecutionCapabilityCatalog,
        hasParticleAudioConsumer: Bool = false
    ) -> Bool {
        hasParticleAudioConsumer
            || resolvedMaterialExecutionCapabilities.hasAudioSpectrumConsumer
    }
}
