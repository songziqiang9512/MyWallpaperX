"""Directory snapshots and shared real filesystem watcher lifetimes; no App."""
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.test_steam_library_interactions import method
from script.tests.test_web_compat_parity import source_block

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host"

HARNESS = r'''
import Foundation
import Darwin
// RESOURCE TYPES
typealias CGDirectDisplayID = UInt32
enum WallpaperEngine {
    struct WebWallpaperLaunchRequest {
        let id: UUID
        let rootURL: URL
        let propertiesJSON: String?
        let resourceGrants: [WebWallpaperResourceGrant]
        let resourceRevision: UInt64
    }
}
final class Host {
    enum Phase { case ready, launching }
    var phase = Phase.ready
    var enumerationCount = 0
    var directorySyncRequestID: UInt64 = 0
    var directoryResourceCancellation = WebWallpaperLocalSchemeHandler.RequestCancellation()
    let directorySyncQueue = DispatchQueue(label: "web-directory-sync-test")
    var deferredDirectorySyncWorkItem: DispatchWorkItem?
    var directorySnapshotsByProperty: [String: DirectorySnapshot] = [:]
    var directoryAccessErrorsByProperty: [DirectoryAccessErrorKey: String] = [:]
    var directoryWatchersByDirectory: [String: DirectoryWatcher] = [:]
    var directoryWatchTimer: DispatchSourceTimer?
    var randomFileEnumeratingDirectoryPaths = Set<String>()
    var changes: [FetchAllDirectoryNotification] = []
    var access: [FetchAllDirectoryAccessNotification] = []
    func refreshRandomFileSnapshots(using _: String?) {}
    func resetRandomFileSnapshots() {}
    func forEachWebView(_ body: (Int) -> Void) { body(0) }
    func notifyFetchAllDirectoryChanges(propertyName: String, addedOrChangedFiles: [String],
                                       removedFiles: [String], webView: Int) {
        changes.append(.init(propertyName: propertyName, addedOrChangedFiles: addedOrChangedFiles,
                             removedFiles: removedFiles))
    }
    func notifyFetchAllDirectoryAccessState(propertyName: String, errorMessage: String?, webView: Int) {
        access.append(.init(propertyName: propertyName, errorMessage: errorMessage))
    }
// PRODUCT
}
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}
@main enum Harness {
    static func spin(_ phase: String, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        check(condition(), "directory lifecycle \(phase) did not settle")
    }

    static func directoryFDs(_ directory: URL) -> Set<Int32> {
        let expected = directory.resolvingSymlinksInPath().standardizedFileURL.path
        var descriptors = Set<Int32>()
        for fd: Int32 in 0..<512 {
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            if fcntl(fd, F_GETPATH, &path) == 0,
               URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().standardizedFileURL.path == expected {
                descriptors.insert(fd)
            }
        }
        return descriptors
    }

    static func watcherLifecycle(_ host: Host, root: URL, directory: URL, alias: URL) throws {
        let fm = FileManager.default
        let project = root.appendingPathComponent("project")
        let other = root.appendingPathComponent("other directory")
        let forbidden = root.appendingPathComponent("ungranted directory")
        for path in [project, other, forbidden] { try fm.createDirectory(at: path, withIntermediateDirectories: true) }
        try Data([2]).write(to: other.appendingPathComponent("other.png"))
        let secret = forbidden.appendingPathComponent("secret.png")
        try Data([3]).write(to: secret)
        let canonicalDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        let canonicalOther = other.resolvingSymlinksInPath().standardizedFileURL
        let grant = WebWallpaperResourceGrant(kind: .directory, url: directory)
        let otherGrant = WebWallpaperResourceGrant(kind: .directory, url: other)
        var requestID = UUID(), resourceRevision: UInt64 = 1
        func install(_ entries: [String: URL], grants: [WebWallpaperResourceGrant]) throws {
            let bag = entries.mapValues { ["type": "directory", "mode": "fetchall", "value": $0.path] }
            let json = String(decoding: try JSONSerialization.data(withJSONObject: bag), as: UTF8.self)
            host.currentRequest = .init(id: requestID, rootURL: project,
                propertiesJSON: json, resourceGrants: grants, resourceRevision: resourceRevision)
            host.syncFetchAllDirectoryProperties(using: json)
        }

        try install(["first": directory, "second": alias], grants: [grant])
        spin("initial shared watcher") { host.directorySnapshotsByProperty.count == 2 && directoryFDs(directory).count == 1 }
        let originalFD = directoryFDs(directory).first!
        let sharedWatcher = host.directoryWatchersByDirectory[canonicalDirectory.path]!
        let event = directory.appendingPathComponent("event-for-both.png")
        try Data([4]).write(to: event)
        spin("event fan-out") { Set(host.changes.filter { $0.addedOrChangedFiles.contains(event.path) }.map(\.propertyName)) == ["first", "second"] }
        check(host.changes.filter { $0.addedOrChangedFiles.contains(event.path) }.count == 2,
              "one actual directory event must reach both property consumers once")
        try install(["second": alias], grants: [grant])
        spin("remove one property") { Set(host.directorySnapshotsByProperty.keys) == ["second"] }
        check(directoryFDs(directory) == [originalFD]
            && host.directoryWatchersByDirectory[canonicalDirectory.path] === sharedWatcher,
            "removing one property must retain the same live watcher and FD")
        try install([:], grants: [grant])
        spin("remove last property") { host.directorySnapshotsByProperty.isEmpty && fcntl(originalFD, F_GETFD) == -1 }
        check(directoryFDs(directory).isEmpty && host.directoryWatchTimer == nil,
              "removing the last property must cancel its source and close its actual FD")

        resourceRevision += 1
        try install(["first": directory, "second": alias], grants: [grant, otherGrant])
        spin("reinstall shared watcher") { host.directorySnapshotsByProperty.count == 2 && directoryFDs(directory).count == 1 }
        let retainedFD = directoryFDs(directory).first!
        try fm.removeItem(at: alias)
        try fm.createSymbolicLink(at: alias, withDestinationURL: other)
        host.pollFetchAllDirectoryProperties()
        spin("retarget alias to granted directory") { host.directorySnapshotsByProperty["second"]?.sourceDirectoryPath == canonicalOther.path
            && directoryFDs(other).count == 1 }
        check(directoryFDs(directory) == [retainedFD], "retargeting one alias retains the other property's source")
        let otherFD = directoryFDs(other).first!
        let otherEvent = other.appendingPathComponent("event-for-second.png")
        try Data([5]).write(to: otherEvent)
        spin("new directory event") { host.changes.contains { $0.propertyName == "second" && $0.addedOrChangedFiles.contains(otherEvent.path) } }
        check(!host.changes.contains { $0.propertyName == "first" && $0.addedOrChangedFiles.contains(otherEvent.path) },
              "the new directory event must not leak into the unchanged property")

        try fm.removeItem(at: alias)
        try fm.createSymbolicLink(at: alias, withDestinationURL: forbidden)
        host.pollFetchAllDirectoryProperties()
        spin("retarget alias outside grants") { host.directorySnapshotsByProperty["second"]?.filesByPath.isEmpty == true
            && fcntl(otherFD, F_GETFD) == -1 }
        check(directoryFDs(forbidden).isEmpty && directoryFDs(directory) == [retainedFD],
              "an ungranted alias cancels only its old directory watcher")
        check(host.access.contains { $0.propertyName == "second" && $0.errorMessage == "directory_not_authorized" }
            && !host.changes.contains { $0.addedOrChangedFiles.contains(secret.path) }, "ungranted files stay undisclosed")

        let gate = DispatchSemaphore(value: 0)
        host.directorySyncQueue.async { gate.wait() }
        host.syncFetchAllDirectoryProperties(using: host.currentRequest!.propertiesJSON!)
        resourceRevision += 1
        try install(["first": directory, "second": alias], grants: [])
        gate.signal()
        spin("revoke while old synchronization is queued") { host.directorySnapshotsByProperty.values.allSatisfy { $0.filesByPath.isEmpty }
            && fcntl(retainedFD, F_GETFD) == -1 }
        check(directoryFDs(directory).isEmpty && directoryFDs(other).isEmpty,
              "revocation and a late old synchronization must leave no live directory FD")

        host.pollFetchAllDirectoryProperties()
        let oldEvent = host.deferredDirectorySyncWorkItem!
        host.deferredDirectorySyncWorkItem = nil
        requestID = UUID()
        resourceRevision = 1
        try install(["cutover": other], grants: [otherGrant])
        let syncAfterCutover = host.directorySyncRequestID
        oldEvent.perform()
        oldEvent.cancel()
        check(host.directorySyncRequestID == syncAfterCutover, "an already-delivered old event cannot synchronize a new request")
        spin("request cutover") { Set(host.directorySnapshotsByProperty.keys) == ["cutover"] && directoryFDs(other).count == 1 }
        let cutoverFD = directoryFDs(other).first!
        let cutoverEvent = other.appendingPathComponent("event-after-cutover.png")
        try Data([6]).write(to: cutoverEvent)
        spin("new request event") { host.changes.contains { $0.propertyName == "cutover" && $0.addedOrChangedFiles.contains(cutoverEvent.path) } }
        check(!host.changes.contains { $0.propertyName != "cutover" && $0.addedOrChangedFiles.contains(cutoverEvent.path) },
              "new request events cannot reach retired property consumers")
        host.currentRequest = nil
        spin("request teardown") { fcntl(cutoverFD, F_GETFD) == -1 }
        check(directoryFDs(other).isEmpty && host.directoryWatchTimer == nil, "request teardown closes the final watcher")
    }

    static func main() throws {
        let host = Host()
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).resolvingSymlinksInPath()
        try Data("must not be disclosed".utf8).write(to: cwd.appendingPathComponent("cwd-secret.txt"))
        func payload(_ path: String, key: String = "slides") throws -> String {
            String(data: try JSONSerialization.data(withJSONObject: [key:
                ["type":"directory", "mode":"fetchall", "value":path]]), encoding: .utf8)!
        }
        for (index, path) in ["", "  ", "\n\t"].enumerated() {
            let status = host.directorySyncStatus(forPath: path, rootURL: cwd, grants: [])
            check(!status.isAccessible && status.errorMessage == "directory_path_empty", "empty path error")
            check(status.snapshot.filesByPath.isEmpty, "empty path must not expose cwd")
            let result = host.computeFetchAllDirectorySyncResult(using: try payload(path, key: "renamed\(index)"), previousSnapshots: [:], rootURL: cwd, grants: [])
            check(result.snapshotsByProperty.values.allSatisfy { $0.filesByPath.isEmpty }, "empty snapshot")
            check(result.watchedDirectoriesByProperty.isEmpty && !result.hasFetchAllDirectory, "no empty-directory polling")
            check(result.changeNotifications.isEmpty, "no spurious files")
        }
        let directory = cwd.appendingPathComponent("selected directory")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("renamed.png")
        try Data([1]).write(to: file)
        let json = try payload(directory.path)
        let initial = host.computeFetchAllDirectorySyncResult(using: json, previousSnapshots: [:], rootURL: cwd, grants: [])
        check(initial.hasFetchAllDirectory && initial.watchedDirectoriesByProperty.count == 1, "selected directory watched")
        check(initial.changeNotifications.first?.addedOrChangedFiles == [file.path], "initial contents")
        check(initial.snapshotsByProperty["slides"]?.sourceDirectoryPath == directory.path, "snapshot records its canonical source")
        let aliasForSharedScan = cwd.appendingPathComponent("shared-alias")
        try FileManager.default.createSymbolicLink(at: aliasForSharedScan, withDestinationURL: directory)
        let sharedPayload = String(data: try JSONSerialization.data(withJSONObject: [
            "first": ["type":"directory", "mode":"fetchall", "value":directory.path],
            "second": ["type":"directory", "mode":"fetchall", "value":aliasForSharedScan.path]
        ]), encoding: .utf8)!
        let beforeSharedScan = host.enumerationCount
        let shared = host.computeFetchAllDirectorySyncResult(using: sharedPayload, previousSnapshots: [:], rootURL: cwd, grants: [])
        check(host.enumerationCount == beforeSharedScan + 1, "same canonical directory enumerates once per synchronization")
        check(shared.snapshotsByProperty.count == 2 && shared.changeNotifications.count == 2, "both authored properties retain their own notifications")
        check(shared.snapshotsByProperty.values.allSatisfy { $0.sourceDirectoryPath == directory.path && $0.filesByPath.count == 1 && $0.filesByPath[file.path] != nil }, "shared value keeps source and files")
        let unchanged = host.computeFetchAllDirectorySyncResult(using: json, previousSnapshots: initial.snapshotsByProperty, rootURL: cwd, grants: [])
        check(unchanged.changeNotifications.isEmpty, "unchanged directory sends no duplicate list")
        let alias = cwd.appendingPathComponent("selected-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
        let aliasResult = host.computeFetchAllDirectorySyncResult(using: try payload(alias.path),
            previousSnapshots: initial.snapshotsByProperty, rootURL: cwd, grants: [])
        check(aliasResult.changeNotifications.isEmpty, "legal alias uses same canonical file identity without duplicate notifications")
        check(aliasResult.watchedDirectoriesByProperty == initial.watchedDirectoriesByProperty, "alias preserves watcher identity")
        let cleared = host.computeFetchAllDirectorySyncResult(using: try payload(""), previousSnapshots: initial.snapshotsByProperty, rootURL: cwd, grants: [])
        check(cleared.changeNotifications.first?.removedFiles == [file.path], "clearing removes prior contents")
        check(cleared.changeNotifications.first?.addedOrChangedFiles.isEmpty == true, "clearing never adds cwd")
        check(!cleared.hasFetchAllDirectory && cleared.watchedDirectoriesByProperty.isEmpty, "clearing stops polling")
        let missing = host.computeFetchAllDirectorySyncResult(using: try payload(directory.appendingPathComponent("missing").path), previousSnapshots: [:], rootURL: cwd, grants: [])
        check(missing.hasFetchAllDirectory && missing.watchedDirectoriesByProperty.isEmpty, "missing explicit directory retains retry")
        try watcherLifecycle(host, root: cwd, directory: directory, alias: aliasForSharedScan)
        print("web-directory-sync-pass")
    }
}
'''


class WebDirectorySyncTests(unittest.TestCase):
    def test_unset_and_selected_directory_semantics(self):
        types = (HOST / "WebWallpaperHostTypes.swift").read_text()
        source = (HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+DirectorySync.swift").read_text()
        watchers = (HOST / "DedicatedWebWallpaperHostPlaceholderAdapter+DirectoryWatchers.swift").read_text()
        resource_types = source_block(types, "struct WebWallpaperResourceGrant")
        handler = (ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLocalSchemeHandler.swift").read_text()
        resource_types += "\nenum WebWallpaperLocalSchemeHandler {\n" + source_block(handler, "class RequestCancellation") + "\n}"
        declarations = [source_block(types, "struct " + name) for name in (
            "DirectorySnapshot", "DirectorySyncStatus", "FetchAllDirectoryProperty",
            "FetchAllDirectoryNotification", "FetchAllDirectoryAccessNotification", "DirectoryAccessErrorKey",
            "FetchAllDirectorySyncResult")]
        declarations += [source_block(types, "class DirectoryWatcher"), source_block(types, "var currentRequest:")]
        declarations += [line.strip() for line in types.splitlines() if "static let directorySyncDebounceInterval:" in line]
        declarations += [method(source, signature) for signature in (
            "func parseFetchAllDirectoryProperties(", "func syncFetchAllDirectoryProperties(",
            "func computeFetchAllDirectorySyncResult(", "func applyFetchAllDirectorySyncResult(",
            "func directorySyncStatus(", "func startDirectoryWatchTimer(", "func stopDirectoryWatchTimer(",
            "func reconfigureDirectoryWatchers(")]
        declarations += [method(watchers, signature) for signature in (
            "func startDirectoryWatcher(", "func stopDirectoryWatcher(",
            "func stopAllDirectoryWatchers(", "func pollFetchAllDirectoryProperties(")]
        # Count the real enumeration boundary; product code keeps no counter.
        declarations = [value.replace("        guard let enumerator = FileManager.default.enumerator(",
                                      "        enumerationCount += 1\n        guard let enumerator = FileManager.default.enumerator(")
                        for value in declarations]
        with tempfile.TemporaryDirectory(prefix="mwx-web-directory-sync-") as temporary:
            root = Path(temporary)
            (root / "Harness.swift").write_text(HARNESS.replace("// PRODUCT", "\n".join(declarations)).replace("// RESOURCE TYPES", resource_types))
            compile_result = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(root / "Harness.swift"),
                "-o", str(root / "harness")], capture_output=True, text=True, timeout=60)
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            run = subprocess.run([str(root / "harness")], cwd=root, capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("web-directory-sync-pass", run.stdout)
