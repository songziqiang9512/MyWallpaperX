"""Run the production spectrum payload and delivery with delayed WebKit replies."""
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method
from script.tests.test_web_compat_parity import source_block

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host"

HARNESS = r'''
import Foundation

struct SystemMediaSnapshot {}
@MainActor final class WKFrameInfo {
    let id: Int
    init(_ id: Int) { self.id = id }
}
enum WKContentWorld { case page }
@MainActor final class WKWebView {
    struct Delivery {
        let script: String
        let frame: WKFrameInfo
        let finish: (Result<Any?, Error>) -> Void
    }
    var sent: [Delivery] = []
    var pending: [Delivery] = []
    func evaluateJavaScript(_ script: String, in frame: WKFrameInfo, in world: WKContentWorld,
                            completionHandler: @escaping (Result<Any?, Error>) -> Void) {
        let delivery = Delivery(script: script, frame: frame, finish: completionHandler)
        sent.append(delivery)
        pending.append(delivery)
    }
    func finish(_ frameID: Int) {
        let index = pending.firstIndex { $0.frame.id == frameID }!
        pending.remove(at: index).finish(.success(nil))
    }
}

@MainActor var formattedValueCount = 0
@MainActor func formatSpectrumValue(_ value: Float) -> String {
    formattedValueCount += 1
    return String(format: "%.6f", value)
}

// PRODUCTION_TYPES

@MainActor final class Adapter {
    let frameEndpointRegistry = WebWallpaperFrameEndpointRegistry()
    var subscriptionRefreshes = 0
    func refreshSystemMediaSubscription() { subscriptionRefreshes += 1 }
    func refreshAudioSpectrumDemand() {}
    // PRODUCTION_METHODS
}

@main struct SpectrumDeliveryChecks {
    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ reason: String) {
        precondition(condition(), reason)
    }
    @MainActor static func settle() async {
        for _ in 0..<8 { await Task.yield() }
    }
    @MainActor static func main() async {
        let adapter = Adapter(), first = WKWebView(), second = WKWebView()
        let endpoint1 = adapter.frameEndpointRegistry.register(documentNonce: "one", frameInfo: WKFrameInfo(1), in: first)!
        let endpoint2 = adapter.frameEndpointRegistry.register(documentNonce: "two", frameInfo: WKFrameInfo(2), in: first)!
        let endpoint3 = adapter.frameEndpointRegistry.register(documentNonce: "three", frameInfo: WKFrameInfo(3), in: second)!
        for endpoint in [endpoint1, endpoint2, endpoint3] { endpoint.audioDemandActive = true }
        let passive = adapter.frameEndpointRegistry.register(documentNonce: "passive", frameInfo: WKFrameInfo(6), in: first)!
        let levels = (0..<128).map { Float($0) / 127 }
        let expectedBody = "window.__myWallpaperPushAudioSpectrum(["
            + levels.map { String(format: "%.6f", $0) }.joined(separator: ",") + "]);"
        let initial = WebWallpaperSpectrumPush(levels)
        expect(formattedValueCount == 0, "constructing a push must not format its values")
        adapter.pushAudioSpectrum(initial, to: first)
        adapter.pushAudioSpectrum(initial, to: second)
        expect(formattedValueCount == 128, "all endpoints/displays share one formatted body")
        expect(passive.pushSequence == 0, "a registered frame without audio demand receives no periodic push")
        expect(first.sent.count == 2 && second.sent.count == 1, "every endpoint receives the push")
        for delivery in first.sent + second.sent {
            expect(delivery.script.contains(expectedBody), "retain exact six-decimal values")
            expect(delivery.script.contains("const sequence = 1;"), "endpoint sequence starts independently")
        }
        let superseded = WebWallpaperSpectrumPush(Array(repeating: 0.75, count: 128))
        let silence = WebWallpaperSpectrumPush(Array(repeating: 0, count: 128))
        for view in [first, second] {
            adapter.pushAudioSpectrum(superseded, to: view)
            adapter.pushAudioSpectrum(silence, to: view)
        }
        expect(formattedValueCount == 128, "all-busy endpoints retain latest values without formatting")
        _ = endpoint1.advancePushSequence() // An ordered control advances this document only.
        first.finish(1)
        await settle()
        expect(first.sent.count == 3 && formattedValueCount == 256, "first available endpoint prepares latest silence")
        expect(first.sent.last!.script.contains("const sequence = 3;"), "a spectrum cannot reuse the prior control sequence")
        expect(first.sent.last!.script.contains(silence.scriptBody()), "pending silence replaces superseded values")
        first.finish(2)
        second.finish(3)
        await settle()
        expect(first.sent.count == 4 && second.sent.count == 2, "both slower endpoints receive latest silence")
        expect(formattedValueCount == 256, "delayed deliveries reuse the already prepared body")
        expect(endpoint2.pushSequence == 2 && endpoint3.pushSequence == 2, "other documents keep their own sequences")

        let afterNavigation = WebWallpaperSpectrumPush(levels)
        adapter.pushAudioSpectrum(afterNavigation, to: first)
        let beforeRevoke = first.sent.count
        adapter.frameEndpointRegistry.revokeAll(in: first)
        let replacement = adapter.frameEndpointRegistry.register(documentNonce: "replacement", frameInfo: WKFrameInfo(5), in: first)!
        replacement.audioDemandActive = true
        let replacementInitial = WebWallpaperSpectrumPush(Array(repeating: 0.5, count: 128))
        adapter.pushAudioSpectrum(replacementInitial, to: first)
        adapter.pushAudioSpectrum(silence, to: first)
        expect(first.sent.count == beforeRevoke + 1 && formattedValueCount == 384,
               "a new endpoint in the same view accepts its own initial push")
        first.finish(1)
        first.finish(2)
        await settle()
        expect(first.sent.count == beforeRevoke + 1, "retired document completions must not flush pending values")
        expect(formattedValueCount == 384, "retired documents must not prepare their pending body")
        expect(replacement.isSpectrumDeliveryInFlight && replacement.pendingSpectrumPush != nil,
               "retired completions cannot clear the current endpoint's in-flight or pending state")
        first.finish(5)
        await settle()
        expect(first.sent.count == beforeRevoke + 2 && first.sent.last!.script.contains(silence.scriptBody()),
               "the current endpoint still flushes its own latest values")
        expect(replacement.pushSequence == 2 && formattedValueCount == 384,
               "current endpoint sequence and shared prepared body remain independent")
        adapter.frameEndpointRegistry.revokeAll(in: first)
        let beforeExpired = first.sent.count
        let expired = adapter.frameEndpointRegistry.register(documentNonce: "expired", frameInfo: WKFrameInfo(4), in: first)!
        expired.leaseExpiresAt = 0
        adapter.pushAudioSpectrum(WebWallpaperSpectrumPush(levels), to: first)
        expect(!adapter.frameEndpointRegistry.hasEndpoints(in: first), "expired endpoints are revoked")
        expect(adapter.subscriptionRefreshes == 1, "lease revocation refreshes current media demand")
        expect(first.sent.count == beforeExpired, "expired endpoint receives no new spectrum")
        let disabled = adapter.frameEndpointRegistry.register(documentNonce: "disabled", frameInfo: WKFrameInfo(7), in: first)!
        disabled.audioDemandActive = true
        adapter.pushAudioSpectrum(WebWallpaperSpectrumPush(levels), to: first)
        adapter.pushAudioSpectrum(silence, to: first)
        let beforeDisabledReply = first.sent.count
        disabled.audioDemandActive = false
        first.finish(7)
        await settle()
        expect(first.sent.count == beforeDisabledReply && disabled.pendingSpectrumPush == nil,
               "an old completion cannot flush a document whose audio demand was withdrawn")
        print("spectrum delivery checks passed")
    }
}
'''


class WebSpectrumDeliveryTests(unittest.TestCase):
    def test_shared_body_latest_values_sequences_and_retired_documents(self):
        types = (HOST / "WebWallpaperHostTypes.swift").read_text()
        payload = source_block(types, "final class WebWallpaperSpectrumPush")
        # Count actual formatting calls without adding a product diagnostic seam.
        payload = payload.replace('String(format: "%.6f", $0)', 'formatSpectrumValue($0)')
        registry = source_block(types, "final class WebWallpaperFrameEndpointRegistry")
        delivery = (HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+FrameReply.swift").read_text()
        methods = "\n".join(method(delivery, marker) for marker in [
            "func sequencedPushScript(", "func pushAudioSpectrum(", "private func deliverAudioSpectrum(",
        ])
        harness = HARNESS.replace("// PRODUCTION_TYPES", "@MainActor\n" + payload + "\n@MainActor\n" + registry)
        harness = harness.replace("// PRODUCTION_METHODS", methods)
        with tempfile.TemporaryDirectory(prefix="mwx-web-spectrum-delivery-") as temporary:
            source = Path(temporary) / "Harness.swift"
            binary = Path(temporary) / "harness"
            source.write_text(harness)
            compiled = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(source), "-o", str(binary)],
                                      capture_output=True, text=True, timeout=90)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
