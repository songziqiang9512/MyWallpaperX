"""Exercise execution-cache rejection order through the production async loader.

Decode, validation, resource BFS and the playback preparation consumer are real.
Only actor metadata and descriptor/payload recomputation leaves are controlled;
the real scanner has a test-local call counter. No App or user library is opened.
"""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method
from script.tests.test_web_compat_parity import source_block

ROOT = Path(__file__).resolve().parents[2]
WEB = ROOT / "MyWallpaperX/Modules/SteamWorkshop/Web/Core"


COLLABORATORS = r'''
import Foundation

struct SteamWorkshopDownloadRecord { let id: String }
enum PropertyKind { case file, directory, other }
struct PropertyDefinition { let key: String; let kind: PropertyKind }
struct PropertyValue { let stringValue: String? }
struct ResolvedWebProjectDescriptor {
    let resolvedEntryURL: URL
    let effectiveRootURL: URL
    let propertyDefinitions: [PropertyDefinition]
}
// Analysis data is irrelevant to execution loading; retain only the fields the
// unchanged analysis validator references so the entire validator compiles.
struct CachedResolvedWebProjectDescriptor: Codable, Equatable {
    let resolvedEntryPath: String
    let effectiveRootPath: String
}
final class ScanCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func record() { lock.lock(); value += 1; lock.unlock() }
    func reset() { lock.lock(); value = 0; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}
@MainActor final class SteamWorkshopService {
    let inputs: WebRuntimeCacheManifestInputs
    nonisolated let scanCounter = ScanCounter()
    var definitions: [PropertyDefinition] = []
    var overrides: [String: PropertyValue] = [:]
    var bookmarkedKeys = Set<String>()
    var descriptorReads = 0
    var saves = 0
    static func resolvedWebWallpaperLanguage() -> String { "en-us" }
    init(inputs: WebRuntimeCacheManifestInputs) { self.inputs = inputs }
    func webRuntimeCacheManifestInputs(for record: SteamWorkshopDownloadRecord) -> WebRuntimeCacheManifestInputs { inputs }
    func webPropertyDefinitions(for record: SteamWorkshopDownloadRecord) -> [PropertyDefinition] { definitions }
    func webPropertyOverrides(for record: SteamWorkshopDownloadRecord) -> [String: PropertyValue] { overrides }
    func hasWebPropertyBookmark(forKey key: String, record: SteamWorkshopDownloadRecord) -> Bool { bookmarkedKeys.contains(key) }
    func resolvedWebProjectDescriptorForLaunch(for record: SteamWorkshopDownloadRecord) async -> ResolvedWebProjectDescriptor? {
        descriptorReads += 1
        return .init(resolvedEntryURL: inputs.entryURL!, effectiveRootURL: inputs.rootURL!, propertyDefinitions: [])
    }
    func resolvedWebResourceGrants(for record: SteamWorkshopDownloadRecord,
        definitions: [PropertyDefinition], valuesOverride: [String: String]? = nil,
        effectiveRootURL: URL) -> [WebWallpaperResourceGrant] { [] }
    func effectiveWebPropertyValues(for record: SteamWorkshopDownloadRecord,
        descriptor: ResolvedWebProjectDescriptor) -> [String: String] { ["marker": "recomputed"] }
    func effectiveWebPropertiesJSONString(for record: SteamWorkshopDownloadRecord,
        definitions: [PropertyDefinition], valuesOverride: [String: String]) -> String? {
        #"{"marker":{"type":"text","value":"recomputed"}}"#
    }
    func saveWebRuntimeCache(descriptor: ResolvedWebProjectDescriptor,
        propertyPayloadJSON: String?, for record: SteamWorkshopDownloadRecord) async { saves += 1 }
}
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
'''


CHECKS = r'''
@main enum Harness {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: fm.currentDirectoryPath).resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent("renamed-project", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let entry = root.appendingPathComponent("entry with space.html")
        let script = root.appendingPathComponent("arbitrary-module.js")
        let css = root.appendingPathComponent("arbitrary-style.css")
        let data = root.appendingPathComponent("arbitrary-data.json")
        let files = [(entry, "<script src='arbitrary-module.js'></script><link href='arbitrary-style.css'>"),
                     (script, "import 'arbitrary-data.json'; const renamedValue = 1;"),
                     (css, "body { color: red; }"), (data, "{\"renamed\":1}")]
        for (url, text) in files { try Data(text.utf8).write(to: url) }
        let input = SteamWorkshopService.WebRuntimeCacheManifestInputs(recordID: "renamed-record", language: "en-us",
            projectModifiedAt: Date(timeIntervalSinceReferenceDate: 100), propertySourceRecordID: "renamed-source",
            propertySourceProjectModifiedAt: Date(timeIntervalSinceReferenceDate: 200),
            resolvedEntryModifiedAt: Date(timeIntervalSinceReferenceDate: 300), overridesSignature: Data([1, 2]),
            entryURL: entry, rootURL: root, currentEntryPath: entry.path, currentRootPath: root.path,
            analysisFileURL: root.appendingPathComponent("analysis.json"), runtimeFileURL: root.appendingPathComponent("runtime.json"),
            sessionStartDate: Date())
        let record = SteamWorkshopDownloadRecord(id: input.recordID)
        let service = SteamWorkshopService(inputs: input)
        let payload = #"{"renamedChoice":{"type":"text","value":"author Default"},"color":{"type":"color","value":"0.1 0.2 0.3"}}"#
        func signature() -> SteamWorkshopWebRuntimeResourceSignature {
            service.webRuntimeResourceSignature(entryURL: entry, rootURL: root)!
        }
        func persist(_ signature: SteamWorkshopWebRuntimeResourceSignature?) throws {
            let manifest = SteamWorkshopWebRuntimeCacheManifest(version: SteamWorkshopWebRuntimeCacheManifest.currentVersion,
                recordID: input.recordID, generatedAt: Date(), language: input.language,
                projectModifiedAt: input.projectModifiedAt, propertySourceRecordID: input.propertySourceRecordID,
                propertySourceProjectModifiedAt: input.propertySourceProjectModifiedAt,
                resolvedEntryModifiedAt: input.resolvedEntryModifiedAt, resourceSignature: signature,
                overridesSignature: input.overridesSignature,
                execution: .init(resolvedEntryPath: entry.path, effectiveRootPath: root.path, propertyPayloadJSON: payload))
            try JSONEncoder().encode(manifest).write(to: input.runtimeFileURL)
        }
        @MainActor func rejected(_ label: String, scans: Int) async {
            service.scanCounter.reset()
            let context = await service.loadCachedWebPlaybackContext(for: record)
            check(context == nil, "invalid execution accepted: " + label)
            check(service.scanCounter.count == scans,
                "unexpected scan count for " + label + ": \(service.scanCounter.count), expected \(scans)")
        }

        let originalSignature = signature()
        check(originalSignature.scannedFileCount == 4 && !originalSignature.truncated,
            "real scanner must reach the entry, JS, CSS and referenced JSON")
        try persist(originalSignature)
        let original = try Data(contentsOf: input.runtimeFileURL)
        service.scanCounter.reset()
        let hit = await service.loadCachedWebPlaybackContext(for: record)
        check(hit == ResolvedWebPlaybackContext(recordID: record.id, effectiveEntryURL: entry,
            effectiveRootURL: root, propertyPayloadJSON: payload, language: input.language),
            "valid cache payload/paths changed: \(String(describing: hit))")
        check(service.scanCounter.count == 1, "valid execution must still scan resources exactly once")

        let cheap: [(String, Any)] = [("version", -1), ("recordID", "other"), ("language", "zh-cn"),
            ("projectModifiedAt", 101.0), ("propertySourceRecordID", "other-source"),
            ("propertySourceProjectModifiedAt", 201.0), ("resolvedEntryModifiedAt", 301.0),
            ("overridesSignature", Data([9]).base64EncodedString())]
        for (key, value) in cheap {
            var json = try JSONSerialization.jsonObject(with: original) as! [String: Any]
            json[key] = value
            try JSONSerialization.data(withJSONObject: json).write(to: input.runtimeFileURL)
            await rejected("cheap field " + key, scans: 0)
        }
        for field in ["resolvedEntryPath", "effectiveRootPath"] {
            var json = try JSONSerialization.jsonObject(with: original) as! [String: Any]
            var execution = json["execution"] as! [String: Any]
            execution[field] = root.appendingPathComponent("different-" + field).path
            json["execution"] = execution
            try JSONSerialization.data(withJSONObject: json).write(to: input.runtimeFileURL)
            await rejected("execution path " + field, scans: 0)
        }
        for malformed in [Data("broken-json".utf8), Data(#"{"version":"eighteen"}"#.utf8)] {
            try malformed.write(to: input.runtimeFileURL)
            await rejected("malformed/typed decode", scans: 0)
        }
        var wrongPayload = try JSONSerialization.jsonObject(with: original) as! [String: Any]
        wrongPayload["execution"] = ["resolvedEntryPath": 12, "effectiveRootPath": root.path]
        try JSONSerialization.data(withJSONObject: wrongPayload).write(to: input.runtimeFileURL)
        await rejected("execution path has wrong type", scans: 0)
        try fm.removeItem(at: input.runtimeFileURL)
        await rejected("missing manifest", scans: 0)

        // Resource edits keep every cheap field equal, so only the unchanged
        // real BFS/signature comparison can reject each referenced resource.
        for (url, body) in files.dropFirst() {
            try persist(signature())
            try Data((body + "\nchanged resource contents with a different size").utf8).write(to: url)
            await rejected("resource " + url.pathExtension, scans: 1)
            try Data(body.utf8).write(to: url)
        }
        try persist(nil)
        await rejected("missing resource signature while resources exist", scans: 1)

        // Build a manifest matching the scanner's missing-file signature. The
        // final existence guard must still reject it after equality succeeds.
        try fm.removeItem(at: entry)
        try persist(signature())
        await rejected("entry missing after otherwise equal checks", scans: 1)
        try Data(files[0].1.utf8).write(to: entry)

        // Existing live-resolution bypass must remain ahead of disk loading.
        try persist(signature())
        service.definitions = [.init(key: "chosenFile", kind: .file)]
        service.bookmarkedKeys = ["chosenFile"]
        await rejected("live bookmark", scans: 0)
        service.bookmarkedKeys = []
        service.overrides = ["chosenFile": .init(stringValue: "/unresolved/raw/file.mp3")]
        await rejected("absolute resource override", scans: 0)
        service.definitions = []; service.overrides = [:]

        // Consume the same optional cache result through the actual preparation
        // method. Recompute leaves are controlled; no copied loader/fallback.
        service.scanCounter.reset()
        let preparedHit = await service.prepareWebPlaybackContext(for: record)
        check(preparedHit?.context.propertyPayloadJSON == payload && service.saves == 0,
            "valid hit unexpectedly recomputed or changed payload")
        check(service.scanCounter.count == 1, "preparation hit must retain its real resource scan")
        for missing in [false, true] {
            if missing { try fm.removeItem(at: input.runtimeFileURL) }
            else { try Data("corrupt cache".utf8).write(to: input.runtimeFileURL) }
            let readsBefore = service.descriptorReads
            let savesBefore = service.saves
            service.scanCounter.reset()
            let rebuilt = await service.prepareWebPlaybackContext(for: record)
            check(rebuilt?.context.propertyPayloadJSON == #"{"marker":{"type":"text","value":"recomputed"}}"#,
                "bad/missing manifest did not take the existing recomputation interface")
            check(rebuilt?.context.effectiveEntryURL == entry && rebuilt?.context.effectiveRootURL == root,
                "recomputed projection changed entry/root")
            check(service.descriptorReads == readsBefore + 1 && service.saves == savesBefore + 1,
                "bad manifest changed fallback ownership or introduced retries")
            check(service.scanCounter.count == 0, "bad manifest scanned before recomputation")
            if !missing { try persist(signature()) }
        }
        print("web-runtime-cache-pass")
    }
}
'''


def harness_source() -> str:
    cache = (WEB / "SteamWorkshopService+WebRuntimeCache.swift").read_text()
    validation = (WEB / "SteamWorkshopService+WebRuntimeCacheValidation.swift").read_text()
    project = (WEB / "SteamWorkshopService+WebProjectSupport.swift").read_text()
    models = (WEB / "SteamWorkshopWebResolvedRuntimeModels.swift").read_text()
    model_types = (WEB / "SteamWorkshopWebResolvedRuntimeModelTypes.swift").read_text()
    host_types = (ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host/WebWallpaperHostTypes.swift").read_text()
    declarations = [source_block(cache, name) for name in (
        "nonisolated struct SteamWorkshopWebAnalysisCacheManifest",
        "nonisolated struct SteamWorkshopWebRuntimeCacheManifest",
        "nonisolated struct SteamWorkshopWebRuntimeResourceSignature",
        "nonisolated struct CachedResolvedWebExecutionManifest")]
    declarations += [source_block(host_types, "struct WebWallpaperResourceGrant"),
                     source_block(model_types, "nonisolated struct ResolvedWebPlaybackContext"),
                     source_block(model_types, "struct ResolvedWebPlaybackPreparation")]
    scanner = method(cache, "nonisolated func webRuntimeResourceSignature(\n        entryURL:")
    # Add only a test-local observation at the real scanner leaf; loader and all
    # validation/FS algorithms compile directly from their production sources.
    scanner = scanner.replace("{", "{\n        scanCounter.record()", 1)
    methods = [source_block(cache, "nonisolated struct WebRuntimeCacheManifestInputs"),
               method(cache, "func loadCachedWebPlaybackContext("),
               method(cache, "nonisolated private static func liveResourceSignature("), scanner,
               method(models, "func prepareWebPlaybackContext(for")]
    methods += [source_block(project, "enum WebResourceReference")]
    # This production function contains unmatched braces inside raw regex text;
    # the shared brace counter is not a Swift lexer. Preserve its complete bytes
    # up to the following declaration instead of truncating the regex function.
    reference_start = project.index("    nonisolated static func extractLocalWebResourceReferences(")
    reference_end = project.index("    nonisolated static func resolveWebResourceURL(", reference_start)
    methods.append(project[reference_start:reference_end])
    methods += [method(project, name) for name in (
        "nonisolated func webRelativePath(",
        "nonisolated static func resolveWebResourceURL(", "nonisolated static func shouldScanWebDependencyFile(",
        "private nonisolated static func isWebPath(")]
    return (COLLABORATORS + "\n" + "\n".join(declarations) + "\nextension SteamWorkshopService {\n"
            + "\n".join(methods) + "\n}\n" + validation + "\n" + CHECKS)


class WebRuntimeCacheTests(unittest.TestCase):
    def test_execution_loader_rejects_cheap_misses_without_resource_scans(self):
        with tempfile.TemporaryDirectory(prefix="mwx-web-runtime-cache-") as temporary:
            task = Path(temporary)
            source = task / "Harness.swift"
            source.write_text(harness_source())
            compiled = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(source),
                "-module-cache-path", str(task / "modules"), "-o", str(task / "harness")],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            home, scratch = task / "home", task / "tmp"
            home.mkdir(); scratch.mkdir()
            environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home), TMPDIR=str(scratch) + "/")
            result = subprocess.run([str(task / "harness")], cwd=task, env=environment,
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("web-runtime-cache-pass", result.stdout)


if __name__ == "__main__":
    unittest.main()
