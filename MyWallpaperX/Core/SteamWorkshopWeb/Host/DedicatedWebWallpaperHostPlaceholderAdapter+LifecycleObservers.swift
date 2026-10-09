import Foundation
import AppKit

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func installLifecycleObservers() {
        removeLifecycleObservers()
        let appCenter = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        lifecycleObservers = [
            (
                workspaceCenter,
                workspaceCenter.addObserver(
                    forName: NSWorkspace.activeSpaceDidChangeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.handleActiveSpaceDidChange()
                }
            ),
            (
                appCenter,
                appCenter.addObserver(
                    forName: NSApplication.didBecomeActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.handleAppActivationChanged()
                }
            ),
            (
                appCenter,
                appCenter.addObserver(
                    forName: NSApplication.didResignActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.handleAppActivationChanged()
                }
            ),
            (
                appCenter,
                appCenter.addObserver(
                    forName: NSApplication.didChangeScreenParametersNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.scheduleScreenReconciliation()
                }
            )
        ]
    }

    func removeLifecycleObservers() {
        screenReconciliationWorkItem?.cancel()
        screenReconciliationWorkItem = nil
        lifecycleObservers.forEach { observer in
            observer.center.removeObserver(observer.token)
        }
        lifecycleObservers.removeAll()
    }

    func scheduleScreenReconciliation() {
        recordDiagnostic(
            type: "lifecycle.screen.observed",
            severity: .info,
            message: "phase=\(phase.rawValue)",
            screenID: nil,
            url: nil
        )
        guard currentRequest != nil else { return }
        screenReconciliationWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let request = self.currentRequest else { return }
            self.reconcileDisplaySurfaces(for: request)
            self.recordDiagnostic(
                type: "lifecycle.screen.reconciled",
                severity: .info,
                message: "surfaces=\(self.surfaces.count)",
                screenID: nil,
                url: nil
            )
        }
        screenReconciliationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    func handleActiveSpaceDidChange() {
        recordDiagnostic(
            type: "lifecycle.space.observed",
            severity: .info,
            message: "phase=\(phase.rawValue)",
            screenID: nil,
            url: nil
        )
        guard phase == .ready else { return }
        reassertSurfaceVisibilityAndRuntimeState(orderFront: true)
        recordDiagnostic(
            type: "lifecycle.space.reasserted",
            severity: .info,
            message: "surfaces=\(surfaces.count)",
            screenID: nil,
            url: nil
        )
    }

    func handleAppActivationChanged() {
        guard phase == .ready else { return }
        reassertSurfaceVisibilityAndRuntimeState(orderFront: false)
    }

    func reassertSurfaceVisibilityAndRuntimeState(orderFront: Bool) {
        for surface in surfaces.values {
            surface.window.collectionBehavior = Self.webWindowCollectionBehavior
            surface.window.level = Self.webWindowLevel
            if orderFront || !surface.window.isVisible {
                surface.window.orderFrontRegardless()
            }
            setTransientMouseCaptureEnabled(false, for: surface)
        }
        // 空间切换/应用激活只需「确保转发在跑」（NSEvent monitor 不随空间
        // 失效）：经幂等入口，全运行零副作用；半态在此自愈。
        startSyntheticInputForwardingIfNeeded()
    }
}
