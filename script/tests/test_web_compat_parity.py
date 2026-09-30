#!/usr/bin/env python3
"""Web 兼容脚本的行为回归：F01 / F40 / F29 / F19，外加多 frame 注入面边界。

前四条行为此前只有一次性 vm/人工验证，仓库内没有可复跑断言。本用例沿用
`test_web_playback_pause` 的模式：从产品源码提取 `webCompatibilityScript` 与
`applyVolume`，与全部兼容脚本段、内联桩一起用 swiftc 编译成一个 harness 可执行
文件，再由 harness 把脚本注入真实 WKWebView 文档后逐条断言：

- F01：attachShadow 包装器作用域错误令 Shadow DOM 壁纸整页脚本中断。
- F40：DOMContentLoaded 包装器破坏 addEventListener/removeEventListener 同一性。
- F29：宿主音量只对快照节点生效，动态新建的媒体节点以默认音量播放。
- F19：网络代理回填非 UTF-8 响应体时缺少编码标志，fetch/XHR 只能拿到文本。
- frames：兼容脚本按 frame 注入后的边界——同源子 frame 收到宿主推送与宿主回包
  （回包中继），跨源子 frame 判为回包不可达、跨域 XHR 回落原生，dom.ready 唯一、
  子 frame 交互区域登记被丢弃。

各场景由命令行参数选择，一次编译、多次独立执行。F19 的原生 fetch 由
document-start 桩替换为必然失败的 Promise（生产中对应原生 fetch 的跨域失败），
因此整个用例不发出任何真实网络请求；XHR 代理路径在产品侧本就拦截 send()，
同样不发真实请求。frames 场景的跨源子 frame 探针指向 IPv6 环回未监听端口
（连接立即被拒）与宿主的本地内容源，同样不向外部网络发请求。
"""

from pathlib import Path
import base64
import io
import subprocess
import tempfile
import unittest
import wave

from script.tests.test_steam_library_interactions import method

ROOT = Path(__file__).resolve().parents[2]
HARNESS = r'''
import AppKit
import Foundation
import WebKit

enum WallpaperEngine { struct WebWallpaperLaunchRequest { var propertiesJSON: String? } }

enum WebWallpaperHostSupport {
    static func javaScriptQuotedString(_ value: String) -> String {
        String(data: try! JSONEncoder().encode(value), encoding: .utf8)!
    }
}

final class Adapter {
    func applyGeneralProperties(to webView: WKWebView) {}
    // ADAPTER_METHODS
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

/// 网络桥接桩：与 DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge 的
/// 成功回包同形状——响应体统一 base64 + bodyIsBase64 标志 + responseURL。
final class NetworkBridgeStub: NSObject, WKScriptMessageHandler {
    static let primaryBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0xFF, 0xFE, 0x80, 0x7F]
    static let secondaryBytes: [UInt8] = [0x00, 0x10, 0x80, 0xFF, 0x41]
    weak var webView: WKWebView?
    /// 到达宿主网络桥的代理请求数：跨源子 frame 回落原生后这里不应再增长。
    private(set) var receivedRequestCount = 0

    static func hexadecimal(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard
            let body = message.body as? [String: Any],
            let requestID = body["requestID"] as? String,
            let url = body["url"] as? String
        else { return }
        receivedRequestCount += 1
        let bytes = url.contains("secondary") ? Self.secondaryBytes : Self.primaryBytes
        let payload: [String: Any] = [
            "requestID": requestID,
            "ok": true,
            "status": 200,
            "headers": ["content-type": "application/octet-stream"],
            "body": Data(bytes).base64EncodedString(),
            "bodyIsBase64": true,
            "responseURL": url
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let json = String(data: data, encoding: .utf8)
        else { return }
        webView?.evaluateJavaScript(
            "window.__myWallpaperResolveNetworkRequest(\(json));",
            completionHandler: nil
        )
    }
}

/// 兼容脚本的宿主侧观测点：记录 wallpaperHostLog 类型序列与交互区域登记次数，
/// 用于断言多 frame 注入面（dom.ready 唯一、子 frame 登记被丢弃并出诊断）。
final class HostProbeRecorder: NSObject, WKScriptMessageHandler {
    var logTypes: [String] = []
    var interactiveRegionMessageCount = 0

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if message.name == "wallpaperHostInteractiveRegions" {
            interactiveRegionMessageCount += 1
            return
        }
        guard message.name == "wallpaperHostLog", let body = message.body as? [String: Any] else { return }
        logTypes.append(body["type"] as? String ?? "")
    }
}

/// 跨源子 frame 的本地内容源：自定义 scheme 与顶层不同源（因此收不到宿主回包
/// 中继），但仍是正常文档、会收到 document-start 注入——用来验证不可达 frame
/// 的请求回落原生，而不是落进只会等桥超时的代理路径。
final class ProbeChildSchemeHandler: NSObject, WKURLSchemeHandler {
    private let html: String

    init(html: String) {
        self.html = html
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "WebCompatibilityParity", code: 3))
            return
        }
        let body = Data(html.utf8)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "text/html; charset=utf-8",
                "Content-Length": String(body.count)
            ]
        ) else {
            urlSchemeTask.didFailWithError(NSError(domain: "WebCompatibilityParity", code: 3))
            return
        }
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(body)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

@MainActor
final class PageHost {
    let view: WKWebView
    let recorder = HostProbeRecorder()
    /// 方案处理器由配置持有的是弱引用不可依赖：这里显式持有，避免子 frame 加载失败。
    private let crossOriginSchemeHandler: ProbeChildSchemeHandler?
    private let window: NSWindow
    /// 新文档代际哨兵（document-start 注入）：`loadHTMLString` 是异步导航，旧文档
    /// （about:blank）的 readyState 可能已经是 complete，只等 readyState 会在页面
    /// 脚本执行前返回，令断言把"页面脚本还没跑"误判成"页面脚本没执行"。哨兵只由
    /// 新文档的 document-start 脚本写出，因此可精确判定导航已提交。
    private let generationToken: String

    init(
        html: String,
        stubNativeFetch: Bool = false,
        networkStub: NetworkBridgeStub? = nil,
        crossOriginChildHTML: String? = nil
    ) {
        let configuration = WKWebViewConfiguration()
        let generationToken = "mwx-parity-\(UUID().uuidString)"
        self.generationToken = generationToken
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.addUserScript(WKUserScript(
            source: "window.__mwxParityGeneration = '\(generationToken)';",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.add(recorder, name: "wallpaperHostLog")
        configuration.userContentController.add(recorder, name: "wallpaperHostInteractiveRegions")
        if let networkStub = networkStub {
            configuration.userContentController.add(networkStub, name: "wallpaperHostNetworkRequest")
        }
        if let crossOriginChildHTML = crossOriginChildHTML {
            let schemeHandler = ProbeChildSchemeHandler(html: crossOriginChildHTML)
            crossOriginSchemeHandler = schemeHandler
            configuration.setURLSchemeHandler(schemeHandler, forURLScheme: "mwx-probe")
        } else {
            crossOriginSchemeHandler = nil
        }
        if stubNativeFetch {
            // 生产里 fetch 代理的触发点是原生 fetch 的跨域失败；这里用同样必然
            // 失败的桩替换原生 fetch，令用例完全不发真实网络请求。
            configuration.userContentController.addUserScript(WKUserScript(
                source: "window.fetch = function() { return Promise.reject(new TypeError('Load failed')); };",
                injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        configuration.userContentController.addUserScript(WKUserScript(
            source: webWallpaperPlaybackScript.replacingOccurrences(of: "__MWX_INITIAL_PAUSED__", with: "false"),
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        configuration.userContentController.addUserScript(WKUserScript(
            source: Adapter.webCompatibilityScript(for: nil, generalPropertiesJSON: "{}",
                volume: 1, playbackRate: 1, paused: false),
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        view = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 320), configuration: configuration)
        window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.orderFrontRegardless()
        networkStub?.webView = view
        view.loadHTMLString(html, baseURL: nil)
    }

    func script(_ source: String) async throws -> Any {
        try await view.evaluateJavaScript(source) as Any
    }

    func wait(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    func open() async throws {
        // 先等新文档的 document-start 哨兵（导航已提交），再等解析完成。
        try await waitUntil(
            "window.__mwxParityGeneration === '\(generationToken)'",
            label: "document-start injection"
        )
        try await waitUntil("document.readyState === 'complete'", label: "document ready")
    }

    func waitUntil(_ source: String, seconds: Double = 10, label: String) async throws {
        var last: Any?
        var lastError: String?
        for _ in 0..<Int(seconds * 10) {
            do {
                let value = try await script(source)
                if (value as? Bool) == true { return }
                last = value
            } catch {
                lastError = String(describing: error)
            }
            try await wait(0.1)
        }
        throw NSError(domain: "WebCompatibilityParity", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "waiting for \(label); last=\(String(describing: last)) error=\(lastError ?? "none")"
        ])
    }

    func close() { window.orderOut(nil) }
}

@MainActor
enum Scenarios {
    static func run(_ name: String) async throws {
        switch name {
        case "f01": try await shadowRootMediaTakeover()
        case "f40": try await domContentLoadedListenerIdentity()
        case "f29": try await dynamicMediaVolumeBackfill()
        case "f19": try await networkBridgeBinaryRestore()
        case "frames": try await frameInjectionBoundaries()
        default:
            throw NSError(domain: "WebCompatibilityParity", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "unknown scenario: \(name)"
            ])
        }
        print("web-compat-parity-pass: \(name)")
    }

    /// 多 frame 注入面边界：兼容脚本按 frame 注入后，同源子 frame 必须收到宿主
    /// 推送与宿主回包（回包中继），跨源子 frame 收不到中继、其跨域 XHR 必须回落
    /// 原生而不是落进只会等桥超时的代理路径；dom.ready 只由顶层 frame 发出。
    /// 跨源子 frame 的原生回落探针指向 IPv6 环回未监听端口（连接立即被拒），
    /// 用例不向外部网络发出请求。
    static func frameInjectionBoundaries() async throws {
        let sameOriginChildPage = "<html><body><script>"
            + "window.startProxyProbe = function (url) {"
            + "  const xhr = new XMLHttpRequest();"
            + "  xhr.open('GET', url);"
            + "  xhr.send();"
            + "  window.__mwxProxyProbe = { proxied: xhr.__mwx_proxied === true, status: null, length: 0 };"
            + "  xhr.onload = function () {"
            + "    window.__mwxProxyProbe.status = xhr.status;"
            + "    window.__mwxProxyProbe.length = String(xhr.responseText || '').length;"
            + "  };"
            + "  return true;"
            + "};"
            + "</script></body></html>"
        let escapedSameOriginChildPage = sameOriginChildPage
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        let crossOriginChildPage = "<html><body><script>"
            + "(function () {"
            + "  const probe = { reachable: window.__mwxHostReplyReachable === true, proxied: null, proxiedValue: null };"
            + "  try {"
            + "    const xhr = new XMLHttpRequest();"
            + "    xhr.open('GET', 'http://[::1]:9/mwx-probe');"
            + "    xhr.send();"
            + "    probe.proxied = xhr.__mwx_proxied === true;"
            + "    probe.proxiedValue = String(xhr.__mwx_proxied);"
            + "  } catch (error) {"
            + "    probe.proxied = false;"
            + "  }"
            + "  parent.postMessage({ mwxFrameProbe: probe }, '*');"
            + "})();"
            + "</script></body></html>"
        let page = """
        <html><body>
        <iframe id="same-origin" srcdoc="\(escapedSameOriginChildPage)"></iframe>
        <iframe id="cross-origin" src="mwx-probe://child/index.html"></iframe>
        <script>
        window.__mwxFrameProbe = null;
        window.addEventListener('message', function (event) {
          if (event.data && event.data.mwxFrameProbe) { window.__mwxFrameProbe = event.data.mwxFrameProbe; }
        });
        </script>
        </body></html>
        """
        let networkStub = NetworkBridgeStub()
        let host = PageHost(html: page, networkStub: networkStub, crossOriginChildHTML: crossOriginChildPage)
        defer { host.close() }
        try await host.open()
        try await host.waitUntil("frames.length === 2", label: "two child frames")
        _ = try await host.script("window.__myWallpaperApplyProperties({ frameProbe: { value: 'child' } });")
        try await host.waitUntil(
            "frames[0].__myWallpaperLastUserProperties"
            + " && frames[0].__myWallpaperLastUserProperties.frameProbe"
            + " && frames[0].__myWallpaperLastUserProperties.frameProbe.value === 'child'",
            label: "same-origin child property push"
        )
        try await host.waitUntil(
            "typeof frames[0].startProxyProbe === 'function'",
            label: "same-origin child proxy probe ready"
        )
        _ = try await host.script("frames[0].startProxyProbe('https://bridge.example.com/primary')")
        try await host.waitUntil(
            "frames[0].__mwxProxyProbe && frames[0].__mwxProxyProbe.proxied === true"
            + " && frames[0].__mwxProxyProbe.status === 200 && frames[0].__mwxProxyProbe.length > 0",
            label: "same-origin child proxied response"
        )
        let bridgeRequestsAfterSameOrigin = networkStub.receivedRequestCount
        expect(bridgeRequestsAfterSameOrigin >= 1, "同源子 frame 的代理请求未到达宿主网络桥")
        try await host.waitUntil("window.__mwxFrameProbe !== null", label: "cross-origin child probe")
        let crossOriginReachable = try await host.script("window.__mwxFrameProbe.reachable === true") as? Bool
        expect(crossOriginReachable != true, "跨源子 frame 不应被判定为可收到宿主回包")
        let crossOriginProxied = try await host.script("window.__mwxFrameProbe.proxied === true") as? Bool
        expect(crossOriginProxied != true, "跨源子 frame 的跨域 XHR 不应进入宿主代理")
        expect(
            networkStub.receivedRequestCount == bridgeRequestsAfterSameOrigin,
            "跨源子 frame 的请求不应到达宿主网络桥（原生回落）"
        )
        var sawUnsupportedLog = false
        for _ in 0..<50 where !sawUnsupportedLog {
            sawUnsupportedLog = host.recorder.logTypes.contains("host-reply.unsupported")
            if !sawUnsupportedLog { try await host.wait(0.1) }
        }
        expect(sawUnsupportedLog, "跨源子 frame 的回落应记录 host-reply.unsupported")
        let regionMessagesBefore = host.recorder.interactiveRegionMessageCount
        _ = try await host.script("""
        (function () {
          const frame = document.getElementById('same-origin');
          if (frame && frame.contentWindow) {
            frame.contentWindow.__myWallpaperRegisterInteractiveRegions({
              source: 'dom-auto',
              regions: [{ id: 'child-region', x: 0.1, y: 0.1, width: 0.5, height: 0.5 }]
            });
          }
        })();
        """)
        try await host.wait(0.3)
        expect(
            host.recorder.interactiveRegionMessageCount == regionMessagesBefore,
            "子 frame 的交互区域登记不应到达宿主"
        )
        expect(
            host.recorder.logTypes.contains("interactive-regions.subframe-ignored"),
            "子 frame 的交互区域登记被丢弃时应留诊断"
        )
        let domReadyCount = host.recorder.logTypes.filter { $0 == "dom.ready" }.count
        expect(domReadyCount == 1, "dom.ready 应由顶层 frame 唯一发出，实际 \(domReadyCount) 次")
    }

    /// F01：解析期的 attachShadow 必须返回真实 shadow root 且页面脚本继续执行；
    /// 解析后创建的 shadow root 内媒体必须被宿主接管——新增媒体节点上唯一会写
    /// volume 的路径是 attachWallpaperMediaNode，故以宿主音量是否回填为接管证据。
    static func shadowRootMediaTakeover() async throws {
        let page = """
        <html><body>
        <div id="f01-root"></div>
        <script>
        window.__f01 = { attachShadowError: null, shadowRootReceived: false, pageContinued: false };
        class MWXShadowHost extends HTMLElement {
          constructor() {
            super();
            let root = null;
            try {
              root = this.attachShadow({ mode: 'open' });
            } catch (error) {
              window.__f01.attachShadowError = String((error && error.message) || error);
              throw error;
            }
            window.__f01.shadowRootReceived = !!root;
            const audio = document.createElement('audio');
            audio.setAttribute('loop', '');
            audio.src = 'data:audio/wav;base64,__MEDIA__';
            root.appendChild(audio);
          }
        }
        customElements.define('mwx-shadow-host', MWXShadowHost);
        const hostElement = document.createElement('mwx-shadow-host');
        hostElement.id = 'f01-parse-host';
        document.getElementById('f01-root').appendChild(hostElement);
        window.__f01.pageContinued = true;
        </script>
        </body></html>
        """
        let host = PageHost(html: page)
        defer { host.close() }
        try await host.open()
        let attachShadowError = try await host.script(
            "window.__f01.attachShadowError === null ? '' : String(window.__f01.attachShadowError)"
        ) as? String
        expect(attachShadowError == "", "解析期 attachShadow 抛错: \(attachShadowError ?? "nil")")
        let parseFlags = try await host.script(
            "window.__f01.shadowRootReceived === true && window.__f01.pageContinued === true"
        ) as? Bool
        expect(parseFlags == true, "解析期 attachShadow 未返回 shadow root 或页面脚本未继续执行")
        try await host.waitUntil(
            "typeof window.__mwxInstallWallpaperShadowObserver === 'function'",
            label: "shadow observer holder"
        )
        _ = try await host.script("window.__myWallpaperSetGlobalVolume(0.25);")
        try await host.waitUntil(
            "window.__myWallpaperLastHostVolume === 0.25",
            label: "host volume push"
        )
        _ = try await host.script(
            "(() => { const late = document.createElement('mwx-shadow-host'); late.id = 'f01-late-host'; document.getElementById('f01-root').appendChild(late); })();"
        )
        try await host.waitUntil(
            "document.getElementById('f01-late-host').shadowRoot.querySelector('audio').volume === 0.25",
            label: "shadow root media takeover"
        )
    }

    /// F40：DCL 包装器必须保持监听器同一性——fire 前 removeEventListener 后不得
    /// 再回调，同一监听器双注册也只能跑一次。
    static func domContentLoadedListenerIdentity() async throws {
        let page = """
        <html><body>
        <script>
        window.__f40 = { removed: 0, twice: 0, registered: false };
        const removedListener = () => { window.__f40.removed += 1; };
        document.addEventListener('DOMContentLoaded', removedListener);
        document.removeEventListener('DOMContentLoaded', removedListener);
        const duplicateListener = () => { window.__f40.twice += 1; };
        document.addEventListener('DOMContentLoaded', duplicateListener);
        document.addEventListener('DOMContentLoaded', duplicateListener);
        window.__f40.registered = true;
        </script>
        </body></html>
        """
        let host = PageHost(html: page)
        defer { host.close() }
        try await host.open()
        let registered = try await host.script("window.__f40.registered === true") as? Bool
        expect(registered == true, "页面 DCL 注册脚本未执行")
        let removed = try await host.script("window.__f40.removed") as? Int
        let twice = try await host.script("window.__f40.twice") as? Int
        expect(removed == 0, "removeEventListener 未按同一性命中包装监听器，已卸载的回调仍被调用 \(removed ?? -1) 次")
        expect(twice == 1, "同一监听器重复注册被原生去重，实际触发 \(twice ?? -1) 次")
    }

    /// F29：宿主音量置 0 后动态插入的媒体节点必须继承宿主音量，而不是默认音量 1。
    static func dynamicMediaVolumeBackfill() async throws {
        let page = """
        <html><body>
        <div id="f29-root"></div>
        </body></html>
        """
        let host = PageHost(html: page)
        defer { host.close() }
        try await host.open()
        Adapter().applyVolume(0, to: host.view)
        try await host.waitUntil(
            "window.__myWallpaperLastHostVolume === 0",
            label: "host volume 0 push"
        )
        _ = try await host.script("""
        (() => {
          const audio = document.createElement('audio');
          audio.id = 'f29-late-media';
          audio.autoplay = true;
          audio.setAttribute('loop', '');
          audio.src = 'data:audio/wav;base64,__MEDIA__';
          document.getElementById('f29-root').appendChild(audio);
        })();
        """)
        try await host.waitUntil(
            "document.getElementById('f29-late-media') !== null && document.getElementById('f29-late-media').volume === 0",
            label: "dynamic media volume backfill"
        )
    }

    /// F19：桥接回包的 base64 响应体必须按 bodyIsBase64 还原成字节——fetch 的
    /// arrayBuffer 与 XHR 的 responseType='arraybuffer' 都要逐字节一致。
    static func networkBridgeBinaryRestore() async throws {
        let page = """
        <html><body>
        <script>
        window.__f19 = { fetch: null, xhr: null };
        const toHex = (bytes) => Array.from(bytes).map(byte => byte.toString(16).padStart(2, '0')).join('');
        (async () => {
          try {
            const response = await fetch('https://assets.example.com/mwx/primary.bin');
            window.__f19.fetch = {
              status: response.status,
              url: response.url,
              contentType: response.headers.get('content-type'),
              hex: toHex(new Uint8Array(await response.arrayBuffer()))
            };
          } catch (error) {
            window.__f19.fetch = { error: String((error && error.message) || error) };
          }
        })();
        const xhr = new XMLHttpRequest();
        xhr.open('GET', 'https://assets.example.com/mwx/secondary.bin');
        xhr.responseType = 'arraybuffer';
        xhr.onload = () => {
          window.__f19.xhr = {
            status: xhr.status,
            responseURL: xhr.responseURL,
            contentType: xhr.getResponseHeader('Content-Type'),
            hex: toHex(new Uint8Array(xhr.response))
          };
        };
        xhr.onerror = () => { window.__f19.xhr = { error: 'xhr_error' }; };
        xhr.send();
        </script>
        </body></html>
        """
        let stub = NetworkBridgeStub()
        let host = PageHost(html: page, stubNativeFetch: true, networkStub: stub)
        defer { host.close() }
        try await host.open()
        try await host.waitUntil(
            "window.__f19.fetch !== null && window.__f19.xhr !== null",
            label: "proxied fetch and xhr"
        )
        let fetchError = try await host.script("window.__f19.fetch.error ? String(window.__f19.fetch.error) : ''") as? String
        let xhrError = try await host.script("window.__f19.xhr.error ? String(window.__f19.xhr.error) : ''") as? String
        expect(fetchError == "", "fetch 代理失败: \(fetchError ?? "nil")")
        expect(xhrError == "", "XHR 代理失败: \(xhrError ?? "nil")")
        let fetchHex = try await host.script("String(window.__f19.fetch.hex)") as? String
        let xhrHex = try await host.script("String(window.__f19.xhr.hex)") as? String
        expect(
            fetchHex == NetworkBridgeStub.hexadecimal(NetworkBridgeStub.primaryBytes),
            "fetch arrayBuffer 未按 base64 还原字节: \(fetchHex ?? "nil")"
        )
        expect(
            xhrHex == NetworkBridgeStub.hexadecimal(NetworkBridgeStub.secondaryBytes),
            "XHR arrayBuffer 未按 base64 还原字节: \(xhrHex ?? "nil")"
        )
        let fetchURL = try await host.script("String(window.__f19.fetch.url)") as? String
        expect(
            fetchURL == "https://assets.example.com/mwx/primary.bin",
            "fetch Response.url 未回填作者可见 URL: \(fetchURL ?? "nil")"
        )
        let fetchStatus = try await host.script("window.__f19.fetch.status") as? Int
        let xhrStatus = try await host.script("window.__f19.xhr.status") as? Int
        expect(
            fetchStatus == 200 && xhrStatus == 200,
            "代理回包状态码未透传: fetch=\(String(describing: fetchStatus)) xhr=\(String(describing: xhrStatus))"
        )
        let xhrContentType = try await host.script("String(window.__f19.xhr.contentType)") as? String
        expect(
            xhrContentType == "application/octet-stream",
            "XHR getResponseHeader 未透传代理响应头: \(xhrContentType ?? "nil")"
        )
    }
}

@main
enum Harness {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let name = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
        Task { @MainActor in
            do {
                try await Scenarios.run(name)
                exit(0)
            } catch {
                print("web-compat-parity-failed: \(name) \(error)")
                exit(1)
            }
        }
        app.run()
    }
}
'''


class WebCompatibilityParityTests(unittest.TestCase):
    temporary: tempfile.TemporaryDirectory | None = None
    directory: Path | None = None

    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-web-compat-parity-")
        directory = Path(cls.temporary.name)
        host = ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host"
        adapter = method(
            (host / "WebWallpaperHostTypes.swift").read_text(),
            "static func webCompatibilityScript(",
        )
        adapter += "\n" + method(
            (host / "DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift").read_text(),
            "func applyVolume(",
        )
        audio = io.BytesIO()
        with wave.open(audio, "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(1)
            wav.setframerate(8000)
            wav.writeframes(bytes([128]) * 8000)
        harness = HARNESS.replace("// ADAPTER_METHODS", adapter).replace(
            "__MEDIA__", base64.b64encode(audio.getvalue()).decode()
        )
        (directory / "Harness.swift").write_text(harness)
        result = subprocess.run(
            [
                "xcrun",
                "swiftc",
                "-parse-as-library",
                str(host / "WebWallpaperPlaybackScript.swift"),
                *map(str, sorted(host.glob("DedicatedWebWallpaperHostCompatibilityScript+*.swift"))),
                str(directory / "Harness.swift"),
                "-o",
                str(directory / "harness"),
            ],
            capture_output=True,
            text=True,
            timeout=180,
        )
        if result.returncode != 0:
            raise AssertionError(f"harness 编译失败:\n{result.stderr}")
        cls.directory = directory

    @classmethod
    def tearDownClass(cls) -> None:
        if cls.temporary is not None:
            cls.temporary.cleanup()

    def scenario(self, name: str) -> None:
        directory = self.directory
        self.assertIsNotNone(directory, "harness 未编译")
        result = subprocess.run(
            ["./harness", name],
            cwd=str(directory),
            capture_output=True,
            text=True,
            timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"web-compat-parity-pass: {name}", result.stdout)

    def test_f01_shadow_root_attach_and_media_takeover(self) -> None:
        self.scenario("f01")

    def test_f40_dom_content_loaded_listener_identity(self) -> None:
        self.scenario("f40")

    def test_f29_dynamic_media_volume_backfill(self) -> None:
        self.scenario("f29")

    def test_f19_network_bridge_binary_restore(self) -> None:
        self.scenario("f19")

    def test_frames_injection_boundaries(self) -> None:
        self.scenario("frames")


if __name__ == "__main__":
    unittest.main()
