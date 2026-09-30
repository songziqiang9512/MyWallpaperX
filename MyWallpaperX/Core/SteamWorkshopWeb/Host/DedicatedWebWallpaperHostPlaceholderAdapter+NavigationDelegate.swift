import Foundation
import AppKit
import WebKit

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    /// WebKit 历史常量 WebKitErrorFrameLoadInterruptedByPolicyChange
    /// （WebKitErrorDomain）：decidePolicyFor 取消导航后 WebKit 报告的帧加载中断。
    private static let webKitFrameLoadInterruptedByPolicyChangeCode = 102

    private static let ignoredNavigationFailureDomains: Set<String> = [
        NSURLErrorDomain,
        WKError.errorDomain,
        "WebKitErrorDomain"
    ]

    private var ignoredNavigationFailureCodes: Set<Int> {
        // NSURLErrorCancelled：在途加载被宿主 stopLoading 或后续导航取代。
        // webKitFrameLoadInterruptedByPolicyChangeCode：navigationPolicy 取消
        // 页面内导航的产物，两者都不构成启动失败。
        [NSURLErrorCancelled, Self.webKitFrameLoadInterruptedByPolicyChangeCode]
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(navigationPolicy(for: navigationAction, webView: webView))
    }

    /// 壁纸页面唯一入口由宿主装载（loadTrackedNavigation、恢复重载）。入口之后的
    /// 主框架跨文档导航一律取消：瞬态鼠标捕获放行的 a[href] 点击和页面 JS 的
    /// location 外跳都不允许把桌面页面替换成外部网页；用户点击的 http(s) 外链
    /// 转交系统浏览器。子框架导航属于页面内容，同文档（仅 fragment 差异）导航
    /// 无法离开当前文档，均放行。
    func navigationPolicy(for navigationAction: WKNavigationAction, webView: WKWebView) -> WKNavigationActionPolicy {
        // 子框架（iframe）导航是页面内容，直接放行；主框架继续走取消判定。
        // WKNavigationAction.targetFrame 是 WKFrameInfo?：仅子框架满足
        // `?isMainFrame == false`；nil（新窗口导航）与主框架同走取消判定，
        // 不允许在桌面另开外部网页窗口。
        if navigationAction.targetFrame?.isMainFrame == false {
            return .allow
        }
        guard let currentURL = webView.url else {
            return .allow
        }
        if navigationAction.navigationType == .reload {
            return .allow
        }
        guard let targetURL = navigationAction.request.url else {
            return .cancel
        }
        if Self.isSameDocumentNavigation(target: targetURL, current: currentURL) {
            return .allow
        }
        let isLinkHandoff = navigationAction.navigationType == .linkActivated
        recordDiagnostic(
            type: "navigation.blocked",
            severity: .info,
            message: isLinkHandoff ? "link_handoff" : "in_page_navigation_cancelled",
            screenID: screenID(for: webView),
            url: targetURL.absoluteString
        )
        if isLinkHandoff,
           let scheme = targetURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(targetURL)
        }
        return .cancel
    }

    static func isSameDocumentNavigation(target: URL, current: URL) -> Bool {
        var targetComponents = URLComponents(url: target, resolvingAgainstBaseURL: false)
        var currentComponents = URLComponents(url: current, resolvingAgainstBaseURL: false)
        targetComponents?.fragment = nil
        currentComponents?.fragment = nil
        return targetComponents != nil
            && currentComponents != nil
            && targetComponents?.url == currentComponents?.url
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard let screenID = screenIDForStartedNavigation(navigation, webView: webView) else { return }
        setAudioSpectrumDemand(false, for: screenID)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {}

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let screenID = screenIDForCurrentNavigation(navigation, webView: webView) else { return }
        installDefaultInteractiveRegionsIfNeeded()
        applyCompatibilityState(to: webView, deferDirectorySync: false)
        startSyntheticInputForwardingIfNeeded()
        finishWebContentRecovery(for: screenID, webView: webView)
        recordDiagnostic(type: "navigation.finish", severity: .info, message: "ready", screenID: screenID, url: webView.url?.absoluteString)
        markScreenReady(screenID)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        handleWebContentTermination(for: webView)
    }

    func handleWebContentTermination(for webView: WKWebView) {
        guard let screenID = screenID(for: webView),
              let surface = surfaces[screenID],
              surface.webView === webView,
              let requestID = currentRequest?.id else {
            return
        }
        setAudioSpectrumDemand(false, for: screenID)

        recordDiagnostic(
            type: "webcontent.terminated",
            severity: .warning,
            message: "WKWebView content process terminated",
            screenID: screenID,
            url: webView.url?.absoluteString
        )

        if recoveringWebContentScreenIDs.contains(screenID) {
            guard webContentRecoveryReloadStartedScreenIDs.contains(screenID) else {
                return
            }
            failWebContentRecovery(for: screenID, message: "WKWebView content process terminated again after recovery reload")
            return
        }

        guard webContentRecoveryAttemptsByScreen[screenID, default: 0] == 0 else {
            failWebContentRecovery(for: screenID, message: "WKWebView content process recovery attempts exhausted")
            return
        }

        webContentRecoveryAttemptsByScreen[screenID] = 1
        recoveringWebContentScreenIDs.insert(screenID)
        readyScreenIDs.remove(screenID)
        resetInteractionState(for: screenID)
        recordDiagnostic(
            type: "webcontent.recovery",
            severity: .warning,
            message: "Reloading the terminated display once",
            screenID: screenID,
            url: webView.url?.absoluteString
        )

        webContentRecoveryWorkItems[screenID]?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak webView] in
            guard let self,
                  let webView,
                  self.currentRequest?.id == requestID,
                  self.recoveringWebContentScreenIDs.contains(screenID),
                  let currentSurface = self.surfaces[screenID],
                  currentSurface.webView === webView else {
                return
            }
            self.webContentRecoveryWorkItems.removeValue(forKey: screenID)
            self.webContentRecoveryReloadStartedScreenIDs.insert(screenID)
            guard self.reloadTrackedNavigation(on: currentSurface, requestID: requestID) else {
                self.failWebContentRecovery(
                    for: screenID,
                    message: "WKWebView recovery reload did not create a navigation"
                )
                return
            }
        }
        webContentRecoveryWorkItems[screenID] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    func finishWebContentRecovery(for screenID: CGDirectDisplayID, webView: WKWebView) {
        guard recoveringWebContentScreenIDs.contains(screenID),
              surfaces[screenID]?.webView === webView else {
            return
        }
        webContentRecoveryWorkItems.removeValue(forKey: screenID)?.cancel()
        recoveringWebContentScreenIDs.remove(screenID)
        webContentRecoveryReloadStartedScreenIDs.remove(screenID)
        recordDiagnostic(
            type: "webcontent.recovery.succeeded",
            severity: .info,
            message: "Reloaded terminated display",
            screenID: screenID,
            url: webView.url?.absoluteString
        )
    }

    func failWebContentRecovery(for screenID: CGDirectDisplayID, message: String) {
        recordDiagnostic(
            type: "webcontent.recovery.exhausted",
            severity: .error,
            message: message,
            screenID: screenID,
            url: surfaces[screenID]?.webView.url?.absoluteString
        )
        failCurrentLaunch(message: "dedicated_web_host_webcontent_terminated")
    }

    func resetWebContentRecoveryState(for screenID: CGDirectDisplayID? = nil) {
        if let screenID {
            webContentRecoveryWorkItems.removeValue(forKey: screenID)?.cancel()
            webContentRecoveryAttemptsByScreen.removeValue(forKey: screenID)
            recoveringWebContentScreenIDs.remove(screenID)
            webContentRecoveryReloadStartedScreenIDs.remove(screenID)
            return
        }
        for workItem in webContentRecoveryWorkItems.values {
            workItem.cancel()
        }
        webContentRecoveryWorkItems.removeAll()
        webContentRecoveryAttemptsByScreen.removeAll()
        recoveringWebContentScreenIDs.removeAll()
        webContentRecoveryReloadStartedScreenIDs.removeAll()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error, navigation: navigation, webView: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error, navigation: navigation, webView: webView)
    }

    func handleNavigationFailure(_ error: Error, navigation: WKNavigation?, webView: WKWebView) {
        guard let screenID = screenIDForCurrentNavigation(navigation, webView: webView) else { return }
        let nsError = error as NSError
        if Self.ignoredNavigationFailureDomains.contains(nsError.domain),
           ignoredNavigationFailureCodes.contains(nsError.code) {
            return
        }
        if nsError.domain == WKError.errorDomain,
           nsError.code == WKError.Code.webContentProcessTerminated.rawValue {
            handleWebContentTermination(for: webView)
            return
        }
        if recoveringWebContentScreenIDs.contains(screenID) {
            recordDiagnostic(
                type: "webcontent.recovery.failed",
                severity: .error,
                message: error.localizedDescription,
                screenID: screenID,
                url: webView.url?.absoluteString
            )
        }
        recordDiagnostic(
            type: "navigation.fail",
            severity: .error,
            message: error.localizedDescription,
            screenID: screenID,
            url: webView.url?.absoluteString
        )
        failCurrentLaunch(message: error.localizedDescription)
    }
}
