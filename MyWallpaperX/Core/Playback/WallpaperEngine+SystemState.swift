//
//  WallpaperEngine+SystemState.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import CoreGraphics
import IOKit
import IOKit.pwr_mgt
import IOKit.ps

extension WallpaperEngine {
    // System-state bridge for playback control.
    // Keep this file focused on macOS notifications, live system queries, and the single pause/resume decision path.

    func requestPlaybackStateEvaluation(immediate: Bool = false, delay: TimeInterval = 0.08) {
        let now = CACurrentMediaTime()
        let requestedDelay = immediate ? 0 : max(0, delay)
        let throttleDelay = max(0, playbackStateEvaluationMinInterval - (now - lastPlaybackStateEvaluationAt))
        let effectiveDelay = max(requestedDelay, throttleDelay)
        let targetDeadline = now + effectiveDelay

        if let existingDeadline = pendingPlaybackStateRefreshDeadline, existingDeadline <= targetDeadline {
            return
        }

        pendingPlaybackStateRefreshWorkItem?.cancel()
        pendingPlaybackStateRefreshWorkItem = nil
        pendingPlaybackStateRefreshDeadline = nil

        if effectiveDelay <= 0 {
            performPlaybackStateEvaluation()
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.performPlaybackStateEvaluation()
        }
        pendingPlaybackStateRefreshWorkItem = workItem
        pendingPlaybackStateRefreshDeadline = targetDeadline
        DispatchQueue.main.asyncAfter(deadline: .now() + effectiveDelay, execute: workItem)
    }

    private func performPlaybackStateEvaluation() {
        // All deferred notifications converge here before the canonical state tree runs.
        pendingPlaybackStateRefreshWorkItem = nil
        pendingPlaybackStateRefreshDeadline = nil
        lastPlaybackStateEvaluationAt = CACurrentMediaTime()
        checkAndUpdatePlaybackState()
    }

    func setupNotifications() {
        // Do not add alternate pause/resume paths in UI code.
        // Every event here is expected to flow into the same evaluator.
        DistributedNotificationCenter.default.addObserver(self, selector: #selector(handleScreenLocked), name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default.addObserver(self, selector: #selector(handleScreenUnlocked), name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleScreensDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleScreensDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeSpaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(powerStatusChanged), name: Notification.Name("NSWorkspacePowerSourceChangedNotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(powerStatusChanged), name: Notification.Name.NSProcessInfoPowerStateDidChange, object: ProcessInfo.processInfo)
    }

    @objc func powerStatusChanged() {
        if Thread.isMainThread {
            handlePowerStatusChangeOnMain()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.handlePowerStatusChangeOnMain()
            }
        }
    }

    func handlePowerStatusChangeOnMain() {
        let onBattery = readBatteryState()
        let lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        let batteryStateChanged = onBattery.map { lastObservedOnBattery != $0 } ?? false
        let lowPowerModeChanged = lastObservedLowPowerMode != lowPowerMode
        if let onBattery {
            lastObservedOnBattery = onBattery
        }
        lastObservedLowPowerMode = lowPowerMode
        guard batteryStateChanged || lowPowerModeChanged else { return }
        requestPlaybackStateEvaluation(immediate: true)
    }

    @objc func handleScreenParametersChanged() {
        scanDisplays()
        invalidateFullscreenSpaceCache()

        guard let currentWallpaper else { return }

        applyWallpaper(
            currentWallpaper,
            multiDisplayEnabled: currentMultiDisplayEnabled,
            videoFillMode: currentVideoFillMode,
            shouldLoopCurrentItem: currentShouldLoopCurrentItem,
            pauseWhenOtherAppFocused: pauseWhenOtherAppFocused,
            pauseWhenOtherAppFullscreen: pauseWhenOtherAppFullscreen,
            pauseWhenUnplugged: pauseWhenUnplugged,
            pauseWhenIdle: pauseWhenIdle,
            idleTimeoutMinutes: idleTimeoutMinutes
        )
    }

    @objc func activeApplicationChanged() {
        guard !screenLocked else { return }
        guard pauseWhenOtherAppFocused else { return }
        requestPlaybackStateEvaluation()
    }

    @objc func activeSpaceChanged() {
        guard !screenLocked else { return }
        guard pauseWhenOtherAppFullscreen else { return }
        // Mission Control / Space animation is noisy; a short suppression window avoids double evaluations.
        suppressFullscreenPauseUntil = CACurrentMediaTime() + 0.35
        invalidateFullscreenSpaceCache()
        requestPlaybackStateEvaluation(delay: 0.36)
    }

    func refreshPowerStateFallbackMonitoring() {
        if pauseWhenUnplugged {
            if powerStateFallbackTimer == nil {
                let timer = DispatchSource.makeTimerSource(queue: .main)
                timer.schedule(deadline: .now() + 1.0, repeating: 2.0, leeway: .milliseconds(300))
                timer.setEventHandler { [weak self] in
                    guard let self else { return }
                    guard let onBattery = self.readBatteryState() else { return }
                    if self.lastObservedOnBattery != onBattery {
                        self.lastObservedOnBattery = onBattery
                        self.requestPlaybackStateEvaluation(immediate: true)
                    }
                }
                powerStateFallbackTimer = timer
                timer.resume()
            }
        } else {
            powerStateFallbackTimer?.cancel()
            powerStateFallbackTimer = nil
            lastObservedOnBattery = nil
        }
    }

    func checkAndUpdatePlaybackState() {
        // Canonical pause/resume decision tree.
        // Hard-stop states first, then user policies, then normal resume.
        let wallpaperHidden = isWallpaperHidden()
        visibilityReductionActive = !playbackPaused && wallpaperHidden

        var shouldPause = screenLocked || systemSleeping || displaysSleeping || wallpaperHidden

        if !shouldPause && pauseWhenOtherAppFocused && !isFrontmostAppAllowed() {
            shouldPause = true
        }

        if !shouldPause
            && pauseWhenOtherAppFullscreen
            && CACurrentMediaTime() >= suppressFullscreenPauseUntil
            && shouldEvaluateFullscreenSpacePause()
            && isOtherAppFullscreenSpaceActive() {
            shouldPause = true
        }

        if !shouldPause && pauseWhenUnplugged && isRunningOnBattery() {
            shouldPause = true
        }

        if !shouldPause
            && currentPlaybackContentKind == .web
            && ProcessInfo.processInfo.isLowPowerModeEnabled {
            shouldPause = true
        }

        if !shouldPause && pauseWhenIdle && idleMonitorReady && isSystemIdlePastThreshold() {
            shouldPause = true
        }

        if shouldPause {
            applySystemPlaybackPausedState(true)
        } else {
            applySystemPlaybackPausedState(false)
        }

        updatePerformanceMode()
    }

    func isOtherAppFullscreenSpaceActive() -> Bool {
        let now = CACurrentMediaTime()
        if let cached = lastFullscreenSpaceState,
           now - lastFullscreenSpaceStateAt <= fullscreenSpaceStateCacheTTL {
            return cached
        }
        let state = isOtherAppFullscreenSpaceActiveViaSpaceAPI() ?? false
        lastFullscreenSpaceState = state
        lastFullscreenSpaceStateAt = now
        return state
    }

    func isOtherAppFullscreenSpaceActiveViaSpaceAPI() -> Bool? {
        // Best-effort private Space lookup.
        // If Apple changes this structure, callers should still fail safely via the nil fallback.
        let connection = CGSMainConnectionID()
        guard let displaySpaces = CGSCopyManagedDisplaySpaces(connection) as? [[String: Any]] else {
            return nil
        }

        for displayInfo in displaySpaces {
            if let currentSpace = displayInfo["Current Space"] as? [String: Any],
               isFullscreenSpaceDictionary(currentSpace) {
                return true
            }

            guard let spaces = displayInfo["Spaces"] as? [[String: Any]],
                  let currentSpace = displayInfo["Current Space"] as? [String: Any],
                  let currentSpaceID = intValue(from: currentSpace["ManagedSpaceID"]) else {
                continue
            }

            guard let matchedSpace = spaces.first(where: { intValue(from: $0["ManagedSpaceID"]) == currentSpaceID }) else {
                continue
            }

            if isFullscreenSpaceDictionary(matchedSpace) {
                return true
            }
        }

        return false
    }

    func intValue(from value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    func isFullscreenSpaceDictionary(_ space: [String: Any]) -> Bool {
        let spaceType = intValue(from: space["type"]) ?? intValue(from: space["Type"])
        if spaceType == 4 {
            return true
        }

        if space["TileLayoutManager"] != nil && space["WallSpace"] != nil {
            return true
        }

        if space["fs_wid"] != nil {
            return true
        }

        return false
    }

    func isWallpaperHidden() -> Bool {
        // Placeholder hook for visibility-based pause logic.
        // Returning false keeps the current product behavior as a no-op.
        false
    }

    func isFrontmostAppAllowed() -> Bool {
        let frontApp = NSWorkspace.shared.frontmostApplication
        guard let bundleIdentifier = frontApp?.bundleIdentifier else { return true }

        if frontApp?.activationPolicy != .regular {
            return true
        }

        var allowedBundleIDs = Set([
            "com.apple.finder",
            "com.apple.dock",
            "com.apple.SystemUIServer",
            "com.apple.controlcenter"
        ])
        if let appBundleID = Bundle.main.bundleIdentifier {
            allowedBundleIDs.insert(appBundleID)
        }
        return allowedBundleIDs.contains(bundleIdentifier)
    }

    func shouldEvaluateFullscreenSpacePause() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return true }
        return frontApp.activationPolicy == .regular
    }

    func updatePerformanceMode() {
        let reduce = visibilityReductionActive && pauseWhenOtherAppFocused
        if reduce != reducedPerformanceMode {
            reducedPerformanceMode = reduce
            targetPlaybackRate = visibilityReductionActive ? 0.75 : 1.0
            // 只在未暂停状态下发 resume，避免覆盖 checkAndUpdatePlaybackState 刚刚执行的 pause。
            guard !playbackPaused else { return }
            for session in displaySessions.values where session.process.isRunning {
                send(DaemonCommand(action: "resume", videoPath: nil, framePath: nil, webRootPath: nil, propertiesJSON: nil, fillMode: nil, shouldLoopCurrentItem: nil, volume: nil, playbackRate: targetPlaybackRate, spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: nil), to: session)
            }
        }
    }

    func invalidateFullscreenSpaceCache() {
        lastFullscreenSpaceState = nil
        lastFullscreenSpaceStateAt = 0
    }

    func isRunningOnBattery() -> Bool {
        // Cached policy gate, not a live UI status query.
        if let observed = lastObservedOnBattery {
            return observed
        }
        guard let onBattery = readBatteryState() else {
            // 电源状态未知时不误判为电池，避免“未开启该开关也被暂停”。
            return false
        }
        lastObservedOnBattery = onBattery
        return onBattery
    }

    private func readBatteryState() -> Bool? {
        // Low-level power-source probe.
        // Unknown states return nil so policy logic can avoid false-positive pauses.
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return nil
        }

        guard let powerSourceType = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? else {
            return nil
        }

        if powerSourceType == kIOPMBatteryPowerKey {
            return true
        }
        if powerSourceType == kIOPMACPowerKey {
            return false
        }
        return nil
    }

    func isSystemIdlePastThreshold() -> Bool {
        // CGEventSource 在无辅助功能权限或沙盒下可能返回极大值（inf / 数千秒），
        // 需要做合法性保护：超过 24 小时视为无效，直接返回 false 避免误暂停。
        let idleSeconds = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .null)
        guard idleSeconds.isFinite, idleSeconds >= 0, idleSeconds < 86400 else { return false }
        let timeoutInterval = Double(max(1, idleTimeoutMinutes) * 60)
        return idleSeconds >= timeoutInterval
    }

    func refreshIdleMonitoring() {
        // 开启空闲暂停时启动轮询定时器，关闭时销毁，避免无用的后台唤醒。
        if pauseWhenIdle {
            if idleMonitorTimer == nil {
                idleMonitorReady = false  // 重置，等待定时器首次触发后才允许评估
                let timer = DispatchSource.makeTimerSource(queue: .main)
                // 首次触发延迟与超时时长一致，避免开启开关瞬间误判为空闲并立即暂停。
                // 之后每 30 秒轮询一次，粒度足够且不影响性能。
                let firstDelay = Double(max(1, idleTimeoutMinutes)) * 60.0
                timer.schedule(deadline: .now() + firstDelay, repeating: 30.0, leeway: .seconds(5))
                timer.setEventHandler { [weak self] in
                    guard let self else { return }
                    self.idleMonitorReady = true
                    self.requestPlaybackStateEvaluation()
                }
                idleMonitorTimer = timer
                timer.resume()
            }
        } else {
            idleMonitorTimer?.cancel()
            idleMonitorTimer = nil
            idleMonitorReady = false
        }
    }
}
