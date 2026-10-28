"""Trusted Web grants across real resource tasks, IPC and directory producers.

Uses production handlers/bookmark resolver and the production mutation/async
methods with shell-only host collaborators. All files and bookmarks are isolated.
"""
from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.test_steam_library_interactions import method
from script.tests.test_web_compat_parity import source_block
from script.tests.test_web_response_transformer import TRANSFORMER_SOURCES

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host"
WEB = ROOT / "MyWallpaperX/Modules/SteamWorkshop/Web/Core"
SUPPORT = ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Support"


def grant_declaration() -> str:
    return source_block((HOST / "WebWallpaperHostTypes.swift").read_text(),
                        "struct WebWallpaperResourceGrant")


def compile_and_run(source: str, sources: list[Path], marker: str) -> None:
    with tempfile.TemporaryDirectory(prefix="mwx-web-resource-grants-") as temporary:
        task = Path(temporary)
        main = task / "Harness.swift"
        main.write_text(source)
        compiled = subprocess.run(["xcrun", "swiftc", "-parse-as-library",
            *map(str, sources), str(main), "-module-cache-path", str(task / "modules"), "-o", str(task / "harness")],
            capture_output=True, text=True, timeout=90)
        if compiled.returncode:
            raise AssertionError(compiled.stdout + compiled.stderr)
        home = task / "home"
        scratch = task / "tmp"
        home.mkdir(); scratch.mkdir()
        environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home), TMPDIR=str(scratch) + "/")
        run = subprocess.run([str(task / "harness")], cwd=task, env=environment,
                             capture_output=True, text=True, timeout=30)
        if run.returncode or marker not in run.stdout:
            raise AssertionError(run.stdout + run.stderr)


RESOURCE_HARNESS = r'''
import Foundation
import AppKit
import WebKit
import Darwin
// DECLARATIONS
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}
func spin(_ complete: () -> Bool) {
    let deadline = Date().addingTimeInterval(5)
    while !complete(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    check(complete(), "async deadline")
}
final class Task: NSObject, WKURLSchemeTask {
    let request: URLRequest
    var bytes = Data()
    var error: Error?
    var finished = false
    var onChunk: ((Int) -> Void)?
    init(_ url: URL) { request = URLRequest(url: url) }
    func didReceive(_ response: URLResponse) {}
    func didReceive(_ data: Data) { bytes.append(data); onChunk?(bytes.count) }
    func didFinish() { finished = true }
    func didFailWithError(_ error: Error) { self.error = error; finished = true }
}
final class StreamProbe: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var finished = false
    private var failure: Error?
    var onFirstData: (() -> Void)?
    var result: (done: Bool, count: Int, error: Error?) {
        lock.lock(); defer { lock.unlock() }; return (finished, count, failure)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock(); let first = count == 0; count += data.count; lock.unlock()
        if first { onFirstData?() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); failure = error; finished = true; lock.unlock()
    }
}
final class PlaybackResourceLifetime {}
enum WallpaperEngine {
// ENGINE TYPES
}
// IPC TYPES
final class ControlPlane {
    final class Session {
        let request: WallpaperEngine.WebWallpaperLaunchRequest
        var propertiesJSON: String?
        var resourceGrants: [WebWallpaperResourceGrant]
        var propertyRevision: UInt64
        var resourceRevision: UInt64
        var multiDisplayEnabled: Bool
        init(_ request: WallpaperEngine.WebWallpaperLaunchRequest) {
            self.request = request; propertiesJSON = request.propertiesJSON
            resourceGrants = request.resourceGrants; propertyRevision = request.propertyRevision
            resourceRevision = request.resourceRevision; multiDisplayEnabled = request.multiDisplayEnabled
        }
// EXECUTION REQUEST
    }
    var active: Session?
    func propertyUpdateSession(for requestID: UUID) -> Session? {
        active?.request.id == requestID ? active : nil
    }
    func handle(_ command: WallpaperEngine.WebWallpaperRuntimeCommand) {
        for session in [active].compactMap({ $0 }) {
            switch command {
// CONTROL APPLY BRANCH
            default: break
            }
        }
    }
}
final class DedicatedWebWallpaperHostPlaceholderAdapter {
    enum Phase { case ready, launching }
    var phase = Phase.ready
    struct Surface { let schemeHandler: WebWallpaperLocalSchemeHandler }
    var surfaces: [Int: Surface] = [:]
    var views: [WKWebView] = []
    var directorySyncRequestID: UInt64 = 0
    var directoryResourceCancellation = WebWallpaperLocalSchemeHandler.RequestCancellation()
    let directorySyncQueue = DispatchQueue(label: "resource-grant-directory-test")
    var deferredDirectorySyncWorkItem: DispatchWorkItem?
    var directorySnapshotsByProperty: [String: DirectorySnapshot] = [:]
    var directoryAccessErrorsByProperty: [DirectoryAccessErrorKey: String] = [:]
    var directoryWatchersByDirectory: [String: DirectoryWatcher] = [:]
    var directoryWatchTimer: DispatchSourceTimer?
    var randomFileSnapshotsByDirectoryPath: [String: DirectorySnapshot] = [:]
    var randomFileSnapshotRefreshedAtByDirectoryPath: [String: TimeInterval] = [:]
    var randomFileEnumeratingDirectoryPaths = Set<String>()
    static let randomFileSnapshotRefreshInterval: TimeInterval = 0.01
    // Tests invoke the captured work item directly; wall-clock scheduling must
    // not decide whether a normal property edit races the deferred callback.
    static let directorySyncDebounceInterval: TimeInterval = 3600
    var published = 0
    func forEachWebView(_ body: (WKWebView) -> Void) { for view in views { body(view) } }
    func applyProperties(_ value: String, to view: WKWebView) {}
    func notifyFetchAllDirectoryChanges(propertyName: String, addedOrChangedFiles: [String], removedFiles: [String], webView: WKWebView) { published += 1 }
    func notifyFetchAllDirectoryAccessState(propertyName: String, errorMessage: String?, webView: WKWebView) {}
    func handle(_ command: WallpaperEngine.WebWallpaperRuntimeCommand) {
        switch command {
// APPLY BRANCH
        default: break
        }
    }
// HOST MEMBERS
}
enum WebWallpaperHostSupport {
    static let localScheme = "mwx-local"
}
@main enum Harness {
    static func main() throws {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: fm.currentDirectoryPath).resolvingSymlinksInPath()
        let root = base.appendingPathComponent("project")
        let selected = base.appendingPathComponent("selected")
        let directory = base.appendingPathComponent("slides")
        for folder in [root, selected, directory] { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        let file = selected.appendingPathComponent("chosen %20 track.mp3")
        let sibling = selected.appendingPathComponent("private sibling.mp3")
        let child = directory.appendingPathComponent("renamed image.png")
        let own = root.appendingPathComponent("index.html")
        for (url, body) in [(own, "project"), (file, "selected-media"), (sibling, "secret"), (child, "slide")] {
            try Data(body.utf8).write(to: url)
        }
        func absolute(_ file: URL) -> URL {
            var value = URLComponents()
            value.scheme = "mwx-local"; value.host = "wallpaper"
            value.path = "/__absolute__" + file.path
            return value.url!
        }
        let handler = WebWallpaperLocalSchemeHandler(rootURL: root)
        let second = WebWallpaperLocalSchemeHandler(rootURL: root)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        func task(_ url: URL, handler: WebWallpaperLocalSchemeHandler = handler) -> Task {
            let result = Task(url)
            handler.webView(view, start: result)
            spin { result.finished }
            return result
        }
        check(task(URL(string: "mwx-local://wallpaper/index.html")!).bytes == Data("project".utf8), "project namespace")
        check(task(absolute(file)).error != nil, "raw absolute path has no authority")
        let fileGrant = WebWallpaperResourceGrant(kind: .file, url: file)
        for surface in [handler, second] { surface.updateResourceGrants([fileGrant]) }
        check(task(absolute(file)).bytes == Data("selected-media".utf8), "file exact bytes with literal percent and spaces")
        check(task(absolute(sibling)).error != nil, "file must not grant its parent/sibling")
        check(task(absolute(sibling), handler: second).error != nil, "second surface same exact authority")
        let old = handler.resolveResource(for: absolute(file), allowsDirectoryIndexFallback: false).resource!
        let directoryGrant = WebWallpaperResourceGrant(kind: .directory, url: directory)
        handler.updateResourceGrants([directoryGrant])
        check(handler.revalidatedResource(old) == nil, "replacement revokes prepared resolution")
        check(task(absolute(file)).error != nil, "grants replace rather than accumulate")
        check(task(absolute(child)).bytes == Data("slide".utf8), "directory descendant")
        let escape = directory.appendingPathComponent("escape.png")
        try fm.createSymbolicLink(at: escape, withDestinationURL: sibling)
        check(task(absolute(escape)).error != nil, "directory symlink escape")
        check(task(URL(string: "mwx-local://wallpaper/__absolute__" + directory.path + "/%2e%2e/selected/private%20sibling.mp3")!).error != nil, "decoded traversal escape")
        let cachedURL = absolute(child)
        check(task(cachedURL).error == nil, "warm cached resolution")
        try fm.removeItem(at: child)
        try fm.createSymbolicLink(at: child, withDestinationURL: sibling)
        check(task(cachedURL).error != nil, "warm cache cannot bypass changed symlink")
        let blocked = DispatchSemaphore(value: 0)
        handler.ioQueue.async { blocked.wait() }
        let pending = Task(absolute(file))
        handler.updateResourceGrants([fileGrant])
        handler.webView(view, start: pending)
        handler.updateResourceGrants([])
        blocked.signal()
        spin { pending.finished }
        check(pending.bytes.isEmpty && pending.error != nil, "revoked queued resource task")
        let streamed = selected.appendingPathComponent("continuous-media.mp4")
        let streamedBytes = Data(repeating: 7, count: 4 * WebWallpaperLocalSchemeHandler.deliveryChunkSize + 17)
        try streamedBytes.write(to: streamed)
        let streamGrant = WebWallpaperResourceGrant(kind: .file, url: streamed)
        handler.updateResourceGrants([streamGrant, fileGrant])
        let retainedStream = Task(absolute(streamed))
        retainedStream.onChunk = { count in
            if count == WebWallpaperLocalSchemeHandler.deliveryChunkSize {
                handler.updateResourceGrants([streamGrant, directoryGrant])
            }
        }
        handler.webView(view, start: retainedStream)
        spin { retainedStream.finished }
        check(retainedStream.error == nil && retainedStream.bytes == streamedBytes, "changing independent B keeps authorized scheme stream A continuous")
        handler.updateResourceGrants([streamGrant, fileGrant])
        let revokedStream = Task(absolute(streamed))
        revokedStream.onChunk = { count in
            if count == WebWallpaperLocalSchemeHandler.deliveryChunkSize { handler.updateResourceGrants([fileGrant]) }
        }
        handler.webView(view, start: revokedStream)
        spin { revokedStream.finished }
        check(revokedStream.error != nil && revokedStream.bytes.count < streamedBytes.count, "revoking A stops its scheme stream")
        let server = WebWallpaperLoopbackServer(schemeHandler: handler)
        var serverURL: URL?
        server.start { if case let .success(url) = $0 { serverURL = url } }
        spin { serverURL != nil }
        defer { server.stop() }
        let network = URLSession(configuration: .ephemeral)
        defer { network.invalidateAndCancel() }
        func http(_ file: URL) -> (Int, Data) {
            let suffix = absolute(file).absoluteString.components(separatedBy: "/__absolute__/")[1]
            let url = URL(string: serverURL!.absoluteString + "__absolute__/" + suffix)!
            let lock = NSLock()
            var result: (Int, Data)?
            network.dataTask(with: url) { body, response, _ in
                lock.lock(); result = ((response as? HTTPURLResponse)?.statusCode ?? 0, body ?? Data()); lock.unlock()
            }.resume()
            spin { lock.lock(); defer { lock.unlock() }; return result != nil }
            return result!
        }
        handler.updateResourceGrants([fileGrant])
        check(http(file) == (200, Data("selected-media".utf8)), "loopback legal selected media")
        check(http(sibling).0 == 404, "loopback exact-file sibling denial")
        handler.updateResourceGrants([])
        check(http(file).0 == 404, "loopback clear revokes grant")
        let large = selected.appendingPathComponent("large-continuous.mp4")
        fm.createFile(atPath: large.path, contents: nil)
        let largeHandle = try FileHandle(forWritingTo: large)
        let largeSize = 65 * 1024 * 1024 + 123
        try largeHandle.truncate(atOffset: UInt64(largeSize)); try largeHandle.close()
        let largeGrant = WebWallpaperResourceGrant(kind: .file, url: large)
        func loopbackStream(revokesA: Bool) -> StreamProbe {
            handler.updateResourceGrants([largeGrant, fileGrant])
            let probe = StreamProbe()
            probe.onFirstData = {
                handler.updateResourceGrants(revokesA ? [directoryGrant] : [largeGrant, directoryGrant])
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            let session = URLSession(configuration: configuration, delegate: probe, delegateQueue: nil)
            let suffix = absolute(large).absoluteString.components(separatedBy: "/__absolute__/")[1]
            session.dataTask(with: URL(string: serverURL!.absoluteString + "__absolute__/" + suffix)!).resume()
            spin { probe.result.done }
            session.invalidateAndCancel()
            return probe
        }
        let retainedHTTPStream = loopbackStream(revokesA: false).result
        check(retainedHTTPStream.error == nil && retainedHTTPStream.count == largeSize, "changing independent B keeps authorized loopback stream A continuous")
        let revokedHTTPStream = loopbackStream(revokesA: true).result
        check(revokedHTTPStream.error != nil && revokedHTTPStream.count < largeSize, "revoking A stops its loopback stream")
        handler.updateResourceGrants([])

        let requestID = UUID()
        func request(_ revision: UInt64, _ json: String, _ grants: [WebWallpaperResourceGrant]) -> WallpaperEngine.WebWallpaperLaunchRequest {
            .init(id: requestID, entryURL: own, rootURL: root, propertiesJSON: json, source: .steamWorkshop,
                recordID: "fixture", language: "en-us", runtimeProfile: .standard,
                multiDisplayEnabled: true, resourceGrants: grants, propertyRevision: revision, resourceRevision: revision,
                allowedNetworkHosts: ["prepared-resource.example"])
        }
        func payload(_ directory: String) throws -> String {
            String(data: try JSONSerialization.data(withJSONObject: ["renamedSlides":
                ["type": "directory", "mode": "fetchall", "value": directory]]), encoding: .utf8)!
        }
        let json = try payload(directory.path)
        let launch = request(0, json, [directoryGrant])
        let wire = WebDaemonEnvelope(requestID: requestID, payload: WebDaemonLaunch(launch,
            state: .init(paused: false, volume: 0, playbackRate: 1, spectrumLevels: nil)))
        let decoded = try JSONDecoder().decode(WebDaemonEnvelope<WebDaemonLaunch>.self,
            from: JSONEncoder().encode(wire))
        check(decoded.version == 2 && decoded.payload.request(id: requestID).resourceGrants == [directoryGrant], "launch IPC typed grants")
        let host = DedicatedWebWallpaperHostPlaceholderAdapter()
        host.surfaces = [1: .init(schemeHandler: handler), 2: .init(schemeHandler: second)]
        host.views = [view]
        host.currentRequest = launch
        host.syncFetchAllDirectoryProperties(using: json)
        spin { host.directoryWatchersByDirectory.count == 1 }
        check(!host.directorySnapshotsByProperty.values.contains { $0.filesByPath[sibling.path] != nil }, "fetchall symlink containment")
        let watchedDirectoryPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let preservedWatcher = host.directoryWatchersByDirectory[watchedDirectoryPath]!
        let directoryEventFile = directory.appendingPathComponent("event-after-color.png")
        try Data("directory-event".utf8).write(to: directoryEventFile)
        host.pollFetchAllDirectoryProperties()
        let delayedDirectoryEvent = host.deferredDirectorySyncWorkItem!
        var changedBag = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        changedBag["unrelatedTint"] = ["type": "color", "value": "0.2 0.4 0.6"]
        let colorJSON = String(data: try JSONSerialization.data(withJSONObject: changedBag), encoding: .utf8)!
        let syncBeforeColor = host.directorySyncRequestID
        let publicationBeforeEvent = host.published
        host.handle(.applyProperties(.init(requestID: requestID, revision: 1, resourceRevision: 0,
            propertiesJSON: colorJSON, resourceGrants: [directoryGrant])))
        check(host.directorySyncRequestID == syncBeforeColor && host.currentRequest?.resourceRevision == 0,
            "ordinary edit must not start resource work or advance resource authority")
        check(host.directoryWatchersByDirectory[watchedDirectoryPath] === preservedWatcher,
            "ordinary edit must not reopen the directory watcher")
        delayedDirectoryEvent.perform()
        delayedDirectoryEvent.cancel()
        check(host.directorySyncRequestID == syncBeforeColor + 1,
            "deferred directory event must consume the current bag after a normal property edit")
        spin { host.directorySnapshotsByProperty["renamedSlides"]?.filesByPath[directoryEventFile.path] != nil }
        check(host.published > publicationBeforeEvent, "directory event must be published without waiting for a periodic poll")
        check(host.directoryWatchersByDirectory[watchedDirectoryPath] === preservedWatcher,
            "deferred synchronization retains the same watcher")
        let ordinaryGate = DispatchSemaphore(value: 0)
        host.directorySyncQueue.async { ordinaryGate.wait() }
        host.resetRandomFileSnapshots()
        host.refreshRandomFileSnapshots(using: json)
        check(host.randomFileEnumeratingDirectoryPaths.isEmpty, "fetchall does not enqueue a second random-pool enumeration")
        let afterOrdinaryFile = directory.appendingPathComponent("after-ordinary-edits.png")
        try Data("updated after queue wait".utf8).write(to: afterOrdinaryFile)
        host.syncFetchAllDirectoryProperties(using: host.currentRequest!.propertiesJSON!)
        for revision in 2...50 {
            host.handle(.applyProperties(.init(requestID: requestID, revision: UInt64(revision), resourceRevision: 0,
                propertiesJSON: json, resourceGrants: [directoryGrant])))
        }
        check(host.directoryWatchersByDirectory[watchedDirectoryPath] === preservedWatcher, "ordinary updates retain watcher")
        ordinaryGate.signal()
        spin { host.directorySnapshotsByProperty["renamedSlides"]?.filesByPath[afterOrdinaryFile.path] != nil }
        check(host.randomFileSnapshotsByDirectoryPath.isEmpty, "fetchall publishes only its original shared snapshot")
        check(host.resolveRandomFilePath(forPropertyNamed: "renamedSlides") != nil, "fetchall random selection consumes that committed snapshot")
        check(host.directoryWatchersByDirectory[watchedDirectoryPath] === preservedWatcher, "ordinary updates do not starve directory work")
        let queueGate = DispatchSemaphore(value: 0)
        host.directorySyncQueue.async { queueGate.wait() }
        host.syncFetchAllDirectoryProperties(using: json)
        host.pollFetchAllDirectoryProperties()
        let revokedDirectoryEvent = host.deferredDirectorySyncWorkItem!
        // Model an event already handed to its executor: detach the cancellation
        // handle so the resource-revision guard itself must reject it.
        host.deferredDirectorySyncWorkItem = nil
        let clearJSON = try payload("")
        let update = WebWallpaperPropertyUpdate(requestID: requestID, revision: 51, resourceRevision: 1,
            propertiesJSON: clearJSON, resourceGrants: [])
        let command = try JSONDecoder().decode(WallpaperEngine.WebWallpaperRuntimeCommand.self,
            from: JSONEncoder().encode(WallpaperEngine.WebWallpaperRuntimeCommand.applyProperties(update)))
        host.handle(command)
        let syncAfterClear = host.directorySyncRequestID
        revokedDirectoryEvent.perform()
        revokedDirectoryEvent.cancel()
        check(host.directorySyncRequestID == syncAfterClear, "deferred directory event must reject revoked resource authority")
        check(host.directoryWatchersByDirectory.isEmpty && host.randomFileSnapshotsByDirectoryPath.isEmpty, "clear immediately revokes producers")
        queueGate.signal()
        spin { host.directorySnapshotsByProperty["renamedSlides"]?.filesByPath.isEmpty == true }
        check(host.directoryWatchersByDirectory.isEmpty, "late fetchall cannot reinstall watcher")
        host.handle(.applyProperties(.init(requestID: requestID, revision: 0, resourceRevision: 0, propertiesJSON: json, resourceGrants: [directoryGrant])))
        host.handle(.applyProperties(.init(requestID: UUID(), revision: 100, resourceRevision: 0, propertiesJSON: json, resourceGrants: [directoryGrant])))
        host.handle(.applyProperties(.init(requestID: requestID, revision: 100, resourceRevision: 0, propertiesJSON: json, resourceGrants: [directoryGrant])))
        check(host.currentRequest?.resourceGrants.isEmpty == true, "old revision/request cannot widen grants")
        check(host.currentRequest?.allowedNetworkHosts == ["prepared-resource.example"],
            "property and resource changes preserve the prepared author network host snapshot")
        let control = ControlPlane()
        control.active = ControlPlane.Session(host.currentRequest!)
        control.handle(.applyProperties(.init(requestID: requestID, revision: 100, resourceRevision: 0,
            propertiesJSON: json, resourceGrants: [directoryGrant])))
        check(control.active?.executionRequest.resourceGrants.isEmpty == true, "stale control message cannot resurrect authority on recovery")
        control.handle(.applyProperties(.init(requestID: requestID, revision: 100, resourceRevision: 2,
            propertiesJSON: json, resourceGrants: [directoryGrant])))
        check(control.active?.executionRequest.resourceGrants == [directoryGrant], "current control update survives recovery projection")
        check(task(absolute(file), handler: second).error != nil, "property replacement reaches both surface handlers")
        let unauthorized = host.computeFetchAllDirectorySyncResult(using: json, previousSnapshots: [:], rootURL: root, grants: [])
        check(unauthorized.watchedDirectoriesByProperty.isEmpty && !unauthorized.hasFetchAllDirectory, "raw directory no enumeration or polling")
        check(host.resolveRandomFilePath(forPropertyNamed: "renamedSlides") == nil, "cleared random producer")
        host.pollFetchAllDirectoryProperties()
        let oldRequestEvent = host.deferredDirectorySyncWorkItem!
        host.deferredDirectorySyncWorkItem = nil
        host.currentRequest = .init(id: UUID(), entryURL: own, rootURL: root, propertiesJSON: clearJSON,
            source: .steamWorkshop, recordID: "replacement-request", language: "en-us", runtimeProfile: .standard,
            multiDisplayEnabled: true, resourceGrants: [], propertyRevision: 51, resourceRevision: 1)
        let syncAfterRequestReplacement = host.directorySyncRequestID
        oldRequestEvent.perform()
        oldRequestEvent.cancel()
        check(host.directorySyncRequestID == syncAfterRequestReplacement,
            "old deferred request must not synchronize a new request even at the same resource revision")
        // Fetch-all and random selection share one value. A changed property
        // must not consume the prior value merely because both roots are granted.
        let nextDirectory = base.appendingPathComponent("next-slides")
        try fm.createDirectory(at: nextDirectory, withIntermediateDirectories: true)
        let nextFile = nextDirectory.appendingPathComponent("current.png")
        try Data("next".utf8).write(to: nextFile)
        let nextGrant = WebWallpaperResourceGrant(kind: .directory, url: nextDirectory)
        let shared = DedicatedWebWallpaperHostPlaceholderAdapter()
        shared.currentRequest = request(0, json, [directoryGrant, nextGrant])
        shared.syncFetchAllDirectoryProperties(using: json)
        spin { shared.directorySnapshotsByProperty["renamedSlides"]?.sourceDirectoryPath == directory.path }
        check(shared.resolveRandomFilePath(forPropertyNamed: "renamedSlides") != nil, "initial fetchall snapshot can serve random selection")
        check(shared.randomFileSnapshotsByDirectoryPath.isEmpty && shared.randomFileEnumeratingDirectoryPaths.isEmpty,
              "fetchall random selection has no second pool or pending enumeration")
        let nextJSON = try payload(nextDirectory.path)
        shared.currentRequest = request(1, nextJSON, [directoryGrant, nextGrant])
        check(shared.resolveRandomFilePath(forPropertyNamed: "renamedSlides") == nil, "switching directory cannot read its old snapshot")
        shared.syncFetchAllDirectoryProperties(using: nextJSON)
        spin { shared.directorySnapshotsByProperty["renamedSlides"]?.sourceDirectoryPath == nextDirectory.path }
        check(shared.resolveRandomFilePath(forPropertyNamed: "renamedSlides") == shared.absoluteLocalSchemeURL(for: nextFile), "new directory snapshot is selected")
        try fm.removeItem(at: nextFile)
        check(shared.resolveRandomFilePath(forPropertyNamed: "renamedSlides") == nil, "deleted cached file cannot be returned")
        try Data("restored".utf8).write(to: nextFile)
        shared.currentRequest = request(2, nextJSON, [])
        check(shared.resolveRandomFilePath(forPropertyNamed: "renamedSlides") == nil, "revocation rejects an already prepared fetchall snapshot")
        let selectedAlias = base.appendingPathComponent("selected-slides-alias")
        try fm.createSymbolicLink(at: selectedAlias, withDestinationURL: directory)
        let aliasJSON = try payload(selectedAlias.path)
        shared.currentRequest = request(3, aliasJSON, [directoryGrant, nextGrant])
        shared.syncFetchAllDirectoryProperties(using: aliasJSON)
        spin { shared.directorySnapshotsByProperty["renamedSlides"]?.sourceDirectoryPath == directory.path }
        try fm.removeItem(at: selectedAlias)
        try fm.createSymbolicLink(at: selectedAlias, withDestinationURL: nextDirectory)
        check(shared.resolveRandomFilePath(forPropertyNamed: "renamedSlides") == nil, "retargeted symlink cannot reuse its former directory snapshot")
        shared.syncFetchAllDirectoryProperties(using: aliasJSON)
        spin { shared.directorySnapshotsByProperty["renamedSlides"]?.sourceDirectoryPath == nextDirectory.path }
        check(shared.resolveRandomFilePath(forPropertyNamed: "renamedSlides") == shared.absoluteLocalSchemeURL(for: nextFile), "retargeted selection uses the new current snapshot")
        try fm.removeItem(at: nextDirectory)
        check(shared.resolveRandomFilePath(forPropertyNamed: "renamedSlides") == nil, "deleted directory cannot use its retained list")
        shared.stopAllDirectoryWatchers(); shared.stopDirectoryWatchTimer()

        let randomOnly = DedicatedWebWallpaperHostPlaceholderAdapter()
        let randomJSON = String(data: try JSONSerialization.data(withJSONObject: ["renamedSlides":
            ["type":"directory", "mode":"random", "value":directory.path]]), encoding: .utf8)!
        randomOnly.currentRequest = request(0, randomJSON, [directoryGrant])
        spin { randomOnly.randomFileSnapshotsByDirectoryPath[directory.path]?.sourceDirectoryPath == directory.path }
        check(randomOnly.resolveRandomFilePath(forPropertyNamed: "renamedSlides") != nil,
              "non-fetchall directory retains its original random pool")
        print("web-resource-grants-pass")
    }
}
'''


class WebResourceGrantTests(unittest.TestCase):
    def test_binding_bookmark_owner_projects_only_live_authority(self):
        model = (WEB / "SteamWorkshopWebResolvedRuntimeModelTypes.swift").read_text()
        normalization = (WEB / "SteamWorkshopService+WebPropertyNormalizationSupport.swift").read_text()
        bindings = "\n".join(source_block(model, marker) for marker in (
            "enum ResolvedWebResourceBindingKind", "enum ResolvedWebResourceBindingSource",
            "enum ResolvedWebResourceBindingOrigin", "struct ResolvedWebResourceBinding"))
        helpers = "\n".join(method(normalization, marker) for marker in (
            "static func webFileURL(", "static func webAllowedContentTypes("))
        source = r'''
import Foundation
import UniformTypeIdentifiers
import AppKit
import WebKit
// DECLARATIONS
final class BindingTask: NSObject, WKURLSchemeTask {
    let request: URLRequest
    var body = Data(); var error: Error?; var done = false
    init(_ url: URL) { request = URLRequest(url: url) }
    func didReceive(_ response: URLResponse) {}
    func didReceive(_ data: Data) { body.append(data) }
    func didFinish() { done = true }
    func didFailWithError(_ value: Error) { error = value; done = true }
}
struct SteamWorkshopDownloadRecord {
    let id: String
    let folderURL: URL
    let isDependencyBackedWeb: Bool
    let webShellRootURL: URL
    let webHostRootURL: URL?
    let resolvedWebRootURL: URL?
    var presets: [String: SteamWorkshopWebPropertyValue] = [:]
}
struct ResolvedWebProjectDescriptor { let defaultValueMap: [String: SteamWorkshopWebPropertyValue] }
final class SteamWorkshopService {
    let defaults = UserDefaults(suiteName: "mwx-web-grant-test-" + UUID().uuidString)!
    var activeWebPropertySecurityScopedURLs: [String: URL] = [:]
    var definitions: [SteamWorkshopWebPropertyDefinition] = []
    func webPropertyDefinitions(for record: SteamWorkshopDownloadRecord) -> [SteamWorkshopWebPropertyDefinition] { definitions }
    static func webPresetValues(for record: SteamWorkshopDownloadRecord) -> [String: SteamWorkshopWebPropertyValue] { record.presets }
    func webShellResourcePathLikePresetValues(for record: SteamWorkshopDownloadRecord) -> [String: SteamWorkshopWebPropertyValue] { record.presets }
    func webShellResourcePathLikeKeys(for record: SteamWorkshopDownloadRecord) -> Set<String> { Set(record.presets.keys.map { $0.lowercased() }) }
    static func normalizedWebColorRuntimeString(from raw: String) -> String? { nil }
    static func trimmedNonEmptyString(_ value: String?) -> String? { value?.isEmpty == false ? value : nil }
// HELPERS
// LIVE CACHE CHECK
}
func check(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }
@main enum Harness {
    static func main() throws {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: fm.currentDirectoryPath).resolvingSymlinksInPath()
        let host = base.appendingPathComponent("host")
        let shell = base.appendingPathComponent("shell")
        let external = base.appendingPathComponent("user-selected")
        for url in [host, shell, external] { try fm.createDirectory(at: url, withIntermediateDirectories: true) }
        let chosen = external.appendingPathComponent("renamed.wav")
        let privatePeer = external.appendingPathComponent("private.wav")
        let bundled = host.appendingPathComponent("bundled.png")
        let preset = shell.appendingPathComponent("renamed-preset.png")
        let shellPeer = shell.appendingPathComponent("shell-bundled-neighbor.png")
        for url in [chosen, privatePeer, bundled, preset, shellPeer] { try Data([1, 2, 3]).write(to: url) }
        var record = SteamWorkshopDownloadRecord(id: "isolated", folderURL: host,
            isDependencyBackedWeb: true, webShellRootURL: shell, webHostRootURL: host, resolvedWebRootURL: host)
        func definition(_ key: String, _ kind: SteamWorkshopWebPropertyKind, _ value: String) -> SteamWorkshopWebPropertyDefinition {
            .init(key: key, title: key, kind: kind, runtimeType: kind.rawValue, order: 0,
                minimumValue: nil, maximumValue: nil, allowsFractionalValues: false,
                fractionalPrecision: nil, displayCondition: nil, directoryMode: nil, fileType: nil,
                defaultValue: .string(value), options: [])
        }
        let service = SteamWorkshopService()
        let handler = WebWallpaperLocalSchemeHandler(rootURL: host)
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        func read(_ file: URL) -> BindingTask {
            var url = URLComponents(); url.scheme = "mwx-local"; url.host = "wallpaper"
            url.path = "/__absolute__" + file.path
            let task = BindingTask(url.url!); handler.webView(view, start: task)
            let deadline = Date().addingTimeInterval(5)
            while !task.done, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            check(task.done, "binding resource task deadline")
            return task
        }
        let file = definition("renamedAudio", .file, chosen.path)
        service.definitions = [file]
        check(service.resolvedWebRuntimeProperty(forKey: file.key, definition: file,
            rawValue: .string(chosen.path), record: record).value == .string(chosen.path), "raw author value remains a value, without authority")
        let rawGrants = service.resolvedWebResourceGrants(for: record, definitions: [file])
        check(!rawGrants.contains { $0.allowsCanonicalURL(chosen) }, "path existence cannot grant authority")
        handler.updateResourceGrants(rawGrants)
        check(read(chosen).error != nil, "raw external file actual task denied")
        // This is the production selection/bookmark owner, not a payload-derived grant.
        service.updateWebPropertyBookmark(for: file, value: .string(chosen.path), record: record)
        check(service.webPropertyOverrides(for: record).isEmpty, "bookmark-only state fixture")
        let grants = service.resolvedWebResourceGrants(for: record, definitions: [file])
        check(grants.contains { $0.kind == .file && $0.allowsCanonicalURL(chosen) }, "bookmarked exact file")
        check(!grants.contains { $0.allowsCanonicalURL(privatePeer) }, "bookmarked file never grants sibling")
        handler.updateResourceGrants(grants)
        check(read(chosen).body == Data([1, 2, 3]) && read(privatePeer).error != nil, "bookmarked actual selected bytes and external sibling denial")
        check(read(bundled).body == Data([1, 2, 3]) && read(shellPeer).body == Data([1, 2, 3]), "host and shell bundled namespaces remain readable")
        check(service.resolvedWebRuntimeProperty(forKey: file.key, definition: file,
            rawValue: .string(chosen.path), record: record).value == .string(chosen.path), "legal bookmark payload preserved")
        check(service.resolvedWebRuntimeProperty(forKey: file.key, definition: file,
            rawValue: .string(chosen.path), record: record).binding?.source == .bookmarkedOverride,
            "current value projection carries its actual binding, not a second interpretation")
        let restored = external.appendingPathComponent("restored.wav")
        try fm.moveItem(at: chosen, to: restored)
        let moved = service.resolvedWebResourceGrants(for: record, definitions: [file])
        check(moved.contains { $0.kind == .file && $0.url == restored }, "moved bookmark is re-resolved rather than copied from cached binding")
        check(service.resolvedWebRuntimeProperty(forKey: file.key, definition: file,
            rawValue: .string(chosen.path), record: record).value == .string(restored.path),
            "next value projection resolves the changed bookmark again")
        service.updateWebPropertyBookmark(for: file, value: .string(""), record: record)
        let cleared = service.resolvedWebResourceGrants(for: record, definitions: [file])
        check(!cleared.contains { $0.allowsCanonicalURL(restored) }, "clear removes live bookmark grant")
        handler.updateResourceGrants(cleared)
        check(read(restored).error != nil && read(shellPeer).body == Data([1, 2, 3]), "clear revokes external bytes while retaining shell namespace")
        let directory = definition("renamedDirectory", .directory, external.path)
        service.updateWebPropertyBookmark(for: directory, value: .string(external.path), record: record)
        let directories = service.resolvedWebResourceGrants(for: record, definitions: [directory])
        check(directories.contains { $0.kind == .directory && $0.allowsCanonicalURL(restored) }, "selected directory descendant")
        service.clearWebPropertyBookmarks(for: record)
        check(!service.resolvedWebResourceGrants(for: record, definitions: [directory]).contains { $0.allowsCanonicalURL(restored) }, "reset revokes external directory")
        let local = definition("local", .file, "bundled.png")
        check(service.resolvedWebResourceGrants(for: record, definitions: [local]).contains { $0.url == bundled }, "legal authored relative resource")
        record.presets = ["custom_background": .string("renamed-preset.png")]
        check(service.resolvedWebResourceGrants(for: record, definitions: []).contains { $0.url == preset }, "dependency shell preset binding")
        record.presets = ["custom_background": .string(privatePeer.path)]
        check(!service.resolvedWebResourceGrants(for: record, definitions: []).contains { $0.allowsCanonicalURL(privatePeer) }, "preset absolute path cannot fabricate grant")
        print("web-binding-grants-pass")
    }
}
'''
        author = (WEB / "SteamWorkshopService+WebAuthorInput.swift").read_text()
        context = source_block(author, "nonisolated struct WebAuthorBindingContext")
        context = context.replace(method(context, "nonisolated static func make("), "")
        bindings += "\nextension SteamWorkshopService {\n" + context + "\n}\n"
        source = source.replace("// DECLARATIONS", grant_declaration() + "\n" + bindings).replace(
            "// HELPERS", helpers).replace("// LIVE CACHE CHECK", "")
        compile_and_run(source, [WEB / "SteamWorkshopWebPropertyModels.swift",
            WEB / "SteamWorkshopService+WebPropertySupport.swift",
            WEB / "SteamWorkshopService+WebPropertyOverridePersistence.swift"] + TRANSFORMER_SOURCES, "web-binding-grants-pass")

    def test_real_resource_tasks_ipc_and_async_directory_revocation(self):
        types = (HOST / "WebWallpaperHostTypes.swift").read_text()
        lifecycle = (HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+Lifecycle.swift").read_text()
        runtime = (HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift").read_text()
        directory = (HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+DirectorySync.swift").read_text()
        watchers = (HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+DirectoryWatchers.swift").read_text()
        ipc = (ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonProtocol.swift").read_text()
        control = (ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonHostAdapter.swift").read_text()
        engine = "\n".join(source_block(types, name) for name in (
            "enum WebWallpaperLaunchSource", "enum WebRuntimeOriginMode", "struct WebRuntimeProfile",
            "struct WebWallpaperLaunchRequest", "struct WebWallpaperRuntimeState", "enum WebWallpaperRuntimeCommand"))
        declarations = grant_declaration() + "\n" + source_block(types, "struct WebWallpaperPropertyUpdate")
        ipc_types = "\n".join(source_block(ipc, name) for name in (
            "enum WebDaemonProtocol", "struct WebDaemonEnvelope", "struct WebDaemonLaunch"))
        members = [source_block(types, name) for name in (
            "struct DirectorySnapshot", "struct DirectorySyncStatus", "struct FetchAllDirectoryProperty",
            "struct FetchAllDirectoryNotification", "struct FetchAllDirectoryAccessNotification",
            "struct DirectoryAccessErrorKey", "struct FetchAllDirectorySyncResult", "class DirectoryWatcher")]
        members += [source_block(types, "var currentRequest:")]
        members += [method(directory, name) for name in (
            "func parseFetchAllDirectoryProperties(", "func syncFetchAllDirectoryProperties(",
            "func computeFetchAllDirectorySyncResult(", "func applyFetchAllDirectorySyncResult(",
            "func directorySyncStatus(", "func startDirectoryWatchTimer(",
            "func stopDirectoryWatchTimer(", "func reconfigureDirectoryWatchers(")]
        members += [method(watchers, name) for name in (
            "func startDirectoryWatcher(", "func stopDirectoryWatcher(",
            "func stopAllDirectoryWatchers(", "func pollFetchAllDirectoryProperties(")]
        members += [method(runtime, name) for name in (
            "func refreshReadableResourceRoots(", "func resolveRandomFilePath(", "func randomFileURL(",
            "func resetRandomFileSnapshots(", "func refreshRandomFileSnapshots(",
            "private func randomFileCacheKey(", "private func scheduleRandomFileSnapshotRefresh(",
            "func absoluteLocalSchemeURL(")]
        branch = lifecycle[lifecycle.index("            case let .applyProperties(update):"):
                           lifecycle.index("            case .stop:", lifecycle.index("            case let .applyProperties(update):"))]
        control_branch = control[control.index("            case let .applyProperties(update):"):
                                 control.index("            case .stop:", control.index("            case let .applyProperties(update):"))]
        source = RESOURCE_HARNESS.replace("// DECLARATIONS", declarations).replace(
            "// ENGINE TYPES", engine).replace("// IPC TYPES", ipc_types).replace(
            "// HOST MEMBERS", "\n".join(members)).replace("// APPLY BRANCH", branch).replace(
            "// CONTROL APPLY BRANCH", control_branch).replace("// EXECUTION REQUEST", source_block(control, "var executionRequest:"))
        compile_and_run(source, TRANSFORMER_SOURCES + [SUPPORT / "WebWallpaperLoopbackServer.swift",
            SUPPORT / "WebWallpaperLoopbackServer+Connection.swift"], "web-resource-grants-pass")


if __name__ == "__main__":
    unittest.main()
