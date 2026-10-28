"""Real author parser, cheap warm cache, binding and cancellation behavior.

Production files are compiled verbatim; only library/card/defaults/bookmark/UI
collaborators are controlled. Instrumentation observes real IO/parse entry and
can pause those leaves; it never supplies a replacement parser or traversal.
"""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method
from script.tests.test_web_compat_parity import source_block
from script.tests.test_steam_library_transaction import SOURCES as LIBRARY_SOURCES

ROOT = Path(__file__).resolve().parents[2]
WEB = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Web/Core'
CORE = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core'

SUPPORT = r'''
import Foundation
import CoreFoundation
import CryptoKit
import UniformTypeIdentifiers
import Darwin
nonisolated enum SteamServiceClient { enum RequestError: Error { case helperError(code: String, message: String) } }

nonisolated enum RecordStatus { case ready, queued }
nonisolated enum ContentType { case web, scene, other }
nonisolated enum DependencyStatus: Equatable { case none, available(String), missing(String) }
nonisolated struct SteamWorkshopDownloadRecord: Sendable {
    let id: String
    var folderURL: URL
    var projectFileURL: URL?
    var entryURL: URL?
    var entryHTMLURL: URL? { entryURL }
    var sourceVideoURL: URL? = nil
    var exportedVideoURL: URL? = nil
    var hostRoot: URL?
    var dependencyHostFolderURL: URL?
    var explicitDependencyID: String? = nil
    var dependencyStatus: DependencyStatus = .none
    var contentType: ContentType = .web
    var status: RecordStatus = .ready
    var isPlayableOrLaunchable: Bool { entryURL != nil }
    var isDependencyBackedWeb: Bool = false
    var dependencyItemID: String? { if let explicitDependencyID { return explicitDependencyID }; if case let .available(id) = dependencyStatus { return id }; return nil }
    var webEntryURL: URL? { entryURL }
    var webHostRootURL: URL? { hostRoot ?? folderURL }
    var resolvedWebRootURL: URL? { hostRoot ?? folderURL }
    var webShellRootURL: URL { folderURL.resolvingSymlinksInPath().standardizedFileURL }
    var webDependencyHostEntryURL: URL? { isDependencyBackedWeb ? entryURL : nil }
}
nonisolated final class Trace: @unchecked Sendable {
    let lock = NSLock()
    var reads: [(String, Int, Bool)] = []
    var parses = 0
    var readGate: Gate?
    var parseGate: Gate?
    func record(_ url: URL, _ count: Int, _ certified: Bool) {
        let gate = lock.withLock { reads.append((url.lastPathComponent, count, certified)); return readGate }
        gate?.pause()
    }
    func parse() { let gate = lock.withLock { parses += 1; return parseGate }; gate?.pause() }
    func reset() { lock.withLock { reads = []; parses = 0; readGate = nil; parseGate = nil } }
    var rows: [(String, Int, Bool)] { lock.withLock { reads } }
    var parseCount: Int { lock.withLock { parses } }
}
nonisolated final class Gate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let lock = NSLock(); var used = false
    func pause() {
        guard lock.withLock({ if used { return false }; used = true; return true }) else { return }
        entered.signal()
        precondition(release.wait(timeout: .now() + 10) == .success)
    }
    func wait() async { await Task.detached { precondition(self.entered.wait(timeout: .now() + 10) == .success) }.value }
}
nonisolated let trace = Trace()
@MainActor final class SteamWorkshopService {
    var removingDownloadIDs = Set<String>()
    var webProjectDescriptorCache: [String: CachedWebProjectDescriptor] = [:]
    var latest: [String: SteamWorkshopDownloadRecord] = [:]
    var builds: [String] = []
    var legacy: [String: SteamWorkshopDownloadRecord] = [:]
    var overrides: [String: SteamWorkshopWebPropertyValue] = [:]
    var bookmarks: [String: URL] = [:]
    let defaults = UserDefaults(suiteName: "mwx-author-harness-" + UUID().uuidString)!
    let steamLibraryVersionLeaseRegistry = SteamWorkshopLibraryVersionLeaseRegistry()
    var steamDownloadLibraryRootURL = URL(fileURLWithPath: "/fixture/library")
    var webLibraryRootURL = URL(fileURLWithPath: "/fixture/web")
    var sceneLibraryRootURL = URL(fileURLWithPath: "/fixture/scene")
    func latestDownloadRecord(for id: String) -> SteamWorkshopDownloadRecord? { latest[id] }
    func buildInstalledRecord(at url: URL) -> SteamWorkshopDownloadRecord? { builds.append(url.path); return legacy[url.path] }
    func webPropertyOverrides(for record: SteamWorkshopDownloadRecord) -> [String: SteamWorkshopWebPropertyValue] { overrides }
    func resolvedBookmarkedWebPropertyURL(forKey key: String, record: SteamWorkshopDownloadRecord) -> URL? { bookmarks[key] }
    func hasWebPropertyBookmark(forKey key: String, record: SteamWorkshopDownloadRecord) -> Bool { bookmarks[key] != nil }
    nonisolated static func loadWorkshopProject(from url: URL?) -> SteamWorkshopProject? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SteamWorkshopProject.self, from: data)
    }
    nonisolated static func relativePath(for url: URL, under root: URL) -> String { String(url.path.dropFirst(root.path.count + 1)) }
}
func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message) }
'''

FILES = [
    'SteamWorkshopWebPropertyModels.swift', 'SteamWorkshopWebResolvedRuntimeModelTypes.swift',
    'SteamWorkshopService+WebProjectSupport.swift', 'SteamWorkshopService+WebPropertyDefinitions.swift',
    'SteamWorkshopService+WebPropertyNormalizationSupport.swift', 'SteamWorkshopService+WebPropertyParsing.swift',
    'SteamWorkshopService+WebPropertySupport.swift', 'SteamWorkshopService+WebPropertyRuntimePayload.swift',
    'SteamWorkshopService+WebDisplayConditionSupport.swift', 'SteamWorkshopService+WebDisplayConditionParsing.swift',
    'SteamWorkshopService+WebRuntimeCache.swift', 'SteamWorkshopService+WebRuntimeCacheMetadata.swift',
    'SteamWorkshopService+WebRuntimeCacheValidation.swift', 'SteamWorkshopService+WebComputationCache.swift',
    'SteamWorkshopService+WebAuthorInput.swift', 'SteamWorkshopService+WebAuthorPreparation.swift',
    'SteamWorkshopWebResolvedRuntimeDiagnostics.swift',
    'SteamWorkshopService+WebValidationContentSignals.swift', 'WebStaticFileSignalScanner.swift',
    'SteamWorkshopWebResolvedRuntimeModels.swift',
]

CHECKS = r'''
@main enum Harness {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: fm.currentDirectoryPath).resolvingSymlinksInPath()
        let own = root.appendingPathComponent("own"), host = root.appendingPathComponent("host")
        for folder in [own, host] { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        func write(_ value: String, _ name: String, _ folder: URL) throws { try Data(value.utf8).write(to: folder.appendingPathComponent(name)) }
        let json = #"{"file":"index.html","general":{"properties":{"speed":{"type":"slider","value":1,"text":"ui_speed"}},"localization":{"fr":{"ui_speed":"First"},"de":{"ui_speed":"Zweite"}}},"preset":{"speed":7}}"#
        try write(json, "project.json", own)
        try write("<script src='a.js'></script>", "index.html", own)
        try write("navigator.serviceWorker.register('worker'); fetch('https://CDN.Example.test./config.json');", "a.js", own)
        let record = SteamWorkshopDownloadRecord(id: "r", folderURL: own, projectFileURL: own.appendingPathComponent("project.json"), entryURL: own.appendingPathComponent("index.html"))
        let service = SteamWorkshopService(); service.steamDownloadLibraryRootURL = root.appendingPathComponent("library")
        let source = service.webPropertyDefinitionSource(for: record)
        let inputs = service.webRuntimeCacheManifestInputs(for: record, source: source)
        trace.reset()
        let captured = service.captureWebAuthorInput(record: record, source: source, inputs: inputs)!
        check(trace.rows.count == 3 && trace.rows.filter { $0.0 == "project.json" }.count == 1, "cold capture reads own/source project once plus each actual dependency once")
        try write(json.replacingOccurrences(of: "\"speed\":7", with: "\"speed\":8"), "project.json", own)
        let old = service.parseWebProjectDescriptorCore(record: record, captured: captured)!
        check(old.presetOverrides["speed"] == .number(7), "parser consumes captured bytes instead of reopening mutable files")
        check(old.staticContentSummary.usesServiceWorkerRegistration, "real origin-risk summary signal survives captured interpretation")
        trace.reset()
        let cold = await service.prepareWebPlaybackContext(for: record)!
        check(cold.descriptor.defaultValueMap["speed"] == .number(8) && trace.parseCount == 1 && trace.rows.count == 3, "real cold interpretation")
        check(cold.context.allowedNetworkHosts == ["cdn.example.test"], "launch carries normalized hosts from the same prepared author summary")
        trace.reset()
        _ = await service.prepareWebPlaybackContext(for: record)
        let ui = service.resolvedWebProjectDescriptor(for: record)!
        check(trace.rows.isEmpty && trace.parseCount == 0 && ui == cold.descriptor, "warm playback and UI share author memo without reading or scanning bytes")

        // A stale library projection still has a readable selected HTML entry.
        // A changed author declaration is not a second playback permission gate.
        try write("<html>other</html>", "other.html", own)
        try write(#"{"file":"other.html"}"#, "project.json", own)
        let retainedEntry = await service.prepareWebPlaybackContext(for: record)!
        check(retainedEntry.context.effectiveEntryURL == record.entryURL, "selected entry remains playable without recursive rediscovery")
        try write(json, "project.json", own)

        // Direct dependencies are revised by stat, including same-size/mtime
        // replacement. Missing and retargeted references invalidate too.
        _ = await service.prepareWebPlaybackContext(for: record)
        let dependency = own.appendingPathComponent("a.js")
        let oldDate = try fm.attributesOfItem(atPath: dependency.path)[.modificationDate] as! Date
        try write("WebAssembly.instantiateStreaming(fetch('addon.wasm'));", "a.js", own)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: dependency.path)
        trace.reset()
        let changed = await service.prepareWebPlaybackContext(for: record)!
        check(changed.descriptor.staticContentSummary.usesWASMStreaming && !changed.descriptor.staticContentSummary.usesServiceWorkerRegistration && trace.parseCount == 1, "dependency mutation cannot reuse old origin-risk facts")
        check(changed.context.allowedNetworkHosts.isEmpty, "new preparation cannot retain prior author network hosts")
        try write("<script src='late.js'></script>", "index.html", own)
        let missing = await service.prepareWebPlaybackContext(for: record)!
        check(missing.descriptor.staticContentSummary.hasUncertainUserPropertyUsage, "optional missing script remains playable")
        try write("WebAssembly.instantiateStreaming(fetch('addon.wasm'));", "late.js", own)
        let added = await service.prepareWebPlaybackContext(for: record)!
        check(added.descriptor.staticContentSummary.usesWASMStreaming, "newly available dependency invalidates missing observation")
        try write("navigator.serviceWorker.register('worker');", "target.js", own)
        let link = own.appendingPathComponent("linked.js")
        try fm.createSymbolicLink(at: link, withDestinationURL: own.appendingPathComponent("late.js"))
        try write("<script src='linked.js'></script>", "index.html", own)
        let firstLink = await service.prepareWebPlaybackContext(for: record)!
        check(!firstLink.descriptor.staticContentSummary.usesServiceWorkerRegistration, "first symlink target")
        try fm.removeItem(at: link); try fm.createSymbolicLink(at: link, withDestinationURL: own.appendingPathComponent("target.js"))
        let secondLink = await service.prepareWebPlaybackContext(for: record)!
        check(secondLink.descriptor.staticContentSummary.usesServiceWorkerRegistration, "retargeted dependency resolver outcome invalidates old profile")
        try fm.createDirectory(at: own.appendingPathComponent("shaders"), withIntermediateDirectories: true)
        let changedDirectory = await service.prepareWebPlaybackContext(for: record)!
        check(changedDirectory.descriptor.sampleStructure == .shaderOrCanvasWeb, "top-level directory changes refresh structure")

        // Dependency-host definitions and shell presets remain distinct.
        try write(#"{"file":"index.html","general":{"properties":{"hostValue":{"type":"textinput","value":"host"}}}}"#, "project.json", host)
        try write("<html>host</html>", "index.html", host)
        var shell = record; shell.isDependencyBackedWeb = true; shell.dependencyStatus = .available("host-id")
        shell.dependencyHostFolderURL = host; shell.entryURL = host.appendingPathComponent("index.html"); shell.hostRoot = host
        let pinned = await service.prepareWebPlaybackContext(for: shell)!
        check(pinned.descriptor.propertyDefinitions.map(\.key) == ["hostValue"] && pinned.descriptor.presetOverrideMap["speed"] == .number(7), "host definitions plus shell preset")
        service.latest["host-id"] = record
        check(service.webPropertyDefinitionSource(for: shell)?.folderURL == host && service.builds.isEmpty, "pinned source does not rescan installed libraries")
        service.removingDownloadIDs = ["host-id"]
        check(service.admitWebAuthorPreparation(for: shell) == nil, "deleting host cannot admit a new reader")
        service.removingDownloadIDs = []

        // Language identity participates in both the parsed input and cache key.
        var fr = inputs; fr = .init(recordID: inputs.recordID, language: inputs.language, authorLanguageKeys: ["zz", "fr", "en"],
            propertySource: inputs.propertySource, ownFolderURL: inputs.ownFolderURL, ownProjectURL: inputs.ownProjectURL,
            dependencyEntryURL: inputs.dependencyEntryURL, dependencyFolderURL: inputs.dependencyFolderURL, candidateRoots: inputs.candidateRoots,
            dependencyRole: inputs.dependencyRole, dependencyItemID: inputs.dependencyItemID, entryURL: inputs.entryURL, rootURL: inputs.rootURL,
            analysisFileURL: inputs.analysisFileURL, authorSourceAvailable: inputs.authorSourceAvailable)
        let frInput = service.captureWebAuthorInput(record: record, source: source, inputs: fr)!
        check(service.parseWebProjectDescriptorCore(record: record, captured: frInput)!.propertyDefinitions[0].title == "First", "actual ordered language parser")
        check(fr.cacheIdentity != inputs.cacheIdentity, "secondary language changes cache identity")

        // Current overrides and exact-file bookmark authority are projected only
        // after the final await. They never come from the analysis cache.
        let authFolder = root.appendingPathComponent("authority"); try fm.createDirectory(at: authFolder, withIntermediateDirectories: true)
        try write(#"{"file":"index.html","general":{"properties":{"selected":{"type":"file","value":"bundled.png"},"speed":{"type":"slider","value":1}}}}"#, "project.json", authFolder)
        try write("<html></html>", "index.html", authFolder); try write("bundled", "bundled.png", authFolder)
        let external = root.appendingPathComponent("external.png"), peer = root.appendingPathComponent("peer.png")
        try Data("external".utf8).write(to: external); try Data("peer".utf8).write(to: peer)
        let authRecord = SteamWorkshopDownloadRecord(id: "authority", folderURL: authFolder, projectFileURL: authFolder.appendingPathComponent("project.json"), entryURL: authFolder.appendingPathComponent("index.html"))
        trace.reset(); let pause = Gate(); trace.parseGate = pause
        let preparing = Task { await service.prepareWebPlaybackContext(for: authRecord) }
        await pause.wait(); service.bookmarks["selected"] = external; service.overrides["speed"] = .number(9); pause.release.signal()
        let authority = await preparing.value
        check(authority!.context.resourceGrants.contains { $0.url == external && $0.kind == .file }, "latest bookmark grants exact file")
        check(!authority!.context.resourceGrants.contains { $0.allowsCanonicalURL(peer) }, "bookmark never grants sibling")
        let payload = try JSONSerialization.jsonObject(with: Data(authority!.context.propertyPayloadJSON!.utf8)) as! [String: [String: Any]]
        check(payload["selected"]?["value"] as? String == external.path && payload["speed"]?["value"] as? Double == 9, "latest payload agrees with grants and override")
        service.bookmarks = [:]; service.overrides = [:]; trace.reset()
        let revoked = await service.prepareWebPlaybackContext(for: authRecord)!
        check(!revoked.context.resourceGrants.contains { $0.url == external } && trace.rows.isEmpty, "warm author hit respects bookmark revocation without rescanning")

        // Changes during an optional read cannot turn playback into refusal.
        trace.reset(); let mutationGate = Gate(); trace.readGate = mutationGate
        let mutating = Task.detached {
            let reader = WebAuthorFileReader()
            let captured = service.captureWebAuthorInput(record: record, source: source, inputs: inputs, reader: reader)
            return (captured, reader.unstable)
        }
        await mutationGate.wait(); try write(json.replacingOccurrences(of: "\"speed\":7", with: "\"speed\":8"), "project.json", own); mutationGate.release.signal()
        let mutation = await mutating.value
        check(mutation.0 != nil && mutation.1, "changing source remains playable and invalidates derived reuse only")

        // A FIFO dependency must be rejected before a blocking read.
        trace.reset(); try write("<script src='pipe.js'></script>", "index.html", own)
        check(mkfifo(own.appendingPathComponent("pipe.js").path, 0o600) == 0, "FIFO fixture")
        let fifo = service.captureWebAuthorInput(record: record, source: source, inputs: inputs)!
        check(fifo.summary.hasUncertainUserPropertyUsage, "FIFO never blocks preparation and stays optional")

        // The actual registry retains the sole version token through a canceled
        // worker's join and transfers it until the playback consumer releases.
        let managed = service.steamDownloadLibraryRootURL.appendingPathComponent(SteamWorkshopLibraryTransaction.versionsName)
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("content")
        try fm.createDirectory(at: managed, withIntermediateDirectories: true)
        try write(#"{"file":"index.html"}"#, "project.json", managed); try write("<html>managed</html>", "index.html", managed)
        let managedRecord = SteamWorkshopDownloadRecord(id: "managed", folderURL: managed, projectFileURL: managed.appendingPathComponent("project.json"), entryURL: managed.appendingPathComponent("index.html"))
        let storage = SteamWorkshopLibraryTransaction.storageIdentity(containing: managed, libraryRoot: service.steamDownloadLibraryRootURL)!
        trace.reset(); let slow = Gate(); trace.readGate = slow
        let canceled = Task { await service.prepareWebPlaybackContext(for: managedRecord) }
        await slow.wait(); canceled.cancel()
        check(service.steamLibraryVersionLeaseRegistry.protectedStorageIdentities().contains(storage), "canceled actual reader keeps lifetime until join")
        slow.release.signal(); let canceledResult = await canceled.value
        check(canceledResult == nil && service.steamLibraryVersionLeaseRegistry.protectedStorageIdentities().isEmpty, "joined cancellation releases single token and publishes nothing")
        trace.reset()
        var result = await service.prepareWebPlaybackContext(for: managedRecord)
        check(result != nil && !service.steamLibraryVersionLeaseRegistry.beginReclamation(storage), "successful consumer holds resource version")
        result = nil
        check(service.steamLibraryVersionLeaseRegistry.beginReclamation(storage), "consumer release permits reclamation")
        check(service.admitWebAuthorPreparation(for: managedRecord) == nil, "retired version cannot acquire new token")

        // The typed payload owner serializes only dictionaries, arrays and
        // scalar leaves. Exercise the actual encoder and its original fallback.
        func object(_ json: String?) throws -> NSDictionary {
            try JSONSerialization.jsonObject(with: Data(json!.utf8)) as! NSDictionary
        }
        let typedRoot = try JSONSerialization.jsonObject(with: Data(#"{"general":{"properties":{"amount":{"type":"slider","value":0.75,"min":0,"max":2,"fraction":true,"precision":3},"choice":{"type":"combo","value":"b","options":[{"label":"Alpha","value":"a"},{"label":"Beta","value":"b"}]},"enabled":{"type":"bool","value":true}}}}"#.utf8)) as! [String: Any]
        let typed = SteamWorkshopService.webPropertyDefinitions(projectRoot: typedRoot)
        let amount = typed.first { $0.key == "amount" }!
        let values = Dictionary(uniqueKeysWithValues: typed.map { ($0.key, $0.defaultValue) })
        let noBindings = SteamWorkshopService.WebAuthorBindingContext(candidateRoots: [], pathlikePresetValues: [:])
        let fullJSON = service.effectiveWebPropertiesJSONString(for: record, definitions: typed,
            valuesOverride: values, bindingContext: noBindings)
        let expected = #"{"amount":{"type":"slider","value":0.75,"min":0,"max":2,"fraction":true,"precision":3},"choice":{"type":"combo","value":"b","text":"Beta","options":[{"label":"Alpha","value":"a"},{"label":"Beta","value":"b"}]},"enabled":{"type":"bool","value":true}}"#
        let fullObject = try object(fullJSON)
        let expectedObject = try object(expected)
        check(fullObject == expectedObject, "complete typed payload preserves min/max/options and all values")
        let singleJSON = service.resolvedWebRuntimePropertyPayloadJSON(for: amount,
            runtimeValue: .number(0.75), binding: nil, visibleOptions: [])
        let singleObject = try object(singleJSON)
        check(singleObject == ["amount": expectedObject["amount"]!] as NSDictionary, "single-property payload keeps complete metadata")
        let fallbackJSON = SteamWorkshopService.webRuntimePropertyPayloadJSON(definitions: [], values: values)
        let fallbackObject = try object(fallbackJSON)
        let expectedFallback = try object(#"{"amount":{"type":"text","value":0.75,"options":[]},"choice":{"type":"text","value":"b","options":[]},"enabled":{"type":"text","value":true,"options":[]}}"#)
        check(fallbackObject == expectedFallback, "minimal fallback preserves the full typed value bag")
        for invalid in [Double.nan, Double.infinity, -Double.infinity] {
            check(service.resolvedWebRuntimePropertyPayloadJSON(for: amount, runtimeValue: .number(invalid),
                binding: nil, visibleOptions: []) == nil, "single-property nonfinite value still fails serialization")
            check(SteamWorkshopService.webRuntimePropertyPayloadJSON(definitions: [], values: ["amount": .number(invalid)]) == nil,
                "minimal fallback does not repair nonfinite values")
            check(service.effectiveWebPropertiesJSONString(for: record, definitions: [amount],
                valuesOverride: ["amount": .number(invalid)], bindingContext: noBindings) == nil,
                "full bag and fallback both reject nonfinite values")
            for field in ["min", "max", "options"] {
                var raw: [String: Any] = ["type": "slider", "value": 0.75]
                if field == "options" { raw[field] = [["label": "invalid", "value": invalid]] }
                else { raw[field] = invalid }
                let bad = SteamWorkshopService.webPropertyDefinitions(projectRoot: ["general": ["properties": ["amount": raw]]])[0]
                check(service.resolvedWebRuntimePropertyPayloadJSON(for: bad, runtimeValue: bad.defaultValue,
                    binding: nil, visibleOptions: bad.options) == nil, "single invalid metadata still fails serialization")
                check(SteamWorkshopService.webRuntimePropertyPayloadJSON(definitions: [bad], values: ["amount": bad.defaultValue],
                    visibleOptionsByKey: ["amount": bad.options]) == nil, "fallback encoder still rejects invalid typed metadata")
                let repaired = service.effectiveWebPropertiesJSONString(for: record, definitions: [bad],
                    valuesOverride: ["amount": .number(0.75)], bindingContext: noBindings)
                let repairedObject = try object(repaired)
                let expectedMinimal = try object(#"{"amount":{"type":"text","value":0.75,"options":[]}}"#)
                check(repairedObject == expectedMinimal, "invalid optional metadata retains the original minimal-value fallback")
            }
        }
        let projection = try JSONSerialization.data(withJSONObject: ["full": fullObject, "single": singleObject,
            "fallback": fallbackObject, "nonfiniteCases": 3, "metadataCases": 9], options: [.sortedKeys])
        print("web-json-payload-projection:" + String(decoding: projection, as: UTF8.self))
        print("web-author-preparation-pass")
    }
}
'''


def harness_source() -> str:
    api = (CORE / 'SteamWorkshopAPIModels.swift').read_text()
    props = (WEB / 'SteamWorkshopService+WebProperties.swift').read_text()
    risk = (WEB / 'SteamWorkshopWebResolvedRuntimeRiskFlags.swift').read_text()
    validation = (WEB / 'SteamWorkshopWebValidationModels.swift').read_text()
    grant = (ROOT / 'MyWallpaperX/Core/SteamWorkshopWeb/Host/WebWallpaperHostTypes.swift').read_text()
    bridge = (ROOT / 'MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift').read_text()
    pieces = [SUPPORT, (ROOT / 'MyWallpaperX/Shared/WorkshopPropertyDisplayResolver.swift').read_text(),
        'enum DedicatedWebWallpaperHostPlaceholderAdapter {\n' + source_block(bridge, 'static func normalizedNetworkBridgeHost(') + '\n}']
    query = (CORE / 'SteamWorkshopQueryClient.swift').read_text()
    pieces += [source_block(query, 'nonisolated struct ' + name + ':') for name in ('SteamWorkshopStagingLeaseIdentity', 'SteamWorkshopStagedReceipt')]
    pieces += [source_block(api, 'nonisolated struct ' + name + ':') for name in ('SteamWorkshopProjectGeneral', 'SteamWorkshopProject')]
    pieces += [source_block(validation, 'nonisolated enum SteamWorkshopWebSampleStructure'), source_block(grant, 'nonisolated struct WebWallpaperResourceGrant')]
    reclamation = (CORE / 'SteamWorkshopService+LibraryReclamation.swift').read_text()
    front = (WEB / 'SteamWorkshopService+WebValidation.swift').read_text()
    access = (CORE / 'SteamWorkshopService+DownloadAccessors.swift').read_text()
    pieces += ['extension SteamWorkshopService {\n' + method(front, 'func webLaunchEntryIsValid(') + '\n' + method(access, 'func canLaunchDownloadRecord(') + '\n' + method(access, 'func cachedCanLaunchDownloadRecord(') + '\n}']
    pieces += ['extension SteamWorkshopService {\n' + method(reclamation, 'func libraryVersionLifetime(recordID:') + '\n' + method(reclamation, 'func libraryVersionLifetime(for record:') + '\n' + '\n'.join(method(props, name) for name in ('nonisolated func visibleWebPropertyOptions(', 'nonisolated func shouldDisplayWebProperty(')) + '\n' + '\n'.join(method(risk, name) for name in ('nonisolated static func resolvedWebStructuralRiskFlags(', 'nonisolated static func webHasKnownSafariIncompatibility(', 'nonisolated func resolvedWebStaticContentRiskFlags(')) + '\n}']
    for name in FILES:
        text = (WEB / name).read_text()
        if name == 'SteamWorkshopService+WebAuthorInput.swift':
            text = text.replace('        if !revision.isCurrent { unstable = true }', '        trace.record(url, data.count, false)\n        if !revision.isCurrent { unstable = true }', 2)
        if name == 'SteamWorkshopWebResolvedRuntimeModels.swift':
            text = text.replace('        let sourceRoot = Self.loadWebProjectRootStatic(data:', '        trace.parse()\n        let sourceRoot = Self.loadWebProjectRootStatic(data:', 1)
        pieces.append(text)
    return '\n'.join(pieces) + CHECKS


def run_harness(test: unittest.TestCase, source_text: str, sentinel: str, *, with_library: bool = True) -> str:
    with tempfile.TemporaryDirectory(prefix='mwx-web-author-') as directory:
        task = Path(directory)
        source = task / 'Harness.swift'; source.write_text(source_text)
        library = [p for p in LIBRARY_SOURCES if with_library and p.name in {
            'ScenePlaybackSource.swift', 'SteamWorkshopStorageTree.swift',
            'ScenePkgReader.swift',
            'DaemonNewlineJSON.swift', 'PlaybackResourceLifetime.swift', 'SteamServiceProtocol.swift',
            'SteamWorkshopLibraryTransaction.swift',
            'SteamWorkshopLibraryTransaction+FailedVisibility.swift',
            'SteamWorkshopLibraryPublication.swift', 'SteamWorkshopLibraryVersionLease.swift'}]
        command = ['xcrun', 'swiftc', '-swift-version', '6', '-strict-concurrency=complete', '-D', 'DEBUG', '-parse-as-library',
            *map(str, library), str(source), '-module-cache-path', str(task / 'modules'), '-o', str(task / 'harness')]
        result = subprocess.run(command, capture_output=True, text=True, timeout=120)
        test.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        home = task / 'home'; home.mkdir()
        result = subprocess.run([str(task / 'harness')], cwd=task,
            env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)), capture_output=True, text=True, timeout=45)
        test.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        test.assertIn(sentinel, result.stdout)
        return result.stdout


class WebAuthorPreparationTests(unittest.TestCase):
    def test_real_author_pipeline(self):
        run_harness(self, harness_source(), 'web-author-preparation-pass')

if __name__ == '__main__': unittest.main()
