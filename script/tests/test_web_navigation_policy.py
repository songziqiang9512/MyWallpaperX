#!/usr/bin/env python3
"""F02 导航策略：主框架决策全分支 + loopback origin 内部链接不得外拉浏览器。

官方语义取证结论（docs.wallpaperengine.io 公开 web 章节抓取：web/overview、
web/first/gettingstarted、web/customization/properties、web/audio/media、
web/performance、web/api/index、web/debug/debug）没有任何关于主框架导航或链接
外跳的记载，官方行为无法定案，因此保持 cancel 分支并在本用例锁定保守语义：
项目内部链接解析到宿主自己的 loopback origin 时必须取消，绝不转交系统浏览器。
"""

from __future__ import annotations

import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
NAVIGATION_SOURCE = (
    ROOT
    / "MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+NavigationDelegate.swift"
)


class WebNavigationPolicyTests(unittest.TestCase):
    def test_main_frame_decisions_block_loopback_internal_and_handoff_external(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")

        harness = textwrap.dedent(
            r'''
            import AppKit
            import Foundation
            import WebKit

            enum WallpaperEngine {
                struct WebWallpaperLaunchRequest { let id: UUID }
            }

            enum WebRuntimeDiagnosticEvent {
                enum Severity { case info, warning, error }
            }

            /// 产品侧 WebWallpaperHostSupport 只提供 JS 字面量转义；决策测试
            /// 不覆盖转义细节，这里给出等价的保守转义占位。
            enum WebWallpaperHostSupport {
                static func javaScriptQuotedString(_ value: String) -> String {
                    let escaped = value
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"")
                    return "\"\(escaped)\""
                }
            }

            /// 产品类的依赖桩：只补 NavigationDelegate 扩展引用、而产品其他文件
            /// 定义的成员（状态容器、诊断、surface 查询、启动失败上报）。
            final class DedicatedWebWallpaperHostPlaceholderAdapter: NSObject {
                struct HostSurface {
                    let screenID: CGDirectDisplayID
                    let webView: WKWebView
                }

                static let webContentRecoveryCoolingWindow: TimeInterval = 5 * 60

                var surfaces: [CGDirectDisplayID: HostSurface] = [:]
                var currentRequest: WallpaperEngine.WebWallpaperLaunchRequest?
                var webContentRecoveryAttemptsByScreen: [CGDirectDisplayID: Int] = [:]
                var lastWebContentTerminationAtByScreen: [CGDirectDisplayID: TimeInterval] = [:]
                var recoveringWebContentScreenIDs = Set<CGDirectDisplayID>()
                var webContentRecoveryReloadStartedScreenIDs = Set<CGDirectDisplayID>()
                var webContentRecoveryWorkItems: [CGDirectDisplayID: DispatchWorkItem] = [:]
                var readyScreenIDs = Set<CGDirectDisplayID>()
                var launchFailureMessages: [String] = []

                /// D5 定向回包的 endpoint 登记（产品在 WebWallpaperHostTypes.swift
                /// 定义）；主导航开始与进程终止路径只消费 revokeAll。
                final class FrameEndpointRegistryStub {
                    var revokeAllCallCount = 0
                    func revokeAll(in webView: WKWebView) { revokeAllCallCount += 1 }
                }
                var frameEndpointRegistry = FrameEndpointRegistryStub()

                func recordDiagnostic(
                    type: String,
                    severity: WebRuntimeDiagnosticEvent.Severity,
                    message: String,
                    screenID: CGDirectDisplayID?,
                    url: String?
                ) {}

                func screenID(for webView: WKWebView) -> CGDirectDisplayID? { nil }
                func screenIDForStartedNavigation(_ navigation: WKNavigation?, webView: WKWebView) -> CGDirectDisplayID? { nil }
                func screenIDForCurrentNavigation(_ navigation: WKNavigation?, webView: WKWebView) -> CGDirectDisplayID? { nil }
                func setAudioSpectrumDemand(_ active: Bool, for screenID: CGDirectDisplayID) {}
                func installDefaultInteractiveRegionsIfNeeded() {}
                func applyCompatibilityState(to webView: WKWebView, deferDirectorySync: Bool) {}
                func startSyntheticInputForwardingIfNeeded() {}
                func markScreenReady(_ screenID: CGDirectDisplayID) {}
                func resetInteractionState(for screenID: CGDirectDisplayID) {}
                func reloadTrackedNavigation(on surface: HostSurface, requestID: UUID) -> Bool { true }
                func failCurrentLaunch(message: String) { launchFailureMessages.append(message) }
            }

            func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
                guard condition() else {
                    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
                    exit(1)
                }
            }

            typealias Decision = DedicatedWebWallpaperHostPlaceholderAdapter.NavigationDecision

            func decision(
                _ target: String?,
                current: String?,
                isMainFrame: Bool = true,
                isReload: Bool = false,
                isLinkActivated: Bool = true
            ) -> Decision {
                DedicatedWebWallpaperHostPlaceholderAdapter.navigationDecision(
                    targetURL: target.flatMap(URL.init(string:)),
                    currentURL: current.flatMap(URL.init(string:)),
                    isMainFrame: isMainFrame,
                    isReload: isReload,
                    isLinkActivated: isLinkActivated
                )
            }

            @main
            enum Harness {
                static func main() {
                    let entry = "http://127.0.0.1:51820/mwx-token/index.html"
                    let internalPage = "http://127.0.0.1:51820/mwx-token/pages/second.html"
                    let external = "https://example.com/help"

                    // 1) httpLoopback 档的项目内部链接解析到宿主自己的 loopback
                    //    origin：必须按内部资源取消，绝不转交系统浏览器。
                    expect(
                        decision(internalPage, current: entry) == .cancel(reason: "internal_link_cancelled"),
                        "loopback 内部链接必须按内部资源取消"
                    )
                    expect(
                        decision("http://127.0.0.1:9/other", current: entry) == .cancel(reason: "internal_link_cancelled"),
                        "任意环回主机都不得转交系统浏览器"
                    )
                    expect(
                        decision("http://localhost:51820/mwx-token/a.html", current: entry) == .cancel(reason: "internal_link_cancelled"),
                        "localhost 别名按内部资源取消"
                    )
                    expect(
                        decision("http://[::1]:51820/mwx-token/a.html", current: entry) == .cancel(reason: "internal_link_cancelled"),
                        "IPv6 环回按内部资源取消"
                    )

                    // 2) 用户点击的 http(s) 外链：取消当前导航并转交系统浏览器。
                    expect(
                        decision(external, current: entry) == .handoffExternal(URL(string: external)!),
                        "外部 https 点击转交系统浏览器"
                    )
                    let plainHTTP = "http://10.1.2.3/doc"
                    expect(
                        decision(plainHTTP, current: entry) == .handoffExternal(URL(string: plainHTTP)!),
                        "非环回 http 点击同样转交"
                    )

                    // 3) 页面 JS 的 location 外跳不是 linkActivated：只取消，不转交。
                    expect(
                        decision(external, current: entry, isLinkActivated: false) == .cancel(reason: "in_page_navigation_cancelled"),
                        "页面 JS 外跳只取消"
                    )
                    // 4) 非 http(s) 的链接点击（导航探针的自定义 scheme）只取消。
                    expect(
                        decision("mwx-nav-probe:link", current: entry) == .cancel(reason: "link_navigation_cancelled"),
                        "自定义 scheme 点击只取消"
                    )
                    // 5) 子框架导航属于页面内容，放行。
                    expect(
                        decision(external, current: entry, isMainFrame: false) == .allow,
                        "子框架导航放行"
                    )
                    // 6) reload 与同文档（仅 fragment 差异）放行。
                    expect(decision(entry, current: entry, isReload: true) == .allow, "reload 放行")
                    expect(
                        decision(entry + "#section", current: entry, isLinkActivated: false) == .allow,
                        "同文档 fragment 放行"
                    )
                    // 7) query 变化不是同文档导航。
                    expect(
                        decision(entry + "?a=1", current: entry, isLinkActivated: false) == .cancel(reason: "in_page_navigation_cancelled"),
                        "query 变化按跨文档取消"
                    )
                    // 8) 宿主首载（webView.url 尚未建立）与缺失目标。
                    expect(decision(entry, current: nil) == .allow, "宿主首载放行")
                    expect(
                        decision(nil, current: entry) == .cancel(reason: "missing_target"),
                        "缺失目标取消"
                    )

                    // 9) WebContent 恢复预算：无终止记录或已超出冷却窗才给预算，
                    //    窗内的再次终止 fail-fast。
                    let window = DedicatedWebWallpaperHostPlaceholderAdapter.webContentRecoveryCoolingWindow
                    expect(
                        DedicatedWebWallpaperHostPlaceholderAdapter.allowsWebContentRecovery(
                            lastTerminationAt: nil, now: 1_000
                        ),
                        "无终止记录时重新武装"
                    )
                    expect(
                        DedicatedWebWallpaperHostPlaceholderAdapter.allowsWebContentRecovery(
                            lastTerminationAt: 1_000, now: 1_000 + window - 1
                        ) == false,
                        "冷却窗内的再次终止不再给恢复预算"
                    )
                    expect(
                        DedicatedWebWallpaperHostPlaceholderAdapter.allowsWebContentRecovery(
                            lastTerminationAt: 1_000, now: 1_000 + window
                        ),
                        "超出冷却窗的终止重新武装"
                    )

                    print("Web navigation policy tests passed")
                }
            }
            '''
        )

        with tempfile.TemporaryDirectory(prefix="mwx-web-navigation-") as directory:
            harness_path = Path(directory) / "main.swift"
            harness_path.write_text(harness, encoding="utf-8")
            subprocess.run(
                [
                    "swiftc",
                    "-parse-as-library",
                    str(NAVIGATION_SOURCE),
                    "main.swift",
                    "-framework",
                    "AppKit",
                    "-framework",
                    "WebKit",
                    "-o",
                    "WebNavigationPolicyTests",
                ],
                check=True,
                cwd=directory,
                timeout=180,
            )
            subprocess.run(
                ["./WebNavigationPolicyTests"],
                check=True,
                cwd=directory,
                timeout=30,
            )


if __name__ == "__main__":
    unittest.main()
