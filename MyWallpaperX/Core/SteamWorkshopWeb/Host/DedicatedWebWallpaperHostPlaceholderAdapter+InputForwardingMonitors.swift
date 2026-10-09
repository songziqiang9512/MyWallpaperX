import AppKit
import Foundation

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func startSyntheticInputForwardingIfNeeded() {
        // 转发是全局监听而非每页资源；dom.ready/didFinish/空间切换/应用
        // 激活都会调到这里。全运行时跳过——重启会取消其他屏在途的已承认
        // 桌面手势、清全局悬停态并重开 0.45s 预热窗（窗口内 down/up 全被
        // 吞，页面 captureTarget 卡死到下次 pointerdown）。半态（一侧
        // monitor 缺失）属于异常态，全量重启自愈——重启副作用只在异常态
        // 付出。
        let localRunning = localMouseMonitor != nil
        let globalRunning = globalMouseMonitor != nil
        if localRunning && globalRunning { return }
        startGlobalMouseForwarding()
    }

    func startGlobalMouseForwarding() {
        stopGlobalMouseForwarding()
        activeInputForwardingStartedAt = ProcessInfo.processInfo.systemUptime
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel]
        ) { [weak self] event in
            self?.forwardMouseEventToWallpaper(event)
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel]
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.forwardMouseEventToWallpaper(event)
            }
        }
        startPointerLocationPolling()
    }

    func stopGlobalMouseForwarding() {
        cancelAdmittedDesktopGestures()
        clearSyntheticHoverState()
        resetDesktopInputEligibilityCache()
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        pointerPollingTimer?.invalidate()
        pointerPollingTimer = nil
        lastPolledMouseLocation = nil
        lastPointerMoveForwardedAt = 0
        activeInputForwardingStartedAt = nil
    }

    func startPointerLocationPolling() {
        pointerPollingTimer?.invalidate()
        lastPolledMouseLocation = nil
        pointerPollingTimer = Timer.scheduledTimer(withTimeInterval: Self.pointerMoveThrottleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.forwardPolledPointerLocationToWallpaper()
            }
        }
        pointerPollingTimer?.tolerance = Self.pointerMoveThrottleInterval * 0.5
    }
}
