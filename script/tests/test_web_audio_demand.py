"""Exercise production endpoint audio demand, retirement, and ordered silence.

WebKit delivery is delayed by the harness. The real registry, surface message
handler, demand reducer, goodbye branch, lease work, and spectrum methods execute;
no CoreAudio device or App is started. A separate JS check runs actual registration
and hello-ACK source for pre-ACK and re-registration ordering.
"""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method
from script.tests.test_web_compat_parity import source_block
from script.tests.test_web_spectrum_delivery import HARNESS as DELIVERY_HARNESS

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host"

ADAPTER_STATE = r'''
    struct Request { let id = UUID(); let propertiesJSON = "{}" }
    struct Surface { let webView: WKWebView; let audioDemandMessageHandler: WebAudioDemandMessageHandler }
    enum Event { case audioSpectrumDemandChanged(Bool, requestID: UUID) }
    var surfaces: [CGDirectDisplayID: Surface] = [:]
    var currentRequest: Request? = Request()
    var lastPublishedAudioSpectrumDemand = false
    var events: [Bool] = []
    var eventHandler: ((Event) -> Void)?
    init() {
        eventHandler = { [weak self] event in
            if case let .audioSpectrumDemandChanged(active, _) = event { self?.events.append(active) }
        }
    }
    func screenID(for view: WKWebView) -> CGDirectDisplayID? {
        surfaces.first { $0.value.webView === view }?.key
    }
    func screenIDForStartedNavigation(_ navigation: WKNavigation?, webView: WKWebView) -> CGDirectDisplayID? {
        screenID(for: webView)
    }
    func forEachWebView(_ action: (WKWebView) -> Void) { surfaces.values.forEach { action($0.webView) } }
    func stopFrameEndpointLeaseRenewalTimer() {}
    func ensureFrameEndpointLeaseRenewalTimer() {}
    var currentSpectrumLevels: [Float]?
    var effectiveVolume = 1.0
    var currentPlaybackRate = 1.0
    var paused = false
    static func screenID(for screen: NSScreen) -> CGDirectDisplayID { 1 }
    func currentGeneralPropertiesJSON(for screen: NSScreen?, screenID: CGDirectDisplayID?) -> String { "{}" }
    var currentSystemMediaSnapshot: SystemMediaSnapshot?
    func isSystemMediaEndpointCurrent(_ endpoint: WebWallpaperFrameEndpointRegistry.Endpoint, in view: WKWebView) -> Bool { false }
    func deliverSystemMedia(_ snapshot: SystemMediaSnapshot, to endpoint: WebWallpaperFrameEndpointRegistry.Endpoint, webView: WKWebView) {}
'''
NATIVE_STUBS = r'''
typealias CGDirectDisplayID = UInt32
@MainActor protocol WKScriptMessageHandler {}
@MainActor final class WKUserContentController {}
@MainActor final class WKNavigation {}
@MainActor struct WKScriptMessage { let name: String; let body: Any }
@MainActor final class NSScreen { static let screens: [NSScreen] = [] }
enum WebWallpaperHostSupport {
    static func javaScriptQuotedString(_ value: String) -> String {
        String(data: try! JSONEncoder().encode(value), encoding: .utf8)!
    }
}
'''
CHECKS = r'''
@main struct EndpointAudioChecks {
    @MainActor static func expect(_ value: @autoclosure () -> Bool, _ reason: String) {
        precondition(value(), reason)
    }
    @MainActor static func payload(_ endpoint: WebWallpaperFrameEndpointRegistry.Endpoint, _ active: Bool = true) -> [String: Any] {
        ["token": endpoint.token, "nonce": endpoint.documentNonce, "active": active]
    }
    @MainActor static func send(_ adapter: Adapter, _ screen: UInt32, _ body: [String: Any]) {
        adapter.surfaces[screen]!.audioDemandMessageHandler.userContentController(
            WKUserContentController(), didReceive: WKScriptMessage(name: "wallpaperHostAudioDemand", body: body))
    }
    @MainActor static func main() async {
        let adapter = Adapter(), first = WKWebView(), second = WKWebView()
        let firstHandler = WebAudioDemandMessageHandler(adapter: adapter, screenID: 1)
        adapter.surfaces[1] = .init(webView: first, audioDemandMessageHandler: firstHandler)
        adapter.surfaces[2] = .init(webView: second, audioDemandMessageHandler: WebAudioDemandMessageHandler(adapter: adapter, screenID: 2))
        let only = adapter.frameEndpointRegistry.register(documentNonce: "only-audio", frameInfo: WKFrameInfo(1), in: first)!
        let passive = adapter.frameEndpointRegistry.register(documentNonce: "passive", frameInfo: WKFrameInfo(2), in: first)!
        send(adapter, 1, ["active": true])
        var wrong = payload(only); wrong["nonce"] = "old-document"
        send(adapter, 1, wrong)
        expect(adapter.events.isEmpty, "unidentified and old-document messages cannot acquire capture")
        send(adapter, 1, payload(only)); send(adapter, 1, payload(only))
        expect(adapter.events == [true], "duplicate hello/demand reports acquire only one aggregate lease")
        adapter.pushAudioSpectrum(WebWallpaperSpectrumPush([0.5]), to: first)
        expect(first.sent.count == 1 && passive.pushSequence == 0, "only the declared audio frame receives periodic spectrum")
        adapter.pushAudioSpectrum(WebWallpaperSpectrumPush([0.8]), to: first)
        adapter.goodbye(payload(only), nonce: only.documentNonce, webView: first)
        expect(adapter.events == [true, false], "the real goodbye branch releases the sole audio consumer")
        expect(adapter.frameEndpointRegistry.endpoints(in: first).count == 1, "passive document remains registered")
        expect(first.sent.count == 2 && first.sent.last!.frame.id == 2 && first.sent.last!.script.contains("fill(0)"),
               "last withdrawal preserves one ordered silence for retained passive documents")
        let afterGoodbye = first.sent.count
        first.finish(1)
        for _ in 0..<8 { await Task.yield() }
        adapter.pushAudioSpectrum(WebWallpaperSpectrumPush([0.9]), to: first)
        send(adapter, 1, payload(only))
        expect(first.sent.count == afterGoodbye && adapter.events == [true, false], "old completions and old demand cannot revive retired audio")

        let next = adapter.frameEndpointRegistry.register(documentNonce: "new-audio", frameInfo: WKFrameInfo(3), in: first)!
        let other = adapter.frameEndpointRegistry.register(documentNonce: "other-display", frameInfo: WKFrameInfo(4), in: second)!
        send(adapter, 1, payload(next)); send(adapter, 2, payload(other))
        expect(adapter.events == [true, false, true], "two displays share one published capture demand")
        let beforePartialWithdrawal = first.sent.count
        send(adapter, 1, payload(next, false))
        expect(adapter.lastPublishedAudioSpectrumDemand && first.sent.count == beforePartialWithdrawal + 1
               && first.sent.last!.frame.id == 3 && first.sent.last!.script.contains("fill(0)"),
               "withdrawing one live consumer preserves the other and clears only its own bars")
        send(adapter, 1, payload(next))
        adapter.goodbye(payload(next), nonce: next.documentNonce, webView: first)
        expect(adapter.lastPublishedAudioSpectrumDemand, "removing one display consumer preserves the other")
        adapter.goodbye(payload(other), nonce: other.documentNonce, webView: second)
        expect(adapter.events.last == false, "removing the final display consumer releases capture")

        let a = adapter.frameEndpointRegistry.register(documentNonce: "new-main", frameInfo: WKFrameInfo(5), in: first)!
        let b = adapter.frameEndpointRegistry.register(documentNonce: "survivor", frameInfo: WKFrameInfo(6), in: second)!
        send(adapter, 1, payload(a)); send(adapter, 2, payload(b))
        adapter.clearAudioSpectrumDemand(for: 1)
        expect(adapter.lastPublishedAudioSpectrumDemand && !a.audioDemandActive && b.audioDemandActive,
               "surface withdrawal preserves the other display's consumer")
        send(adapter, 1, payload(a))
        adapter.webView(first, didStartProvisionalNavigation: WKNavigation())
        expect(adapter.lastPublishedAudioSpectrumDemand && !adapter.frameEndpointRegistry.hasEndpoints(in: first),
               "real main-navigation branch retires only its own display")
        adapter.webView(second, didStartProvisionalNavigation: WKNavigation())
        expect(!adapter.lastPublishedAudioSpectrumDemand, "navigation of the last consumer releases capture")

        let expiring = adapter.frameEndpointRegistry.register(documentNonce: "lease", frameInfo: WKFrameInfo(7), in: first)!
        send(adapter, 1, payload(expiring)); expiring.leaseExpiresAt = 0
        adapter.renewFrameEndpointLeases()
        expect(!adapter.lastPublishedAudioSpectrumDemand, "lease expiry releases audio without page goodbye")
        send(adapter, 1, payload(expiring))
        expect(!adapter.lastPublishedAudioSpectrumDemand, "expired producer cannot reacquire its retired endpoint")

        let old = adapter.frameEndpointRegistry.register(documentNonce: "challenge-old", frameInfo: WKFrameInfo(8), in: first)!
        send(adapter, 1, payload(old)); adapter.renewFrameEndpointLeases()
        adapter.goodbye(payload(old), nonce: old.documentNonce, webView: first)
        let current = adapter.frameEndpointRegistry.register(documentNonce: "challenge-new", frameInfo: WKFrameInfo(9), in: first)!
        send(adapter, 1, payload(current))
        let pendingChallenge = first.pending.first { $0.frame.id == 8 }!
        pendingChallenge.finish(.failure(NSError(domain: "old-frame", code: 1)))
        for _ in 0..<8 { await Task.yield() }
        expect(adapter.lastPublishedAudioSpectrumDemand && current.audioDemandActive,
               "a late old-frame challenge failure cannot withdraw replacement demand")
        let activeEvents = adapter.events.count
        adapter.handleAudioSpectrumDemand(payload(old, false), nonce: old.documentNonce, webView: first)
        expect(adapter.events.count == activeEvents && current.audioDemandActive, "old false cannot clear new document")

        adapter.pushAudioSpectrum(WebWallpaperSpectrumPush([1]), to: first)
        adapter.pushAudioSpectrum(WebWallpaperSpectrumPush([0.8]), to: first)
        let beforeWithdraw = first.sent.count
        send(adapter, 1, payload(current, false))
        expect(first.sent.count == beforeWithdraw + 1 && first.sent.last!.script.contains("fill(0)"),
               "live last consumer receives one newer ordered clear")
        let clearSequence = current.pushSequence
        first.finish(9)
        for _ in 0..<8 { await Task.yield() }
        adapter.pushAudioSpectrum(WebWallpaperSpectrumPush([1]), to: first)
        expect(current.pushSequence == clearSequence && current.pendingSpectrumPush == nil,
               "late in-flight completion cannot flush pending bars after withdrawal")
        send(adapter, 1, payload(current, false))
        expect(current.pushSequence == clearSequence, "duplicate false does not stream silence")

        adapter.surfaces[1] = .init(webView: WKWebView(), audioDemandMessageHandler: WebAudioDemandMessageHandler(adapter: adapter, screenID: 1))
        firstHandler.userContentController(WKUserContentController(), didReceive: .init(name: "wallpaperHostAudioDemand", body: payload(current)))
        expect(!adapter.lastPublishedAudioSpectrumDemand, "retired surface handler cannot grant new surface demand")
        let replacementView = adapter.surfaces[1]!.webView
        adapter.handleFrameEndpointHello(nonce: "ack-old", frameInfo: WKFrameInfo(10), webView: replacementView)
        let ackOld = adapter.frameEndpointRegistry.endpoints(in: replacementView).first { $0.documentNonce == "ack-old" }!
        send(adapter, 1, payload(ackOld))
        adapter.goodbye(payload(ackOld), nonce: ackOld.documentNonce, webView: replacementView)
        adapter.handleFrameEndpointHello(nonce: "ack-current", frameInfo: WKFrameInfo(11), webView: replacementView)
        adapter.handleFrameEndpointHello(nonce: "ack-current", frameInfo: WKFrameInfo(11), webView: replacementView)
        let ackCurrent = adapter.frameEndpointRegistry.endpoints(in: replacementView).first { $0.documentNonce == "ack-current" }!
        send(adapter, 1, payload(ackCurrent))
        replacementView.pending.first { $0.frame.id == 10 }!.finish(.failure(NSError(domain: "old-ack", code: 1)))
        for _ in 0..<8 { await Task.yield() }
        expect(adapter.lastPublishedAudioSpectrumDemand && ackCurrent.audioDemandActive && adapter.frameEndpointRegistry.endpoints(in: replacementView).count == 1,
               "old ACK failure cannot revoke a replacement; repeated hello shares one current endpoint")
        let duplicateAcks = replacementView.pending.filter { $0.frame.id == 11 && $0.script.contains("stale-frame-hello") }
        duplicateAcks[0].finish(.failure(NSError(domain: "superseded-ack", code: 1)))
        duplicateAcks[1].finish(.success(true))
        for _ in 0..<8 { await Task.yield() }
        expect(adapter.lastPublishedAudioSpectrumDemand && adapter.frameEndpointRegistry.contains(ackCurrent, in: replacementView),
               "a superseded ACK failure cannot withdraw the same token's newer hello")
        adapter.renewFrameEndpointLeases()
        let oldRouteChallenge = replacementView.pending.last { $0.frame.id == 11 }!
        adapter.handleFrameEndpointHello(nonce: "ack-current", frameInfo: WKFrameInfo(12), webView: replacementView)
        oldRouteChallenge.finish(.failure(NSError(domain: "superseded-challenge", code: 1)))
        for _ in 0..<8 { await Task.yield() }
        expect(adapter.lastPublishedAudioSpectrumDemand && adapter.frameEndpointRegistry.contains(ackCurrent, in: replacementView),
               "a challenge sent before repeated hello cannot retire its newer frame route")
        adapter.clearAudioSpectrumDemand()
        expect(!adapter.lastPublishedAudioSpectrumDemand, "whole-host demand withdrawal releases aggregate")
        send(adapter, 1, payload(ackCurrent))
        replacementView.pending.first { $0.frame.id == 12 }!.finish(.failure(NSError(domain: "current-ack", code: 1)))
        for _ in 0..<8 { await Task.yield() }
        expect(!adapter.lastPublishedAudioSpectrumDemand && !adapter.frameEndpointRegistry.contains(ackCurrent, in: replacementView),
               "the current ACK failure still retires its own endpoint and capture demand")
        let failedChallenge = adapter.frameEndpointRegistry.register(documentNonce: "failed-challenge", frameInfo: WKFrameInfo(13), in: replacementView)!
        send(adapter, 1, payload(failedChallenge)); adapter.renewFrameEndpointLeases()
        replacementView.pending.first { $0.frame.id == 13 }!.finish(.failure(NSError(domain: "current-challenge", code: 1)))
        for _ in 0..<8 { await Task.yield() }
        expect(!adapter.lastPublishedAudioSpectrumDemand && !adapter.frameEndpointRegistry.contains(failedChallenge, in: replacementView),
               "the current challenge failure still retires its own endpoint and capture demand")

        let snapshotAdapter = Adapter(), snapshotView = WKWebView()
        snapshotAdapter.surfaces[1] = .init(webView: snapshotView, audioDemandMessageHandler: WebAudioDemandMessageHandler(adapter: snapshotAdapter, screenID: 1))
        let listening = snapshotAdapter.frameEndpointRegistry.register(documentNonce: "snapshot-audio", frameInfo: WKFrameInfo(20), in: snapshotView)!
        let retained = snapshotAdapter.frameEndpointRegistry.register(documentNonce: "snapshot-passive", frameInfo: WKFrameInfo(21), in: snapshotView)!
        send(snapshotAdapter, 1, payload(listening))
        snapshotAdapter.currentSpectrumLevels = [0.75]
        snapshotAdapter.goodbye(payload(listening), nonce: listening.documentNonce, webView: snapshotView)
        snapshotAdapter.applyCompatibilitySnapshot(to: retained, webView: snapshotView)
        var snapshots = [snapshotView.sent.last!.script]
        // Reproduce a late in-flight runtime command overwriting the cache;
        // the actual hello -> snapshot projection must still publish silence.
        snapshotAdapter.currentSpectrumLevels = [0.9]
        snapshotAdapter.handleFrameEndpointHello(nonce: "late-passive", frameInfo: WKFrameInfo(22), webView: snapshotView)
        snapshots.append(snapshotView.sent.last!.script)
        snapshotAdapter.handleFrameEndpointHello(nonce: retained.documentNonce, frameInfo: WKFrameInfo(21), webView: snapshotView)
        snapshots.append(snapshotView.sent.last!.script)
        let renewed = snapshotAdapter.frameEndpointRegistry.register(documentNonce: "snapshot-renewed-audio", frameInfo: WKFrameInfo(23), in: snapshotView)!
        send(snapshotAdapter, 1, payload(renewed))
        snapshotAdapter.currentSpectrumLevels = [0.25]
        snapshotAdapter.applyCompatibilitySnapshot(to: renewed, webView: snapshotView)
        snapshots.append(snapshotView.sent.last!.script)
        renewed.leaseExpiresAt = 0
        snapshotAdapter.applyCompatibilitySnapshot(to: retained, webView: snapshotView)
        snapshots.append(snapshotView.sent.last!.script)
        let otherSnapshotView = WKWebView()
        snapshotAdapter.surfaces[2] = .init(webView: otherSnapshotView, audioDemandMessageHandler: WebAudioDemandMessageHandler(adapter: snapshotAdapter, screenID: 2))
        let otherScreenListener = snapshotAdapter.frameEndpointRegistry.register(documentNonce: "other-screen-audio", frameInfo: WKFrameInfo(24), in: otherSnapshotView)!
        send(snapshotAdapter, 2, payload(otherScreenListener))
        snapshotAdapter.currentSpectrumLevels = [0.85]
        snapshotAdapter.applyCompatibilitySnapshot(to: retained, webView: snapshotView)
        snapshots.append(snapshotView.sent.last!.script)
        print("snapshots=" + String(data: try! JSONEncoder().encode(snapshots), encoding: .utf8)!)
        print("endpoint audio demand checks passed")
    }
}
'''


class WebAudioDemandTests(unittest.TestCase):
    def test_native_registration_retirement_multidisplay_and_old_callbacks(self):
        types = (HOST / "WebWallpaperHostTypes.swift").read_text()
        registry = source_block(types, "final class WebWallpaperFrameEndpointRegistry")
        payload = source_block(types, "final class WebWallpaperSpectrumPush")
        delivery = (HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+FrameReply.swift").read_text()
        lifecycle = (HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+Lifecycle.swift").read_text()
        navigation = (HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+NavigationDelegate.swift").read_text()
        methods = "\n".join(method(delivery, marker) for marker in [
            "func sequencedPushScript(", "func pushAudioSpectrum(", "func clearAudioSpectrum(",
            "func compatibilityStateScript(", "func applyCompatibilitySnapshot(",
            "private func deliverAudioSpectrum(", "private func renewFrameEndpointLeases(",
        ]).replace("private func renewFrameEndpointLeases", "func renewFrameEndpointLeases")
        goodbye = lifecycle.split('            case "goodbye":', 1)[1].split('            case "hello", nil:', 1)[0]
        methods += '\nfunc goodbye(_ body: [String: Any], nonce: String, webView: WKWebView) {\n' + goodbye + '\n}\n'
        methods += method(navigation, "func webView(_ webView: WKWebView, didStartProvisionalNavigation")
        methods += "\n" + method(lifecycle, "func handleFrameEndpointHello(")
        base = DELIVERY_HARNESS.split("@main struct SpectrumDeliveryChecks", 1)[0]
        base = base.replace("    func refreshAudioSpectrumDemand() {}\n", "")
        base = base.replace("    let id: Int\n", "    let id: Int\n    var isMainFrame = false\n")
        base = base.replace("    let frameEndpointRegistry", ADAPTER_STATE + "\n    let frameEndpointRegistry")
        base = base.replace("// PRODUCTION_TYPES", NATIVE_STUBS + "\n@MainActor\n" + registry + "\n@MainActor\n" + payload)
        base = base.replace("// PRODUCTION_METHODS", methods)
        audio = (HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+AudioDemand.swift").read_text()
        audio = "\n".join(x for x in audio.splitlines() if not x.startswith("import "))
        audio = audio.replace("DedicatedWebWallpaperHostPlaceholderAdapter", "Adapter")
        audio = audio.replace("final class WebAudioDemandMessageHandler", "@MainActor final class WebAudioDemandMessageHandler")
        with tempfile.TemporaryDirectory(prefix="mwx-web-audio-demand-") as temporary:
            source, binary = Path(temporary) / "Harness.swift", Path(temporary) / "harness"
            source.write_text(base + audio + CHECKS)
            compiled = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(source), "-o", str(binary)],
                                      capture_output=True, text=True, timeout=90)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            snapshots = json.loads(next(line.removeprefix("snapshots=") for line in result.stdout.splitlines()
                                        if line.startswith("snapshots=")))
            for index, snapshot in enumerate(snapshots):
                # Execute every native-generated script in a fresh page so the
                # actual visible levels, rather than its source shape, decide.
                script = "const window=new Proxy({levels:null},{get:(o,k)=>k in o?o[k]:(()=>{}),set:(o,k,v)=>(o[k]=v,true)}); window.__myWallpaperPushAudioSpectrum=x=>{window.levels=x};\n"
                script += snapshot + "\nconsole.log(JSON.stringify(window.levels));"
                page = subprocess.run(["node", "-e", script], capture_output=True, text=True, timeout=15)
                self.assertEqual(page.returncode, 0, page.stderr)
                self.assertEqual(json.loads(page.stdout), [0.25] if index == 3 else [0] * 128,
                                 f"snapshot case {index}")

    def test_js_pre_ack_registration_and_document_reack(self):
        foundation = (HOST / "DedicatedWebWallpaperHostCompatibilityScript+BootstrapFoundation.swift").read_text()
        registration = foundation.split("  window.__myWallpaperReportAudioDemand =", 1)[1]
        registration = "window.__myWallpaperReportAudioDemand =" + registration.split("  window.wallpaperRegisterVolumeListener", 1)[0]
        lifecycle = method((HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+Lifecycle.swift").read_text(), "func handleFrameEndpointHello(")
        ack = lifecycle.split('"""', 2)[1]
        def ack_for(nonce, token):
            return ack.replace(r"\(nonceLiteral)", json.dumps(nonce)).replace(r"\(tokenLiteral)", json.dumps(token))
        script = "const audioListeners=[]; const reports=[]; const hostLogger=null; const window={webkit:{messageHandlers:{wallpaperHostAudioDemand:{postMessage:x=>reports.push(x)}}}};\n"
        script += registration
        script += "\nwindow.__myWallpaperHostFrameDocumentNonce='document-a'; window.wallpaperRegisterAudioListener(()=>{}); if(reports.length) throw Error('pre-ACK must wait');\n"
        script += ack_for("document-a", "token-a")
        script += "\nif(reports.length!==1 || !reports[0].active || reports[0].token!=='token-a' || reports[0].nonce!=='document-a') throw Error('ACK must replay early registration');\n"
        script += "window.__myWallpaperHostFrameEndpointToken=null;\n" + ack_for("document-a", "token-b")
        script += "\nif(reports.length!==2 || reports[1].token!=='token-b' || !reports[1].active) throw Error('BFCache/reack must bind current token');\n"
        script += "window.__myWallpaperHostFrameDocumentNonce='document-new'; try {\n" + ack_for("document-a", "old-token") + "\n} catch(_){} if(reports.length!==2) throw Error('old document ACK must not report demand');\n"
        script += "audioListeners.length=0; window.__myWallpaperHostFrameEndpointToken=null;\n" + ack_for("document-new", "token-new")
        script += "\nif(reports.length!==3 || reports[2].active) throw Error('passive ACK must not acquire capture'); window.wallpaperRegisterAudioListener(()=>{}); if(reports.length!==4 || !reports[3].active || reports[3].token!=='token-new') throw Error('late registration must use current ACK');\n"
        delivery = method((HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+FrameReply.swift").read_text(), "func sequencedPushScript(")
        sequenced = delivery.split('"""', 2)[1]
        def push(body, sequence):
            return sequenced.replace(r"\(sequence)", str(sequence)).replace(r"\(body)", body)
        script += "window.__myWallpaperPushAudioSpectrum=x=>{window.lastLevels=x};\n"
        script += push("window.__myWallpaperPushAudioSpectrum(new Array(128).fill(0));", 2)
        script += push("window.__myWallpaperPushAudioSpectrum([0.8]);", 1)
        script += "\nif(window.lastLevels.length!==128 || window.lastLevels.some(x=>x!==0)) throw Error('old evaluation must not override withdrawal silence');\n"
        result = subprocess.run(["node", "-e", script], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
