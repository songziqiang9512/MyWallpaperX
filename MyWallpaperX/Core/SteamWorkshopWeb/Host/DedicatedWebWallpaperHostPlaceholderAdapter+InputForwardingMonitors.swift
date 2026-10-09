import AppKit
import Foundation

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func startSyntheticInputForwardingIfNeeded() {
        // 转发是全局监听而非每页资源；dom.ready/didFinish 每屏每次导航都会
        // 调到这里。已在运行时重启会取消其他屏在途的已承认桌面手势、清全局
        // 悬停态并重开 0.45s 预热窗（窗口内 down/up 全被吞，页面 captureTarget
        // 卡死到下次 pointerdown）——只在未运行时启动。
        guard localMouseMonitor == nil, globalMouseMonitor == nil else { return }
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
