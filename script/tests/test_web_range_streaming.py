"""Bounded Range delivery through the production scheme and TCP connection owners.

The sparse HTTP fixture is synthetic; no App, Web page or user media is launched.
"""
from __future__ import annotations

import unittest

from script.tests.test_web_resource_grants import SUPPORT, compile_and_run, grant_declaration
from script.tests.test_web_response_transformer import TRANSFORMER_SOURCES


HARNESS = r'''
import Foundation
import WebKit
import Network
import Darwin
// GRANT
enum WebWallpaperHostSupport { static let localScheme = "mwx-local" }
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}
func spin(_ complete: () -> Bool) {
    let deadline = Date().addingTimeInterval(12)
    while !complete(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    check(complete(), "async deadline")
}
final class SchemeTask: NSObject, WKURLSchemeTask {
    let request: URLRequest
    var response: HTTPURLResponse?
    var chunks: [Int] = []
    var bytes = Data()
    var failure: Error?
    var finishes = 0
    var failures = 0
    var onResponse: (() -> Void)?
    var onChunk: (() -> Void)?
    init(_ url: URL, method: String = "GET", range: String? = nil, etag: String? = nil) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let range { request.setValue(range, forHTTPHeaderField: "Range") }
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        self.request = request
    }
    func didReceive(_ response: URLResponse) { self.response = response as? HTTPURLResponse; onResponse?() }
    func didReceive(_ data: Data) { chunks.append(data.count); bytes.append(data); onChunk?() }
    func didFinish() { finishes += 1 }
    func didFailWithError(_ error: Error) { failure = error; failures += 1 }
    var done: Bool { finishes + failures > 0 }
}
final class Done: @unchecked Sendable {
    let lock = NSLock()
    var finished = false
    func finish() { lock.lock(); finished = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return finished }
}
func network(_ body: @escaping () -> Void) {
    let done = Done()
    DispatchQueue.global().async { body(); done.finish() }
    spin { done.value }
}
struct HTTPResponse {
    let status: Int
    let headers: [String: String]
    let body: Data
    let count: Int
    let complete: Bool
}
final class TCP {
    let fd: Int32
    var pending = Data()
    init(_ url: URL) {
        fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        check(fd >= 0, "socket")
        var timeout = timeval(tv_sec: 8, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(url.port!).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        check(result == 0, "connect")
    }
    deinit { Darwin.close(fd) }
    func send(_ text: String) {
        let data = Data(text.utf8)
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < data.count {
                let n = Darwin.send(fd, bytes.baseAddress!.advanced(by: offset), data.count - offset, 0)
                check(n > 0, "send request")
                offset += n
            }
        }
    }
    func receive() -> Bool {
        var bytes = [UInt8](repeating: 0, count: 64 * 1024)
        let n = Darwin.recv(fd, &bytes, bytes.count, 0)
        if n <= 0 { return false }
        pending.append(contentsOf: bytes.prefix(n))
        return true
    }
    func response(head: Bool = false, collect: Bool = true, firstBody: (() -> Void)? = nil) -> HTTPResponse {
        let separator = Data("\r\n\r\n".utf8)
        while pending.range(of: separator) == nil { check(receive(), "response header") }
        let split = pending.range(of: separator)!
        let lines = String(data: pending[..<split.lowerBound], encoding: .utf8)!.components(separatedBy: "\r\n")
        let status = Int(lines[0].split(separator: " ")[1])!
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 { headers[String(parts[0]).lowercased()] = parts[1].trimmingCharacters(in: .whitespaces) }
        }
        pending.removeSubrange(..<split.upperBound)
        let length = head ? 0 : Int(headers["content-length"] ?? "0")!
        var body = Data(), count = 0
        while count < length {
            if pending.isEmpty && !receive() { break }
            let n = min(length - count, pending.count)
            if collect { body.append(pending.prefix(n)) }
            pending.removeFirst(n)
            count += n
            if count == n { firstBody?() }
        }
        return .init(status: status, headers: headers, body: body, count: count, complete: count == length)
    }
    func request(_ path: String, method: String = "GET", range: String? = nil,
                 connection: String = "keep-alive", extra: String = "") {
        send("\(method) \(path) HTTP/1.1\r\nHost: localhost\r\nConnection: \(connection)\r\n"
            + (range.map { "Range: \($0)\r\n" } ?? "") + extra + "\r\n")
    }
}
@main enum Harness {
    static func main() throws {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: fm.currentDirectoryPath).resolvingSymlinksInPath()
        let root = base.appendingPathComponent("project")
        let external = base.appendingPathComponent("selected")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: external, withIntermediateDirectories: true)
        let file = external.appendingPathComponent("renamed %20 media.bin")
        let peer = external.appendingPathComponent("private-peer.bin")
        let body = Data((0..<(3 * 1024 * 1024 + 131)).map { UInt8(truncatingIfNeeded: $0 * 37 + 11) })
        try body.write(to: file); try Data("private".utf8).write(to: peer)
        func absolute(_ file: URL) -> URL {
            var url = URLComponents()
            url.scheme = "mwx-local"; url.host = "wallpaper"; url.path = "/__absolute__" + file.path
            return url.url!
        }
        let handler = WebWallpaperLocalSchemeHandler(rootURL: root)
        let grant = WebWallpaperResourceGrant(kind: .file, url: file)
        handler.updateResourceGrants([grant])
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        let url = absolute(file)
        func deliver(_ task: SchemeTask) -> SchemeTask {
            handler.webView(view, start: task)
            spin { task.done }
            return task
        }
        let ranged = deliver(SchemeTask(url, range: "bytes=137-"))
        check(ranged.response?.statusCode == 206 && ranged.bytes == body.dropFirst(137), "scheme exact seek/body")
        check(ranged.chunks.count > 1 && ranged.chunks.max()! <= WebWallpaperLocalSchemeHandler.deliveryChunkSize,
            "Range must use bounded production didReceive chunks")
        check(ranged.response?.value(forHTTPHeaderField: "Content-Range") == "bytes 137-\(body.count - 1)/\(body.count)", "scheme Content-Range")
        check(ranged.response?.value(forHTTPHeaderField: "Content-Length") == "\(body.count - 137)", "scheme Content-Length")
        let suffix = deliver(SchemeTask(url, range: "bytes=-123"))
        check(suffix.bytes == body.suffix(123), "scheme suffix")
        let clamped = deliver(SchemeTask(url, range: "bytes=1048573-99999999"))
        check(clamped.bytes == body.dropFirst(1048573), "scheme end clamp and nonaligned seek")
        let head = deliver(SchemeTask(url, method: "HEAD", range: "bytes=2-101"))
        check(head.response?.statusCode == 206 && head.bytes.isEmpty && head.finishes == 1
            && head.response?.value(forHTTPHeaderField: "Content-Length") == "100", "scheme HEAD preserves range headers/no body")
        let unsatisfied = deliver(SchemeTask(url, range: "bytes=99999999-"))
        check(unsatisfied.response?.statusCode == 416 && unsatisfied.failure == nil && unsatisfied.bytes.isEmpty
            && unsatisfied.response?.value(forHTTPHeaderField: "Content-Range") == "bytes */\(body.count)", "scheme 416 is recoverable HTTP")
        check(deliver(SchemeTask(url, range: "bytes=1-2,4-5")).failure != nil, "multipart rejection retained")
        let unchanged = deliver(SchemeTask(url, etag: ranged.response!.value(forHTTPHeaderField: "ETag")))
        check(unchanged.response?.statusCode == 304 && unchanged.bytes.isEmpty, "scheme 304")
        check(deliver(SchemeTask(absolute(peer), range: "bytes=0-2")).failure != nil, "Range cannot grant sibling")
        let insideLink = root.appendingPathComponent("escape.bin")
        try fm.createSymbolicLink(at: insideLink, withDestinationURL: peer)
        check(deliver(SchemeTask(URL(string: "mwx-local://wallpaper/escape.bin")!, range: "bytes=0-2")).failure != nil,
            "Range cannot follow unauthorized symlink")
        let retained = SchemeTask(url, range: "bytes=137-")
        retained.onChunk = { handler.updateResourceGrants([grant, .init(kind: .file, url: peer)]) }
        _ = deliver(retained)
        check(retained.bytes == body.dropFirst(137) && retained.failure == nil, "unrelated grant edit keeps scheme Range")
        let revoked = SchemeTask(url, range: "bytes=137-")
        revoked.onChunk = { handler.updateResourceGrants([]) }
        _ = deliver(revoked)
        check(revoked.failure != nil && revoked.bytes.count <= WebWallpaperLocalSchemeHandler.deliveryChunkSize, "revoked scheme Range stops")
        handler.updateResourceGrants([grant])
        let stopped = SchemeTask(url, range: "bytes=0-12")
        stopped.onChunk = { handler.webView(view, stop: stopped) }
        handler.webView(view, start: stopped)
        spin { !stopped.bytes.isEmpty && handler.cancellation(for: stopped) == nil }
        check(!stopped.done && stopped.chunks == [13], "synchronous stop in final didReceive cannot finish")
        let stoppedAtHeader = SchemeTask(url, range: "bytes=0-12")
        stoppedAtHeader.onResponse = { handler.webView(view, stop: stoppedAtHeader) }
        handler.webView(view, start: stoppedAtHeader)
        spin { stoppedAtHeader.response != nil && handler.cancellation(for: stoppedAtHeader) == nil }
        check(stoppedAtHeader.bytes.isEmpty && !stoppedAtHeader.done, "stop at response prevents body")
        let truncated = SchemeTask(url, range: "bytes=137-")
        truncated.onChunk = { try! FileHandle(forWritingTo: file).truncate(atOffset: 0) }
        _ = deliver(truncated)
        check(truncated.failure != nil && truncated.finishes == 0 && truncated.bytes.count <= WebWallpaperLocalSchemeHandler.deliveryChunkSize,
            "mid-Range EOF fails rather than completing short content")
        try body.write(to: file)
        let css = root.appendingPathComponent("author.css")
        let cssBody = Data("body { color: rgb(10, 20, 30); }".utf8)
        try cssBody.write(to: css)
        let cssResponse = deliver(SchemeTask(URL(string: "mwx-local://wallpaper/author.css")!, range: "bytes=0-2"))
        check(cssResponse.response?.statusCode == 200 && cssResponse.bytes == cssBody, "transformed resource Range behavior retained")

        let server = WebWallpaperLoopbackServer(schemeHandler: handler)
        var endpoint: URL?
        server.start { if case let .success(url) = $0 { endpoint = url } }
        spin { endpoint != nil }
        defer { server.stop() }
        let endpointURL = endpoint!
        let prefix = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false)!.percentEncodedPath
        // URL absoluteString retains literal-percent encoding exactly once.
        let selectedPath = prefix + "__absolute__/" + absolute(file).absoluteString.components(separatedBy: "/__absolute__/")[1]
        network {
            let client = TCP(endpointURL)
            client.request(selectedPath, range: "bytes=137-")
            let response = client.response()
            check(response.status == 206 && response.complete && response.body == body.dropFirst(137),
                "TCP exact large Range status=\(response.status) count=\(response.count) headers=\(response.headers)")
            check(response.headers["content-range"] == "bytes 137-\(body.count - 1)/\(body.count)"
                && response.headers["content-length"] == "\(body.count - 137)", "TCP range headers")
            check(response.headers["connection"] != "close", "Range keeps original keep-alive")
            client.request(selectedPath, method: "HEAD", range: "bytes=17-119")
            let head = client.response(head: true)
            check(head.status == 206 && head.count == 0 && head.headers["content-length"] == "103", "TCP HEAD")
            client.request(selectedPath, range: "bytes=-123")
            check(client.response().body == body.suffix(123), "TCP suffix after previous Range on same socket")
            client.request(selectedPath, range: "bytes=99999999-")
            let rejected = client.response()
            check(rejected.status == 416 && rejected.count == 0 && rejected.headers["content-range"] == "bytes */\(body.count)", "TCP recoverable 416")
            client.request(selectedPath, range: "bytes=0-3", extra: "If-None-Match: \(response.headers["etag"]!)\r\n")
            check(client.response().status == 304, "TCP 304")
            client.send("GET \(selectedPath) HTTP/1.1\r\nHost: localhost\r\nRange: bytes=11-18\r\n\r\n"
                + "GET \(selectedPath) HTTP/1.1\r\nHost: localhost\r\nRange: bytes=21-27\r\nConnection: close\r\n\r\n")
            check(client.response().body == body[11...18] && client.response().body == body[21...27], "pipelined Range bytes preserve response boundaries")
            let unauthorized = TCP(endpointURL)
            unauthorized.request("/unprefixed.bin", range: "bytes=0-2", connection: "close")
            check(unauthorized.response().status == 403, "TCP token auth still required")
            let escaped = TCP(endpointURL)
            escaped.request(prefix + "escape.bin", range: "bytes=0-2", connection: "close")
            check(escaped.response().status == 404, "TCP symlink escape still rejected")
        }
        // Sparse synthetic bytes exceed network buffering; changing the file
        // after the first body receipt distinguishes streaming from old read-all.
        let large = external.appendingPathComponent("sparse-range.bin")
        fm.createFile(atPath: large.path, contents: nil)
        let largeLength = 65 * 1024 * 1024 + 123
        let largeGrant = WebWallpaperResourceGrant(kind: .file, url: large)
        let largePath = prefix + "__absolute__/" + absolute(large).absoluteString.components(separatedBy: "/__absolute__/")[1]
        func restoreLarge() {
            let handle = try! FileHandle(forWritingTo: large)
            try! handle.truncate(atOffset: UInt64(largeLength)); try! handle.close()
            handler.updateResourceGrants([grant, largeGrant])
        }
        restoreLarge()
        network {
            let client = TCP(endpointURL)
            client.request(largePath, range: "bytes=137-", connection: "close")
            let response = client.response(collect: false, firstBody: {
                let writer = try! FileHandle(forWritingTo: large)
                try! writer.truncate(atOffset: 0); try! writer.close()
            })
            check(response.status == 206 && !response.complete && response.count < largeLength - 137, "TCP Range must observe mid-stream truncation")
        }
        restoreLarge()
        network {
            let client = TCP(endpointURL)
            client.request(largePath, range: "bytes=137-", connection: "close")
            let response = client.response(collect: false, firstBody: { handler.updateResourceGrants([grant]) })
            check(response.status == 206 && !response.complete, "TCP Range revocation cancels body")
        }
        restoreLarge()
        network {
            let client = TCP(endpointURL)
            client.request(largePath, range: "bytes=137-", connection: "close")
            let response = client.response(collect: false, firstBody: { DispatchQueue.main.sync { server.stop() } })
            check(response.status == 206 && !response.complete, "server stop cancels accepted Range")
        }
        // An invalid admission ID cannot register an accepted connection.
        let stale = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(endpointURL.port!))!, using: .tcp)
        check(!server.registerAndStartConnection(for: stale, cancellation: .init(), admissionID: UUID(),
            connectionID: UUID(), queue: DispatchQueue(label: "stale-accept")), "invalid admission ID rejects accepted connection")
        stale.cancel()
        endpoint = nil
        server.start { if case let .success(url) = $0 { endpoint = url } }
        spin { endpoint != nil }
        let restarted = endpoint!
        handler.updateResourceGrants([grant])
        network {
            let client = TCP(restarted)
            let prefix = URLComponents(url: restarted, resolvingAgainstBaseURL: false)!.percentEncodedPath
            client.request(prefix + "__absolute__/" + absolute(file).absoluteString.components(separatedBy: "/__absolute__/")[1], range: "bytes=5-12", connection: "close")
            check(client.response().body == body[5...12], "new listener remains healthy after stop and old completions")
        }
        print("web-range-streaming-pass")
    }
}
'''


class WebRangeStreamingTests(unittest.TestCase):
    def test_real_scheme_and_loopback_range_delivery(self):
        source = HARNESS.replace("// GRANT", grant_declaration())
        compile_and_run(source, TRANSFORMER_SOURCES + [
            SUPPORT / "WebWallpaperLoopbackServer.swift",
            SUPPORT / "WebWallpaperLoopbackServer+Connection.swift",
        ], "web-range-streaming-pass")


if __name__ == "__main__":
    unittest.main()
