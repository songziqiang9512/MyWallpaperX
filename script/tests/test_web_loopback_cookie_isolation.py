"""Two real loopback pages share one WK cookie store without sharing authority."""
from __future__ import annotations

import unittest

from script.tests.test_web_resource_grants import SUPPORT, compile_and_run, grant_declaration
from script.tests.test_web_response_transformer import TRANSFORMER_SOURCES


HARNESS = r'''
import Foundation
import AppKit
import WebKit
import Network
// GRANT
enum WebWallpaperHostSupport { static let localScheme = "mwx-local" }
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}
func spin(_ complete: () -> Bool) {
    let deadline = Date().addingTimeInterval(8)
    while !complete(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    check(complete(), "async deadline")
}
final class Navigation: NSObject, WKNavigationDelegate {
    var finished = false
    var error: Error?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { self.error = error }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.error = error
    }
}
final class Messages: NSObject, WKScriptMessageHandler {
    var result: [String: Any]?
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        result = message.body as? [String: Any]
    }
}
final class HTTPResult: @unchecked Sendable {
    let lock = NSLock()
    private var stored: (Int, String)?
    func finish(_ status: Int, _ data: Data?) {
        lock.lock(); stored = (status, data.flatMap { String(data: $0, encoding: .utf8) } ?? ""); lock.unlock()
    }
    var value: (Int, String)? { lock.lock(); defer { lock.unlock() }; return stored }
}
@main enum CookieIsolationHarness {
    static func main() throws {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cookie-isolation", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let aRoot = root.appendingPathComponent("author-renamed-a", isDirectory: true)
        let bRoot = root.appendingPathComponent("author-renamed-b", isDirectory: true)
        for (folder, text) in [(aRoot, "author-a"), (bRoot, "author-b")] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("<!doctype html><meta charset='utf-8'><title>Owned cookie fixture</title><body>\(text)</body>".utf8)
                .write(to: folder.appendingPathComponent("index.html"))
            try Data(text.utf8).write(to: folder.appendingPathComponent("selected.txt"))
        }
        let a = WebWallpaperLoopbackServer(schemeHandler: .init(rootURL: aRoot))
        let b = WebWallpaperLoopbackServer(schemeHandler: .init(rootURL: bRoot))
        defer { a.stop(); b.stop() }
        var aURL: URL?, bURL: URL?
        a.start { if case let .success(url) = $0 { aURL = url } }
        b.start { if case let .success(url) = $0 { bURL = url } }
        spin { aURL != nil && bURL != nil }
        let endpointA = aURL!, endpointB = bURL!
        check(endpointA.port != endpointB.port, "two actual listener endpoints")
        let store = WKWebsiteDataStore.nonPersistent()
        let pool = WKProcessPool()
        let messagesA = Messages(), messagesB = Messages()
        func view(_ messages: Messages) -> WKWebView {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = store
            configuration.processPool = pool
            configuration.userContentController.add(messages, name: "cookieProbe")
            return WKWebView(frame: .zero, configuration: configuration)
        }
        let viewA = view(messagesA), viewB = view(messagesB)
        defer {
            for view in [viewA, viewB] {
                view.stopLoading(); view.navigationDelegate = nil
                view.configuration.userContentController.removeScriptMessageHandler(forName: "cookieProbe")
            }
        }
        let navigationA = Navigation(), navigationB = Navigation()
        viewA.navigationDelegate = navigationA; viewB.navigationDelegate = navigationB
        func load(_ view: WKWebView, _ navigation: Navigation, _ endpoint: URL, _ phase: String) {
            navigation.finished = false; navigation.error = nil
            let url = URL(string: endpoint.appendingPathComponent("index.html").absoluteString + "?phase=" + phase)!
            view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
            spin { navigation.finished || navigation.error != nil }
            check(navigation.error == nil, "owned HTML load \(phase): \(String(describing: navigation.error))")
        }
        func fetch(_ view: WKWebView, _ messages: Messages) -> (Int, String) {
            messages.result = nil
            let script = """
            fetch('/selected.txt', {credentials:'include', cache:'no-store'})
              .then(async r => ({status:r.status, body:await r.text()}))
              .then(r => window.webkit.messageHandlers.cookieProbe.postMessage(r))
              .catch(e => window.webkit.messageHandlers.cookieProbe.postMessage({status:-1,body:String(e)}));
            true;
            """
            view.evaluateJavaScript(script) { _, error in check(error == nil, "fetch script dispatch") }
            spin { messages.result != nil }
            return (messages.result?["status"] as? Int ?? -2, messages.result?["body"] as? String ?? "")
        }
        func cookies() -> [HTTPCookie] {
            var result: [HTTPCookie]?
            store.httpCookieStore.getAllCookies { result = $0 }
            spin { result != nil }; return result!
        }
        func cookieName(_ server: WebWallpaperLoopbackServer) -> String {
            String(server.accessCookieHeader.split(separator: "=", maxSplits: 1)[0])
        }
        let nameA = cookieName(a), nameB = cookieName(b)
        var facts: [String: Bool] = [:]
        var observations: [String: Any] = [:]
        facts["sameActualWKWebsiteDataStore"] = viewA.configuration.websiteDataStore === store
            && viewB.configuration.websiteDataStore === store
        load(viewA, navigationA, endpointA, "initial-a")
        let actualCookieA = cookies().first { $0.name == nameA && $0.domain == "127.0.0.1" && $0.path == "/" }!
        facts["actualFirstCookieValue"] = actualCookieA.value == a.accessToken
        facts["initialAUnprefixedFetch"] = fetch(viewA, messagesA) == (200, "author-a")
        load(viewB, navigationB, endpointB, "initial-b")
        facts["BUnprefixedAfterALoad"] = fetch(viewB, messagesB) == (200, "author-b")
        let aAfterB = fetch(viewA, messagesA)
        observations["AAfterB"] = ["status": aAfterB.0, "body": aAfterB.1]
        facts["AUnprefixedAfterBLoad"] = aAfterB == (200, "author-a")
        facts["cookieNamesDistinct"] = nameA != nameB
        observations["cookieNamesAfterBothLoads"] = cookies().map(\.name).sorted()
        load(viewA, navigationA, endpointA, "reload-a")
        facts["AUnprefixedAfterReload"] = fetch(viewA, messagesA) == (200, "author-a")
        let bAfterA = fetch(viewB, messagesB)
        observations["BAfterAReload"] = ["status": bAfterA.0, "body": bAfterA.1]
        facts["BUnprefixedAfterAReload"] = bAfterA == (200, "author-b")
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.httpCookieStorage = nil; sessionConfiguration.httpShouldSetCookies = false
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        func http(_ path: String, _ cookie: String? = nil) -> (Int, String) {
            var components = URLComponents(url: endpointA, resolvingAgainstBaseURL: false)!
            components.percentEncodedPath = path; components.query = nil
            var request = URLRequest(url: components.url!)
            request.httpShouldHandleCookies = false
            if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
            let result = HTTPResult()
            session.dataTask(with: request) { data, response, _ in
                result.finish((response as? HTTPURLResponse)?.statusCode ?? -1, data)
            }.resume()
            spin { result.value != nil }; return result.value!
        }
        facts["ownPrefixWithoutCookie"] = http(a.accessPathPrefix + "selected.txt") == (200, "author-a")
        facts["ownCookieWithoutPrefix"] = http("/selected.txt", "\(nameA)=\(a.accessToken)") == (200, "author-a")
        facts["noCookieDenied"] = http("/selected.txt").0 == 403
        facts["wrongTokenDenied"] = http("/selected.txt", "\(nameA)=\(b.accessToken)").0 == 403
        facts["wrongNameDenied"] = http("/selected.txt", "unrelated-cookie=\(a.accessToken)").0 == 403
        facts["oldFixedNameDenied"] = http("/selected.txt", "mwx-access=\(a.accessToken)").0 == 403
        facts["foreignPrefixWithoutCookieDenied"] = http(b.accessPathPrefix + "selected.txt").0 == 403
        facts["existingCookieNameCaseSemantics"] = http("/selected.txt", "\(nameA.uppercased())=\(a.accessToken)") == (200, "author-a")
        // Both HTML navigations completed. This proves exact-key native deletion,
        // not cancellation/drain of an arbitrarily delayed Set-Cookie response.
        viewA.stopLoading(); a.stop()
        var deleted = false
        store.httpCookieStore.delete(a.accessCookie) { deleted = true }
        spin { deleted }
        facts["AExactCookieAbsentAfterDelete"] = !cookies().contains {
            $0.name == nameA && $0.domain == "127.0.0.1" && $0.path == "/"
        }
        facts["BHealthyAfterAStopAndExactCookieDelete"] = fetch(viewB, messagesB) == (200, "author-b")
        facts["BActualCookieSurvivesDeleteA"] = cookies().contains {
            $0.name == nameB && $0.value == b.accessToken && $0.domain == "127.0.0.1" && $0.path == "/"
        }
        observations["facts"] = facts
        observations["lateResponseDrainProved"] = false
        let encoded = try JSONSerialization.data(withJSONObject: observations, options: [.sortedKeys])
        print(String(decoding: encoded, as: UTF8.self))
        if facts.values.allSatisfy({ $0 }) { print("web-loopback-cookie-isolation-pass") }
        else { print("web-loopback-cookie-isolation-failed") }
    }
}
'''


class WebLoopbackCookieIsolationTests(unittest.TestCase):
    def test_real_shared_wk_store_keeps_both_server_credentials(self):
        source = HARNESS.replace("// GRANT", grant_declaration())
        compile_and_run(source, TRANSFORMER_SOURCES + [
            SUPPORT / "WebWallpaperLoopbackServer.swift",
            SUPPORT / "WebWallpaperLoopbackServer+Connection.swift",
        ], "web-loopback-cookie-isolation-pass")


if __name__ == "__main__":
    unittest.main()
