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

    /// 主框架导航决策的唯一权威。壁纸页面唯一入口由宿主装载
    /// （loadTrackedNavigation、恢复重载）：入口之后的主框架跨文档导航一律取消，
    /// 瞬态鼠标捕获放行的 a[href] 点击和页面 JS 的 location 外跳都不允许把桌面
    /// 页面替换成外部网页；用户点击的 http(s) 外链转交系统浏览器，但宿主自己的
    /// loopback 资源面（http://127.0.0.1:<port>/mwx-<token>/）不是外链——项目内部
    /// 链接在 httpLoopback 档解析到该 origin，必须取消且不得拉起浏览器。
    /// 子框架导航属于页面内容，同文档（仅 fragment 差异）导航无法离开当前文档，
    /// 均放行。
    ///
    /// 纯函数形式：输入只有导航上下文，便于 DEBUG harness 直接驱动全部分支。
    enum NavigationDecision: Equatable {
        case allow
        /// 取消：内部链接点击、页面 JS 外跳、缺失目标。reason 落
        /// navigation.blocked 诊断与 WebView 侧通道。
        case cancel(reason: String)
        /// 用户点击的 http(s) 外链：取消当前导航并转交系统浏览器。
        case handoffExternal(URL)
    }

    static func navigationDecision(
        targetURL: URL?,
        currentURL: URL?,
        isMainFrame: Bool,
        isReload: Bool,
        isLinkActivated: Bool
    ) -> NavigationDecision {
        if !isMainFrame {
            return .allow
        }
        guard let currentURL else {
            // 宿主首载：webView.url 尚未建立，属于入口装载。
            return .allow
        }
        if isReload {
            return .allow
        }
        guard let targetURL else {
            return .cancel(reason: "missing_target")
        }
        if isSameDocumentNavigation(target: targetURL, current: currentURL) {
            return .allow
        }
        if isLinkActivated,
           let scheme = targetURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            guard !isLoopbackHost(targetURL.host) else {
                return .cancel(reason: "internal_link_cancelled")
            }
            return .handoffExternal(targetURL)
        }
        return .cancel(reason: isLinkActivated ? "link_navigation_cancelled" : "in_page_navigation_cancelled")
    }

    /// 环回主机（含 IPv6 与 localhost 别名）永不属于用户外链：命中的 http(s)
    /// 目标一律按内部资源取消，绝不转交系统浏览器。
    static func isLoopbackHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        if host == "localhost" || host == "::1" { return true }
        return host.hasPrefix("127.")
    }

    func navigationPolicy(for navigationAction: WKNavigationAction, webView: WKWebView) -> WKNavigationActionPolicy {
        let decision = Self.navigationDecision(
            targetURL: navigationAction.request.url,
            currentURL: webView.url,
            // WKNavigationAction.targetFrame 是 WKFrameInfo?：仅子框架满足
            // `isMainFrame == false`；nil（新窗口导航）与主框架同走取消判定，
            // 不允许在桌面另开外部网页窗口。
            isMainFrame: navigationAction.targetFrame?.isMainFrame != false,
            isReload: navigationAction.navigationType == .reload,
            isLinkActivated: navigationAction.navigationType == .linkActivated
        )
        publishNavigationDecision(decision, targetURL: navigationAction.request.url, webView: webView)
        switch decision {
        case .allow:
            return .allow
        case .cancel, .handoffExternal:
            return .cancel
        }
    }

    /// 策略落地后的诊断与 WebView 侧通道：阻断事实同时落宿主诊断与页面
    /// （window.__mwxNavigationState），页面/探针可各自取证。
    private func publishNavigationDecision(_ decision: NavigationDecision, targetURL: URL?, webView: WKWebView) {
        switch decision {
        case .allow:
            return
        case let .handoffExternal(url):
            recordDiagnostic(
                type: "navigation.blocked",
                severity: .info,
                message: "link_handoff",
                screenID: screenID(for: webView),
                url: url.absoluteString
            )
            publishNavigationBlockedToWebView(url: url, reason: "link_handoff", webView: webView)
            NSWorkspace.shared.open(url)
        case let .cancel(reason):
            recordDiagnostic(
                type: "navigation.blocked",
                severity: .info,
                message: reason,
                screenID: screenID(for: webView),
                url: targetURL?.absoluteString
            )
            publishNavigationBlockedToWebView(url: targetURL, reason: reason, webView: webView)
        }
    }

    /// navigation.blocked 的 WebView 侧可查询通道：把阻断事实写进当前文档
    /// （webNavigationStateScript 注入的 __mwxNavigationBlocked）。取消导航不会
    /// 更换文档，页面 JS 上下文仍在原处；写入失败（文档已销毁）按诊断缺失处理。
    private func publishNavigationBlockedToWebView(url: URL?, reason: String, webView: WKWebView) {
        let urlLiteral = url.map { WebWallpaperHostSupport.javaScriptQuotedString($0.absoluteString) } ?? "null"
        let reasonLiteral = WebWallpaperHostSupport.javaScriptQuotedString(reason)
        let script = "window.__mwxNavigationBlocked && window.__mwxNavigationBlocked({ url: \(urlLiteral), reason: \(reasonLiteral) });"
        webView.evaluateJavaScript(script) { _, _ in }
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
        // D5：主导航开始即撤销该 webView 全部 endpoint——旧文档的 endpoint 不
        // 得接收新文档的推送；新文档由注入脚本重新 hello 登记。
        frameEndpointRegistry.revokeAll(in: webView)
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
        // D5：进程终止即撤销 endpoint（终止后所有 frame 身份失效；恢复重载的
        // 新文档经注入脚本重新 hello）。
        frameEndpointRegistry.revokeAll(in: webView)
        handleWebContentTermination(for: webView)
    }

    /// WebContent 恢复预算的唯一判定（纯函数）：没有终止记录，或上次终止已
    /// 超出冷却窗，才允许再付一次恢复预算；窗内的再次终止直接 fail-fast。
    static func allowsWebContentRecovery(lastTerminationAt: TimeInterval?, now: TimeInterval) -> Bool {
        guard let lastTerminationAt else { return true }
        return now - lastTerminationAt >= webContentRecoveryCoolingWindow
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

        // 恢复预算按冷却窗判定：窗内的再次终止即 fail-fast（防 WebContent
        // 崩溃循环），冷却窗之外的独立终止重新武装——长跑壁纸被 jetsam 回收
        // 不应因为"这辈子已经恢复过一次"而永久拆屏停摆。
        let now = ProcessInfo.processInfo.systemUptime
        guard Self.allowsWebContentRecovery(
            lastTerminationAt: lastWebContentTerminationAtByScreen[screenID],
            now: now
        ) else {
            failWebContentRecovery(
                for: screenID,
                message: "WKWebView content process terminated again within the recovery cooling window"
            )
            return
        }

        webContentRecoveryAttemptsByScreen[screenID] = 1
        lastWebContentTerminationAtByScreen[screenID] = now
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
        // 恢复成功即重新武装：本次终止时刻留在冷却窗记录里，窗内的下一次终止
        // 仍 fail-fast；窗外的终止按独立事件重新获得一次恢复预算。
        let consumedBudget = webContentRecoveryAttemptsByScreen[screenID] ?? 0
        webContentRecoveryAttemptsByScreen[screenID] = 0
        recordDiagnostic(
            type: "webcontent.recovery.succeeded",
            severity: .info,
            message: "Reloaded terminated display (attempts \(consumedBudget) reset to 0); budget re-arms beyond the \(Int(Self.webContentRecoveryCoolingWindow))s cooling window",
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
            lastWebContentTerminationAtByScreen.removeValue(forKey: screenID)
            recoveringWebContentScreenIDs.remove(screenID)
            webContentRecoveryReloadStartedScreenIDs.remove(screenID)
            return
        }
        for workItem in webContentRecoveryWorkItems.values {
            workItem.cancel()
        }
        webContentRecoveryWorkItems.removeAll()
        webContentRecoveryAttemptsByScreen.removeAll()
        lastWebContentTerminationAtByScreen.removeAll()
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
