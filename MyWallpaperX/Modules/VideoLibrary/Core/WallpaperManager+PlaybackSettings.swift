//
//  WallpaperManager+PlaybackSettings.swift
//  MyWallpaperX
//

import Foundation
import ServiceManagement

extension WallpaperManager {
    enum PlaybackMode {
        case loop
        case random
        case sequential
    }

    // 重置设置为默认值
    public func resetSettings() {
        // 重置必须走“首次安装状态”入口，不能只改局部字段，否则会遗留标签/列表/缓存状态。
        resetToFreshInstallState()
    }

    func updateVolume(_ volume: Double) {
        // 音量是播放态设置，既要写回 settings，也要同步到当前 engine。
        let candidate = volume.isFinite ? volume : settings.volume
        let clampedVolume = min(max(candidate, 0), 100)
        settings.volume = clampedVolume
        if clampedVolume > 0 {
            previousAudibleVolume = clampedVolume
        }
        PlaybackVolumeState.shared.setNormalizedVolume(Float(clampedVolume / 100))
        PlaybackCommandMultiplexer.shared.dispatch(.setVolume(Float(clampedVolume)))
    }

    func setMuted(_ muted: Bool) {
        // 静音是独立门，不把公共主音量改成 0；这样 Scene/Web/Video
        // 都能保留同一个可听音量，解除静音只需重新投影该值。
        if muted {
            if settings.volume > 0 {
                previousAudibleVolume = settings.volume
            }
        } else if settings.volume <= 0 {
            let restoredVolume = previousAudibleVolume > 0 ? previousAudibleVolume : 50
            settings.volume = restoredVolume
        }
        PlaybackVolumeState.shared.setNormalizedVolume(
            Float(min(max(settings.volume, 0), 100) / 100)
        )
        PlaybackCommandMultiplexer.shared.dispatch(
            .setVolume(Float(min(max(settings.volume, 0), 100)))
        )
    }

    func applyEngineSettings(reloadWallpaper: Bool = false) {
        PlaybackPolicyController.shared.updateSettings(settings)
        // Scene 显示集随设置即时裁决（多屏开=全部、关=首屏），scene 活跃
        // 时不再依赖 currentWallpaper 重载分支。
        SceneDaemonClient.shared.setMultiDisplayEnabled(settings.multiDisplayEnabled)
        if reloadWallpaper {
            if activeWallpaperRuntime == .web {
                WallpaperEngine.shared.updateWebDisplayConfiguration(
                    multiDisplayEnabled: settings.multiDisplayEnabled
                )
            } else if let currentWallpaper {
                setAsWallpaper(currentWallpaper)
                return
            }
        }

        // 音量和频谱投影到各运行时，不改变共享暂停意图。
        PlaybackVolumeState.shared.setNormalizedVolume(Float(settings.volume / 100))
        PlaybackCommandMultiplexer.shared.dispatch(.setVolume(Float(settings.volume)))
        applySystemAudioSpectrumToEngine()
    }

    // 启动自动切换 timer（始终从 0 重新计时）
    func startAutoSwitchTimer() {
        settings.randomInterval = max(1, min(settings.randomInterval, 100000))
        guard shouldRunAutoSwitchTimer() else {
            stopAutoSwitchTimer()
            return
        }
        stopAutoSwitchTimer()
        let timeInterval = Double(settings.randomInterval) * Double(settings.timeUnit.secondsValue)
        let timer = Timer(timeInterval: timeInterval, repeats: true) { [weak self] _ in
            self?.timerDidFire()
        }
        RunLoop.main.add(timer, forMode: .common)
        autoSwitchTimer = timer
    }

    // 销毁 timer
    func stopAutoSwitchTimer() {
        autoSwitchTimer?.invalidate()
        autoSwitchTimer = nil
    }

    // timer 到期：切换下一张，timer repeats:true 自动续计，不需要重建。
    private func timerDidFire() {
        guard shouldRunAutoSwitchTimer() else {
            stopAutoSwitchTimer()
            return
        }
        advanceWallpaperForCurrentMode(triggeredByTimer: true)
    }

    // 兼容旧调用点，统一走 startAutoSwitchTimer
    func refreshAutoSwitchTimerIfNeeded(forceRestart: Bool = false) {
        if forceRestart || autoSwitchTimer == nil {
            startAutoSwitchTimer()
        } else {
            // 检查时间间隔是否变了，变了就重建
            let timeInterval = Double(settings.randomInterval) * Double(settings.timeUnit.secondsValue)
            if let t = autoSwitchTimer, abs(t.timeInterval - timeInterval) > 0.001 {
                startAutoSwitchTimer()
            } else if !shouldRunAutoSwitchTimer() {
                stopAutoSwitchTimer()
            }
        }
    }

    func syncAutoSwitchPlaybackPolicy(forceTimerRestart: Bool = false) {
        // 只管 timer，不动引擎，不重载视频。
        refreshAutoSwitchTimerIfNeeded(forceRestart: forceTimerRestart)
    }

    func setLoopPlaybackEnabled(_ enabled: Bool) {
        // 三种播放模式互斥，开启一个模式时会自动清理其它模式。
        if enabled {
            applyPlaybackMode(.loop)
            settings.autoSwitchEnabled = false
        } else {
            // 循环关闭时自动切换到顺序播放，保证始终有一个播放模式可用。
            applyPlaybackMode(.sequential)
        }
        syncAutoSwitchPlaybackPolicy()
    }

    func setRandomPlaybackEnabled(_ enabled: Bool) {
        if enabled {
            applyPlaybackMode(.random)
        } else {
            settings.randomPlayback = false
            ensureAtLeastOnePlaybackMode()
        }
        // 模式切换时重建 timer，从 0 开始计时，不动引擎。
        startAutoSwitchTimer()
    }

    func setSequentialPlaybackEnabled(_ enabled: Bool) {
        if enabled {
            applyPlaybackMode(.sequential)
        } else {
            settings.sequentialPlayback = false
            ensureAtLeastOnePlaybackMode()
        }
        // 模式切换时重建 timer，从 0 开始计时，不动引擎。
        startAutoSwitchTimer()
    }

    func normalizePlaybackSettings() {
        // 启动/导入/重置后都先归一化播放模式，避免 settings 带着非法组合进入引擎。
        switch playbackMode() {
        case .random:
            applyPlaybackMode(.random)
        case .sequential:
            applyPlaybackMode(.sequential)
        case .loop:
            applyPlaybackMode(.loop)
            settings.autoSwitchEnabled = false
        }
    }

    func playbackMode() -> PlaybackMode {
        // 播放模式优先级固定：随机 > 顺序 > 循环。
        if settings.randomPlayback { return .random }
        if settings.sequentialPlayback { return .sequential }
        return .loop
    }

    func isSwitchingPlaybackMode() -> Bool {
        playbackMode() != .loop
    }

    func shouldRunAutoSwitchTimer() -> Bool {
        // 只有“启用自动切换 + 有壁纸 + 处于可切换模式”时才启动 timer。
        settings.autoSwitchEnabled && !wallpapers.isEmpty && effectiveCurrentWallpaper != nil && isSwitchingPlaybackMode()
    }

    func shouldLoopCurrentItemInEngine() -> Bool {
        // 循环模式：始终循环。
        // 自动切换开启的顺序/随机模式：视频循环，等 timer 到期再切换。
        // 自动切换关闭的顺序/随机模式：不循环，视频播完由 handlePlaybackEnded 切下一张。
        settings.loopPlayback || (settings.autoSwitchEnabled && isSwitchingPlaybackMode())
    }

    func applyPlaybackMode(_ mode: PlaybackMode) {
        // 模式写回只在这里统一处理，防止三个开关各自散落互斥逻辑。
        switch mode {
        case .loop:
            settings.loopPlayback = true
            settings.randomPlayback = false
            settings.sequentialPlayback = false
        case .random:
            settings.loopPlayback = false
            settings.randomPlayback = true
            settings.sequentialPlayback = false
        case .sequential:
            settings.loopPlayback = false
            settings.randomPlayback = false
            settings.sequentialPlayback = true
        }
    }

    func ensureAtLeastOnePlaybackMode() {
        // 关闭某个模式后，优先回落到顺序播放，避免意外进入循环模式导致 timer 失效。
        if !settings.loopPlayback && !settings.randomPlayback && !settings.sequentialPlayback {
            settings.sequentialPlayback = true
        }
    }

    @discardableResult
    func sanitizeSystemHotkeySettingsIfNeeded() -> Bool {
        // 热键必须保证互斥；重复项会自动去重成 none。
        var sanitized = settings
        var usedShortcuts = Set<FunctionKeyShortcut>()

        func sanitize(_ shortcut: inout FunctionKeyShortcut) {
            guard shortcut != .none else { return }
            if usedShortcuts.contains(shortcut) {
                shortcut = .none
            } else {
                usedShortcuts.insert(shortcut)
            }
        }

        sanitize(&sanitized.previousWallpaperHotkey)
        sanitize(&sanitized.nextWallpaperHotkey)
        sanitize(&sanitized.togglePlaybackHotkey)
        sanitize(&sanitized.toggleMuteHotkey)

        let changed =
            sanitized.previousWallpaperHotkey != settings.previousWallpaperHotkey ||
            sanitized.nextWallpaperHotkey != settings.nextWallpaperHotkey ||
            sanitized.togglePlaybackHotkey != settings.togglePlaybackHotkey ||
            sanitized.toggleMuteHotkey != settings.toggleMuteHotkey

        if changed {
            settings = sanitized
        }

        return changed
    }

    func performSystemHotkeyAction(_ action: SystemHotkeyAction) {
        // 全局快捷键只做动作分发，不直接改 UI 状态。
        switch action {
        case .previous:
            navigateWallpaperManually(.previous, userInitiated: true)
        case .next:
            navigateWallpaperManually(.next, userInitiated: true)
        case .playPause:
            let command: WallpaperEngineCommand =
                PlaybackCommandMultiplexer.shared.isAnyEnginePlaying
                ? .pause : .resume
            PlaybackCommandMultiplexer.shared.dispatch(command)
            isPlaying = PlaybackCommandMultiplexer.shared.isAnyEnginePlaying
        case .muteToggle:
            // M0.2：跨引擎决策读公共静音权威，而非 video 派生态。
            PlaybackCommandMultiplexer.shared.dispatch(
                .setMuted(!PlaybackMuteState.shared.isMuted)
            )
        }
    }

    func updateLoginItemStatus() {
        // 登录项状态只和 settings.startOnBoot 绑定，不和窗口显示状态绑定。
        if #available(macOS 13.0, *) {
            do {
                if settings.startOnBoot {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // 登录项注册/注销失败时静默忽略，不影响其他设置。
            }
        }
    }

    func setSyncSystemWallpaperEnabled(_ enabled: Bool) {
        settings.syncSystemWallpaper = enabled
        if !enabled {
            pendingSystemWallpaperSyncWorkItem?.cancel()
            pendingSystemWallpaperSyncWorkItem = nil
        }
    }

    func applyPlaybackRateToEngine(settings source: WallpaperSettings? = nil) {
        // 播放速率只影响引擎内部，不重建 daemon session，直接更新速率并在未暂停时立即生效。
        // sink 调用必须传 newSettings：willSet 期读 self.settings 是旧值。
        let settings = source ?? self.settings
        let effectiveRate = settings.playbackRateEnabled ? settings.playbackRate : 1.0
        let rate = Float(max(0.25, min(2.0, effectiveRate)))
        WallpaperEngine.shared.setPlaybackRate(rate)
    }

    func applySystemAudioSpectrumToEngine(settings source: WallpaperSettings? = nil) {
        let settings = source ?? self.settings
        // 频谱开关只归属 video 叠加层；Web/Scene 跟随样本声明的音频需求
        // （加共享暂停门），没有需要广播的公共策略位。可视化细节归
        // WallpaperEngine 的 configure 入口单点下发。
        WallpaperEngine.shared.configureSystemAudioSpectrum(
            enabled: settings.systemAudioSpectrumEnabled,
            style: settings.systemAudioSpectrumStyle,
            sensitivity: settings.systemAudioSpectrumSensitivity,
            colorHex: settings.systemAudioSpectrumColorHex,
            offsetX: Float(settings.systemAudioSpectrumOffsetX),
            offsetY: Float(settings.systemAudioSpectrumOffsetY),
            barCount: settings.systemAudioSpectrumBarCount,
            peakCapsEnabled: settings.systemAudioSpectrumPeakCapsEnabled
        )
    }

    /// 启动期一次性播种：音量与速率权威在任何 play/web/scene 播种之前
    /// 就位，避免上次运行时为 web/scene 时新会话拿到默认 0.5/1.0。
    /// 音量要同时落 PlaybackVolumeState（scene replay 读它）和引擎
    /// currentVolumeNormalized（web runtimeState 播种读它）。
    /// 同时建立 sink 差分投影的基线（订阅发生在 init 更晚处）。
    func seedEngineProjectionFromPersistedSettings() {
        let persistedVolume = Float(min(max(settings.volume, 0), 100))
        PlaybackVolumeState.shared.setNormalizedVolume(persistedVolume / 100)
        WallpaperEngine.shared.setVolume(persistedVolume)
        applyPlaybackRateToEngine(settings: settings)
        // Scene 显示集也从持久化设置起步，避免本会话首次 setDisplayConfiguration
        // 用全屏默认值覆盖用户的多屏选择。
        SceneDaemonClient.shared.setMultiDisplayEnabled(settings.multiDisplayEnabled)
        lastEngineProjectionBaseline = settings
    }

    /// settings 写入 → 引擎投影的唯一差分入口。只投影真正变化的字段组，
    /// 避免无关写入（拖音量）重发频谱全量配置并清空频谱条。
    func projectEngineSettingsIfChanged(
        from previous: WallpaperSettings?,
        to next: WallpaperSettings
    ) {
        if previous?.playbackRate != next.playbackRate
            || previous?.playbackRateEnabled != next.playbackRateEnabled {
            applyPlaybackRateToEngine(settings: next)
        }

        if previous?.systemAudioSpectrumEnabled != next.systemAudioSpectrumEnabled
            || previous?.systemAudioSpectrumStyle != next.systemAudioSpectrumStyle
            || previous?.systemAudioSpectrumSensitivity != next.systemAudioSpectrumSensitivity
            || previous?.systemAudioSpectrumColorHex != next.systemAudioSpectrumColorHex
            || previous?.systemAudioSpectrumOffsetX != next.systemAudioSpectrumOffsetX
            || previous?.systemAudioSpectrumOffsetY != next.systemAudioSpectrumOffsetY
            || previous?.systemAudioSpectrumBarCount != next.systemAudioSpectrumBarCount
            || previous?.systemAudioSpectrumPeakCapsEnabled != next.systemAudioSpectrumPeakCapsEnabled {
            applySystemAudioSpectrumToEngine(settings: next)
        }

        if previous?.loopPlayback != next.loopPlayback
            || previous?.randomPlayback != next.randomPlayback
            || previous?.sequentialPlayback != next.sequentialPlayback
            || previous?.autoSwitchEnabled != next.autoSwitchEnabled {
            projectLoopPolicyToEngine(settings: next)
        }
    }

    /// 播放模式/自动切换 → 引擎 loop 策略的单点投影。video daemon 是
    /// "循环当前项"的唯一消费者；web/scene 没有"播完"语义，不下发。
    func projectLoopPolicyToEngine(settings source: WallpaperSettings? = nil) {
        let settings = source ?? self.settings
        let switchingMode = settings.randomPlayback || settings.sequentialPlayback
        let shouldLoop = settings.loopPlayback
            || (settings.autoSwitchEnabled && switchingMode)
        guard activeWallpaperRuntime == .video else { return }
        WallpaperEngine.shared.setLoopCurrentItem(shouldLoop)
    }
}
