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
        let clampedVolume = min(max(volume, 0), 100)
        settings.volume = clampedVolume
        if clampedVolume > 0 {
            previousAudibleVolume = clampedVolume
        }
        WallpaperEngine.shared.setVolume(Float(clampedVolume))
    }

    func setMuted(_ muted: Bool) {
        // 静音只是 volume 的一个派生态，恢复时优先回到最近一次可听音量。
        if muted {
            if settings.volume > 0 {
                previousAudibleVolume = settings.volume
            }
            updateVolume(0)
        } else {
            let restoredVolume = previousAudibleVolume > 0 ? previousAudibleVolume : 50
            updateVolume(restoredVolume)
        }
    }

    func applyEngineSettings(reloadWallpaper: Bool = false) {
        // 只有引擎真正关心的播放策略才通过这里下发，避免 UI 选项污染播放链路。
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

        // 引擎只需要暂停策略和音量这类播放态配置，别把 UI 选择状态塞进这里。
        WallpaperEngine.shared.updateSettings(
            pauseWhenOtherAppFocused: settings.pauseWhenOtherAppFocused,
            pauseWhenOtherAppFullscreen: settings.pauseWhenOtherAppFullscreen,
            pauseWhenUnplugged: settings.pauseWhenUnplugged,
            pauseWhenIdle: settings.pauseWhenIdle,
            idleTimeoutMinutes: settings.idleTimeoutMinutes
        )
        lastAppliedEnginePauseSettings = EnginePauseSettingsSnapshot(settings: settings)
        WallpaperEngine.shared.setVolume(Float(settings.volume))
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
        settings.autoSwitchEnabled && !wallpapers.isEmpty && currentWallpaper != nil && isSwitchingPlaybackMode()
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
            PlaybackCommandMultiplexer.shared.dispatch(.setMuted(!isMuted))
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

    func applyPlaybackRateToEngine() {
        // 播放速率只影响引擎内部，不重建 daemon session，直接更新速率并在未暂停时立即生效。
        let effectiveRate = settings.playbackRateEnabled ? settings.playbackRate : 1.0
        let rate = Float(max(0.25, min(2.0, effectiveRate)))
        WallpaperEngine.shared.setPlaybackRate(rate)
    }

    func applySystemAudioSpectrumToEngine() {
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
}
