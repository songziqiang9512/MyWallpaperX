"""Run the production pause script in real WKWebView documents and child frames."""
from pathlib import Path
import subprocess
import base64
import io
import wave
import tempfile
import unittest
from script.tests.test_steam_library_interactions import method

ROOT = Path(__file__).resolve().parents[2]
HARNESS = r'''
import AppKit
import WebKit

enum WallpaperEngine { struct WebWallpaperLaunchRequest { var propertiesJSON: String? } }
enum WebWallpaperHostSupport {
    static func javaScriptQuotedString(_ value: String) -> String {
        String(data: try! JSONEncoder().encode(value), encoding: .utf8)!
    }
}
final class Adapter {
    func applyGeneralProperties(to webView: WKWebView) {}
    /// D5：与产品 adapter 同名的 frame endpoint 登记桩（同表面），供提取出的
    /// applyPausedState/deliverStatePush 在 harness 内编译与运行。
    var frameEndpointRegistry = WebWallpaperFrameEndpointRegistry()
    // ADAPTER_METHODS
}
/// D5 frame endpoint 登记桩：与产品 WebWallpaperFrameEndpointRegistry 同表面。
final class WebWallpaperFrameEndpointRegistry {
    final class Endpoint {
        let token: String
        let documentNonce: String
        var frameInfo: WKFrameInfo
        private(set) var pushSequence: Int64 = 0
        init(token: String, documentNonce: String, frameInfo: WKFrameInfo) {
            self.token = token
            self.documentNonce = documentNonce
            self.frameInfo = frameInfo
        }
        func isLeaseValid(now: TimeInterval) -> Bool { true }
        func advancePushSequence() -> Int64 { pushSequence += 1; return pushSequence }
    }
    private var endpointsByWebView: [ObjectIdentifier: [String: Endpoint]] = [:]
    func register(documentNonce: String, frameInfo: WKFrameInfo, in webView: WKWebView) -> Endpoint? {
        let key = ObjectIdentifier(webView)
        var endpoints = endpointsByWebView[key] ?? [:]
        if let existing = endpoints.first(where: { $0.value.documentNonce == documentNonce }) {
            existing.value.frameInfo = frameInfo
            return existing.value
        }
        let endpoint = Endpoint(token: UUID().uuidString, documentNonce: documentNonce, frameInfo: frameInfo)
        endpoints[endpoint.token] = endpoint
        endpointsByWebView[key] = endpoints
        return endpoint
    }
    func endpoints(in webView: WKWebView) -> [Endpoint] {
        Array(endpointsByWebView[ObjectIdentifier(webView)]?.values ?? [:].values)
    }
    func revoke(token: String, in webView: WKWebView) {
        let key = ObjectIdentifier(webView)
        guard var endpoints = endpointsByWebView[key] else { return }
        endpoints.removeValue(forKey: token)
        endpointsByWebView[key] = endpoints
    }
}
/// D5 frame endpoint hello 桩：登记后向发送 frame 定向回写 ack（与宿主同形状）。
final class FrameEndpointHelloStub: NSObject, WKScriptMessageHandler {
    weak var adapter: Adapter?
    weak var webView: WKWebView?
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let adapter = adapter,
              let webView = webView,
              let body = message.body as? [String: Any],
              let nonce = body["nonce"] as? String,
              nonce.isEmpty == false else { return }
        guard let endpoint = adapter.frameEndpointRegistry.register(
            documentNonce: nonce,
            frameInfo: message.frameInfo,
            in: webView
        ) else { return }
        let tokenLiteral = WebWallpaperHostSupport.javaScriptQuotedString(endpoint.token)
        webView.evaluateJavaScript(
            "(() => { window.__myWallpaperHostFrameEndpointToken = \(tokenLiteral); window.__myWallpaperHostFrameEndpointAck = true; })();",
            in: message.frameInfo,
            in: .page,
            completionHandler: nil
        )
    }
}
/// 兼容脚本的宿主侧观测点：记录 wallpaperHostLog 类型序列与交互区域登记次数，
/// 用于断言多 frame 注入面（dom.ready 只来自顶层、子 frame 登记被丢弃）。
final class ProbeRecorder: NSObject, WKScriptMessageHandler {
    var logTypes: [String] = []
    var interactiveRegionMessageCount = 0
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "wallpaperHostInteractiveRegions" {
            interactiveRegionMessageCount += 1
            return
        }
        guard message.name == "wallpaperHostLog", let body = message.body as? [String: Any] else { return }
        logTypes.append(body["type"] as? String ?? "")
    }
}
@main enum Harness {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = []
        let recorder = ProbeRecorder()
        let endpointStub = FrameEndpointHelloStub()
        config.userContentController.add(recorder, name: "wallpaperHostLog")
        config.userContentController.add(recorder, name: "wallpaperHostInteractiveRegions")
        // D5：frame endpoint hello 通道（每个注入文档一条），与宿主消息面同名；
        // adapter/view 引用在两者创建后接线。
        config.userContentController.add(endpointStub, name: "wallpaperHostFrameEndpoint")
        config.userContentController.addUserScript(WKUserScript(
            source: webWallpaperPlaybackScript.replacingOccurrences(of: "__MWX_INITIAL_PAUSED__", with: "true"),
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.userContentController.addUserScript(WKUserScript(
            source: Adapter.webCompatibilityScript(for: nil, generalPropertiesJSON: "{}",
                volume: 0, playbackRate: 1, paused: true),
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let adapter = Adapter()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 320, height: 200), configuration: config)
        endpointStub.adapter = adapter
        endpointStub.webView = view
        view.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.orderFrontRegardless()
        let page = #"""
        <style>@keyframes move {to {transform:translateX(100px)}}
        #animated {animation:move 2s linear infinite; width:10px; height:10px; background:red}</style>
        <div id=animated></div><div id=wa></div>
        <audio id=media muted autoplay loop src="data:audio/wav;base64,__MEDIA__"></audio>
        <script>
        window.framesSeen=0; window.ticks=0; window.timeouts=0; window.cancelled=0; window.correctThis=0;
        const frame=()=>{framesSeen++;requestAnimationFrame(frame)};requestAnimationFrame(frame);
        setInterval(()=>ticks++,20);setTimeout(()=>timeouts++,250);
        const cancelledID=setTimeout(()=>cancelled++,50);clearInterval(String(cancelledID));
        setTimeout(function(value){if(this===window && value===7) correctThis++}, 0, 7);
        requestAnimationFrame(function(){if(this===window) correctThis++});
        window.wa= document.getElementById('wa').animate([{opacity:0},{opacity:1}],{duration:2000,iterations:Infinity});
        window.authorPaused=document.body.animate([{opacity:1},{opacity:1}],{duration:2000,iterations:Infinity});
        authorPaused.pause();
        // 可控 AudioContext：state/suspend/resume 全部在实例上遮蔽，真实上下文
        // 既不启动渲染线程也不触碰音频硬件；兼容层仍按产品构造器路径采纳本实例
        // （wrapAudioContextConstructor 在构造时把它放进 audioContextInstances）。
        window.__mwxAudio = { state: 'running', suspendCalls: 0, resumeCalls: 0 };
        (() => {
          const ctx = new AudioContext();
          Object.defineProperty(ctx, 'state', {
            configurable: true,
            get: () => window.__mwxAudio.state
          });
          ctx.suspend = () => {
            window.__mwxAudio.suspendCalls++;
            window.__mwxAudio.state = 'suspended';
            return Promise.resolve();
          };
          ctx.resume = () => {
            window.__mwxAudio.resumeCalls++;
            window.__mwxAudio.state = 'running';
            return Promise.resolve();
          };
        })();
        </script>
        """#
        let escaped = page.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
        view.loadHTMLString(page + "<iframe srcdoc=\"" + escaped + "\"></iframe>", baseURL: nil)
        Task { @MainActor in
            do {
                func wait(_ seconds: Double) async throws { try await Task.sleep(for: .seconds(seconds)) }
                func js(_ script: String) async throws -> Any { try await view.evaluateJavaScript(script) as Any }
                func counters(allowUnresolvedAnimations: Bool = false) async throws -> [Double] {
                    let result = try await js("[framesSeen,ticks,timeouts,cancelled,wa.currentTime,document.getElementById('animated').getAnimations()[0].currentTime,frames[0].framesSeen,frames[0].ticks,document.getElementById('media').currentTime]")
                    guard let values = result as? [Any], values.count == 9 else {
                        throw NSError(domain: "WebPauseFixture", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid counters: \(result)"])
                    }
                    return try values.enumerated().map { index, value in
                        if let number = value as? NSNumber { return number.doubleValue }
                        // A never-started animation has an unresolved currentTime.
                        if allowUnresolvedAnimations && [4, 5].contains(index) && value is NSNull { return 0 }
                        throw NSError(domain: "WebPauseFixture", code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Counter \(index) is not numeric: \(value)"])
                    }
                }
                var ready = false
                for _ in 0..<100 {
                    ready = (try? await js("document.readyState === 'complete' && frames.length === 1 && frames[0].document.readyState === 'complete' && typeof frames[0].framesSeen === 'number' && typeof wa === 'object'")) as? Bool == true
                    if ready { break }
                    try await wait(0.1)
                }
                precondition(ready, "Main document and iframe did not finish loading")
                let initial = try await counters(allowUnresolvedAnimations: true)
                precondition(initial[0] == 0 && initial[1] == 0 && initial[2] == 0)
                precondition(initial[6] == 0 && initial[7] == 0, "Initially paused iframe ran")
                adapter.applyPausedState(false, to: view)
                try await wait(0.6)
                let running = try await counters()
                precondition(running[0] > 3 && running[1] > 3 && running[2] == 1 && running[3] == 0)
                precondition(running[6] > 3 && running[7] > 3)
                precondition(running[4] > 0 && running[5] > 0, "Animations did not start after resume")
                precondition(running[8] > 0.1, "Native WebKit media did not start")
                let callbackSemantics = try await js("correctThis") as? Int
                precondition(callbackSemantics == 2, "Native callback this/arguments semantics changed")
                adapter.applyPausedState(true, to: view)
                try await wait(0.15) // Child postMessage and compositor settle.
                let frozen = try await counters()
                try await wait(0.4)
                let still = try await counters()
                precondition(zip(frozen, still).allSatisfy { abs($0 - $1) < 0.01 }, "Paused RAF/timer/CSS/WA/iframe advanced: \(frozen) -> \(still)")
                // Work scheduled while paused must wait, and cancelled work must stay cancelled.
                _ = try await js("setTimeout(()=>timeouts++,50); wa.play(); document.getElementById('animated').style.animationPlayState='paused'; void document.getElementById('media').play().catch(()=>{});")
                try await wait(0.2)
                let held = try await counters()
                precondition(held[2] == 1)
                precondition(abs(held[8] - still[8]) < 0.01, "Media restarted while native gate was suspended")
                adapter.applyPausedState(false, to: view)
                var resumed = try await counters()
                for _ in 0..<20 where resumed[8] <= held[8] + 0.05 {
                    try await wait(0.1)
                    resumed = try await counters()
                }
                precondition(resumed[0] > still[0] && resumed[1] > still[1] && resumed[2] == 2)
                precondition(resumed[6] > still[6] && resumed[7] > still[7])
                let authoredState = try await js("authorPaused.playState") as? String
                precondition(authoredState == "paused")
                precondition(abs(resumed[5] - still[5]) < 0.01, "Author CSS pause was overridden")
                precondition(resumed[8] > held[8] + 0.05, "Native media failed to resume: held=\(held), resumed=\(resumed)")
                // 多 frame 注入面（D5）：宿主定向推送直达同源子 frame——属性推送
                // 走 adapter.applyProperties（deliverStatePush 逐 endpoint 投递），
                // 不再经主 frame 中继；dom.ready 只由顶层 frame 发出；子 frame 的
                // 交互区域登记被丢弃并留诊断。
                adapter.applyProperties("{\"frameProbe\":{\"value\":\"child\"}}", to: view)
                var childReceivedPropertyPush = false
                for _ in 0..<50 where !childReceivedPropertyPush {
                    childReceivedPropertyPush = (try? await js(
                        "frames[0].__myWallpaperLastUserProperties"
                        + " && frames[0].__myWallpaperLastUserProperties.frameProbe"
                        + " && frames[0].__myWallpaperLastUserProperties.frameProbe.value === 'child'")) as? Bool == true
                    if !childReceivedPropertyPush { try await wait(0.1) }
                }
                precondition(childReceivedPropertyPush, "同源子 frame 未收到 __myWallpaperApplyProperties 推送")
                let childPaused = try await js("frames[0].wallpaperEngine_paused") as? Bool
                let topPaused = try await js("window.wallpaperEngine_paused") as? Bool
                precondition(childPaused == topPaused, "同源子 frame 的暂停态未随推送更新")
                let domReadyCount = recorder.logTypes.filter { $0 == "dom.ready" }.count
                precondition(domReadyCount == 1, "dom.ready 应由顶层 frame 唯一发出，实际 \(domReadyCount) 次")
                let regionMessagesBefore = recorder.interactiveRegionMessageCount
                _ = try await js("""
                frames[0].__myWallpaperRegisterInteractiveRegions({
                  source: 'dom-auto',
                  regions: [{ id: 'child-region', x: 0.1, y: 0.1, width: 0.5, height: 0.5 }]
                });
                """)
                try await wait(0.3)
                precondition(
                    recorder.interactiveRegionMessageCount == regionMessagesBefore,
                    "子 frame 的交互区域登记不应到达宿主"
                )
                precondition(
                    recorder.logTypes.contains("interactive-regions.subframe-ignored"),
                    "子 frame 的交互区域登记被丢弃时应留诊断"
                )
                // 暂停快照按「回合」记录：同一暂停被重复应用（种子期、dom.ready、
                // DCL/load 重放、applyPausedState）后，宿主自身的 suspend 不得被
                // 记成作者挂起，恢复时必须 resume 可恢复的 AudioContext。
                adapter.applyPausedState(true, to: view)
                var audioState = try await js("__mwxAudio.state") as? String
                for _ in 0..<20 where audioState != "suspended" {
                    try await wait(0.1)
                    audioState = try await js("__mwxAudio.state") as? String
                }
                precondition(audioState == "suspended", "宿主暂停未挂起 AudioContext：\(audioState ?? "nil")")
                let resumeCallsBeforeRepeat = try await js("__mwxAudio.resumeCalls") as? Int ?? -1
                adapter.applyPausedState(true, to: view) // 同一暂停回合的重复应用
                try await wait(0.2)
                adapter.applyPausedState(false, to: view)
                var resumedAudioState = try await js("__mwxAudio.state") as? String
                for _ in 0..<20 where resumedAudioState != "running" {
                    try await wait(0.1)
                    resumedAudioState = try await js("__mwxAudio.state") as? String
                }
                precondition(
                    resumedAudioState == "running",
                    "重复应用暂停后 AudioContext 未恢复：\(resumedAudioState ?? "nil")"
                )
                let resumeCallsAfterRepeat = try await js("__mwxAudio.resumeCalls") as? Int ?? -1
                precondition(
                    resumeCallsAfterRepeat > resumeCallsBeforeRepeat,
                    "恢复未调用 resume()：before=\(resumeCallsBeforeRepeat) after=\(resumeCallsAfterRepeat)"
                )
                print("webkit-pause-pass: initial pause, RAF, timers, CSS, Web Animations, iframe, resume, frames, audio rounds")
                window.orderOut(nil)
                exit(0)
            } catch { print("webkit-pause-failed: \(error)"); exit(1) }
        }
        app.run()
    }
}
'''


class WebPlaybackPauseTests(unittest.TestCase):
    def test_real_webkit_pause_resume(self):
        with tempfile.TemporaryDirectory(prefix="mwx-webkit-pause-") as directory:
            path = Path(directory)
            host = ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host"
            adapter = method((host / "WebWallpaperHostTypes.swift").read_text(), "static func webCompatibilityScript(")
            adapter += "\n" + method((host / "DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift").read_text(), "func applyPausedState(")
            # D5：applyPausedState 经推送投递面送达，投递面与序号包装随提取（拆分
            # 后从 FrameReply.swift 提取，sequencedPushScript 已放宽 internal）；
            # 属性推送断言同步改走 adapter.applyProperties 定向投递。
            adapter += "\n" + method((host / "DedicatedWebWallpaperHostPlaceholderAdapter+FrameReply.swift").read_text(), "func deliverStatePush(")
            adapter += "\n" + method((host / "DedicatedWebWallpaperHostPlaceholderAdapter+FrameReply.swift").read_text(), "func sequencedPushScript(")
            adapter += "\n" + method((host / "DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift").read_text(), "func applyProperties(")
            audio = io.BytesIO()
            with wave.open(audio, "wb") as wav:
                wav.setnchannels(1); wav.setsampwidth(1); wav.setframerate(8000)
                wav.writeframes(bytes([128]) * 24000)
            harness = HARNESS.replace("// ADAPTER_METHODS", adapter).replace("__MEDIA__", base64.b64encode(audio.getvalue()).decode())
            (path / "Harness.swift").write_text(harness)
            source = host / "WebWallpaperPlaybackScript.swift"
            result = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(source),
                *map(str, sorted(host.glob("DedicatedWebWallpaperHostCompatibilityScript+*.swift"))),
                str(path / "Harness.swift"), "-o", str(path / "harness")],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(path / "harness")], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("webkit-pause-pass", result.stdout)


if __name__ == "__main__":
    unittest.main()
