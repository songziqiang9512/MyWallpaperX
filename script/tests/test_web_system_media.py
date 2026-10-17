"""Exercise the product system-song reducer and D5 delivery in real WKWebView frames.

Only the platform producer is substituted. Snapshot/store, endpoint registry,
subscription/delivery methods, hello acknowledgement and all JS are product code.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method
from script.tests.test_web_compat_parity import HARNESS as PARITY_HARNESS, source_block

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host"

SERVICE = r'''
@MainActor final class SystemMediaService {
    static let shared = SystemMediaService()
    var currentSnapshot = SystemMediaSnapshot.empty
    var subscriptions: [UUID: (Bool, (SystemMediaSnapshot) -> Void)] = [:]
    var contentConsumerCount: Int { subscriptions.values.filter { $0.0 }.count }
    func subscribe(_ id: UUID, needsMedia: Bool = true, receive: @escaping (SystemMediaSnapshot) -> Void) {
        subscriptions[id] = (needsMedia, receive)
        receive(currentSnapshot)
    }
    func unsubscribe(_ id: UUID) { subscriptions.removeValue(forKey: id) }
    func publish(_ snapshot: SystemMediaSnapshot) {
        currentSnapshot = snapshot
        for (_, receive) in Array(subscriptions.values) { receive(snapshot) }
    }
}
'''
ADAPTER = r'''
@MainActor final class Adapter {
    struct Request { var id = UUID() }
    struct Surface { let webView: WKWebView }
    enum Severity { case warning }
    var surfaces: [Int: Surface] = [:]
    var currentRequest: Request? = Request()
    var frameEndpointRegistry = WebWallpaperFrameEndpointRegistry()
    let systemMediaConsumerID = UUID()
    var systemMediaSubscriptionNeedsContent: Bool?
    var currentSystemMediaSnapshot: SystemMediaSnapshot?
    func screenID(for view: WKWebView) -> Int? { surfaces.first { $0.value.webView === view }?.key }
    func forEachWebView(_ action: (WKWebView) -> Void) { surfaces.values.forEach { action($0.webView) } }
    func recordDiagnostic(type: String, severity: Severity, message: String, screenID: Int?, url: String?) {}
    func ensureFrameEndpointLeaseRenewalTimer() {}
    func applyCompatibilitySnapshot(to endpoint: WebWallpaperFrameEndpointRegistry.Endpoint, webView: WKWebView) {}
    // ADAPTER_METHODS
}
'''
HANDLER = r'''
@MainActor final class FrameEndpointHelloStub: NSObject, WKScriptMessageHandler {
    weak var adapter: Adapter?
    weak var webView: WKWebView?
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let adapter, let webView, let body = message.body as? [String: Any],
              let nonce = body["nonce"] as? String else { return }
        switch body["type"] as? String {
        case "mediaDemand": adapter.handleSystemMediaDemand(body, nonce: nonce, webView: webView)
        case "goodbye":
            if let token = body["token"] as? String,
               let endpoint = adapter.frameEndpointRegistry.endpoints(in: webView).first(where: {
                   $0.token == token && $0.documentNonce == nonce
               }) {
                adapter.frameEndpointRegistry.revoke(token: endpoint.token, in: webView)
                adapter.refreshSystemMediaSubscription()
            }
        default: adapter.handleFrameEndpointHello(nonce: nonce, frameInfo: message.frameInfo, webView: webView)
        }
    }
}
'''
SCENARIOS = r'''
@MainActor enum Scenarios {
    static let png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=="
    static func snapshot(_ title: String, revision: UInt64, playback: Int = 1, art: Bool = true,
                         enabled: Bool = true, position: Double = 12, session: UInt64 = 1) -> SystemMediaSnapshot {
        let media = SystemMediaSnapshotStore.Snapshot(
            current: art ? Data([1]) : nil, primaryColor: SIMD3(1, 0.5, 0), secondaryColor: SIMD3(0, 0.5, 1),
            generation: session, playbackState: playback, playbackGeneration: revision,
            properties: .init(title: title, artist: "Artist", subTitle: "", albumTitle: "Album",
                              albumArtist: "Album Artist", genres: "Rock", contentType: "music"),
            propertiesGeneration: session, timeline: .init(position: position, duration: 180), timelineGeneration: revision)
        return SystemMediaSnapshot(enabled: enabled, epoch: 1, revision: revision, sourceID: "test.player",
            sessionID: "track-\(session)", sessionGeneration: session, media: media, webThumbnail: art ? png : nil)
    }
    static let listeners = """
      window.events = { status: [], properties: [], thumbnail: [], timeline: [], playback: [] };
      wallpaperRegisterMediaStatusListener(x => events.status.push(x));
      wallpaperRegisterMediaPropertiesListener(x => {
        events.properties.push(x);
        window.atomicTitle = __myWallpaperMediaState.properties.title;
        window.atomicArt = __myWallpaperMediaState.thumbnail.thumbnail;
      });
      wallpaperRegisterMediaThumbnailListener(x => events.thumbnail.push(x));
      wallpaperRegisterMediaTimelineListener(x => events.timeline.push(x));
      wallpaperRegisterMediaPlaybackListener(x => events.playback.push(x));
    """
    static func run(_ name: String) async throws {
        switch name {
        case "legacy": try await legacyCallbacksAndEmptySession()
        case "cached-legacy": try await cachedLegacyOriginalObjectMutation()
        case "state": try await stateAndLifecycle()
        case "frames": try await framesAndNavigation()
        case "backpressure": try await backpressureAndRevocation()
        default: fatalError("unknown scenario")
        }
        expect(SystemMediaService.shared.subscriptions.isEmpty, "last media endpoint must release shared subscription")
        print("web-system-media-pass: \(name)")
    }
    static func stateAndLifecycle() async throws {
        let service = SystemMediaService.shared
        service.publish(snapshot("A", revision: 1))
        let host = PageHost(html: "<html><body><script>wallpaperRegisterMediaStatusListener(x => window.statusValue = x.enabled);</script></body></html>")
        defer { host.close() }
        try await host.open()
        try await host.waitUntil("window.statusValue === true", label: "status setting replay")
        expect(service.contentConsumerCount == 0 && service.subscriptions.count == 1, "status-only does not capture songs")
        _ = try await host.script(listeners)
        try await host.waitUntil("__myWallpaperMediaState.properties.title === 'A' && __myWallpaperMediaState.thumbnail.thumbnail.startsWith('data:image/png;base64,')", label: "late listeners receive current track")
        expect(service.contentConsumerCount == 1, "all listeners share one producer lease")
        try await host.waitUntil("window.atomicTitle === 'A' && window.atomicArt.startsWith('data:')", label: "atomic full-session publication")
        let colors = try await host.script("__myWallpaperMediaState.thumbnail.primaryColor") as? String
        expect(colors == "#ff8000", "normalized provider colors map to CSS")
        let coverEvents = try await host.script("events.thumbnail.length") as? Int
        let endpoint = host.adapter.frameEndpointRegistry.endpoints(in: host.view).first!
        // The payload builder itself omits the potentially large base64 image.
        let update = snapshot("A", revision: 2, position: 18)
        expect(Adapter.systemMediaPayload(update, needsContent: true, includeArtwork: false)["thumbnail"] == nil,
               "timeline-only updates must not encode artwork")
        service.publish(update)
        try await host.waitUntil("__myWallpaperMediaState.timeline.position === 18", label: "timeline delta")
        let coverEventsAfter = try await host.script("events.thumbnail.length") as? Int
        expect(coverEventsAfter == coverEvents, "unchanged cover must not dispatch again")
        // A page's own mediaSession and media nodes must never replace the system song.
        _ = try await host.script("""
          var audio = document.createElement('audio'); audio.src = 'page-background.mp3'; document.body.append(audio);
          if (navigator.mediaSession && window.MediaMetadata) navigator.mediaSession.metadata = new MediaMetadata({title:'Page title'});
          audio.dispatchEvent(new Event('loadedmetadata')); audio.dispatchEvent(new Event('timeupdate')); true;
        """)
        try await host.wait(0.15)
        let afterPageMedia = try await host.script("__myWallpaperMediaState.properties.title") as? String
        expect(afterPageMedia == "A", "page media cannot overwrite system track")
        _ = try await host.script("__myWallpaperSetPaused(true); true")
        service.publish(snapshot("B", revision: 3, art: false, session: 2))
        service.publish(snapshot("C", revision: 4, session: 3))
        try await host.wait(0.2)
        let whilePaused = try await host.script("__myWallpaperMediaState.properties.title") as? String
        expect(whilePaused == "A", "wallpaper pause merges media updates")
        _ = try await host.script("__myWallpaperSetPaused(false); true")
        try await host.waitUntil("__myWallpaperMediaState.properties.title === 'C' && __myWallpaperMediaState.thumbnail.thumbnail.startsWith('data:')", label: "resume replays newest complete state")
        service.publish(snapshot("C", revision: 5, playback: 0, session: 3))
        try await host.waitUntil("__myWallpaperMediaState.playback.state === wallpaperMediaIntegration.PLAYBACK_STOPPED", label: "zero-valued stopped state")
        service.publish(snapshot("D", revision: 6, playback: 2, art: false, session: 4))
        try await host.waitUntil("__myWallpaperMediaState.playback.state === wallpaperMediaIntegration.PLAYBACK_PAUSED && __myWallpaperMediaState.thumbnail.thumbnail === ''", label: "missing cover clears previous track")
        _ = try await host.script("__myWallpaperSetPaused(true); true")
        service.publish(snapshot("ignored", revision: 7, enabled: false))
        try await host.waitUntil("__myWallpaperMediaState.status.enabled === false && __myWallpaperMediaState.properties.title === '' && __myWallpaperMediaState.thumbnail.thumbnail === '' && __myWallpaperMediaState.timeline.duration === 0", label: "switch-off clears even while paused")
        _ = try await host.script("__myWallpaperSetPaused(false); true")
        service.publish(snapshot("E", revision: 8, session: 5))
        try await host.waitUntil("__myWallpaperMediaState.properties.title === 'E'", label: "re-enable track")
        // Force an old/ABA provider publication directly into the reducer with a
        // newer transport sequence. Provider revision must still reject it.
        var stale = Adapter.systemMediaPayload(snapshot("old", revision: 6), needsContent: true, includeArtwork: true)
        stale["deliverySequence"] = "999999"
        let staleJSON = String(data: try JSONSerialization.data(withJSONObject: stale), encoding: .utf8)!
        let token = WebWallpaperHostSupport.javaScriptQuotedString(endpoint.token)
        let nonce = WebWallpaperHostSupport.javaScriptQuotedString(endpoint.documentNonce)
        let rejected = try await host.script("__myWallpaperApplySystemMedia(\(staleJSON), \(token), \(nonce))") as? Bool
        expect(rejected == false, "old provider revision must be rejected")
        let wrongDocument = try await host.script("__myWallpaperApplySystemMedia(\(staleJSON), \(token), 'old-document')") as? Bool
        expect(wrongDocument == false, "stale document nonce must be rejected")
        // Exact UInt64 comparison above JS's integer range.
        var large = Adapter.systemMediaPayload(snapshot("UInt64", revision: UInt64.max), needsContent: true, includeArtwork: true)
        large["deliverySequence"] = "999999"
        let largeJSON = String(data: try JSONSerialization.data(withJSONObject: large), encoding: .utf8)!
        let accepted = try await host.script("__myWallpaperApplySystemMedia(\(largeJSON), \(token), \(nonce))") as? Bool
        expect(accepted == true, "UInt64 provider counter must keep exact precision")
        _ = try await host.script("window.dispatchEvent(new Event('pagehide')); true")
        try await host.wait(0.15)
        expect(service.subscriptions.isEmpty, "pagehide withdraws media demand immediately")
    }
    static func legacyCallbacksAndEmptySession() async throws {
        let service = SystemMediaService.shared
        service.publish(snapshot("legacy", revision: 1))
        let host = PageHost(html: "<html><body></body></html>")
        defer { host.close() }
        try await host.open()
        _ = try await host.script("wallpaperPropertyListener.updateMediaProperties = x => window.legacyTitle = x.title; true")
        try await host.waitUntil("window.legacyTitle === 'legacy'", label: "legacy object mutation acquires media")
        expect(service.contentConsumerCount == 1, "legacy callback demand starts one shared reader")
        _ = try await host.script("delete wallpaperPropertyListener.updateMediaProperties; true")
        try await host.wait(0.15)
        expect(service.subscriptions.isEmpty, "legacy callback removal withdraws demand")
        _ = try await host.script("wallpaperPropertyListener = { updateMediaStatus: x => window.legacyEnabled = x.enabled }; true")
        try await host.waitUntil("window.legacyEnabled === true", label: "legacy status replay")
        expect(service.contentConsumerCount == 0, "legacy status-only never captures media")
        _ = try await host.script("wallpaperPropertyListener = { updateMediaProperties: x => window.legacyTitle = x.title }; true")
        try await host.waitUntil("window.legacyTitle === 'legacy'", label: "legacy full callback replacement replay")
        var empty = SystemMediaSnapshot.empty
        empty.enabled = true; empty.epoch = 2; empty.revision = 2
        service.publish(empty)
        try await host.waitUntil("window.legacyTitle === '' && __myWallpaperMediaState.status.enabled === true && __myWallpaperMediaState.status.available === 'false'", label: "enabled without session clears fields")
        _ = try await host.script("wallpaperPropertyListener = {}; true")
        try await host.wait(0.15)
        expect(service.subscriptions.isEmpty, "empty legacy object releases subscription")
    }
    static func cachedLegacyOriginalObjectMutation() async throws {
        let service = SystemMediaService.shared
        service.publish(snapshot("cached-legacy", revision: 1))
        let host = PageHost(html: "<html><body></body></html>")
        defer { host.close() }
        try await host.open()
        try await host.waitUntil("__myWallpaperHostFrameEndpointAck === true", label: "legacy endpoint acknowledged")
        let endpoint = host.adapter.frameEndpointRegistry.endpoints(in: host.view).first!
        let token = WebWallpaperHostSupport.javaScriptQuotedString(endpoint.token)
        // Let the getter's microtask run before the asynchronous write through
        // the cached reference; no window access or DOM event detects this edit.
        _ = try await host.script("window.cachedListener = wallpaperPropertyListener; true")
        try await host.wait(0.15)
        _ = try await host.script("cachedListener.updateMediaProperties = x => window.cachedTitle = x.title; true")
        try await host.waitUntil("window.cachedTitle === 'cached-legacy'", label: "cached getter object assignment activates immediately")
        expect(service.contentConsumerCount == 1, "cached callback starts one shared reader")
        try await host.wait(0.15)
        _ = try await host.script("delete cachedListener.updateMediaProperties; true")
        _ = try await host.script("__myWallpaperHostFrameEndpointChallenge(\(token))")
        try await host.wait(0.15)
        expect(service.subscriptions.isEmpty, "cached callback deletion withdraws at lease challenge")
        // A Proxy returned by the getter cannot observe an author's independent
        // original reference, so exercise that separate counterexample too.
        _ = try await host.script("window.originalListener = {}; wallpaperPropertyListener = originalListener; true")
        try await host.wait(0.15)
        _ = try await host.script("originalListener.updateMediaProperties = x => window.originalTitle = x.title; true")
        try await host.waitUntil("window.originalTitle === 'cached-legacy'", label: "independent original object assignment activates immediately")
        expect(service.contentConsumerCount == 1, "independent original callback acquires demand")
        try await host.wait(0.15)
        _ = try await host.script("delete originalListener.updateMediaProperties; true")
        _ = try await host.script("__myWallpaperHostFrameEndpointChallenge(\(token))")
        try await host.wait(0.15)
        expect(service.subscriptions.isEmpty, "independent original callback deletion releases demand")
        _ = try await host.script("""
          window.accessorListener = {}; window.accessorCallback = null; window.setterCount = 0;
          Object.defineProperty(accessorListener, 'updateMediaProperties', {
            configurable: true, enumerable: true,
            get() { return window.accessorCallback; },
            set(value) { window.setterCount += 1; window.accessorCallback = value; }
          });
          wallpaperPropertyListener = accessorListener; true;
        """)
        try await host.wait(0.15)
        _ = try await host.script("accessorListener.updateMediaProperties = x => window.accessorTitle = x.title; true")
        try await host.waitUntil("window.accessorTitle === 'cached-legacy' && window.setterCount === 1", label: "original getter/setter preserved")
        // Non-configurable data fields retain their descriptor; subsequent raw
        // writes/deletes cannot be hooked and are reconciled by the same lease.
        _ = try await host.script("Object.defineProperty(accessorListener, 'updateMediaProperties', {configurable:false, writable:true, value:null}); true")
        _ = try await host.script("__myWallpaperHostFrameEndpointChallenge(\(token))")
        try await host.wait(0.15)
        expect(service.subscriptions.isEmpty, "non-configurable cleared field withdraws at lease")
        _ = try await host.script("accessorListener.updateMediaProperties = x => window.fixedTitle = x.title; true")
        _ = try await host.script("__myWallpaperHostFrameEndpointChallenge(\(token))")
        try await host.waitUntil("window.fixedTitle === 'cached-legacy' && Object.getOwnPropertyDescriptor(accessorListener,'updateMediaProperties').configurable === false", label: "non-configurable original field stays intact")
        _ = try await host.script("wallpaperPropertyListener = { updateMediaProperties() { wallpaperPropertyListener = {}; } }; true")
        try await host.wait(0.15)
        expect(service.subscriptions.isEmpty, "self-removing callback cannot leave stale outer demand")
    }
    static func framesAndNavigation() async throws {
        let service = SystemMediaService.shared
        service.publish(snapshot("frames-A", revision: 10))
        let child = "<html><body><script>" + listeners + "</script></body></html>"
        let escaped = child.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
        let page = "<html><body><iframe srcdoc=\"\(escaped)\"></iframe><iframe src='mwx-probe://child/index.html'></iframe><script>" + listeners + "</script></body></html>"
        let host = PageHost(html: page, crossOriginChildHTML: child)
        defer { host.close() }
        try await host.open()
        try await host.waitUntil("frames.length === 2 && frames[0].__myWallpaperMediaState.properties.title === 'frames-A'", label: "same-origin media")
        for _ in 0..<30 {
            if host.adapter.frameEndpointRegistry.endpoints(in: host.view).count == 3 { break }
            try await host.wait(0.1)
        }
        let endpoints = host.adapter.frameEndpointRegistry.endpoints(in: host.view)
        expect(endpoints.count == 3, "main, same-origin, and cross-origin endpoints registered")
        for endpoint in endpoints {
            let value: Any? = try await withCheckedThrowingContinuation { continuation in
                host.view.evaluateJavaScript("__myWallpaperMediaState.properties.title", in: endpoint.frameInfo, in: .page) {
                    continuation.resume(with: $0)
                }
            }
            expect(value as? String == "frames-A", "directed media push must reach each origin")
        }
        expect(service.subscriptions.count == 1 && service.contentConsumerCount == 1, "three frames share one subscription")
        let oldChild = endpoints.first { !$0.frameInfo.isMainFrame }!
        _ = try await host.script("frames[0].dispatchEvent(new Event('pagehide')); document.querySelector('iframe').srcdoc = '<html><body>new document</body></html>'; true")
        try await host.wait(0.3)
        let newNonce = try? await host.script("frames[0].__myWallpaperHostFrameDocumentNonce") as? String
        expect(!host.adapter.isSystemMediaEndpointCurrent(oldChild, in: host.view) || oldChild.documentNonce != newNonce, "child document identity changes")
        // Simulate native navigation/teardown's registry revocation, then deliver
        // a callback already queued for an old endpoint. It cannot reacquire or
        // schedule a push to the replacement document.
        host.adapter.frameEndpointRegistry.revokeAll(in: host.view)
        host.adapter.refreshSystemMediaSubscription()
        host.adapter.deliverSystemMedia(snapshot("stale", revision: 11), to: oldChild, webView: host.view)
        expect(service.subscriptions.isEmpty, "navigation revokes all per-frame demand")
    }
    static func backpressureAndRevocation() async throws {
        let service = SystemMediaService.shared
        service.publish(snapshot("start", revision: 20))
        let host = PageHost(html: "<html><body><script>" + listeners + "</script></body></html>")
        defer { host.close() }
        try await host.open()
        try await host.waitUntil("__myWallpaperMediaState.properties.title === 'start'", label: "initial media")
        let endpoint = host.adapter.frameEndpointRegistry.endpoints(in: host.view).first!
        for _ in 0..<30 {
            if !endpoint.isMediaDeliveryInFlight { break }; try await host.wait(0.05)
        }
        endpoint.isMediaDeliveryInFlight = true
        service.publish(snapshot("B", revision: 21, art: false, session: 2))
        service.publish(snapshot("C", revision: 22, session: 3))
        expect(endpoint.pendingMediaSnapshot?.media.properties?.title == "C", "slow endpoint keeps only latest complete publication")
        endpoint.isMediaDeliveryInFlight = false
        let pending = endpoint.pendingMediaSnapshot!
        endpoint.pendingMediaSnapshot = nil
        host.adapter.deliverSystemMedia(pending, to: endpoint, webView: host.view)
        try await host.waitUntil("__myWallpaperMediaState.properties.title === 'C' && __myWallpaperMediaState.thumbnail.thumbnail.startsWith('data:')", label: "coalesced artwork preserved")
        host.adapter.frameEndpointRegistry.revokeAll(in: host.view)
        host.adapter.refreshSystemMediaSubscription()
        host.adapter.deliverSystemMedia(snapshot("late", revision: 23), to: endpoint, webView: host.view)
        try await host.wait(0.1)
        expect(endpoint.pendingMediaSnapshot == nil, "revoked endpoint cannot retain/requeue pending media")
    }
}
@main enum Harness {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let name = CommandLine.arguments[1]
        Task { @MainActor in
            do { try await Scenarios.run(name); exit(0) }
            catch { print("web-system-media-failed: \(error)"); exit(1) }
        }
        NSApplication.shared.run()
    }
}
'''


class WebSystemMediaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-web-system-media-")
        cls.directory = Path(cls.temporary.name)
        types = (HOST / "WebWallpaperHostTypes.swift").read_text()
        base = PARITY_HARNESS[:PARITY_HARNESS.index("@MainActor\nenum Scenarios")]
        base = base.replace(source_block(base, "final class Adapter"), ADAPTER)
        base = base.replace(source_block(base, "final class WebWallpaperFrameEndpointRegistry"),
                            source_block(types, "final class WebWallpaperFrameEndpointRegistry"))
        base = base.replace(source_block(base, "final class FrameEndpointHelloStub"), HANDLER)
        base = base.replace("    // RUNTIME_HELPERS", "")
        base = base.replace("// RUNTIME_HELPERS", SERVICE)
        methods = method(types, "static func webCompatibilityScript(")
        methods += "\n" + method((HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+Lifecycle.swift").read_text(),
                                  "func handleFrameEndpointHello(")
        base = base.replace("// ADAPTER_METHODS", methods)
        base = base.replace("        endpointStub.webView = view", "        self.adapter.surfaces[1] = .init(webView: view)\n        endpointStub.webView = view")
        base = base.replace("    func close() { window.orderOut(nil) }", """    func close() {
            adapter.frameEndpointRegistry.revokeAll(in: view)
            adapter.surfaces.removeAll()
            adapter.refreshSystemMediaSubscription()
            view.stopLoading()
            window.orderOut(nil)
        }""")
        extension = (HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+SystemMedia.swift").read_text().replace(
            "extension DedicatedWebWallpaperHostPlaceholderAdapter", "extension Adapter")
        (cls.directory / "Harness.swift").write_text(base + extension + SCENARIOS)
        shared = ROOT / "MyWallpaperX/Core/Playback/SystemMedia"
        result = subprocess.run([
            "xcrun", "swiftc", "-parse-as-library", str(shared / "SystemMediaSnapshotStore.swift"),
            str(shared / "SystemMediaSnapshot.swift"), str(HOST / "WebWallpaperPlaybackScript.swift"),
            *map(str, sorted(HOST.glob("DedicatedWebWallpaperHostCompatibilityScript+*.swift"))),
            str(cls.directory / "Harness.swift"), "-o", str(cls.directory / "harness")
        ], text=True, capture_output=True, timeout=180)
        if result.returncode:
            cls.temporary.cleanup()
            raise AssertionError(result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def scenario(self, name):
        result = subprocess.run([str(self.directory / "harness"), name], text=True, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"web-system-media-pass: {name}", result.stdout)

    def test_cached_legacy_original_references_and_delete(self):
        self.scenario("cached-legacy")

    def test_legacy_callbacks_and_enabled_empty_session(self):
        self.scenario("legacy")

    def test_system_song_state_and_local_page_independence(self):
        self.scenario("state")

    def test_directed_frames_and_navigation_revoke(self):
        self.scenario("frames")

    def test_complete_latest_snapshot_and_endpoint_revocation(self):
        self.scenario("backpressure")
