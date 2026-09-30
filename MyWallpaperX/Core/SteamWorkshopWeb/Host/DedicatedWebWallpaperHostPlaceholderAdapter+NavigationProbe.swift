//
//  DedicatedWebWallpaperHostPlaceholderAdapter+NavigationProbe.swift
//  MyWallpaperX
//

import AppKit
import Foundation
import WebKit

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    /// F02 验证债的 DEBUG-only 运行时探针：仅在启动参数
    /// `--mwx-debug-web-nav-probe` 显式开启时，于页面 ready 后触发两种
    /// 主框架外跳（合成 a[href] 点击 + JS location 赋值），断言
    /// navigation.blocked 诊断事件出现且 webView.url 未变，结果落诊断
    /// 事件。独立 opt-in，不混入常规证据采集；Release 下函数体为空。
    func scheduleWebNavigationProbeIfNeeded() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains(Self.webNavigationProbeArgument) else { return }
        for surface in surfaces.values.sorted(by: { $0.screenID < $1.screenID }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self, weak webView = surface.webView] in
                guard let self,
                      let webView,
                      self.surfaces[surface.screenID]?.webView === webView else {
                    return
                }
                self.runNavigationProbeClickStage(from: webView, screenID: surface.screenID)
            }
        }
        #endif
    }

    #if DEBUG
    private static let webNavigationProbeArgument = "--mwx-debug-web-nav-probe"

    /// 点击探针必须用非 http(s) scheme：linkActivated + http(s) 会被
    /// NavigationDelegate 真转交系统浏览器；自定义 scheme 走同一取消分支
    /// 且不会外拉浏览器。
    private static let navigationProbeClickScript = #"""
    (() => {
      const anchor = document.createElement('a');
      anchor.href = 'mwx-nav-probe:link';
      anchor.style.display = 'none';
      (document.body || document.documentElement).appendChild(anchor);
      anchor.click();
      anchor.remove();
      return 'probe-link-clicked';
    })();
    """#

    /// location 探针用保留 TLD 的 https URL：JS 赋值产生 linkActivated 之外
    /// 的导航类型，取消分支不会转交系统浏览器；.invalid 不可解析，即使
    /// 放行也不会产生真实网络请求。
    private static let navigationProbeLocationScript = #"""
    (() => {
      window.location.href = 'https://mwx-nav-probe.invalid/external';
      return 'probe-location-assigned';
    })();
    """#

    private func runNavigationProbeClickStage(from webView: WKWebView, screenID: CGDirectDisplayID) {
        runNavigationProbeStage(
            "link_click",
            script: Self.navigationProbeClickScript,
            from: webView,
            screenID: screenID
        ) { [weak self, weak webView] in
            guard let self,
                  let webView,
                  self.surfaces[screenID]?.webView === webView else {
                return
            }
            self.runNavigationProbeStage(
                "location_assignment",
                script: Self.navigationProbeLocationScript,
                from: webView,
                screenID: screenID
            )
        }
    }

    /// 单阶段探针：快照基线事件与基线 URL，evaluateJavaScript 触发外跳，
    /// 延时后断言出现新的 navigation.blocked 事件且 webView.url 未变。
    private func runNavigationProbeStage(
        _ stage: String,
        script: String,
        from webView: WKWebView,
        screenID: CGDirectDisplayID,
        continuation: (() -> Void)? = nil
    ) {
        let baselineEventIDs = Set(
            WebRuntimeDiagnosticsStore.shared
                .recentEvents(recordID: currentRequest?.recordID, limit: 500)
                .map(\.id)
        )
        let baselineURL = webView.url
        webView.evaluateJavaScript(script) { [weak self, weak webView] _, error in
            guard let self, let webView else { return }
            if let error {
                self.recordDiagnostic(
                    type: "probe.navigation.fail",
                    severity: .error,
                    message: "stage=\(stage) script_error=\(error.localizedDescription)",
                    screenID: screenID,
                    url: webView.url?.absoluteString
                )
                continuation?()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self, weak webView] in
                guard let self,
                      let webView,
                      self.surfaces[screenID]?.webView === webView else {
                    return
                }
                let newBlockedEvents = WebRuntimeDiagnosticsStore.shared
                    .recentEvents(recordID: self.currentRequest?.recordID, limit: 500)
                    .filter { $0.type == "navigation.blocked" && !baselineEventIDs.contains($0.id) }
                let urlUnchanged = webView.url == baselineURL
                let passed = !newBlockedEvents.isEmpty && urlUnchanged
                self.recordDiagnostic(
                    type: passed ? "probe.navigation.pass" : "probe.navigation.fail",
                    severity: passed ? .info : .error,
                    message: "stage=\(stage) blocked=\(newBlockedEvents.count) urlUnchanged=\(urlUnchanged) messages=[\(newBlockedEvents.map(\.message).joined(separator: ","))]",
                    screenID: screenID,
                    url: webView.url?.absoluteString
                )
                continuation?()
            }
        }
    }
    #endif
}
