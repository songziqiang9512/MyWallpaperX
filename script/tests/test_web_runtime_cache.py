"""Production warm analysis reuse, nonblocking save and publication CAS.

No parser substitutes: the shared harness compiles the real capture, JSON,
properties, assembly and playback preparation. Gates pause staging/rename only.
"""
from __future__ import annotations

import unittest
from script.tests.test_steam_library_interactions import method
from script.tests.test_web_author_preparation import CHECKS, WEB, harness_source as author_source, run_harness

CACHE_CHECKS = r'''
@main enum CacheHarness {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: fm.currentDirectoryPath).resolvingSymlinksInPath()
        let folder = root.appendingPathComponent("author"); try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        func write(_ text: String, _ name: String) throws { try Data(text.utf8).write(to: folder.appendingPathComponent(name)) }
        let project = #"{"file":"index.html","general":{"properties":{"speed":{"type":"slider","value":1},"selected":{"type":"file","value":"bundled.png"}}},"preset":{"speed":7}}"#
        try write(project, "project.json"); try write("<script src='a.js'></script>", "index.html"); try write("properties.fps", "a.js")
        try write("bundled", "bundled.png")
        let external = root.appendingPathComponent("external.png"), peerFileURL = root.appendingPathComponent("peer.png")
        try Data("external".utf8).write(to: external); try Data("peer".utf8).write(to: peerFileURL)
        let record = SteamWorkshopDownloadRecord(id: "cached", folderURL: folder,
            projectFileURL: folder.appendingPathComponent("project.json"), entryURL: folder.appendingPathComponent("index.html"))
        let service = SteamWorkshopService(); service.steamDownloadLibraryRootURL = root.appendingPathComponent("library")
        trace.reset(); let backgroundWrite = Gate(); cacheStaging.gate = backgroundWrite
        let cold = await service.prepareWebPlaybackContext(for: record)!
        await backgroundWrite.wait()
        check(!fm.fileExists(atPath: service.webAnalysisCacheFileURL(for: record).path), "playback preparation returns while optional cache publication is blocked")
        cacheStaging.gate = nil; backgroundWrite.release.signal()
        check(cold.descriptor.defaultValueMap["speed"] == .number(7) && trace.parseCount == 1, "real cold parser and final projection")
        check(trace.rows.count == 3, "cold capture plus parse plus save performs one actual read per author file")
        let analysisURL = service.webAnalysisCacheFileURL(for: record)
        func waitForAnalysis(expectedSpeed: Double = 7) async throws -> Data {
            for _ in 0..<200 {
                if let data = try? Data(contentsOf: analysisURL),
                   let manifest = try? JSONDecoder().decode(SteamWorkshopWebAnalysisCacheManifest.self, from: data),
                   manifest.version == SteamWorkshopWebAnalysisCacheManifest.currentVersion,
                   manifest.author.product.presetOverrides["speed"] == .number(expectedSpeed) { return data }
                try await Task.sleep(for: .milliseconds(10))
            }
            fatalError("analysis writer did not finish")
        }
        let analysisOriginal = try await waitForAnalysis()
        trace.reset()
        let warmMemo = await service.prepareWebPlaybackContext(for: record)!
        check(cold == warmMemo && trace.rows.isEmpty && trace.parseCount == 0, "memo warm performs no author byte reads or scan")
        service.webProjectDescriptorCache = [:]; trace.reset()
        let warm = await service.prepareWebPlaybackContext(for: record)!
        check(cold == warm && trace.rows.isEmpty && trace.parseCount == 0, "disk warm reuses author analysis without scanning dependencies")
        // Exercise the actual property actions. Persistence/bookmark and live
        // player delivery remain the harness's existing controlled leaves.
        let speed = warm.descriptor.propertyDefinitions.first { $0.key == "speed" }!
        let authorMemo = service.webProjectDescriptorCache[record.id]
        check(authorMemo != nil, "warm preparation has a reusable author memo")
        trace.reset()
        service.updateWebPropertyValue(.number(11), for: speed, record: record)
        check(service.webProjectDescriptorCache[record.id] == authorMemo, "property update retains author-only memo")
        service.bookmarks["selected"] = external
        let updated = await service.prepareWebPlaybackContext(for: record)!
        let updatedJSON = try JSONSerialization.jsonObject(with: Data(updated.context.propertyPayloadJSON!.utf8)) as! [String: [String: Any]]
        check(updatedJSON["speed"]?["value"] as? Double == 11 && updated.descriptor == cold.descriptor
            && trace.rows.isEmpty && trace.parseCount == 0, "actual property update keeps next preparation warm with latest override")
        check(updatedJSON["selected"]?["value"] as? String == external.path
            && updated.context.resourceGrants.contains { $0.url == external && $0.kind == .file }
            && !updated.context.resourceGrants.contains { $0.allowsCanonicalURL(peerFileURL) }, "warm author cannot cache bookmark payload or widen exact-file grants")
        service.resetWebPropertyValues(for: record)
        check(service.webProjectDescriptorCache[record.id] == authorMemo, "property reset retains author-only memo")
        trace.reset()
        let reset = await service.prepareWebPlaybackContext(for: record)!
        let resetJSON = try JSONSerialization.jsonObject(with: Data(reset.context.propertyPayloadJSON!.utf8)) as! [String: [String: Any]]
        check(resetJSON["speed"]?["value"] as? Double == 7 && trace.rows.isEmpty && trace.parseCount == 0
            && !reset.context.resourceGrants.contains { $0.url == external }, "actual reset clears current override/bookmark while author remains warm")
        service.observeWebPlaybackFailures()
        NotificationCenter.default.post(name: WallpaperEngine.playbackFailedNotification, object: nil,
            userInfo: ["contentKind": "web", "recordID": record.id, "path": record.entryURL!.path, "message": "controlled runtime failure"])
        for _ in 0..<100 {
            if service.lastWebPlaybackFailureMessage == "controlled runtime failure" { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        check(service.lastWebPlaybackFailureRecordID == record.id
            && service.lastWebPlaybackFailurePath == record.entryURL!.path
            && service.lastWebPlaybackFailureMessage == "controlled runtime failure"
            && service.webProjectDescriptorCache[record.id] == authorMemo, "actual failure observer publishes feedback without clearing author analysis")
        trace.reset()
        let recovered = await service.prepareWebPlaybackContext(for: record)!
        check(recovered == reset && trace.rows.isEmpty && trace.parseCount == 0, "runtime failure leaves same-author preparation warm")
        let inputs = service.webRuntimeCacheManifestInputs(for: record, source: service.webPropertyDefinitionSource(for: record))
        for missing in [false, true] {
            if missing { try fm.removeItem(at: analysisURL) } else { try Data("corrupt".utf8).write(to: analysisURL) }
            check(SteamWorkshopService.loadCachedAnalysisDescriptor(inputs: inputs) == nil, "missing/corrupt analysis is a cache miss, not a playback refusal")
            try analysisOriginal.write(to: analysisURL)
        }
        for wrongVersion in [false, true] {
            var json = try JSONSerialization.jsonObject(with: analysisOriginal) as! [String: Any]
            if wrongVersion { json["version"] = -1 }
            else {
                var author = json["author"] as! [String: Any]
                var identity = author["identity"] as! [String: Any]
                identity["languageKeys"] = ["different"]; author["identity"] = identity; json["author"] = author
            }
            try JSONSerialization.data(withJSONObject: json).write(to: analysisURL)
            check(SteamWorkshopService.loadCachedAnalysisDescriptor(inputs: inputs) == nil, "schema/ordered locale changes invalidate derived analysis")
            try analysisOriginal.write(to: analysisURL)
        }
        // Same size and mtime still changes ctime/replacement identity.
        let projectURL = record.projectFileURL!
        let oldDate = try fm.attributesOfItem(atPath: projectURL.path)[.modificationDate] as! Date
        try write(project.replacingOccurrences(of: "\"speed\":7", with: "\"speed\":8"), "project.json")
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: projectURL.path)
        service.webProjectDescriptorCache = [:]
        let edited = await service.prepareWebPlaybackContext(for: record)!
        check(edited.descriptor.defaultValueMap["speed"] == .number(8), "stat revisions reject stale same-size/mtime author input")

        _ = try await waitForAnalysis(expectedSpeed: 8)

        let owner = SteamWorkshopWebRuntimeCachePublication.shared
        let target = root.appendingPathComponent("publication/analysis.json")
        let peer = root.appendingPathComponent("publication/runtime.json")
        let key = target.path
        // Writer already passed actor checks and completed IO outside its lock.
        // A new ticket can publish; the old rename cannot overwrite it.
        let old = owner.begin(key: key)
        let staging = Gate(); cacheStaging.gate = staging
        let late = Task.detached { owner.publish(Data("old".utf8), to: target, ticket: old) }
        await staging.wait()
        let newer = owner.begin(key: key)
        check(owner.publish(Data("new".utf8), to: target, ticket: newer), "new publication while old staging is blocked")
        staging.release.signal(); let lateResult = await late.value
        let finalData = try Data(contentsOf: target)
        check(!lateResult && finalData == Data("new".utf8), "final CAS fences check-before-IO race")
        cacheStaging.gate = nil
        // Deletion shares the same commit fence and cannot be resurrected.
        let deleted = owner.begin(key: key)
        check(owner.publish(Data("A".utf8), to: target, ticket: deleted) && owner.publish(Data("B".utf8), to: peer, ticket: deleted), "delete fixture")
        let deleteStaging = Gate(); cacheStaging.gate = deleteStaging
        let resurrection = Task.detached { owner.publish(Data("late".utf8), to: target, ticket: deleted) }
        await deleteStaging.wait(); owner.invalidate(key: key, removing: [target, peer]); deleteStaging.release.signal()
        let resurrectionResult = await resurrection.value
        check(!resurrectionResult && !fm.fileExists(atPath: target.path) && !fm.fileExists(atPath: peer.path), "delete cannot be undone by staged old save")
        cacheStaging.gate = nil
        // Cancellation while staging is complete rejects rename and cleans only
        // this O_EXCL staging file, leaving no pending writer behind.
        let cancelTicket = owner.begin(key: key); let cancelGate = Gate(); cacheStaging.gate = cancelGate
        let canceled = Task.detached { owner.publish(Data("cancel".utf8), to: target, ticket: cancelTicket) }
        await cancelGate.wait(); canceled.cancel(); cancelGate.release.signal(); let canceledResult = await canceled.value
        check(!canceledResult && !fm.fileExists(atPath: target.path), "canceled save cannot publish")
        cacheStaging.gate = nil
        let pending = try fm.contentsOfDirectory(atPath: target.deletingLastPathComponent().path).filter { $0.hasSuffix(".pending") }
        check(pending.isEmpty, "owned staging cleanup after stale/delete/cancel")
        // A publication already in rename serializes with deletion. The test
        // releases it from outside the actor instead of blocking the UI owner.
        let committed = owner.begin(key: key); let renameGate = Gate(); cacheCommit.gate = renameGate
        let writer = Task.detached { owner.publish(Data("committing".utf8), to: target, ticket: committed) }
        await renameGate.wait()
        let remover = Task.detached { owner.invalidate(key: key, removing: [target]) }
        renameGate.release.signal(); _ = await writer.value; await remover.value
        check(!fm.fileExists(atPath: target.path), "in-commit writer finishes before same-fence physical delete")
        cacheCommit.gate = nil
        for i in 0..<500 { _ = owner.begin(key: "ephemeral-\(i)") }
        _ = owner.begin(key: "reap")
        check(owner.testLiveSlots <= 2, "registry retains active tickets, not historical records")
        print("web-runtime-cache-pass")
    }
}
'''


def harness_source() -> str:
    source = author_source().removesuffix(CHECKS)
    source = source.replace('import Foundation\n', 'import Foundation\nimport Combine\n', 1)
    source = source.replace('@MainActor final class SteamWorkshopService {', r'''@MainActor final class SteamWorkshopService {
    let objectWillChange = ObservableObjectPublisher()
    var cancellables = Set<AnyCancellable>()
    var lastWebPlaybackFailureRecordID: String?
    var lastWebPlaybackFailurePath: String?
    var lastWebPlaybackFailureMessage: String?
    func saveWebPropertyOverrides(_ values: [String: SteamWorkshopWebPropertyValue], for record: SteamWorkshopDownloadRecord) { overrides = values }
    func updateWebPropertyBookmark(for definition: SteamWorkshopWebPropertyDefinition,
        value: SteamWorkshopWebPropertyValue, record: SteamWorkshopDownloadRecord) {}
    func clearWebPropertyBookmarks(for record: SteamWorkshopDownloadRecord) { bookmarks.removeAll() }
    func isActiveWebRecord(_ record: SteamWorkshopDownloadRecord) -> Bool { false }
''', 1)
    properties = (WEB / 'SteamWorkshopService+WebProperties.swift').read_text()
    controls = (WEB / 'SteamWorkshopService+WebPropertyControlSupport.swift').read_text()
    source += '\nextension SteamWorkshopService {\n' + '\n'.join(method(properties, signature) for signature in (
        '    func updateWebPropertyValue(', '    func resetWebPropertyValues(',
        '    private func webPropertyChangesResources(', '    func currentWebPropertyValue(',
        '    func visibleWebPropertyOptions(',
    )) + '\n' + method(controls, '    func shouldRefreshFullWebPropertyPayload(') + '\n}\n'
    source += (WEB / 'SteamWorkshopService+WebRuntimeState.swift').read_text()
    source += r'''
@MainActor final class WallpaperEngine {
    static let shared = WallpaperEngine()
    nonisolated static let playbackFailedNotification = Notification.Name("controlled-web-runtime-failed")
    var currentWebResourceGrants: [WebWallpaperResourceGrant] = []
    var currentWebResourceRootURL: URL?
    func updateCurrentWebWallpaperProperties(_ payload: String?, resourceGrants: [WebWallpaperResourceGrant], resourcesChanged: Bool) {}
}
'''
    source += r'''
nonisolated final class PublicationGate: @unchecked Sendable { var gate: Gate? }
nonisolated let cacheStaging = PublicationGate()
nonisolated let cacheCommit = PublicationGate()
'''
    source = source.replace('            try handle.write(contentsOf: data)', '            try handle.write(contentsOf: data)\n            cacheStaging.gate?.pause()', 1)
    source = source.replace('            return rename(staging.path, fileURL.path) == 0', '            cacheCommit.gate?.pause()\n            return rename(staging.path, fileURL.path) == 0', 1)
    source = source.replace('    private let registryLock = NSLock()', '    var testLiveSlots: Int { registryLock.withLock { slots.values.filter { $0.value != nil }.count } }\n    private let registryLock = NSLock()', 1)
    # Compare complete resulting preparations without granting value types a new
    # product conformance just for this gate.
    source += r'''
@MainActor func == (lhs: ResolvedWebPlaybackPreparation, rhs: ResolvedWebPlaybackPreparation) -> Bool {
    let a = lhs.context, b = rhs.context
    let aj = a.propertyPayloadJSON.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? NSDictionary
    let bj = b.propertyPayloadJSON.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? NSDictionary
    return a.recordID == b.recordID && a.effectiveEntryURL == b.effectiveEntryURL && a.effectiveRootURL == b.effectiveRootURL
        && a.language == b.language && a.resourceGrants == b.resourceGrants && aj == bj && lhs.descriptor == rhs.descriptor
}
'''
    return source + CACHE_CHECKS


class WebRuntimeCacheTests(unittest.TestCase):
    def test_real_preparation_and_publication_fence(self):
        run_harness(self, harness_source(), 'web-runtime-cache-pass')


if __name__ == '__main__': unittest.main()
