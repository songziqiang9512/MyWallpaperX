"""Bounded Range delivery through the production scheme and TCP connection owners.

The sparse HTTP fixture is synthetic; no App, Web page or user media is launched.
"""
from __future__ import annotations

import unittest
import tempfile
from pathlib import Path

from script.tests.test_web_resource_grants import SUPPORT, compile_and_run, grant_declaration
from script.tests.test_web_response_transformer import TRANSFORMER_SOURCES


HARNESS = r'''
import Foundation
import WebKit
import Network
import Darwin
final class ResourceIOTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var action: (stage: String, path: String, body: () -> Void)?
    func record(_ event: String) { lock.lock(); counts[event, default: 0] += 1; lock.unlock() }
    func count(_ event: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[event, default: 0] }
    func reset() { lock.lock(); counts = [:]; action = nil; lock.unlock() }
    func arm(_ stage: String, at url: URL, body: @escaping () -> Void) {
        lock.lock(); action = (stage, url.standardizedFileURL.path, body); lock.unlock()
    }
    func hook(_ stage: String, at url: URL) {
        lock.lock()
        let current = action
        let matches = current?.stage == stage && current?.path == url.standardizedFileURL.path
        if matches { action = nil }
        lock.unlock()
        if matches { current?.body() }
    }
}
let resourceIOTrace = ResourceIOTrace()
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
        // A stopped request that has not reached the IO executor must not
        // prepare anything or call WebKit, including response/error callbacks.
        let queuedGate = DispatchSemaphore(value: 0)
        handler.ioQueue.async { queuedGate.wait() }
        let cancelled = SchemeTask(url)
        resourceIOTrace.reset()
        handler.webView(view, start: cancelled)
        handler.webView(view, stop: cancelled)
        var queueDrained = false
        handler.ioQueue.async { DispatchQueue.main.async { queueDrained = true } }
        queuedGate.signal()
        spin { queueDrained && handler.cancellation(for: cancelled) == nil }
        check(resourceIOTrace.count("prepare") == 0 && resourceIOTrace.count("open") == 0
            && cancelled.response == nil && !cancelled.done && cancelled.bytes.isEmpty,
            "stopped queued task has zero preparation/read/callback work")
        resourceIOTrace.reset()
        let ranged = deliver(SchemeTask(url, range: "bytes=137-"))
        check(ranged.response?.statusCode == 206 && ranged.bytes == body.dropFirst(137), "scheme exact seek/body")
        check(ranged.chunks.count > 1 && ranged.chunks.max()! <= WebWallpaperLocalSchemeHandler.deliveryChunkSize,
            "Range must use bounded production didReceive chunks")
        check(ranged.response?.value(forHTTPHeaderField: "Content-Range") == "bytes 137-\(body.count - 1)/\(body.count)", "scheme Content-Range")
        check(ranged.response?.value(forHTTPHeaderField: "Content-Length") == "\(body.count - 137)", "scheme Content-Length")
        check(resourceIOTrace.count("open") == 1 && resourceIOTrace.count("fstat") == 1
            && resourceIOTrace.count("range") == 1 && resourceIOTrace.count("pathStat") == 0
            && resourceIOTrace.count("revalidate") == 0, "GET uses one actual opened file and one range parse")
        resourceIOTrace.reset()
        let suffix = deliver(SchemeTask(url, range: "bytes=-123"))
        check(suffix.bytes == body.suffix(123), "scheme suffix")
        check(resourceIOTrace.count("open") == 1 && resourceIOTrace.count("fstat") == 1
            && resourceIOTrace.count("revalidate") == 0, "warm path still binds the actual FD once")
        let clamped = deliver(SchemeTask(url, range: "bytes=1048573-99999999"))
        check(clamped.bytes == body.dropFirst(1048573), "scheme end clamp and nonaligned seek")
        resourceIOTrace.reset()
        let head = deliver(SchemeTask(url, method: "HEAD", range: "bytes=2-101"))
        check(head.response?.statusCode == 206 && head.bytes.isEmpty && head.finishes == 1
            && head.response?.value(forHTTPHeaderField: "Content-Length") == "100", "scheme HEAD preserves range headers/no body")
        check(resourceIOTrace.count("open") == 0 && resourceIOTrace.count("pathStat") == 1,
            "HEAD keeps the metadata-only path")
        let unsatisfied = deliver(SchemeTask(url, range: "bytes=99999999-"))
        check(unsatisfied.response?.statusCode == 416 && unsatisfied.failure == nil && unsatisfied.bytes.isEmpty
            && unsatisfied.response?.value(forHTTPHeaderField: "Content-Range") == "bytes */\(body.count)", "scheme 416 is recoverable HTTP")
        check(deliver(SchemeTask(url, range: "bytes=1-2,4-5")).failure != nil, "multipart rejection retained")
        resourceIOTrace.reset()
        let unchanged = deliver(SchemeTask(url, etag: ranged.response!.value(forHTTPHeaderField: "ETag")))
        check(unchanged.response?.statusCode == 304 && unchanged.bytes.isEmpty, "scheme 304")
        check(resourceIOTrace.count("open") == 0 && resourceIOTrace.count("pathStat") == 1,
            "304 does not open a body FD")
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

        // Mutate after the real resolver and immediately before the real open.
        // The grant revision stays unchanged: only the opened FD distinguishes it.
        let changing = root.appendingPathComponent("changing.bin")
        try Data("allowed".utf8).write(to: changing)
        let changingURL = URL(string: "mwx-local://wallpaper/changing.bin")!
        func replaceBeforeOpen(_ change: @escaping () -> Void) -> SchemeTask {
            check(handler.resolveResource(for: changingURL, allowsDirectoryIndexFallback: true).resource != nil,
                "warm candidate exists before mutation")
            resourceIOTrace.arm("before", at: changing, body: change)
            return deliver(SchemeTask(changingURL))
        }
        let retargeted = replaceBeforeOpen {
            try! fm.removeItem(at: changing)
            try! fm.createSymbolicLink(at: changing, withDestinationURL: peer)
        }
        check(retargeted.failure != nil && retargeted.bytes.isEmpty, "actual FD cannot escape through a warm symlink replacement")
        try fm.removeItem(at: changing); try Data("allowed".utf8).write(to: changing)
        let fifoStarted = Date()
        let fifo = replaceBeforeOpen {
            try! fm.removeItem(at: changing)
            check(mkfifo(changing.path, 0o600) == 0, "make synthetic FIFO")
        }
        check(fifo.failure != nil && fifo.bytes.isEmpty && Date().timeIntervalSince(fifoStarted) < 2,
            "nonregular FIFO open cannot block the IO owner")
        try fm.removeItem(at: changing); try Data("allowed".utf8).write(to: changing)
        let directory = replaceBeforeOpen {
            try! fm.removeItem(at: changing); try! fm.createDirectory(at: changing, withIntermediateDirectories: false)
        }
        check(directory.failure != nil && directory.bytes.isEmpty, "opened directory is rejected as nonregular")
        try fm.removeItem(at: changing); try Data("allowed".utf8).write(to: changing)
        let deleted = replaceBeforeOpen { try! fm.removeItem(at: changing) }
        check(deleted.failure != nil && deleted.bytes.isEmpty, "deletion before open is local failure")

        // Missing warm locations refresh once through the original resolver,
        // including its current spelling and existing compatibility candidates.
        let fallbackImage = root.appendingPathComponent("image/bg.png")
        let directImage = root.appendingPathComponent("background.png")
        try fm.createDirectory(at: fallbackImage.deletingLastPathComponent(), withIntermediateDirectories: true)
        let imageURL = URL(string: "mwx-local://wallpaper/background.png")!
        try Data("old-fallback".utf8).write(to: fallbackImage)
        let imageCandidate = handler.resolveResource(for: imageURL, allowsDirectoryIndexFallback: true).resource!
        check(imageCandidate.fileURL == fallbackImage, "initial compatibility candidate")
        resourceIOTrace.reset()
        resourceIOTrace.arm("before", at: fallbackImage) {
            try! fm.removeItem(at: fallbackImage); try! Data("current-direct".utf8).write(to: directImage)
        }
        let reopenedImage = try handler.openResponseStream(from: imageCandidate, request: URLRequest(url: imageURL))
        let reopenedImageBytes = try reopenedImage.handle.readToEnd()
        check(reopenedImageBytes == Data("current-direct".utf8),
            "removed warm compatibility candidate returns to the current original request")
        try reopenedImage.handle.close()
        check(resourceIOTrace.count("open") == 2 && resourceIOTrace.count("fstat") == 1,
            "only actual missing-path failure opens a second candidate")
        try fm.removeItem(at: directImage); try Data("old-authorized".utf8).write(to: fallbackImage)
        let deniedCandidate = handler.resolveResource(for: imageURL, allowsDirectoryIndexFallback: true,
            refreshCachedResolution: true).resource!
        resourceIOTrace.reset()
        resourceIOTrace.arm("before", at: fallbackImage) {
            try! fm.removeItem(at: fallbackImage)
            try! fm.createSymbolicLink(at: fallbackImage, withDestinationURL: peer)
            try! Data("available-original".utf8).write(to: directImage)
        }
        do {
            let unexpected = try handler.openResponseStream(from: deniedCandidate, request: URLRequest(url: imageURL))
            try unexpected.handle.close(); fatalError("unsafe actual FD cannot fall back to another candidate")
        } catch {
            check(error is WebWallpaperLocalSchemeHandler.AccessDenied, "unsafe actual FD keeps its denial")
        }
        check(resourceIOTrace.count("open") == 1 && resourceIOTrace.count("fstat") == 1,
            "authorization failure cannot search the now-available original candidate")
        try fm.removeItem(at: fallbackImage)
        let originalSpelling = root.appendingPathComponent("Café.BIN")
        let currentSpelling = root.appendingPathComponent("Cafe.bin")
        try Data("old-spelling".utf8).write(to: originalSpelling)
        let spellingURL = URL(string: "mwx-local://wallpaper/caf%C3%A9.bin")!
        let spellingCandidate = handler.resolveResource(for: spellingURL, allowsDirectoryIndexFallback: true).resource!
        resourceIOTrace.reset()
        resourceIOTrace.arm("before", at: spellingCandidate.fileURL) {
            try! fm.removeItem(at: originalSpelling); try! Data("current-spelling".utf8).write(to: currentSpelling)
        }
        let reopenedSpelling = try handler.openResponseStream(from: spellingCandidate, request: URLRequest(url: spellingURL))
        let reopenedSpellingBytes = try reopenedSpelling.handle.readToEnd()
        check(reopenedSpellingBytes == Data("current-spelling".utf8),
            "removed warm spelling preserves case/diacritic-insensitive discovery")
        try reopenedSpelling.handle.close()
        check(resourceIOTrace.count("open") == 2 && resourceIOTrace.count("fstat") == 1,
            "renamed warm location reuses the original resolver exactly once")
        let oldMapRoot = root.appendingPathComponent("Default Content")
        let fallbackMap = oldMapRoot.appendingPathComponent("map/tile.bin")
        let directMap = root.appendingPathComponent("map/tile.bin")
        try fm.createDirectory(at: fallbackMap.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old-map".utf8).write(to: fallbackMap)
        let mapURL = URL(string: "mwx-local://wallpaper/map/tile.bin")!
        let mapCandidate = handler.resolveResource(for: mapURL, allowsDirectoryIndexFallback: true).resource!
        resourceIOTrace.reset()
        resourceIOTrace.arm("before", at: fallbackMap) {
            try! fm.removeItem(at: oldMapRoot); try! Data("directory-replaced".utf8).write(to: oldMapRoot)
            try! fm.createDirectory(at: directMap.deletingLastPathComponent(), withIntermediateDirectories: true)
            try! Data("current-map".utf8).write(to: directMap)
        }
        let reopenedMap = try handler.openResponseStream(from: mapCandidate, request: URLRequest(url: mapURL))
        let reopenedMapBytes = try reopenedMap.handle.readToEnd()
        check(reopenedMapBytes == Data("current-map".utf8),
            "ENOTDIR on a stale compatibility path returns to current original request")
        try reopenedMap.handle.close()
        check(resourceIOTrace.count("open") == 2 && resourceIOTrace.count("fstat") == 1,
            "ENOTDIR also performs at most one fresh candidate open")

        // HEAD/304 use the same fallback only after their existing metadata
        // validation fails, and still never open a body descriptor.
        let metadataBody = Data("metadata-current".utf8)
        let metadataDate = Date(timeIntervalSince1970: 1_700_000_000)
        let metadataTag = WebWallpaperLocalSchemeHandler.responseValidators(for:
            .init(fileSize: Int64(metadataBody.count), modificationDate: metadataDate)).entityTag
        for method in ["HEAD", "GET"] {
            try fm.removeItem(at: directImage); try Data("metadata-old".utf8).write(to: fallbackImage)
            let metadataHandler = WebWallpaperLocalSchemeHandler(rootURL: root)
            let metadataCandidate = metadataHandler.resolveResource(for: imageURL, allowsDirectoryIndexFallback: true).resource!
            check(metadataCandidate.fileURL == fallbackImage, "metadata path starts from original fallback")
            resourceIOTrace.reset()
            resourceIOTrace.arm("revalidate", at: fallbackImage) {
                try! fm.removeItem(at: fallbackImage); try! metadataBody.write(to: directImage)
                try! fm.setAttributes([.modificationDate: metadataDate], ofItemAtPath: directImage.path)
            }
            let metadataTask = SchemeTask(imageURL, method: method, etag: method == "GET" ? metadataTag : nil)
            metadataHandler.webView(view, start: metadataTask); spin { metadataTask.done }
            check(metadataTask.failure == nil && metadataTask.response?.statusCode == (method == "HEAD" ? 200 : 304)
                && metadataTask.bytes.isEmpty && resourceIOTrace.count("open") == 0,
                "stale metadata candidate keeps lightweight HEAD/304 recovery")
            if method == "HEAD" {
                check(metadataTask.response?.value(forHTTPHeaderField: "Content-Length") == String(metadataBody.count),
                    "refreshed HEAD describes the current candidate")
            }
        }

        // Revocation between fresh resolution and the retry's actual open is
        // checked at the opened FD; retry cannot authorize an old selection.
        let retryDirectory = external.appendingPathComponent("retry-selection")
        try fm.createDirectory(at: retryDirectory, withIntermediateDirectories: true)
        let retryOld = retryDirectory.appendingPathComponent("Sélected.bin")
        let retryCurrent = retryDirectory.appendingPathComponent("Selected.bin")
        try Data("old-selected".utf8).write(to: retryOld)
        let retryHandler = WebWallpaperLocalSchemeHandler(rootURL: root)
        retryHandler.updateResourceGrants([.init(kind: .directory, url: retryDirectory)])
        let retryURL = absolute(retryOld)
        let retryCandidate = retryHandler.resolveResource(for: retryURL, allowsDirectoryIndexFallback: true).resource!
        resourceIOTrace.reset()
        resourceIOTrace.arm("before", at: retryOld) {
            try! fm.removeItem(at: retryOld); try! Data("current-selected".utf8).write(to: retryCurrent)
            resourceIOTrace.arm("before", at: retryCurrent) { retryHandler.updateResourceGrants([]) }
        }
        do {
            let unexpected = try retryHandler.openResponseStream(from: retryCandidate, request: URLRequest(url: retryURL))
            try unexpected.handle.close(); fatalError("revoked retry must not expose a readable handle")
        } catch {
            check(error is WebWallpaperLocalSchemeHandler.AccessDenied, "retry revocation preserves authorization denial")
        }
        check(resourceIOTrace.count("open") == 2 && resourceIOTrace.count("fstat") == 1,
            "retry tests current grants at actual FD consumption")

        let parent = root.appendingPathComponent("parent")
        let savedParent = root.appendingPathComponent("saved-parent")
        let outsideParent = external.appendingPathComponent("outside-parent")
        for folder in [parent, outsideParent] { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        let parentFile = parent.appendingPathComponent("same-name.bin")
        try Data("allowed-parent".utf8).write(to: parentFile)
        try Data("private-parent".utf8).write(to: outsideParent.appendingPathComponent("same-name.bin"))
        let parentURL = URL(string: "mwx-local://wallpaper/parent/same-name.bin")!
        check(handler.resolveResource(for: parentURL, allowsDirectoryIndexFallback: true).resource != nil, "parent warm candidate")
        resourceIOTrace.arm("before", at: parentFile) {
            try! fm.moveItem(at: parent, to: savedParent)
            try! fm.createSymbolicLink(at: parent, withDestinationURL: outsideParent)
        }
        let parentRetarget = deliver(SchemeTask(parentURL))
        check(parentRetarget.failure != nil && parentRetarget.bytes.isEmpty, "actual FD rejects parent-directory retarget")
        try fm.removeItem(at: parent); try fm.moveItem(at: savedParent, to: parent)

        let html = root.appendingPathComponent("single-open.html")
        let originalHTML = Data("<link rel='stylesheet' href='http://fonts.googleapis.com/css2?family=Inter'><main>allowed</main>".utf8)
        let secretHTML = external.appendingPathComponent("private.html")
        try originalHTML.write(to: html); try Data("private-external-html".utf8).write(to: secretHTML)
        resourceIOTrace.reset()
        resourceIOTrace.arm("after", at: html) {
            try! fm.removeItem(at: html); try! fm.createSymbolicLink(at: html, withDestinationURL: secretHTML)
        }
        let htmlResponse = deliver(SchemeTask(URL(string: "mwx-local://wallpaper/single-open.html")!))
        check(htmlResponse.failure == nil && htmlResponse.bytes == WebWallpaperResponseTransformer.transform(originalHTML, fileURL: html)
            && htmlResponse.response?.value(forHTTPHeaderField: "Content-Length") == String(htmlResponse.bytes.count)
            && resourceIOTrace.count("open") == 1, "transform uses the accepted FD and reports transformed length without reopening a replacement")
        try fm.removeItem(at: html); try originalHTML.write(to: html)
        let htmlHead = deliver(SchemeTask(URL(string: "mwx-local://wallpaper/single-open.html")!, method: "HEAD"))
        check(htmlHead.bytes.isEmpty && htmlHead.response?.value(forHTTPHeaderField: "Content-Length") == String(htmlResponse.bytes.count),
            "transformed HEAD keeps transformed content length")
        let caseFile = root.appendingPathComponent("CaseVariant.BIN")
        try Data("case-preserved".utf8).write(to: caseFile)
        let strictHandler = WebWallpaperLocalSchemeHandler(rootURL: root, strictSymlinkPolicy: true)
        let caseTask = SchemeTask(URL(string: "mwx-local://wallpaper/casevariant.bin")!)
        strictHandler.webView(view, start: caseTask); spin { caseTask.done }
        check(caseTask.bytes == Data("case-preserved".utf8), "FD path spelling cannot turn case compatibility into a strict-symlink rejection")
        let allowedLink = root.appendingPathComponent("allowed-link.bin")
        try fm.createSymbolicLink(at: allowedLink, withDestinationURL: caseFile)
        check(deliver(SchemeTask(URL(string: "mwx-local://wallpaper/allowed-link.bin")!)).bytes == Data("case-preserved".utf8),
            "ordinary profile retains in-root authored symlinks")
        let strictLink = SchemeTask(URL(string: "mwx-local://wallpaper/allowed-link.bin")!)
        strictHandler.webView(view, start: strictLink); spin { strictLink.done }
        check(strictLink.failure != nil && strictLink.bytes.isEmpty, "strict profile retains its actual symlink policy")
        resourceIOTrace.arm("after", at: file) { handler.updateResourceGrants([]) }
        let revokeBeforePublish = deliver(SchemeTask(url, range: "bytes=0-31"))
        check(revokeBeforePublish.bytes.isEmpty && revokeBeforePublish.failure != nil,
            "revocation after opening but before asynchronous publication still rejects")
        handler.updateResourceGrants([grant])

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
            resourceIOTrace.reset()
            let client = TCP(endpointURL)
            client.request(selectedPath, range: "bytes=137-")
            let response = client.response()
            check(response.status == 206 && response.complete && response.body == body.dropFirst(137),
                "TCP exact large Range status=\(response.status) count=\(response.count) headers=\(response.headers)")
            check(response.headers["content-range"] == "bytes 137-\(body.count - 1)/\(body.count)"
                && response.headers["content-length"] == "\(body.count - 137)", "TCP range headers")
            check(response.headers["connection"] != "close", "Range keeps original keep-alive")
            check(resourceIOTrace.count("open") == 1 && resourceIOTrace.count("fstat") == 1
                && resourceIOTrace.count("range") == 1 && resourceIOTrace.count("pathStat") == 0
                && resourceIOTrace.count("revalidate") == 0, "TCP Range keeps one FD and does not repeat path validation")
            resourceIOTrace.reset()
            client.request(selectedPath, method: "HEAD", range: "bytes=17-119")
            let head = client.response(head: true)
            check(head.status == 206 && head.count == 0 && head.headers["content-length"] == "103", "TCP HEAD")
            check(resourceIOTrace.count("open") == 0 && resourceIOTrace.count("pathStat") == 1,
                "TCP HEAD remains metadata-only")
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
            let small = TCP(endpointURL)
            resourceIOTrace.reset()
            small.request(selectedPath)
            let smallResponse = small.response()
            check(smallResponse.body == body && resourceIOTrace.count("open") == 1
                && resourceIOTrace.count("fstat") == 1 && resourceIOTrace.count("revalidate") == 0,
                "small TCP body reads its actual opened FD once")
            resourceIOTrace.reset()
            resourceIOTrace.arm("after", at: html) {
                try! fm.removeItem(at: html); try! fm.createSymbolicLink(at: html, withDestinationURL: secretHTML)
            }
            small.request(prefix + "single-open.html")
            let transformed = small.response()
            check(transformed.body == htmlResponse.bytes && resourceIOTrace.count("open") == 1
                && transformed.headers["content-length"] == String(transformed.body.count),
                "TCP transform cannot reopen a replacement path")
            try! fm.removeItem(at: html); try! originalHTML.write(to: html)
            small.request(prefix + "single-open.html", method: "HEAD")
            let transformedHead = small.response(head: true)
            check(transformedHead.count == 0 && transformedHead.headers["content-length"] == String(transformed.body.count),
                "TCP transformed HEAD reports transformed bytes")
            resourceIOTrace.reset()
            small.request(prefix + "single-open.html", extra: "If-None-Match: \(transformedHead.headers["etag"]!)\r\n")
            check(small.response().status == 304 && resourceIOTrace.count("open") == 0,
                "TCP reusable 304 does not create a body FD")
            for method in ["HEAD", "GET"] {
                try! fm.removeItem(at: directImage); try! Data("TCP-metadata-old".utf8).write(to: fallbackImage)
                _ = handler.resolveResource(for: imageURL, allowsDirectoryIndexFallback: true, refreshCachedResolution: true)
                resourceIOTrace.reset()
                resourceIOTrace.arm("revalidate", at: fallbackImage) {
                    try! fm.removeItem(at: fallbackImage); try! metadataBody.write(to: directImage)
                    try! fm.setAttributes([.modificationDate: metadataDate], ofItemAtPath: directImage.path)
                }
                small.request(prefix + "background.png", method: method,
                    extra: method == "GET" ? "If-None-Match: \(metadataTag)\r\n" : "")
                let refreshedMetadata = small.response(head: method == "HEAD")
                check(refreshedMetadata.status == (method == "HEAD" ? 200 : 304)
                    && refreshedMetadata.body.isEmpty && resourceIOTrace.count("open") == 0,
                    "TCP stale metadata keeps HEAD/304 response without a body FD")
            }
            try! fm.removeItem(at: directImage); try! Data("TCP-old-fallback".utf8).write(to: fallbackImage)
            _ = handler.resolveResource(for: imageURL, allowsDirectoryIndexFallback: true, refreshCachedResolution: true)
            resourceIOTrace.reset()
            resourceIOTrace.arm("before", at: fallbackImage) {
                try! fm.removeItem(at: fallbackImage); try! metadataBody.write(to: directImage)
            }
            small.request(prefix + "background.png")
            let refreshedBody = small.response()
            check(refreshedBody.status == 200 && refreshedBody.body == metadataBody
                && resourceIOTrace.count("open") == 2 && resourceIOTrace.count("fstat") == 1,
                "TCP missing actual candidate recovers once through original resolution")
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
        sources = TRANSFORMER_SOURCES + [
            SUPPORT / "WebWallpaperLoopbackServer.swift",
            SUPPORT / "WebWallpaperLoopbackServer+Connection.swift",
        ]
        edits = {
            "WebWallpaperLocalSchemeHandler.swift": [
                ("    func revalidatedResource(_ resource: ResolvedResource) -> ResolvedResource? {",
                 '    func revalidatedResource(_ resource: ResolvedResource) -> ResolvedResource? {\n        resourceIOTrace.record("revalidate")\n        resourceIOTrace.hook("revalidate", at: resource.fileURL)')],
            "WebWallpaperLocalSchemeHandler+Resolve.swift": [
                ("    static func fileStat(for fileURL: URL) -> FileStat? {",
                 '    static func fileStat(for fileURL: URL) -> FileStat? {\n        resourceIOTrace.record("pathStat")')],
            "WebWallpaperLocalSchemeHandler+IO.swift": [
                ("        let outcome = resolveResource(for: requestURL, allowsDirectoryIndexFallback: true)",
                 '        resourceIOTrace.record("prepare")\n        let outcome = resolveResource(for: requestURL, allowsDirectoryIndexFallback: true)'),
                ("        var descriptor = Darwin.open(resource.fileURL.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)",
                 '        resourceIOTrace.record("open")\n        resourceIOTrace.hook("before", at: resource.fileURL)\n        var descriptor = Darwin.open(resource.fileURL.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)'),
                ("            descriptor = Darwin.open(resource.fileURL.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)",
                 '            resourceIOTrace.record("open")\n            resourceIOTrace.hook("before", at: resource.fileURL)\n            descriptor = Darwin.open(resource.fileURL.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)'),
                ("            var facts = stat()", '            resourceIOTrace.record("fstat")\n            var facts = stat()'),
                ("            return (current, handle, fileStat, range,", '            resourceIOTrace.hook("after", at: resource.fileURL)\n            return (current, handle, fileStat, range,'),
                ("    static func byteRange(for request: URLRequest, totalSize: Int64) throws -> ClosedRange<Int64>? {",
                 '    static func byteRange(for request: URLRequest, totalSize: Int64) throws -> ClosedRange<Int64>? {\n        resourceIOTrace.record("range")'),
            ],
        }
        # Instrument actual IO leaves only in temporary source copies. The
        # hooks control a real filesystem race; they never supply parsed data,
        # an authorization decision, a response, or replacement IO methods.
        with tempfile.TemporaryDirectory(prefix="mwx-web-resource-io-leaves-") as raw:
            observed = []
            for path in sources:
                if path.name not in edits:
                    observed.append(path); continue
                text = path.read_text()
                for old, new in edits[path.name]:
                    self.assertEqual(text.count(old), 1, old)
                    text = text.replace(old, new, 1)
                target = Path(raw) / path.name; target.write_text(text)
                observed.append(target)
            compile_and_run(source, observed, "web-range-streaming-pass")


if __name__ == "__main__":
    unittest.main()
