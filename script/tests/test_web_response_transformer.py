from __future__ import annotations

import shutil
import json
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

from script.tests.test_web_compat_parity import source_block


ROOT = Path(__file__).resolve().parents[2]
# 转换器 + mwx-local resolve：两类断言共用一次 swiftc 编译，覆盖 Support 层
# 的响应改写与受控读取解析（resolve 百分号合同见 harness 末段）。
TRANSFORMER_SOURCES = [
    ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host/WebRuntimeDiagnosticsStore.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLocalSchemeHandler.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLocalSchemeHandler+Resolve.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLocalSchemeHandler+IO.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperResponseTransformer.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperHTMLTransformer.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperCSSImportTransformer.swift",
]


def remote_stylesheet_behavior_script(production: str, debug: bool) -> str:
    """Execute the Swift-composed recovery script against controlled DOM/events."""
    return r'''
const vm = require('node:vm'), assert = require('node:assert/strict');
function page(layer = null) {
  let clock = 0, clockCalls = 0, nextTimer = 0, mutation;
  const timers = new Map(), scheduled = [], logs = [], capturedStates = [];
  const links = [], styles = [], documentEvents = new Map();
  const location = {href: 'mwx-local://wallpaper/index.html'};
  class Element {
    constructor(name) { this.nodeName = name.toUpperCase(); this.attributes = new Map(); this.events = new Map(); this.isConnected = false; this.sheet = null; }
    setAttribute(name, value) { this.attributes.set(name, String(value)); }
    getAttribute(name) { return this.attributes.get(name) ?? null; }
    hasAttribute(name) { return this.attributes.has(name); }
    removeAttribute(name) { this.attributes.delete(name); }
    addEventListener(type, callback) { const set = this.events.get(type) ?? new Set(); set.add(callback); this.events.set(type, set); }
    removeEventListener(type, callback) { this.events.get(type)?.delete(callback); }
    fire(type) { for (const callback of [...(this.events.get(type) ?? [])]) callback({target: this}); }
    remove() { this.isConnected = false; }
    querySelectorAll() { return []; }
    querySelector() { return null; }
  }
  class Link extends Element {
    constructor() { super('link'); this.relList = {contains: name => this.rel.split(/\s+/).includes(name)}; }
    get rel() { return this.getAttribute('rel') ?? ''; }
    set rel(value) { this.setAttribute('rel', value); }
    get as() { return this.getAttribute('as') ?? ''; }
    set as(value) { this.setAttribute('as', value); }
    get href() { return new URL(this.getAttribute('href') ?? '', location.href).href; }
    set href(value) { this.setAttribute('href', value); }
  }
  const link = new Link();
  link.rel = 'preload'; link.as = 'style'; link.href = 'https://fonts.googleapis.com/original.css';
  link.setAttribute('data-mwx-deferred-stylesheet', 'stylesheet');
  link.setAttribute('crossorigin', 'anonymous'); link.setAttribute('integrity', 'sha256-authored');
  if (layer !== null) link.setAttribute('data-mwx-import-layer', layer);
  link.isConnected = true; links.push(link);
  const head = {appendChild(node) { node.isConnected = true; return node; }};
  const document = {nodeName: '#document', location, head, documentElement: head, styleSheets: [], adoptedStyleSheets: [],
    createElement(name) {
      if (name === 'link') { const node = new Link(); links.push(node); return node; }
      assert.equal(name, 'style'); const node = new Element('style'); styles.push(node); return node;
    },
    addEventListener(type, callback) { const list = documentEvents.get(type) ?? []; list.push(callback); documentEvents.set(type, list); },
    querySelectorAll(selector) { assert.equal(selector, 'link[data-mwx-deferred-stylesheet]'); return links.filter(node => node.isConnected && node.hasAttribute('data-mwx-deferred-stylesheet')); },
    querySelector() { return null; }
  };
  class ObservedWeakMap extends WeakMap { set(key, value) { capturedStates.push(value); return super.set(key, value); } }
  const context = {document, URL, HTMLLinkElement: Link, WeakMap: ObservedWeakMap,
    MutationObserver: class { constructor(callback) { mutation = callback; } observe() {} },
    performance: {now() { clockCalls++; return clock; }}, Date: {now: () => clock},
    webkit: {messageHandlers: {wallpaperHostLog: {postMessage(value) { logs.push(value); }}}},
    setTimeout(callback, delay) { const id = ++nextTimer; timers.set(id, {callback, deadline: clock + delay}); scheduled.push(delay); return id; },
    clearTimeout(id) { timers.delete(id); }
  };
  context.window = context;
  vm.createContext(context); vm.runInContext(PRODUCTION, context);
  const advance = milliseconds => {
    const target = clock + milliseconds;
    let deliveries = 0;
    while (true) {
      const next = [...timers].filter(([, timer]) => timer.deadline <= target)
        .sort((a, b) => a[1].deadline - b[1].deadline)[0];
      if (!next) break;
      assert.ok(++deliveries < 10000, 'controlled timer queue did not settle');
      timers.delete(next[0]); clock = next[1].deadline; next[1].callback();
    }
    clock = target;
  };
  return {link, links, styles, timers, scheduled, logs, capturedStates, advance,
    state: () => capturedStates.at(-1), clockCalls: () => clockCalls,
    fire(type) { for (const callback of documentEvents.get(type) ?? []) callback({target: link}); },
    attribute() { mutation([{type: 'attributes', target: link}]); },
    remove() { link.remove(); mutation([{type: 'childList', removedNodes: [link], addedNodes: []}]); },
    probes: () => links.filter(node => node.hasAttribute('data-mwx-remote-stylesheet-probe')),
    activeProbes: () => links.filter(node => node.isConnected && node.hasAttribute('data-mwx-remote-stylesheet-probe'))
  };
}

const waiting = page();
assert.equal(waiting.state().phase, 'initial');
for (const field of ['startedAt', 'degraded', 'degradedTimer']) assert.equal(Object.hasOwn(waiting.state(), field), DEBUG);
assert.deepEqual(waiting.scheduled, DEBUG ? [3000] : []);
assert.equal(waiting.clockCalls(), DEBUG ? 1 : 0, 'Release must not sample an unused diagnostic start time');
waiting.advance(4000);
assert.equal(waiting.state().phase, 'initial', 'degraded logging never drives recovery');
assert.equal(waiting.logs.some(log => log.type === 'resource.remote-stylesheet.degraded'), DEBUG);
waiting.link.sheet = {}; waiting.fire('load');
assert.equal(waiting.state().phase, 'applied');
assert.equal(waiting.link.rel, 'stylesheet'); assert.equal(waiting.timers.size, 0);
assert.equal(waiting.logs.some(log => log.type === 'resource.remote-stylesheet.recovered'), DEBUG);
assert.equal(waiting.logs.length > 0, DEBUG, 'Release has no logger even when a native log handler exists');

const retry = page(); retry.fire('error');
assert.equal(retry.state().phase, 'waiting-retry');
retry.advance(1999); assert.equal(retry.probes().length, 0);
retry.advance(1); assert.equal(retry.activeProbes().length, 1);
const firstProbe = retry.probes()[0];
assert.equal(firstProbe.getAttribute('crossorigin'), 'anonymous');
assert.equal(firstProbe.getAttribute('integrity'), 'sha256-authored');
retry.advance(14999); assert.equal(firstProbe.isConnected, true);
retry.advance(1); assert.equal(firstProbe.isConnected, false, 'real request deadline remains 15 seconds');
assert.equal(firstProbe.events.get('load').size, 0); assert.equal(firstProbe.events.get('error').size, 0);
retry.advance(3999); assert.equal(retry.probes().length, 1);
retry.advance(1); const secondProbe = retry.probes()[1];
assert.equal(secondProbe.isConnected, true); retry.link.sheet = {}; secondProbe.fire('load');
assert.equal(retry.state().phase, 'applied'); assert.equal(retry.link.rel, 'stylesheet');
assert.ok(new URL(retry.link.href).searchParams.get('__mwx_retry').startsWith('2_'));
assert.equal(retry.activeProbes().length, 0); assert.equal(retry.timers.size, 0);

const exhausted = page(); exhausted.fire('error');
for (const [index, delay] of [2000, 4000, 8000, 16000, 30000].entries()) {
  exhausted.advance(delay); assert.equal(exhausted.probes().length, index + 1);
  exhausted.probes()[index].fire('error');
}
assert.equal(exhausted.state().phase, 'failed'); assert.equal(exhausted.link.rel, 'stylesheet');
assert.equal(exhausted.link.hasAttribute('data-mwx-deferred-stylesheet'), false);
assert.equal(exhausted.activeProbes().length, 0); assert.equal(exhausted.timers.size, 0);

for (const layer of ['theme', '']) {
  const applied = page(layer); applied.fire('load');
  assert.equal(applied.styles.length, 1);
  const style = applied.styles[0];
  assert.equal(style.textContent, `@import url("https://fonts.googleapis.com/original.css") ${layer ? 'layer(theme)' : 'layer'};`);
  assert.equal(applied.link.rel, 'preload', 'layer recovery never applies an unlayered stylesheet');
  style.sheet = {cssRules: [{styleSheet: {cssRules: [{}]}}]}; applied.advance(50);
  assert.equal(applied.state().phase, 'applied'); assert.equal(applied.timers.size, 0);
  assert.equal(applied.link.hasAttribute('data-mwx-deferred-stylesheet'), true);
  const timedOut = page(layer); timedOut.fire('load'); timedOut.advance(4999);
  assert.equal(timedOut.state().phase, 'activating'); timedOut.advance(1);
  assert.equal(timedOut.state().phase, 'failed'); assert.equal(timedOut.link.rel, 'preload');
  assert.equal(timedOut.styles[0].isConnected, true, 'late CSS can still apply within its original layer');
  assert.equal(timedOut.timers.size, 0);
}
const activation = page(); activation.fire('load'); activation.advance(4999);
assert.equal(activation.state().phase, 'activating'); activation.advance(1);
assert.equal(activation.state().phase, 'failed'); assert.equal(activation.timers.size, 0);

const switched = page(); switched.fire('error'); switched.advance(2000);
const oldProbe = switched.probes()[0], oldLoaded = [...oldProbe.events.get('load')][0];
const oldState = switched.state(); switched.link.href = 'https://fonts.googleapis.com/replaced.css'; switched.attribute();
assert.equal(oldState.phase, 'cancelled'); assert.equal(oldProbe.isConnected, false);
oldLoaded(); assert.equal(switched.state().phase, 'initial');
switched.link.sheet = {}; switched.fire('load');
assert.equal(switched.state().phase, 'applied'); assert.equal(switched.timers.size, 0);
assert.equal(switched.link.href, 'https://fonts.googleapis.com/replaced.css');

const removed = page(); removed.fire('error'); removed.advance(2000);
const pending = removed.probes()[0], lateFailure = [...pending.events.get('error')][0];
removed.remove(); lateFailure(); removed.advance(60000);
assert.equal(removed.state().phase, 'cancelled'); assert.equal(removed.activeProbes().length, 0);
assert.equal(removed.timers.size, 0); assert.equal(removed.probes().length, 1);
const waitingRemoved = page(); waitingRemoved.fire('error'); waitingRemoved.remove(); waitingRemoved.advance(60000);
assert.equal(waitingRemoved.state().phase, 'cancelled'); assert.equal(waitingRemoved.probes().length, 0);
assert.equal(waitingRemoved.timers.size, 0, 'removal also cancels an unstarted retry');
const layerRemoved = page('theme'); layerRemoved.fire('load'); layerRemoved.styles[0].remove(); layerRemoved.advance(50);
assert.equal(layerRemoved.state().phase, 'cancelled'); assert.equal(layerRemoved.timers.size, 0);
console.log('remote-stylesheet-state-machine-pass');
'''.replace("PRODUCTION", json.dumps(production)).replace("DEBUG", json.dumps(debug))


class WebResponseTransformerTests(unittest.TestCase):
    def test_production_transformers(self) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")

        harness = textwrap.dedent(
            r'''
            import Foundation

            var responseUTF8Decodes = 0
            func observedResponseUTF8Decode(_ data: Data) -> String? {
                responseUTF8Decodes += 1
                return String(data: data, encoding: .utf8)
            }

            func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
                guard condition() else {
                    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
                    exit(1)
                }
            }

            func markerCount(_ value: String) -> Int {
                value.components(separatedBy: "data-mwx-deferred-stylesheet").count - 1
            }

            let googleLink = #"<link rel='stylesheet' href='http://fonts.googleapis.com/css2?family=Inter'>"#
            let transformedGoogleLink = WebWallpaperHTMLTransformer.transform(googleLink)
            expect(transformedGoogleLink.contains("rel='preload'"), "Google Fonts link should become a preload")
            expect(transformedGoogleLink.contains("href='https://fonts.googleapis.com/css2?family=Inter'"), "Google Fonts HTTP links should upgrade to HTTPS")
            expect(transformedGoogleLink.contains("as=\"style\""), "deferred link should identify a style preload")
            expect(transformedGoogleLink.contains("data-mwx-deferred-stylesheet=\"stylesheet\""), "original rel should be retained")

            let protocolRelativeLink = #"<link href="//fonts.googleapis.com/css2?family=Fira+Code" rel="stylesheet">"#
            let transformedProtocolRelativeLink = WebWallpaperHTMLTransformer.transform(protocolRelativeLink)
            expect(transformedProtocolRelativeLink.contains(#"href="https://fonts.googleapis.com/css2?family=Fira+Code""#), "protocol-relative Google Fonts links should become absolute HTTPS URLs")
            expect(transformedProtocolRelativeLink.contains(#"rel="preload""#), "href-before-rel links should still replace rel correctly")
            expect(markerCount(transformedProtocolRelativeLink) == 1, "protocol-relative Google Fonts links should transform once")

            let quotedGreaterThan = #"<link title='a > b' rel='stylesheet' href='https://fonts.googleapis.com/css2?family=Roboto'>"#
            let transformedQuotedGreaterThan = WebWallpaperHTMLTransformer.transform(quotedGreaterThan)
            expect(transformedQuotedGreaterThan.contains("title='a > b'"), "quoted greater-than should not truncate a tag")
            expect(markerCount(transformedQuotedGreaterThan) == 1, "quoted greater-than link should transform once")

            let rawText = #"""
            <!-- <link rel="stylesheet" href="https://fonts.googleapis.com/comment"> -->
            <script>const template = '<link rel="stylesheet" href="https://fonts.googleapis.com/script">';</script>
            <style>.sample::before { content: '<link rel="stylesheet" href="https://fonts.googleapis.com/style">'; }</style>
            <textarea><link rel="stylesheet" href="https://fonts.googleapis.com/textarea"></textarea>
            <title><link rel="stylesheet" href="https://fonts.googleapis.com/title"></title>
            <link rel="stylesheet" href="https://fonts.googleapis.com/real">
            """#
            expect(markerCount(WebWallpaperHTMLTransformer.transform(rawText)) == 1, "raw text and comments must remain untouched")

            let expandedRawText = #"""
            <xmp><link rel="stylesheet" href="https://fonts.googleapis.com/xmp"></xmp>
            <iframe><link rel="stylesheet" href="https://fonts.googleapis.com/iframe-fallback"></iframe>
            <noembed><link rel="stylesheet" href="https://fonts.googleapis.com/noembed"></noembed>
            <noframes><link rel="stylesheet" href="https://fonts.googleapis.com/noframes"></noframes>
            <noscript><link rel="stylesheet" href="https://fonts.googleapis.com/noscript"></noscript>
            <link rel="stylesheet" href="https://fonts.googleapis.com/after-raw-text">
            """#
            expect(markerCount(WebWallpaperHTMLTransformer.transform(expandedRawText)) == 1, "legacy raw-text and iframe fallback content must remain untouched")

            let plaintext = #"<link rel="stylesheet" href="https://fonts.googleapis.com/before-plaintext"><plaintext><link rel="stylesheet" href="https://fonts.googleapis.com/inside-plaintext"></plaintext><link rel="stylesheet" href="https://fonts.googleapis.com/after-plaintext-close">"#
            expect(markerCount(WebWallpaperHTMLTransformer.transform(plaintext)) == 1, "plaintext should consume the rest of its parent document")

            let iframeDocument = #"<link rel="stylesheet" href="https://fonts.googleapis.com/iframe-document">"#
            expect(markerCount(WebWallpaperHTMLTransformer.transform(iframeDocument)) == 1, "an independently loaded iframe document should still transform")

            let skippedLinks = [
                #"<link rel="alternate stylesheet" href="https://fonts.googleapis.com/a">"#,
                #"<link rel="stylesheet" href="https://fonts.googleapis.com/a" disabled>"#,
                #"<link rel="stylesheet" href="https://fonts.googleapis.com/a" media="print">"#,
                #"<link rel="stylesheet" href="https://fonts.googleapis.com/a" as="style">"#,
                #"<link rel="stylesheet" href="https://fonts.googleapis.com/a" onload="ready()">"#,
                #"<link rel="stylesheet" href="https://fonts.googleapis.com/a" data-mwx-deferred-stylesheet="stylesheet">"#,
                #"<link rel="stylesheet" data-href="https://fonts.googleapis.com/a">"#,
                #"<link data-rel="stylesheet" href="https://fonts.googleapis.com/a">"#,
                #"<link rel="stylesheet" href="https://cdn.example.com/business.css">"#,
                #"<link rel="stylesheet" href="https://fonts.googleapis.com/a" type="text/plain">"#,
            ]
            for (index, link) in skippedLinks.enumerated() {
                expect(WebWallpaperHTMLTransformer.transform(link) == link, "skip boundary \(index) should remain byte-for-byte unchanged")
            }

            let optedIn = #"<link rel="stylesheet" href="http://127.0.0.1:48765/slow.css" data-mwx-defer-stylesheet>"#
            let transformedOptedIn = WebWallpaperHTMLTransformer.transform(optedIn)
            expect(markerCount(transformedOptedIn) == 1, "explicit opt-in should defer a non-Google stylesheet")
            expect(transformedOptedIn.contains(#"href="http://127.0.0.1:48765/slow.css""#), "explicit non-Google opt-in should preserve its authored URL")

            let css = #"""
            @charset "UTF-8";
            /* leading comment */
            @layer reset;
            @import url("http://fonts.googleapis.com/css2?family=Inter");
            body { color: black; }
            @import "https://fonts.googleapis.com/css2?family=Late";
            """#
            let transformedCSS = WebWallpaperCSSImportTransformer.transform(css)
            expect(transformedCSS.contains(#"@import url("https://fonts.googleapis.com/css2?family=Inter") not all;"#), "eligible Google import should be deferred and upgraded to HTTPS")
            expect(transformedCSS.contains(#"@import "https://fonts.googleapis.com/css2?family=Late";"#), "late import should remain untouched")

            let supportedGoogleImports = [
                #"@import url(https://fonts.googleapis.com/css2?family=Roboto);"#,
                #"@import "//fonts.googleapis.com/css2?family=Lato";"#,
                #"@import url('//fonts.googleapis.com/css2?family=Nunito');"#,
                #"@import url(//fonts.googleapis.com/css2?family=Oswald);"#,
            ]
            for (index, statement) in supportedGoogleImports.enumerated() {
                let transformed = WebWallpaperCSSImportTransformer.transform(statement)
                expect(transformed.hasPrefix(#"@import url("https://fonts.googleapis.com/"#), "supported Google import \(index) should normalize to HTTPS")
                expect(transformed.hasSuffix(#"") not all;"#), "supported Google import \(index) should become nonblocking")
            }

            let cssStringOnly = #"body::before { content: '@import "https://fonts.googleapis.com/not-a-rule";'; }"#
            expect(WebWallpaperCSSImportTransformer.transform(cssStringOnly) == cssStringOnly, "CSS strings must remain untouched")
            let conditionalImport = #"@import url("https://fonts.googleapis.com/css2?family=Print") print;"#
            expect(WebWallpaperCSSImportTransformer.transform(conditionalImport) == conditionalImport, "conditional imports must retain their authored media semantics")
            let compoundMediaImport = #"@import url("https://fonts.googleapis.com/css2?family=Wide") screen and (min-width:400px);"#
            expect(WebWallpaperCSSImportTransformer.transform(compoundMediaImport) == compoundMediaImport, "compound media imports must retain their authored media semantics")
            // layer()/layer 是无条件层指定（非媒体条件）：改写为非阻塞时保留
            // 原段——恢复侧（RemoteStylesheets）以 <style>@import … layer(…);</style>
            // 重插，层语义不丢。
            let layeredImport = #"@import url(//fonts.googleapis.com/css2?family=Layered) layer(fonts);"#
            let transformedLayered = WebWallpaperCSSImportTransformer.transform(layeredImport)
            expect(transformedLayered == #"@import url("https://fonts.googleapis.com/css2?family=Layered") layer(fonts) not all;"#, "named-layer import must defer with the authored layer segment preserved")
            let anonymousLayerImport = #"@import url(https://fonts.googleapis.com/css2?family=Anon) layer;"#
            let transformedAnonymousLayer = WebWallpaperCSSImportTransformer.transform(anonymousLayerImport)
            expect(transformedAnonymousLayer == #"@import url("https://fonts.googleapis.com/css2?family=Anon") layer not all;"#, "anonymous-layer import must defer with the bare layer segment preserved")
            let unsafeLayerNameImport = #"@import url(https://fonts.googleapis.com/css2?family=Weird) layer(a)b);"#
            expect(WebWallpaperCSSImportTransformer.transform(unsafeLayerNameImport) == unsafeLayerNameImport, "layer names needing re-serialization must remain untouched")
            let emptyLayerNameImport = #"@import url(https://fonts.googleapis.com/css2?family=NoName) layer();"#
            expect(WebWallpaperCSSImportTransformer.transform(emptyLayerNameImport) == emptyLayerNameImport, "empty layer names must remain untouched")
            let layeredMediaImport = #"@import url("https://fonts.googleapis.com/css2?family=LayeredScreen") layer(base) screen;"#
            expect(WebWallpaperCSSImportTransformer.transform(layeredMediaImport) == layeredMediaImport, "layer+media compound qualifiers must retain their authored semantics")
            // 裸 screen 在壁纸 WKWebView 恒真：随 not all 丢弃无语义损失，
            // 必须与其他恒真形式一样改写为非阻塞。
            let screenQualifiedImport = #"@import url("https://fonts.googleapis.com/css2?family=ScreenOnly") screen;"#
            let transformedScreenQualified = WebWallpaperCSSImportTransformer.transform(screenQualifiedImport)
            expect(transformedScreenQualified == #"@import url("https://fonts.googleapis.com/css2?family=ScreenOnly") not all;"#, "bare screen qualifier is always true in the wallpaper webview and must defer like unqualified imports")
            let screenQualifiedQuotedImport = #"@import "https://fonts.googleapis.com/css2?family=ScreenQuoted" screen;"#
            let transformedScreenQuoted = WebWallpaperCSSImportTransformer.transform(screenQualifiedQuotedImport)
            expect(transformedScreenQuoted == #"@import url("https://fonts.googleapis.com/css2?family=ScreenQuoted") not all;"#, "quoted import with bare screen qualifier must defer and normalize to HTTPS")

            expect(WebWallpaperResponseTransformer.supportsTransformation(for: URL(fileURLWithPath: "/tmp/index.HTML")), "HTML should be transformable")
            expect(WebWallpaperResponseTransformer.supportsTransformation(for: URL(fileURLWithPath: "/tmp/site.css")), "CSS should be transformable")
            expect(!WebWallpaperResponseTransformer.supportsTransformation(for: URL(fileURLWithPath: "/tmp/video.mp4")), "binary media must not be transformed")

            let beforeOpaqueResources = responseUTF8Decodes
            for fileExtension in ["js", "json", "svg", "png", "bin"] {
                let url = URL(fileURLWithPath: "/fixture/resource." + fileExtension)
                for original in [Data(googleLink.utf8), Data([0xff, 0x00, 0x80])] {
                    expect(WebWallpaperResponseTransformer.transform(original, fileURL: url) == original,
                           "opaque resource bytes must pass through unchanged")
                }
            }
            expect(responseUTF8Decodes == beforeOpaqueResources, "non-transformable resources must not be UTF8 decoded")
            let transformedHTML = WebWallpaperResponseTransformer.transform(Data(googleLink.utf8), fileURL: URL(fileURLWithPath: "/fixture/index.html"))
            expect(String(data: transformedHTML, encoding: .utf8) == transformedGoogleLink, "HTML response retains real font transformation")
            let transformedCSSResponse = WebWallpaperResponseTransformer.transform(Data(screenQualifiedImport.utf8), fileURL: URL(fileURLWithPath: "/fixture/site.css"))
            expect(String(data: transformedCSSResponse, encoding: .utf8) == transformedScreenQualified, "CSS response retains authored qualifier semantics")
            expect(responseUTF8Decodes == beforeOpaqueResources + 2, "only transformable response bodies are decoded")

            // mwx-local resolve 百分号合同：三条生产路径（入口构造、
            // randomFile/__absolute__ 逐段编码、页面 encodeURIComponent）都
            // 恰好编码一次，自定义 scheme 的 URL.path 恰好解码一次——resolve
            // 侧不得再做第二次 removingPercentEncoding，否则字面 %XX 文件名
            // 解析到错误路径或 404，且缓存键互相碰撞会静默交付错内容。
            let resolveRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("mwx-web-scheme-resolve-\(UUID().uuidString)", isDirectory: true)
            let resolveAssets = resolveRoot.appendingPathComponent("assets", isDirectory: true)
            try FileManager.default.createDirectory(at: resolveAssets, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: resolveRoot) }
            for (name, payload) in [
                ("bg%20cover.png", Data("LITERAL".utf8)),
                ("bg cover.png", Data("SPACED".utf8)),
                ("sub%2Ffile.png", Data("SLASHY".utf8)),
                ("100%.png", Data("PCT".utf8)),
                ("plain.png", Data("PLAIN".utf8)),
            ] {
                try Data(payload).write(to: resolveAssets.appendingPathComponent(name))
            }
            let schemeHandler = WebWallpaperLocalSchemeHandler(rootURL: resolveRoot)
            func resolvedLastComponent(_ urlString: String) -> String? {
                guard let url = URL(string: urlString) else { return nil }
                return schemeHandler.resolveResource(for: url, allowsDirectoryIndexFallback: false).resource?.fileURL.lastPathComponent
            }
            expect(resolvedLastComponent("mwx-local://wallpaper/assets/bg%2520cover.png") == "bg%20cover.png",
                   "literal %20 filename must resolve to itself")
            expect(resolvedLastComponent("mwx-local://wallpaper/assets/bg%20cover.png") == "bg cover.png",
                   "space filename must resolve to itself")
            expect(resolvedLastComponent("mwx-local://wallpaper/assets/sub%252Ffile.png") == "sub%2Ffile.png",
                   "literal %2F filename must stay one path component")
            expect(resolvedLastComponent("mwx-local://wallpaper/assets/100%25.png") == "100%.png",
                   "invalid percent sequence filename must resolve to itself")
            expect(resolvedLastComponent("mwx-local://wallpaper/assets/plain.png") == "plain.png",
                   "plain filename must resolve to itself")
            expect(resolvedLastComponent("mwx-local://wallpaper/assets/bg%2520cover.png?cb=1") == "bg%20cover.png",
                   "literal %20 request with query must still resolve to the literal file")
            expect(resolvedLastComponent("mwx-local://wallpaper/assets/bg%20cover.png?cb=1") == "bg cover.png",
                   "space request with query must still resolve to the spaced file")

            print("Web response transformer tests passed")
            '''
        )

        with tempfile.TemporaryDirectory(prefix="mwx-web-transformer-tests-") as directory:
            temporary = Path(directory)
            harness_path = temporary / "main.swift"
            binary_path = temporary / "WebResponseTransformerTests"
            grant = source_block((ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host/WebWallpaperHostTypes.swift").read_text(),
                                 "struct WebWallpaperResourceGrant")
            harness_path.write_text("import Foundation\n" + grant + "\n" + harness, encoding="utf-8")
            # Observe the sole production UTF8 conversion without adding any
            # product diagnostic state. All control flow and transforms stay real.
            sources = list(TRANSFORMER_SOURCES)
            transformer = next(path for path in sources if path.name == "WebWallpaperResponseTransformer.swift")
            instrumented = Path(directory) / transformer.name
            production = transformer.read_text()
            conversion = "String(data: data, encoding: .utf8)"
            self.assertEqual(production.count(conversion), 1)
            instrumented.write_text(production.replace(conversion, "observedResponseUTF8Decode(data)"))
            sources[sources.index(transformer)] = instrumented
            subprocess.run(
                [swiftc, *(str(path) for path in sources), str(harness_path), "-o", str(binary_path)],
                cwd=ROOT,
                check=True,
            )
            completed = subprocess.run(
                [str(binary_path)],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("tests passed", completed.stdout)


if __name__ == "__main__":
    unittest.main()
