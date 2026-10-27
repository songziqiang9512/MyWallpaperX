"""Exercise production endpoint audio demand, retirement, and ordered silence.

WebKit delivery is delayed by the harness. The real registry, surface message
handler, demand reducer, goodbye branch, lease work, and spectrum methods execute;
no CoreAudio device or App is started. A separate JS check runs actual registration
and hello-ACK source for pre-ACK and re-registration ordering. Media-control JS
also preserves author setters/notifications while deduplicating each target list.
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
    struct Request {
        let id = UUID()
        var propertiesJSON: String? = "{}"
        var rootURL = URL(fileURLWithPath: "/a")
        var resourceGrants: [WebWallpaperResourceGrant] = []
    }
    // DIRECTORY TYPES
    struct DirectoryAccessErrorKey: Hashable { let propertyName: String; let screenID: CGDirectDisplayID? }
    var directorySnapshotsByProperty: [String: DirectorySnapshot] = [:]
    var directoryAccessErrorsByProperty: [DirectoryAccessErrorKey: String] = [:]
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
    var resourceRefreshes = 0
    var directoryScans = 0
    var generalPropertyPushes = 0
    func applyGeneralProperties(to webView: WKWebView) { generalPropertyPushes += 1 }
    func refreshReadableResourceRoots(using propertiesJSON: String?) { resourceRefreshes += 1 }
    func syncFetchAllDirectoryProperties(using propertiesJSON: String) { directoryScans += 1 }
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
extension WKWebView {
    func evaluateJavaScript(_ script: String, completionHandler: ((Any?, Error?) -> Void)?) {
        sent.append(.init(script: script, frame: WKFrameInfo(-1), finish: { _ in }))
    }
}
enum WebWallpaperHostSupport {
    static func javaScriptQuotedString(_ value: String) -> String {
        String(data: try! JSONEncoder().encode(value), encoding: .utf8)!
    }
    static func javaScriptArrayLiteral(from values: [String]) -> String {
        String(data: try! JSONEncoder().encode(values), encoding: .utf8)!
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
        for _ in 0..<2 {
            adapter.applyCompatibilityState(to: first)
            adapter.applyCompatibilityState(to: second)
        }
        expect(adapter.resourceRefreshes == 0 && adapter.directoryScans == 0,
               "per-surface DOM-ready/didFinish state replay must not repeat global resource work")
        expect(first.sent.count == 2 && second.sent.count == 2, "every surface retains compatibility-state replay")
        first.sent.removeAll(); second.sent.removeAll()
        let propertyFrame = adapter.frameEndpointRegistry.register(documentNonce: "property-only", frameInfo: WKFrameInfo(30), in: first)!
        adapter.applyProperties(#"{"speed":{"value":4},"enabled":{"value":true}}"#, to: first)
        expect(adapter.generalPropertyPushes == 0 && first.sent.count == 1 && first.sent[0].frame.id == 30,
               "user property changes deliver the full payload without repeating unchanged general properties")
        print("property-push=" + String(data: try! JSONEncoder().encode(first.sent[0].script), encoding: .utf8)!)
        adapter.frameEndpointRegistry.revoke(token: propertyFrame.token, in: first)
        first.sent.removeAll(); first.pending.removeAll()
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
        snapshotAdapter.currentRequest!.propertiesJSON = #"{"slides":{"type":"directory","mode":"fetchall","value":"/a"},"blocked":{"type":"directory","mode":"fetchall","value":"/a/blocked"}}"#
        snapshotAdapter.directorySnapshotsByProperty = ["slides": .init(sourceDirectoryPath: "/a", filesByPath: ["/a/photo.jpg": 1, "/a/next.jpg": 2])]
        snapshotAdapter.directoryAccessErrorsByProperty = [
            .init(propertyName: "blocked", screenID: 1): "permission denied",
            .init(propertyName: "other-display-only", screenID: 2): "unrelated error"
        ]
        snapshotAdapter.handleFrameEndpointHello(nonce: "late-directory-child", frameInfo: WKFrameInfo(25), webView: snapshotView)
        let directorySnapshot = snapshotView.sent.last!
        expect(directorySnapshot.frame.id == 25, "late child receives its own current resource snapshot")
        print("directory-snapshot=" + String(data: try! JSONEncoder().encode(directorySnapshot.script), encoding: .utf8)!)
        snapshotAdapter.currentRequest!.propertiesJSON = #"{"slides":{"type":"directory","mode":"fetchall","value":"/a/new-selection"}}"#
        let lateReplacement = snapshotAdapter.frameEndpointRegistry.register(documentNonce: "late-directory-replacement", frameInfo: WKFrameInfo(26), in: snapshotView)!
        snapshotAdapter.applyCompatibilitySnapshot(to: lateReplacement, webView: snapshotView)
        var notReadySnapshots = [snapshotView.sent.last!.script]
        snapshotAdapter.currentRequest!.propertiesJSON = #"{"slides":{"type":"directory","mode":"fetchall","value":"/outside"}}"#
        snapshotAdapter.currentRequest!.resourceGrants = [.init(kind: .directory, url: URL(fileURLWithPath: "/outside"))]
        snapshotAdapter.directorySnapshotsByProperty = ["slides": .init(sourceDirectoryPath: "/outside", filesByPath: ["/outside/private.jpg": 1])]
        snapshotAdapter.currentRequest!.resourceGrants = []
        let lateRevoked = snapshotAdapter.frameEndpointRegistry.register(documentNonce: "late-directory-revoked", frameInfo: WKFrameInfo(27), in: snapshotView)!
        snapshotAdapter.applyCompatibilitySnapshot(to: lateRevoked, webView: snapshotView)
        notReadySnapshots.append(snapshotView.sent.last!.script)
        print("directory-not-ready=" + String(data: try! JSONEncoder().encode(notReadySnapshots), encoding: .utf8)!)
        print("snapshots=" + String(data: try! JSONEncoder().encode(snapshots), encoding: .utf8)!)
        print("endpoint audio demand checks passed")
    }
}
'''


class WebAudioDemandTests(unittest.TestCase):
    def test_media_sources_follow_values_and_actual_failures_not_url_names(self):
        resource = (HOST / "DedicatedWebWallpaperHostCompatibilityScript+BootstrapResourceRewriting.swift").read_text()
        interaction = (HOST / "DedicatedWebWallpaperHostCompatibilityScript+InteractionAndRuntimeMedia.swift").read_text()
        bridge = (HOST / "DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift").read_text()
        observers = (HOST / "DedicatedWebWallpaperHostCompatibilityScript+MediaObservers.swift").read_text()
        blocks = [source_block(resource, marker) + ";" for marker in (
            "  window.__myWallpaperRewriteLocalFileURL = function",
            "  const myWallpaperIsMediaOrSourceElement =",
            "  window.__myWallpaperIsInvalidMediaSourceValue = function",
            "  const myWallpaperClearInvalidMediaSource =",
            "  const myWallpaperMediaSourceDidChange =",
            "  const patchURLBackedProperty =",
        )]
        blocks += [
            "patchURLBackedProperty(HTMLMediaElement.prototype, 'src');",
            "patchURLBackedProperty(HTMLSourceElement.prototype, 'src');",
            "const originalSetAttribute = Element.prototype.setAttribute;",
            source_block(resource, "      Element.prototype.setAttribute = function") + ";",
            source_block(interaction, "  if (window.HTMLMediaElement && window.HTMLMediaElement.prototype)") ,
            source_block(observers, "    if (typeof HTMLMediaElement !== 'undefined' && typeof HTMLMediaElement.prototype.play === 'function')"),
            source_block(observers, "    if (typeof HTMLMediaElement !== 'undefined' && typeof HTMLMediaElement.prototype.pause === 'function')"),
            source_block(bridge, "  const wallpaperShouldResumeMediaAfterHostPause =") + ";",
            source_block(bridge, "  window.__myWallpaperSetPaused = function") + ";",
        ]
        scheme = (ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLocalSchemeHandler.swift").read_text()
        failure = method(scheme, "    func silenceFailedMediaRequestIfNeeded(")
        failure = failure.split('let script = """', 1)[1].split('"""', 1)[0]
        failure = failure.replace('\\(escapedRequestURL)', 'mwx-local://wallpaper/failed.mp4')
        script = r'''
const vm = require('node:vm'), assert = require('node:assert/strict');
const nodes = [], notifications = [];
class Element {
  constructor(tag) { this.tagName = tag; this.attributes = new Map(); this.children = []; this.parentElement = null; }
  setAttribute(name, value) { this.attributes.set(name, String(value)); }
  getAttribute(name) { return this.attributes.get(name) ?? null; }
  removeAttribute(name) { this.attributes.delete(name); }
  querySelectorAll(selector) { assert.equal(selector, 'source'); return this.children; }
}
const location = {href: 'mwx-local://wallpaper/index.html'};
class Media extends Element {
  constructor() { super('video'); this.playCalls = 0; this.pauseCalls = 0; this.loads = 0; this.paused = false; }
  get src() { const value = this.getAttribute('src'); return value ? new URL(value, location.href).href : ''; }
  set src(value) { this.attributes.set('src', String(value)); }
  get currentSrc() { return this.selectedSource ?? ''; }
  play() { this.playCalls++; this.paused = false; return Promise.resolve(); }
  pause() { this.pauseCalls++; this.paused = true; }
  load() { this.loads++; }
}
class Source extends Element {
  constructor() { super('source'); }
  get src() { const value = this.getAttribute('src'); return value ? new URL(value, location.href).href : ''; }
  set src(value) { this.attributes.set('src', String(value)); }
}
const context = {URL, Element, HTMLMediaElement: Media, HTMLSourceElement: Source,
  document: {location, querySelectorAll(selector) { assert.equal(selector, 'audio,video'); return nodes; }},
  hostLogger: null, rewriteStyleValue: value => value, audioContextInstances: [], audioStreams: [],
  playbackStateListeners: [paused => notifications.push(paused)],
  dispatchEvent() {}, __myWallpaperSetPagePaused() {},
  CustomEvent: function(type, init) { this.type = type; this.detail = init.detail; }};
context.window = context; vm.createContext(context);
vm.runInContext(PRODUCTION, context);
let validSources = 0;
const legal = ['null', 'undefined', '(null)', 'index.html', 'about:blank', location.href,
  'renamed/video.mp4', 'media/null', 'media/undefined', 'media/(null)', 'media/index.html',
  '/media/null', 'mwx-local://wallpaper/media/null',
  'https://example.invalid/media/null', 'https://example.invalid/media/index.html?variant=2',
  'file:///tmp/renamed/null', '/private/tmp/renamed/null'];
for (const value of legal) {
  assert.equal(context.__myWallpaperIsInvalidMediaSourceValue(value), false, value);
  const rewritten = context.__myWallpaperRewriteLocalFileURL(value);
  assert.ok(rewritten, value);
  if (value.startsWith('file:///') || value.startsWith('/private/')) assert.ok(rewritten.startsWith('mwx-local://wallpaper/__absolute__/'));
  for (const attribute of [false, true]) {
    const media = new Media();
    if (attribute) media.setAttribute('src', value); else media.src = value;
    assert.equal(media.getAttribute('src'), rewritten);
    media.play(); assert.equal(media.playCalls, 1, 'original media play receives ' + value);
    const source = new Source(); source.src = value;
    assert.equal(source.getAttribute('src'), rewritten, 'source element preserves same URL semantics');
    validSources++;
  }
}
for (const value of [null, undefined, '', '   ']) {
  assert.equal(context.__myWallpaperIsInvalidMediaSourceValue(value), true);
  assert.equal(context.__myWallpaperRewriteLocalFileURL(value), '');
  const media = new Media(); media.src = value;
  assert.equal(media.getAttribute('src'), null); media.play();
  assert.equal(media.playCalls, 1, 'native play owns resource selection and no-source failure');
}
const freshParent = new Media(), freshChild = new Source(); freshChild.src = 'media/null';
freshChild.parentElement = freshParent; freshParent.children = [freshChild];
assert.equal(freshParent.currentSrc || '', ''); assert.equal(freshParent.src || '', '');
freshParent.play(); assert.equal(freshParent.playCalls, 1, 'fresh source may be selected by native play');
const objectMedia = new Media(); objectMedia.srcObject = {};
assert.equal(objectMedia.src, ''); assert.equal(objectMedia.currentSrc, '');
objectMedia.play(); assert.equal(objectMedia.playCalls, 1, 'srcObject is handed to native play without a URL');
objectMedia.pause(); assert.equal(objectMedia.__myWallpaperAuthorPaused, true);
objectMedia.play(); assert.equal(objectMedia.__myWallpaperAuthorPaused, false);
assert.equal(objectMedia.playCalls, 2, 'author resume still delegates through both actual wrappers');
const knownMissing = new Media(); knownMissing.src = 'media/null'; knownMissing.__mwxMissingSource = knownMissing.src;
knownMissing.play(); assert.equal(knownMissing.playCalls, 0, 'actual failed-source marker still controls play');
for (const attribute of [false, true]) {
  const changed = new Media(); changed.src = 'failed.mp4';
  changed.__mwxMissingSource = changed.src; changed.selectedSource = changed.src;
  if (attribute) changed.setAttribute('src', 'media/null'); else changed.src = 'media/null';
  assert.equal(changed.__mwxMissingSource, undefined, 'accepted source invalidates only its old failed marker');
  changed.play(); assert.equal(changed.playCalls, 1);
}
for (const attribute of [false, true]) {
  const parent = new Media(), child = new Source(); child.src = 'failed.mp4';
  child.parentElement = parent; parent.children = [child]; parent.selectedSource = child.src;
  parent.__mwxMissingSource = child.src; child.__mwxMissingSource = child.src;
  if (attribute) child.setAttribute('src', 'media/undefined'); else child.src = 'media/undefined';
  assert.equal(child.__mwxMissingSource, undefined); assert.equal(parent.__mwxMissingSource, undefined);
  parent.play(); assert.equal(parent.playCalls, 1);
}
const replaced = new Media(), attachedLater = new Source();
replaced.__mwxMissingSource = 'mwx-local://wallpaper/failed.mp4'; replaced.selectedSource = replaced.__mwxMissingSource;
attachedLater.src = 'media/index.html'; replaced.children = [attachedLater]; attachedLater.parentElement = replaced;
replaced.play(); assert.equal(replaced.playCalls, 1, 'replacement before parent attachment invalidates stale failure at consumption');
const running = new Media(), authorPaused = new Media();
running.src = 'media/null'; authorPaused.src = 'media/renamed.mp4'; authorPaused.__myWallpaperAuthorPaused = true;
nodes.push(running, authorPaused);
context.__myWallpaperSetPaused(true); context.__myWallpaperSetPaused(false);
assert.equal(running.pauseCalls, 1); assert.equal(running.playCalls, 1, 'host resume uses legal named URL');
assert.equal(authorPaused.playCalls, 0, 'host does not resume an author-paused media element');
assert.deepEqual(notifications, [true, false]);
const failed = new Media(), failedSource = new Source(), alternative = new Source(), empty = new Source();
failed.src = 'failed.mp4'; failed.selectedSource = failed.src;
failedSource.src = 'failed.mp4'; alternative.src = 'media/null';
failed.children = [failedSource, alternative, empty]; nodes.length = 0; nodes.push(failed);
vm.runInContext(FAILURE, context);
assert.equal(failed.__mwxMissingSource, 'mwx-local://wallpaper/failed.mp4');
assert.equal(failed.getAttribute('src'), null); assert.equal(failedSource.getAttribute('src'), null);
assert.equal(alternative.getAttribute('src'), 'media/null', 'one real failure does not remove an unrelated valid fallback');
failed.play(); assert.equal(failed.playCalls, 1, 'remaining authored fallback can be consumed');
for (const childOnly of [false, true]) {
  const late = new Media(); late.selectedSource = 'mwx-local://wallpaper/failed.mp4';
  if (childOnly) { const next = new Source(); next.src = 'media/null'; next.parentElement = late; late.children = [next]; }
  else late.src = 'media/null';
  nodes.length = 0; nodes.push(late); vm.runInContext(FAILURE, context);
  assert.equal(late.__mwxMissingSource, undefined); assert.equal(late.pauseCalls, 0, 'late A failure cannot pause B');
  late.play(); assert.equal(late.playCalls, 1);
}
const stillFailed = new Media(); stillFailed.src = 'failed.mp4'; stillFailed.selectedSource = stillFailed.src;
nodes.length = 0; nodes.push(stillFailed); vm.runInContext(FAILURE, context);
stillFailed.play(); assert.equal(stillFailed.playCalls, 0, 'actual current failure without a new declaration stays suppressed');
assert.equal(stillFailed.__mwxMissingSource, 'mwx-local://wallpaper/failed.mp4');
console.log(JSON.stringify({validSources, noSourceCases: 4, missingMarker: true, authorPause: true,
  retainedAlternative: true, sourceChanges: true, lateFailure: true, currentFailure: true}));
'''.replace('PRODUCTION', json.dumps("\n".join(blocks))).replace('FAILURE', json.dumps(failure))
        result = subprocess.run(["node", "-e", script], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout), {
            "validSources": 34, "noSourceCases": 4, "missingMarker": True,
            "authorPause": True, "retainedAlternative": True,
            "sourceChanges": True, "lateFailure": True, "currentFailure": True,
        })

    def test_native_registration_retirement_multidisplay_and_old_callbacks(self):
        types = (HOST / "WebWallpaperHostTypes.swift").read_text()
        registry = source_block(types, "final class WebWallpaperFrameEndpointRegistry")
        payload = source_block(types, "final class WebWallpaperSpectrumPush")
        delivery = (HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+FrameReply.swift").read_text()
        lifecycle = (HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+Lifecycle.swift").read_text()
        navigation = (HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+NavigationDelegate.swift").read_text()
        methods = "\n".join(method(delivery, marker) for marker in [
            "func sequencedPushScript(", "func pushAudioSpectrum(", "func clearAudioSpectrum(",
            "func compatibilityStateScript(", "func applyCompatibilitySnapshot(", "func deliverStatePush(",
            "private func deliverAudioSpectrum(", "private func renewFrameEndpointLeases(",
        ]).replace("private func renewFrameEndpointLeases", "func renewFrameEndpointLeases")
        runtime = (HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift").read_text()
        methods += "\n" + method(runtime, "func applyCompatibilityState(")
        methods += "\n" + method(runtime, "func applyProperties(")
        methods += "\n" + method((HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+DirectorySync.swift").read_text(), "func parseFetchAllDirectoryProperties(")
        goodbye = lifecycle.split('            case "goodbye":', 1)[1].split('            case "hello", nil:', 1)[0]
        methods += '\nfunc goodbye(_ body: [String: Any], nonce: String, webView: WKWebView) {\n' + goodbye + '\n}\n'
        methods += method(navigation, "func webView(_ webView: WKWebView, didStartProvisionalNavigation")
        methods += "\n" + method(lifecycle, "func handleFrameEndpointHello(")
        base = DELIVERY_HARNESS.split("@main struct SpectrumDeliveryChecks", 1)[0]
        base = base.replace("    func refreshAudioSpectrumDemand() {}\n", "")
        base = base.replace("    let id: Int\n", "    let id: Int\n    var isMainFrame = false\n")
        directory_types = "\n".join(source_block(types, marker) for marker in ["struct DirectorySnapshot", "struct FetchAllDirectoryProperty"])
        state = ADAPTER_STATE.replace("// DIRECTORY TYPES", directory_types)
        base = base.replace("    let frameEndpointRegistry", state + "\n    let frameEndpointRegistry")
        base = base.replace("// PRODUCTION_TYPES", NATIVE_STUBS + "\n" + source_block(types, "struct WebWallpaperResourceGrant") + "\n@MainActor\n" + registry + "\n@MainActor\n" + payload)
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
            property_push = json.loads(next(line.removeprefix("property-push=") for line in result.stdout.splitlines()
                                             if line.startswith("property-push=")))
            projection = "const window={__myWallpaperApplyProperties:p=>{window.current=p}};\n" + property_push
            projection += "\nconsole.log(JSON.stringify(window.current));"
            projected = subprocess.run(["node", "-e", projection], capture_output=True, text=True, timeout=15)
            self.assertEqual(projected.returncode, 0, projected.stderr)
            self.assertEqual(json.loads(projected.stdout), {"speed": {"value": 4}, "enabled": {"value": True}})
            directory_snapshot = json.loads(next(line.removeprefix("directory-snapshot=") for line in result.stdout.splitlines()
                                                  if line.startswith("directory-snapshot=")))
            bridge = (HOST / "DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift").read_text()
            projection = method(bridge, "  window.__myWallpaperNotifyDirectoryFilesChanged =") + ";\n"
            projection += method(bridge, "  window.__myWallpaperNotifyDirectoryAccessError =") + ";\n"
            script = r'''
            const events=[], hostLogger=null, window={};
            const CustomEvent=function(type,init){this.type=type;this.detail=init.detail};
            for (const name of ['__myWallpaperNotifyPluginLoaded', '__myWallpaperApplyProperties',
                                '__myWallpaperApplyGeneralProperties', '__myWallpaperSetGlobalVolume',
                                '__myWallpaperSetPlaybackRate', '__myWallpaperApplyInitialPausedState',
                                '__myWallpaperPushAudioSpectrum']) window[name]=()=>{};
            window.dispatchEvent=e=>events.push(e);
            window.wallpaperPropertyListener={userDirectoryFilesAddedOrChanged:(name,files)=>events.push({type:'files',name,files})};
            '''

            script += projection + directory_snapshot
            script += "\nconsole.log(JSON.stringify({state:window.__myWallpaperDirectoryState,events}));"
            projected = subprocess.run(["node", "-e", script], capture_output=True, text=True, timeout=15)
            self.assertEqual(projected.returncode, 0, projected.stderr)
            current = json.loads(projected.stdout)
            self.assertEqual(current["state"], {"slides": ["/a/next.jpg", "/a/photo.jpg"]})
            self.assertEqual([e for e in current["events"] if e["type"] == "files"],
                             [{"type": "files", "name": "slides", "files": ["/a/next.jpg", "/a/photo.jpg"]}])
            self.assertEqual([e["detail"] for e in current["events"] if e["type"] == "wallpaper-directory-access-error"],
                             [{"propertyName": "blocked", "errorMessage": "permission denied"}])
            not_ready_snapshots = json.loads(next(line.removeprefix("directory-not-ready=") for line in result.stdout.splitlines()
                                                 if line.startswith("directory-not-ready=")))
            for pending_snapshot in not_ready_snapshots:
                fixture = "const directoryCalls=[]; const window={};\n"
                fixture += "for(const name of ['__myWallpaperNotifyPluginLoaded','__myWallpaperApplyProperties','__myWallpaperApplyGeneralProperties','__myWallpaperSetGlobalVolume','__myWallpaperSetPlaybackRate','__myWallpaperApplyInitialPausedState','__myWallpaperPushAudioSpectrum']) window[name]=()=>{};\n"
                fixture += "window.__myWallpaperNotifyDirectoryFilesChanged=(...args)=>directoryCalls.push(args);\n"
                fixture += pending_snapshot + "\nconsole.log(JSON.stringify(directoryCalls));"
                pending = subprocess.run(["node", "-e", fixture], capture_output=True, text=True, timeout=15)
                self.assertEqual(pending.returncode, 0, pending.stderr)
                self.assertEqual(json.loads(pending.stdout), [], "new paths and revoked grants must not replay an old directory")
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

    def test_media_control_deduplicates_objects_and_preserves_author_setters(self):
        bridge = (HOST / "DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift").read_text()
        discovery = source_block((HOST / "DedicatedWebWallpaperHostCompatibilityScript+MediaDiscovery.swift").read_text(),
                                 "const wallpaperMediaNodes = () =>")
        foundation = (HOST / "DedicatedWebWallpaperHostCompatibilityScript+BootstrapFoundation.swift").read_text()
        production = discovery + ";\n" + source_block(foundation, "window.wallpaperRegisterAudioStream = function(audio)")
        for marker in ["window.__myWallpaperSetGlobalVolume = function(value)",
                       "window.__myWallpaperSetPlaybackRate = function(value)"]:
            production += ";\n" + source_block(bridge, marker)
        script = r"""
const vm = require('node:vm'), assert = require('node:assert/strict');
function media(name, throwingGetter = false) {
  const state = { name, volume: 1, rate: 1, volumeWrites: 0, rateWrites: 0, reads: 0 };
  const node = {
    get volume() { state.reads++; if (throwingGetter) throw Error('author volume getter'); return state.volume; },
    set volume(value) { state.volume = value; state.volumeWrites++; },
    get playbackRate() { state.reads++; if (throwingGetter) throw Error('author rate getter'); return state.rate; },
    set playbackRate(value) { state.rate = value; state.rateWrites++; }
  };
  return { node, state };
}
function root(nodes, elements = []) {
  return { querySelectorAll(selector) {
    if (selector === 'audio,video') return nodes;
    assert.equal(selector, '*'); return elements;
  } };
}
function page(document) {
  const events = [], volumeCalls = [];
  const context = { document, audioStreams: [], volumeListeners: [value => volumeCalls.push(value)],
    CustomEvent: class { constructor(type, options) { this.type = type; this.detail = options.detail; } },
    dispatchEvent(event) { events.push(event); } };
  context.window = context; vm.createContext(context); vm.runInContext(PRODUCTION, context);
  return { context, events, volumeCalls,
    register: node => context.wallpaperRegisterAudioStream(node),
    volume: value => context.__myWallpaperSetGlobalVolume(value),
    rate: value => context.__myWallpaperSetPlaybackRate(value) };
}
const shared = media('DOM-and-stream'), shadow = media('shadow'), child = media('iframe');
const detached = media('registered-only'), accessor = media('author-accessor', true);
const childNodes = [child.node], mainNodes = [shared.node];
const childRoot = root(childNodes);
const mainRoot = root(mainNodes, [
  { shadowRoot: root([shadow.node]) }, { tagName: 'IFRAME', contentDocument: childRoot }
]);
const main = page(mainRoot), frame = page(childRoot);
for (let i = 0; i < 4; i++) main.register(shared.node);
main.register(detached.node); main.register(detached.node);
main.register(accessor.node); main.register(accessor.node);
main.volume(0.25); main.rate(1.5);
for (const target of [shared, shadow, child, detached, accessor]) {
  assert.equal(target.state.volume, 0.25, target.state.name);
  assert.equal(target.state.rate, 1.5, target.state.name);
  assert.equal(target.state.volumeWrites, 1, 'one object is written once per volume invocation: ' + target.state.name);
  assert.equal(target.state.rateWrites, 1, 'one object is written once per rate invocation: ' + target.state.name);
}
assert.equal(accessor.state.reads, 0, 'author writeable properties do not gain a getter prerequisite');
assert.deepEqual(main.volumeCalls, [0.25]);
assert.deepEqual(main.events.map(event => [event.type, event.detail]), [
  ['wallpaper-volume-changed', 0.25], ['wallpaper-playback-rate-changed', 1.5]
]);

// The parent retains coverage of a same-origin child before that child's
// endpoint update; the child also keeps its own notifications/control call.
frame.volume(0.25); frame.rate(1.5);
assert.equal(child.state.volumeWrites, 2); assert.equal(child.state.rateWrites, 2);
assert.deepEqual(frame.volumeCalls, [0.25]);
assert.deepEqual(frame.events.map(event => event.type), ['wallpaper-volume-changed', 'wallpaper-playback-rate-changed']);

// Author edits and new/detached/iframe media are rediscovered on every control
// event. No last-host-value early return may bypass them.
child.node.playbackRate = 0.75;
shared.node.volume = 0.9;
const late = media('new-DOM'), lateChild = media('new-iframe'), lateRegistered = media('new-stream');
mainNodes.push(late.node); childNodes.push(lateChild.node);
main.register(lateRegistered.node); main.register(lateRegistered.node);
main.volume(0.25); main.rate(1.5);
for (const target of [shared, shadow, child, detached, accessor, late, lateChild, lateRegistered]) {
  assert.equal(target.state.volume, 0.25, 'current volume reaches ' + target.state.name);
  assert.equal(target.state.rate, 1.5, 'current rate reaches ' + target.state.name);
}
assert.equal(child.state.rateWrites, 4, 'author-edited rate receives the later host value');
for (const target of [late, lateChild, lateRegistered]) {
  assert.equal(target.state.volumeWrites, 1); assert.equal(target.state.rateWrites, 1);
}
assert.equal(accessor.state.reads, 0);
main.volume(0.25); main.rate(1.5);
assert.deepEqual(main.volumeCalls, [0.25, 0.25, 0.25], 'same-value control calls retain author listeners');
assert.equal(main.events.filter(event => event.type === 'wallpaper-volume-changed').length, 3);
assert.equal(main.events.filter(event => event.type === 'wallpaper-playback-rate-changed').length, 3);
assert.equal(shared.state.rateWrites, 3, 'local deduplication does not alter subsequent control events');
assert.equal(detached.state.rateWrites, 3);
console.log('web-media-control-object-deduplication-pass');
""".replace("PRODUCTION", json.dumps(production))
        result = subprocess.run(["node", "-e", script], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("web-media-control-object-deduplication-pass", result.stdout)


def property_replay_behavior_script(properties: str, scheduling: str, debug: bool) -> str:
    """Exercise actual Swift-composed replay JS in Debug and Release.

    The Release isolation gate supplies product strings. Keep the scheduling and
    late-registration fixture here without interpreting Swift interpolation.
    """
    return r'''
const vm = require('node:vm'), assert = require('node:assert/strict');
function page(listener) {
  let nextID = 0, rafCount = 0;
  const timers = new Map(), frames = [], events = [], logs = [];
  const context = { hostLogger: DEBUG ? { post(type, message) { logs.push({type, message}); } } : undefined,
    document: { readyState: 'complete' },
    setTimeout(fn, delay) { const id = ++nextID; timers.set(id, { fn, delay }); return id; },
    clearTimeout(id) { timers.delete(id); },
    requestAnimationFrame(fn) { rafCount++; frames.push(fn); return ++nextID; },
    dispatchEvent(event) { events.push(event); },
    CustomEvent: class { constructor(type, init) { this.type = type; this.detail = init.detail; } },
    Event: class { constructor(type) { this.type = type; } },
    wallpaperPropertyListener: listener,
    __myWallpaperNormalizePropertyBag: value => value
  };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(PRODUCTION, context);
  const runTimer = delay => {
    const entry = Array.from(timers).find(([id, timer]) => timer.delay === delay);
    assert.ok(entry, 'expected timer delay=' + delay);
    timers.delete(entry[0]); entry[1].fn();
  };
  const settled = () => {
    while (frames.length) frames.shift()(0);
    runTimer(0);
  };
  return { context, logs, events, timers, frames, runTimer, settled, rafCount: () => rafCount };
}
const delivered = [];
const main = page({ applyUserProperties: value => delivered.push(value.speed.value) });
main.context.__myWallpaperApplyProperties({ speed: { value: 1 } });
main.runTimer(0);
assert.equal(main.frames.length, 1);
for (let value = 2; value <= 20; value++) {
  main.context.__myWallpaperApplyProperties({ speed: { value } });
}
assert.equal(main.frames.length, 1, 'updates while frames settle share the existing timer owner');
assert.equal(main.timers.size, 1, 'only the one existing settled-frame fallback remains');
main.settled();
assert.deepEqual(delivered, [20], 'one complete callback consumes the current property bag');
assert.equal(main.context.__myWallpaperPropertyReplayState.pendingProperties, null);
assert.equal(main.timers.size, 0);

const alreadyConsumed = [];
const empty = page({ applyUserProperties: value => alreadyConsumed.push(value.speed.value) });
empty.context.__myWallpaperApplyProperties({ speed: { value: 7 } });
empty.context.__myWallpaperDrainPendingProperties();
assert.deepEqual(alreadyConsumed, [7]);
empty.runTimer(0);
assert.equal(empty.rafCount(), 0, 'an emptied pending queue creates no RAF or fallback chain');
assert.equal(empty.timers.size, 0);

const alias = {}, late = [], waiting = page(alias);
waiting.context.__myWallpaperApplyProperties({ renamedSetting: { value: 'current' } });
waiting.runTimer(0); waiting.settled();
for (let attempt = 0; attempt < 3; attempt++) {
  waiting.runTimer(80); waiting.settled();
}
assert.equal(waiting.context.__myWallpaperPropertyReplayState.pendingSignature.length > 0, true);
Object.defineProperty(alias, 'applyUserProperties', {
  configurable: true, value: value => late.push(value.renamedSetting.value)
});
waiting.runTimer(80); waiting.settled();
assert.deepEqual(late, ['current'], 'late defineProperty on a captured alias remains supported');
assert.equal(waiting.timers.size, 0);
assert.equal(waiting.context.__myWallpaperPropertyReplayState.pendingProperties, null);

const stalledCalls = [], stalled = page({ applyUserProperties: value => stalledCalls.push(value.mode.value) });
stalled.context.__myWallpaperApplyProperties({ mode: { value: 'fallback' } });
stalled.runTimer(0); stalled.runTimer(250);
assert.deepEqual(stalledCalls, ['fallback'], 'stalled author RAF retains the existing fallback');

const isolatedCalls = [];
let brokenCalls = 0;
const isolated = page({ applyUserProperties(value) {
  if (Object.keys(value).length !== 1) throw new Error('Cannot read properties of undefined');
  const [key, property] = Object.entries(value)[0];
  if (key === 'broken') { brokenCalls++; throw new Error('author isolated failure'); }
  if (key === 'tint' && !Array.isArray(property.value)) throw new Error('push is not a function');
  isolatedCalls.push([key, property.value]);
} });
isolated.context.__myWallpaperApplyProperties({
  speed: { value: 0.75 }, broken: { value: true }, tint: { type: 'color', value: '0.1 0.2 0.3' }
});
isolated.runTimer(0); isolated.settled();
for (const delay of [80, 140, 220, 340, 520, 780, 1100, 1400, 1800, 2200, 2600, 3000]) {
  isolated.runTimer(delay); isolated.settled();
}
assert.deepEqual(JSON.parse(JSON.stringify(isolatedCalls)), [['speed', 0.75], ['tint', [0.1, 0.2, 0.3]]],
  'exhausted initialization retries still isolate properties and preserve color-array compatibility');
assert.equal(isolated.context.__myWallpaperPropertyReplayState.pendingProperties, null);
assert.equal(isolated.timers.size, 0);
assert.equal(isolated.events.filter(event => event.type === 'wallpaper-properties-applied').length, 1);
assert.equal(isolated.logs.filter(log => log.type === 'properties.skipped').length, DEBUG ? 1 : 0);
assert.equal(isolated.logs.some(log => log.type === 'properties.applied.partial' && log.message === 'applied=2 skipped=1'), DEBUG);
assert.equal(Object.hasOwn(isolated.context.__myWallpaperPropertyReplayState, 'reportedSkips'), DEBUG,
  'Release has no diagnostic history even after a real isolated callback failure');
vm.runInContext('myWallpaperApplyPropertiesIndividually({broken:{value:true}}, window.wallpaperPropertyListener,' +
  'window.wallpaperPropertyListener.applyUserProperties, window.__myWallpaperLastAppliedUserPropertySignature);' +
  'myWallpaperApplyPropertiesIndividually({broken:{value:true}}, window.wallpaperPropertyListener,' +
  'window.wallpaperPropertyListener.applyUserProperties, window.__myWallpaperLastAppliedUserPropertySignature);', isolated.context);
assert.equal(brokenCalls, 3, 'diagnostic deduplication cannot gate author callbacks');
assert.equal(isolated.logs.filter(log => log.type === 'properties.skipped').length, DEBUG ? 1 : 0);

const colorCalls = [];
const color = page({ applyUserProperties(value) {
  colorCalls.push(value.tint.value);
  if (!Array.isArray(value.tint.value)) throw new Error('push is not a function');
} });
color.context.__myWallpaperApplyProperties({ tint: { type: 'color', value: '0.2 0.4 0.6' } });
color.runTimer(0); color.settled();
assert.deepEqual(JSON.parse(JSON.stringify(colorCalls)), ['0.2 0.4 0.6', [0.2, 0.4, 0.6]]);
assert.equal(color.timers.size, 0, 'color compatibility does not start initialization retries');
assert.equal(color.events.filter(event => event.type === 'wallpaper-properties-applied').length, 1);

let sideEffects = 0, asynchronousCalls = 0;
const asynchronous = page({ applyUserProperties() {
  asynchronousCalls++;
  asynchronous.context.setTimeout(() => { sideEffects++; }, 17);
  throw new Error('Cannot read properties of undefined');
} });
asynchronous.context.__myWallpaperApplyProperties({ delayed: { value: true } });
asynchronous.runTimer(0); asynchronous.settled(); asynchronous.runTimer(17);
assert.equal(sideEffects, 1);
assert.equal(asynchronousCalls, 1, 'initialization failure after scheduling work cannot repeat author side effects');
assert.equal(asynchronous.timers.size, 0);
assert.equal(asynchronous.context.__myWallpaperPropertyReplayState.pendingProperties, null);

let failedCalls = 0;
const failed = page({ applyUserProperties() { failedCalls++; throw new Error('author property failed'); } });
failed.context.__myWallpaperApplyProperties({ renamedMode: { value: true } });
failed.runTimer(0); failed.settled(); failed.settled();
assert.equal(failedCalls, 1, 'non-initialization failure does not loop callbacks');
assert.equal(failed.events.filter(event => event.type === 'resize').length, 1,
  'resize compatibility survives diagnostic stripping');
assert.equal(failed.timers.size, 0);
console.log('web-pending-property-replay-pass');
'''.replace("PRODUCTION", json.dumps(scheduling + ";\n" + properties)).replace("DEBUG", json.dumps(debug))
