//
//  WallpaperManager+PlaybackSettings.swift
//  MyWallpaperX
//

import Foundation
import ServiceManagement
import QuartzCore

extension WallpaperManager {
    enum PlaybackMode {
        case loop
        case random
        case sequential
    }

    func updateVolume(_ volume: Double) {
        // 音量是播放态设置，既要写回 settings，也要同步到当前 engine。
        let candidate = volume.isFinite ? volume : settings.volume
        let clampedVolume = min(max(candidate, 0), 100)
        if settings.volume != clampedVolume {
            settings.volume = clampedVolume
        }
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
            } else if let session = libraryPlaybackSequence.committed {
                _ = requestLibraryPlayback(reference: session.reference, from: session.snapshot, cause: .settingsReload)
                return
            } else if let currentWallpaper {
                _ = requestLibraryPlayback(reference: .init(provider: .videoLibrary, sourceID: currentWallpaper.id),
                                           cause: .settingsReload)
                return
            }
        }

        // 频谱由启动播种和 settings 差分投影负责；这里仅投影音量。
        PlaybackVolumeState.shared.setNormalizedVolume(Float(settings.volume / 100))
        PlaybackCommandMultiplexer.shared.dispatch(.setVolume(Float(settings.volume)))
    }

    // The existing Timer consumes the single pure monotonic deadline.
    var libraryRotationInterval: TimeInterval {
        Double(max(1, min(settings.randomInterval, 100000))) * Double(settings.timeUnit.secondsValue)
    }

    var libraryRotationEligible: Bool {
        guard settings.autoSwitchEnabled, isSwitchingPlaybackMode(), !libraryPlaybackSequence.isExhausted,
              let session = libraryPlaybackSequence.committed else { return false }
        return session.snapshot.entries.contains { $0.isPlayable && $0.reference != session.reference }
    }

    func rescheduleLibraryRotationTimer() {
        stopAutoSwitchTimer()
        let now = CACurrentMediaTime()
        libraryRotationDeadline.configure(now: now, interval: libraryRotationInterval,
            eligible: libraryRotationEligible)
        libraryRotationDeadline.setPause(effective: PlaybackCommandMultiplexer.shared.isPlaybackPaused, now: now)
        guard let session = libraryPlaybackSequence.committed,
              playbackSwitch.committed?.ticket == session.ticket,
              let deadline = libraryRotationDeadline.deadline,
              libraryPlaybackSequence.pending == nil, playbackSwitch.pending == nil else { return }
        let generation = libraryPlaybackSequence.rotationGeneration
        let timer = Timer(timeInterval: max(0.001, deadline - now), repeats: false) { [weak self] _ in
            guard let self, self.libraryPlaybackSequence.rotationGeneration == generation,
                  self.libraryRotationDeadline.takeDue(now: CACurrentMediaTime(), scheduledDeadline: deadline) else { return }
            self.autoSwitchTimer = nil
            self.advanceLibraryPlayback(cause: .timer)
        }
        RunLoop.main.add(timer, forMode: .common)
        autoSwitchTimer = timer
    }

    func startAutoSwitchTimer() {
        rescheduleLibraryRotationTimer()
    }

    // 销毁 timer
    func stopAutoSwitchTimer() {
        libraryRotationDeadline.configure(now: CACurrentMediaTime(), interval: libraryRotationInterval,
            eligible: libraryRotationEligible)
        autoSwitchTimer?.invalidate()
        autoSwitchTimer = nil
    }



    // All policy callers preserve the current session budget.
    func refreshAutoSwitchTimerIfNeeded() {
        rescheduleLibraryRotationTimer()
    }

    func syncAutoSwitchPlaybackPolicy() {
        // 只管 timer，不动引擎，不重载视频。
        refreshAutoSwitchTimerIfNeeded()
    }

    func setLoopPlaybackEnabled(_ enabled: Bool) {
        // 三种播放模式互斥，开启一个模式时会自动清理其它模式。
        if enabled {
            applyPlaybackMode(.loop)
        } else {
            // 循环关闭时自动切换到顺序播放，保证始终有一个播放模式可用。
            applyPlaybackMode(.sequential)
        }
        syncAutoSwitchPlaybackPolicy()
    }

    func setRandomPlaybackEnabled(_ enabled: Bool) {
        applyPlaybackMode(enabled ? .random : settings.loopPlayback ? .loop : .sequential)
        // Settings preserve elapsed display time in the shared deadline.
        startAutoSwitchTimer()
    }

    func setSequentialPlaybackEnabled(_ enabled: Bool) {
        applyPlaybackMode(enabled ? .sequential : settings.randomPlayback ? .random : settings.loopPlayback ? .loop : .sequential)
        // Settings preserve elapsed display time in the shared deadline.
        startAutoSwitchTimer()
    }

    func normalizePlaybackSettings() {
        // 启动/导入/重置后都先归一化播放模式，避免 settings 带着非法组合进入引擎。
        applyPlaybackMode(playbackMode())
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

    func shouldLoopCurrentItemInEngine(settings source: WallpaperSettings? = nil) -> Bool {
        // 循环模式：始终循环。
        // 自动切换开启的顺序/随机模式：视频循环，等 timer 到期再切换。
        // 自动切换关闭的顺序/随机模式：不循环，视频播完由 handlePlaybackEnded 切下一张。
        // sink 差分投影必须传 newSettings：willSet 期读 self.settings 是旧值。
        let settings = source ?? self.settings
        let switchingMode = settings.randomPlayback || settings.sequentialPlayback
        return settings.loopPlayback || (settings.autoSwitchEnabled && switchingMode)
    }

    func applyPlaybackMode(_ mode: PlaybackMode) {
        // 一次发布有效组合；顺序/随机沿用当前间隔，循环停止跨项轮换。
        var next = settings
        next.loopPlayback = mode == .loop
        next.randomPlayback = mode == .random
        next.sequentialPlayback = mode == .sequential
        next.autoSwitchEnabled = mode != .loop
        settings = next
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
        case .previous, .next:
            // 上一张/下一张由 App 装配层（MyWallpaperXApplication 的热键
            // handler）拦截并交给跨引擎导航器；本分支不再是产品路径，
            // 也不保留旧的"仅视频库"行为作为静默回退。
            break
        case .playPause:
            let command: WallpaperEngineCommand =
                PlaybackCommandMultiplexer.shared.pauseSnapshot.isUserPaused ? .resume : .pause
            PlaybackCommandMultiplexer.shared.dispatch(command)
            isPlaying = playbackSwitch.committed.map { $0.ticket.runtime != .systemStill } == true
                && !PlaybackCommandMultiplexer.shared.pauseSnapshot.isPaused
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
                // 注册/注销失败必须留痕：静默吞掉会让面板与系统登录项
                // 状态永久漂移且无从排查。
                let failedOperation = settings.startOnBoot ? "register" : "unregister"
#if DEBUG
                NSLog(
                    "MWX LoginItem: SMAppService %@ failed: %@",
                    failedOperation,
                    String(describing: error)
                )
#endif
                // 失败后把 startOnBoot 回写为系统真实注册状态：不落盘
                // 未生效的期望值，持久化与 SMAppService 保持一致，面板
                // 回填不再和系统脱节。回写经 $settings sink 自动落盘。
                let systemEnabled = SMAppService.mainApp.status == .enabled
                if settings.startOnBoot != systemEnabled {
                    settings.startOnBoot = systemEnabled
                }
                // 错误回传 UI：设置面板监听该通知呈现失败原因，开关弹回
                // 时用户能看到为什么。userInfo：operation（register/
                // unregister）、error（NSError）。
                NotificationCenter.default.post(
                    name: .wallpaperManagerLoginItemSyncFailed,
                    object: self,
                    userInfo: [
                        "operation": failedOperation,
                        "error": error as NSError
                    ]
                )
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

    /// 启动期一次性播种：音量、速率和频谱在任何 play/web/scene 播种之前
    /// 就位，避免上次运行时为 web/scene 时新会话拿到默认 0.5/1.0。
    /// 音量要同时落 PlaybackVolumeState（scene replay 读它）和引擎
    /// currentVolumeNormalized（web runtimeState 播种读它）。
    /// 同时建立 sink 差分投影的基线（订阅发生在 init 更晚处）。
    func seedEngineProjectionFromPersistedSettings() {
        let persistedVolume = Float(min(max(settings.volume, 0), 100))
        PlaybackVolumeState.shared.setNormalizedVolume(persistedVolume / 100)
        WallpaperEngine.shared.setVolume(persistedVolume)
        applyPlaybackRateToEngine(settings: settings)
        applySystemAudioSpectrumToEngine(settings: settings)
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

        if previous?.videoFillMode != next.videoFillMode {
            WallpaperEngine.shared.setFillMode(next.videoFillMode.ipcValue)
        }
    }

    /// 播放模式/自动切换 → 引擎 loop 策略的单点投影。video daemon 是
    /// "循环当前项"的唯一消费者；web/scene 没有"播完"语义，不下发。
    func projectLoopPolicyToEngine(settings source: WallpaperSettings? = nil) {
        guard activeWallpaperRuntime == .video else { return }
        WallpaperEngine.shared.setLoopCurrentItem(
            shouldLoopCurrentItemInEngine(settings: source)
        )
    }
}

extension Notification.Name {
    /// SMAppService register/unregister 失败时由 updateLoginItemStatus()
    /// 发出，供设置面板向用户呈现失败原因。userInfo：operation
    /// （"register"/"unregister"）、error（NSError）。
    static let wallpaperManagerLoginItemSyncFailed = Notification.Name(
        "WallpaperManagerLoginItemSyncFailed"
    )
}
