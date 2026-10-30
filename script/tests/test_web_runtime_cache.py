"""Production warm analysis reuse, nonblocking save and publication CAS.

No parser substitutes: the shared harness compiles the real capture, JSON,
properties, assembly and playback preparation. Gates pause staging/rename only.
"""
from __future__ import annotations

import json
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
        trace.reset(); ProjectionWork.reset()
        let warmMemo = await service.prepareWebPlaybackContext(for: record)!
        check(cold == warmMemo && trace.rows.isEmpty && trace.parseCount == 0, "memo warm performs no author byte reads or scan")
        check(ProjectionWork.bindings == 4 && ProjectionWork.fallbacks == 0,
            "two current properties resolve once for values/payload and once for actual grants, without eager fallback JSON")
        let selected = warmMemo.descriptor.propertyDefinitions.first { $0.key == "selected" }!
        service.activeRecord = true; ProjectionWork.reset()
        service.previewWebPropertyValue(.string(external.path), for: selected, record: record)
        check(ProjectionWork.bindings == 3 && ProjectionWork.fallbacks == 0,
            "preview resolves the changed value once, then current grant definitions independently")
        let preview = try JSONSerialization.jsonObject(with: Data(WallpaperEngine.shared.payloads.last!.utf8)) as! [String: [String: Any]]
        check(preview["selected"]?["value"] as? String == external.path
            && !WallpaperEngine.shared.currentWebResourceGrants.contains { $0.allowsCanonicalURL(external) },
            "preview value is delivered without granting an unbookmarked external path")
        ProjectionWork.reset()
        service.updateWebPropertyValue(.string(external.path), for: selected, record: record)
        check(ProjectionWork.bindings == 3 && ProjectionWork.fallbacks == 0,
            "commit consumes its one current value binding without a payload re-resolution")
        let committedPayload = try JSONSerialization.jsonObject(with: Data(WallpaperEngine.shared.payloads.last!.utf8)) as! [String: [String: Any]]
        check((committedPayload as NSDictionary) == (preview as NSDictionary), "actual preview and commit preserve the complete delta payload")
        service.activeRecord = false; service.overrides = [:]
        ProjectionWork.reset()
        let emptyPayload = service.effectiveWebPropertiesJSONString(for: record, definitions: [], valuesOverride: [:])
        check(emptyPayload == "{}" && ProjectionWork.fallbacks == 1,
            "empty payload still uses the original fallback only when returned")
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
        // Saving an already captured author is optional derived work, even if
        // the source changes before publication. Its actual consumer decides
        // whether the hint is current; the writer does not reread dependencies.
        let oldAuthor = try JSONDecoder().decode(SteamWorkshopWebAnalysisCacheManifest.self, from: analysisOriginal).author
        try fm.removeItem(at: analysisURL)
        let staleTicket = SteamWorkshopWebRuntimeCachePublication.shared.begin(key: analysisURL.path)
        SteamWorkshopService.saveWebAnalysisCache(oldAuthor, inputs: inputs, publication: staleTicket)
        _ = try await waitForAnalysis()
        check(SteamWorkshopService.loadCachedAnalysisDescriptor(inputs: inputs) == nil,
            "published old hint is a miss after current author changes")
        service.webProjectDescriptorCache = [:]
        trace.reset()
        let edited = await service.prepareWebPlaybackContext(for: record)!
        check(edited.descriptor.defaultValueMap["speed"] == .number(8), "stat revisions reject stale same-size/mtime author input")
        check(trace.parseCount == 1, "stale hint returns to the actual parser for current author input")

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
        // Exercise the service deletion owner, including memo removal and the
        // retired execution cache, while an older analysis save is staged.
        let serviceRuntime = analysisURL.deletingLastPathComponent()
            .appendingPathComponent("\(SteamWorkshopService.webRuntimeCacheFileStem(for: record.id))-runtime.json")
        let otherID = "unrelated-cache"
        let otherAnalysis = analysisURL.deletingLastPathComponent()
            .appendingPathComponent("\(SteamWorkshopService.webRuntimeCacheFileStem(for: otherID))-analysis.json")
        let otherMemo = service.webProjectDescriptorCache[record.id]
        check(otherMemo != nil, "service deletion fixture has an author memo")
        service.webProjectDescriptorCache[otherID] = otherMemo
        let otherTicket = owner.begin(key: otherAnalysis.path)
        check(owner.publish(Data("keep".utf8), to: otherAnalysis, ticket: otherTicket), "unrelated record fixture")
        let serviceDeleted = owner.begin(key: analysisURL.path)
        check(owner.publish(Data("analysis".utf8), to: analysisURL, ticket: serviceDeleted)
            && owner.publish(Data("runtime".utf8), to: serviceRuntime, ticket: serviceDeleted), "service deletion files")
        let serviceDeleteGate = Gate(); cacheStaging.gate = serviceDeleteGate
        let serviceResurrection = Task.detached {
            owner.publish(Data("late-service".utf8), to: analysisURL, ticket: serviceDeleted)
        }
        await serviceDeleteGate.wait()
        service.removeWebRuntimeCaches(for: record.id)
        check(service.webProjectDescriptorCache[record.id] == nil && !owner.isCurrent(serviceDeleted)
            && !fm.fileExists(atPath: analysisURL.path) && !fm.fileExists(atPath: serviceRuntime.path),
            "actual service deletion clears memo, invalidates old ticket and removes both cache files")
        serviceDeleteGate.release.signal(); let serviceResurrectionResult = await serviceResurrection.value
        check(!serviceResurrectionResult && !fm.fileExists(atPath: analysisURL.path)
            && !fm.fileExists(atPath: serviceRuntime.path), "staged writer cannot restore a service-deleted cache")
        let otherData = try Data(contentsOf: otherAnalysis)
        check(service.webProjectDescriptorCache[otherID] == otherMemo && owner.isCurrent(otherTicket)
            && otherData == Data("keep".utf8), "service deletion leaves unrelated memo, ticket and file intact")
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
        // The opposite lock order: the old writer is already committing when
        // actual service deletion arrives. Release it outside the service actor.
        service.webProjectDescriptorCache[record.id] = otherMemo
        try Data("runtime-again".utf8).write(to: serviceRuntime)
        let serviceCommitted = owner.begin(key: analysisURL.path)
        let serviceCommitGate = Gate(); cacheCommit.gate = serviceCommitGate
        let serviceWriter = Task.detached {
            owner.publish(Data("committing-service".utf8), to: analysisURL, ticket: serviceCommitted)
        }
        await serviceCommitGate.wait()
        let releaseServiceCommit = Task.detached { serviceCommitGate.release.signal() }
        service.removeWebRuntimeCaches(for: record.id)
        _ = await releaseServiceCommit.value; let serviceWriterResult = await serviceWriter.value
        check(serviceWriterResult && service.webProjectDescriptorCache[record.id] == nil
            && !owner.isCurrent(serviceCommitted) && !fm.fileExists(atPath: analysisURL.path)
            && !fm.fileExists(atPath: serviceRuntime.path), "actual service delete follows in-commit writer and removes both files")
        cacheCommit.gate = nil
        let repeated = owner.begin(key: key)
        check(repeated.slot === committed.slot && owner.isCurrent(repeated) && !owner.isCurrent(committed),
            "live-key lookup reuses the same slot and advances its generation")
        weak var unrelatedSlot: SteamWorkshopWebRuntimeCachePublication.Slot?
        do {
            let unrelated = owner.begin(key: "unrelated-live")
            unrelatedSlot = unrelated.slot
            let next = owner.begin(key: key)
            check(owner.isCurrent(unrelated) && owner.isCurrent(next), "live hit preserves unrelated current ticket")
        }
        check(unrelatedSlot == nil, "live hit does not retain unrelated slot after its ticket is released")
        for i in 0..<500 { _ = owner.begin(key: "ephemeral-\(i)") }
        _ = owner.begin(key: "reap")
        let counts = owner.testRegistryCounts
        check(counts.stored <= counts.live + 1, "miss reaps dead historical keys, leaving at most its own weak entry")
        // No options means the actual result is empty without consulting a
        // second project/defaults source. Nonempty options still use current
        // definitions and overrides through the original record wrapper.
        let optionFolder = root.appendingPathComponent("option-author")
        try fm.createDirectory(at: optionFolder, withIntermediateDirectories: true)
        let optionProject = optionFolder.appendingPathComponent("project.json")
        let optionJSON = #"{"general":{"properties":{"mode":{"type":"slider","value":0},"pick":{"type":"combo","value":"a","options":[{"label":"Always","value":"a"},{"label":"Current","value":"b","condition":"mode == 1"}]}}}}"#
        try Data(optionJSON.utf8).write(to: optionProject)
        let optionRecord = SteamWorkshopDownloadRecord(id: "option-check", folderURL: optionFolder,
            projectFileURL: optionProject, entryURL: optionFolder.appendingPathComponent("index.html"))
        let pick = service.webPropertyDefinitions(for: optionRecord).first { $0.key == "pick" }!
        optionReads.reset()
        check(service.visibleWebPropertyOptions(for: speed, record: optionRecord).isEmpty && optionReads.urls.isEmpty,
            "empty option result does not read project definitions or presets")
        check(service.visibleWebPropertyOptions(for: pick, record: optionRecord).map(\.value) == [.string("a")],
            "nonempty options preserve current project defaults")
        service.overrides["mode"] = .number(1)
        check(service.visibleWebPropertyOptions(for: pick, record: optionRecord).map(\.value) == [.string("a"), .string("b")],
            "nonempty option conditions consume current overrides")
        service.overrides = [:]
        try Data(optionJSON.replacingOccurrences(of: "\"value\":0", with: "\"value\":1").utf8).write(to: optionProject)
        check(service.visibleWebPropertyOptions(for: pick, record: optionRecord).map(\.value) == [.string("a"), .string("b")],
            "nonempty option conditions re-read changed project defaults")
        let mode = service.webPropertyDefinitions(for: optionRecord).first { $0.key == "mode" }!
        let engine = WallpaperEngine.shared
        var updateObservations: [String: Any] = [:]
        service.activeRecord = true
        optionReads.reset(); let beforeFullOff = engine.payloads.count
        service.updateWebPropertyValue(.number(0), for: mode, record: optionRecord)
        updateObservations["fullOffProjectReads"] = optionReads.urls.count
        let fullOff = try JSONSerialization.jsonObject(with: Data(engine.payloads.last!.utf8)) as! [String: [String: Any]]
        check(engine.payloads.count == beforeFullOff + 1 && Set(fullOff.keys) == ["mode", "pick"]
            && fullOff["mode"]?["value"] as? Double == 0
            && (fullOff["pick"]?["options"] as? [[String: Any]])?.compactMap { $0["value"] as? String } == ["a"],
            "full property update publishes one complete payload with current conditional options")
        updateObservations["fullOffPayload"] = fullOff
        optionReads.reset(); let beforeFullOn = engine.payloads.count
        service.updateWebPropertyValue(.number(1), for: mode, record: optionRecord)
        updateObservations["fullOnProjectReads"] = optionReads.urls.count
        let fullOn = try JSONSerialization.jsonObject(with: Data(engine.payloads.last!.utf8)) as! [String: [String: Any]]
        check(engine.payloads.count == beforeFullOn + 1 && Set(fullOn.keys) == ["mode", "pick"]
            && fullOn["mode"]?["value"] as? Double == 1
            && (fullOn["pick"]?["options"] as? [[String: Any]])?.compactMap { $0["value"] as? String } == ["a", "b"],
            "full property update restores condition-dependent options without another publication")
        updateObservations["fullOnPayload"] = fullOn
        optionReads.reset(); let beforeDelta = engine.payloads.count
        service.updateWebPropertyValue(.string("b"), for: pick, record: optionRecord)
        updateObservations["deltaProjectReads"] = optionReads.urls.count
        let delta = try JSONSerialization.jsonObject(with: Data(engine.payloads.last!.utf8)) as! [String: [String: Any]]
        check(engine.payloads.count == beforeDelta + 1 && Set(delta.keys) == ["pick"]
            && service.overrides["pick"] == .string("b") && delta["pick"]?["value"] as? String == "b",
            "delta property update still reads the committed value and publishes once")
        updateObservations["deltaPayload"] = delta
        service.activeRecord = false
        optionReads.reset(); let beforeInactive = engine.payloads.count
        service.updateWebPropertyValue(.number(0), for: mode, record: optionRecord)
        updateObservations["inactiveProjectReads"] = optionReads.urls.count
        check(engine.payloads.count == beforeInactive && service.overrides["mode"] == .number(0),
            "inactive property update persists without preparing or publishing a live payload")
        _ = try webBindingFallbackChecks()
        print("web-property-update-observations:" + String(decoding: try JSONSerialization.data(withJSONObject: updateObservations,
            options: [.sortedKeys]), as: UTF8.self))
        print("web-runtime-cache-pass")
    }
}
'''

BINDING_CHECKS = r'''
@MainActor func webBindingFallbackChecks(expectedTypedReads: Int = 0) throws -> [[String: Any]] {
    let fm = FileManager.default
    let folder = URL(fileURLWithPath: fm.currentDirectoryPath).resolvingSymlinksInPath()
        .standardizedFileURL.appendingPathComponent("binding-author")
    let images = folder.appendingPathComponent("images"), slides = folder.appendingPathComponent("slides")
    try fm.createDirectory(at: images, withIntermediateDirectories: true)
    try fm.createDirectory(at: slides, withIntermediateDirectories: true)
    try Data("bundled".utf8).write(to: folder.appendingPathComponent("bundled.png"))
    try Data("alternate".utf8).write(to: images.appendingPathComponent("alternate.png"))
    let project = folder.appendingPathComponent("project.json")
    try Data(#"{"preset":{"renamedMedia":"images/alternate.png"}}"#.utf8).write(to: project)
    let external = folder.deletingLastPathComponent().appendingPathComponent("external.png")
    let sibling = folder.deletingLastPathComponent().appendingPathComponent("sibling.png")
    try Data("external".utf8).write(to: external); try Data("sibling".utf8).write(to: sibling)
    let service = SteamWorkshopService()
    var record = SteamWorkshopDownloadRecord(id: "binding-shell", folderURL: folder,
        projectFileURL: project, entryURL: folder.appendingPathComponent("index.html"))
    record.isDependencyBackedWeb = true
    let context = SteamWorkshopService.WebAuthorBindingContext(candidateRoots: [.init(source: .recordFolder, url: folder)],
        pathlikePresetValues: ["renamedMedia": .string("images/alternate.png")])
    var rows: [[String: Any]] = [], reads: [String: Int] = [:]
    func run(_ label: String, key: String, kind: SteamWorkshopWebPropertyKind?, raw: String,
             expectedKind: ResolvedWebResourceBindingKind?, url: URL?, bookmark: URL? = nil,
             prepared: SteamWorkshopService.WebAuthorBindingContext? = nil, usesBookmarks: Bool = true,
             expectedReads: Int) throws {
        let definition = kind.map { SteamWorkshopWebPropertyDefinition(key: key, title: key, kind: $0,
            runtimeType: $0.rawValue, order: 0, minimumValue: nil, maximumValue: nil, allowsFractionalValues: false,
            fractionalPrecision: nil, displayCondition: nil, directoryMode: $0 == .directory ? "fetchall" : nil,
            fileType: nil, defaultValue: .string(raw), options: []) }
        service.bookmarks = bookmark.map { [key: $0] } ?? [:]
        optionReads.reset()
        let binding = service.resolvedWebResourceBinding(forKey: key, definition: definition,
            rawValue: .string(raw), record: record, usesBookmarks: usesBookmarks, bindingContext: prepared)
        reads[label] = optionReads.urls.count
        check(optionReads.urls.count == expectedReads, "only fallback classification reads the shell project: " + label)
        check(binding?.kind == expectedKind && binding?.resolvedPath == url?.path, "binding semantics: " + label)
        if let binding {
            check(binding.key == key && binding.rawValue == raw
                && binding.origin == (definition == nil ? .presetFallback : .propertyDefinition), "complete binding identity: " + label)
            if bookmark != nil { check(binding.source == .bookmarkedOverride, "current bookmark remains authoritative") }
        }
        let definitions = definition.map { [$0] } ?? []
        let payload = service.effectiveWebPropertiesJSONString(for: record, definitions: definitions,
            valuesOverride: [key: .string(raw)], bindingContext: prepared)!
        let payloadObject = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as! [String: [String: Any]]
        check(payloadObject[key]?["value"] as? String == (url?.path ?? raw), "runtime value retains the binding result: " + label)
        let grants = service.resolvedWebResourceGrants(for: record, definitions: definitions,
            valuesOverride: [key: .string(raw)], effectiveRootURL: folder, bindingContext: prepared)
        if bookmark == external {
            check(grants.contains { $0.kind == .file && $0.url == external }
                && !grants.contains { $0.allowsCanonicalURL(sibling) }, "exact-file bookmark cannot authorize its sibling")
        }
        let encodedBinding = try JSONSerialization.jsonObject(with: JSONEncoder().encode(binding), options: [.fragmentsAllowed])
        let encodedGrants = try JSONSerialization.jsonObject(with: JSONEncoder().encode(grants))
        rows.append(["case": label, "binding": encodedBinding, "payload": payloadObject, "grants": encodedGrants])
    }
    try run("file", key: "selected", kind: .file, raw: "bundled.png", expectedKind: .file,
        url: folder.appendingPathComponent("bundled.png"), expectedReads: expectedTypedReads)
    try run("directory", key: "chosenFolder", kind: .directory, raw: "slides", expectedKind: .directory,
        url: slides, expectedReads: expectedTypedReads)
    try run("bookmark", key: "selected", kind: .file, raw: external.path, expectedKind: .file,
        url: external, bookmark: external, expectedReads: expectedTypedReads)
    try run("selection", key: "selected", kind: .file, raw: "bundled.png", expectedKind: .file,
        url: folder.appendingPathComponent("bundled.png"), usesBookmarks: false, expectedReads: expectedTypedReads)
    try run("text", key: "plain", kind: .text, raw: "hello", expectedKind: nil, url: nil, expectedReads: 1)
    try run("unknown", key: "plain", kind: .unknown, raw: "hello", expectedKind: nil, url: nil, expectedReads: 1)
    for kind in [SteamWorkshopWebPropertyKind.text, .unknown] {
        try run("pathlike-" + kind.rawValue, key: "renamedMedia", kind: kind, raw: "images/alternate.png",
            expectedKind: .pathlikePreset, url: images.appendingPathComponent("alternate.png"), expectedReads: 1)
    }
    try run("preset", key: "renamedMedia", kind: nil, raw: "images/alternate.png", expectedKind: .pathlikePreset,
        url: images.appendingPathComponent("alternate.png"), expectedReads: 1)
    try run("prepared-file", key: "selected", kind: .file, raw: "bundled.png", expectedKind: .file,
        url: folder.appendingPathComponent("bundled.png"), prepared: context, expectedReads: 0)
    try run("prepared-preset", key: "renamedMedia", kind: nil, raw: "images/alternate.png", expectedKind: .pathlikePreset,
        url: images.appendingPathComponent("alternate.png"), prepared: context, expectedReads: 0)
    print("web-binding-projection:" + String(decoding: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), as: UTF8.self))
    print("web-binding-reads:" + String(decoding: try JSONSerialization.data(withJSONObject: reads, options: [.sortedKeys]), as: UTF8.self))
    return rows
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
    var activeRecord = false
    func isActiveWebRecord(_ record: SteamWorkshopDownloadRecord) -> Bool { activeRecord }
''', 1)
    properties = (WEB / 'SteamWorkshopService+WebProperties.swift').read_text()
    controls = (WEB / 'SteamWorkshopService+WebPropertyControlSupport.swift').read_text()
    source += '\nextension SteamWorkshopService {\n' + '\n'.join(method(properties, signature) for signature in (
        '    func previewWebPropertyValue(', '    func updateWebPropertyValue(', '    func resetWebPropertyValues(',
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
    var payloads: [String] = []
    func updateCurrentWebWallpaperProperties(_ payload: String?, resourceGrants: [WebWallpaperResourceGrant], resourcesChanged: Bool) {
        currentWebResourceGrants = resourceGrants
        if let payload { payloads.append(payload) }
    }
}
'''
    source += r'''
nonisolated final class PublicationGate: @unchecked Sendable { var gate: Gate? }
nonisolated let cacheStaging = PublicationGate()
nonisolated let cacheCommit = PublicationGate()
'''
    source = source.replace('            try handle.write(contentsOf: data)', '            try handle.write(contentsOf: data)\n            cacheStaging.gate?.pause()', 1)
    source = source.replace('            return rename(staging.path, fileURL.path) == 0', '            cacheCommit.gate?.pause()\n            return rename(staging.path, fileURL.path) == 0', 1)
    source = source.replace('    private let registryLock = NSLock()', '    var testRegistryCounts: (stored: Int, live: Int) { registryLock.withLock { (slots.count, slots.values.filter { $0.value != nil }.count) } }\n    private let registryLock = NSLock()', 1)
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
    source += r'''
nonisolated final class OptionProjectReads: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URL] = []
    func record(_ url: URL?) { if let url { lock.withLock { values.append(url) } } }
    func reset() { lock.withLock { values.removeAll() } }
    var urls: [URL] { lock.withLock { values } }
}
nonisolated let optionReads = OptionProjectReads()
'''
    loader = "    nonisolated static func loadWebProjectRootStatic(projectFileURL: URL?) -> [String: Any]? {"
    if source.count(loader) != 1: raise AssertionError("One actual project URL loader required")
    source = source.replace(loader, loader + "\n        optionReads.record(projectFileURL)", 1)
    source += r'''
@MainActor enum ProjectionWork {
    static var bindings = 0
    static var fallbacks = 0
    static func reset() { bindings = 0; fallbacks = 0 }
}
'''
    binding = method(source, "    func resolvedWebResourceBinding(")
    source = source.replace(binding, binding.replace(
        ") -> ResolvedWebResourceBinding? {", ") -> ResolvedWebResourceBinding? {\n        ProjectionWork.bindings += 1", 1), 1)
    fallback = method(source, "    static func webRuntimePropertyPayloadJSON(")
    source = source.replace(fallback, fallback.replace(
        ") -> String? {", ") -> String? {\n        ProjectionWork.fallbacks += 1", 1), 1)
    return source + BINDING_CHECKS + CACHE_CHECKS


class WebRuntimeCacheTests(unittest.TestCase):
    def test_real_preparation_and_publication_fence(self):
        output = run_harness(self, harness_source(), 'web-runtime-cache-pass')
        observations = json.loads(next(line.removeprefix('web-property-update-observations:')
            for line in output.splitlines() if line.startswith('web-property-update-observations:')))
        for name, expected in {'fullOffProjectReads': 3, 'fullOnProjectReads': 3,
                               'deltaProjectReads': 5, 'inactiveProjectReads': 1}.items():
            with self.subTest(observation=name):
                self.assertEqual(observations[name], expected, output)


if __name__ == '__main__': unittest.main()
