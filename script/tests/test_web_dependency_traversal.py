"""Exercise the three production dependency traversals with real filesystem graphs.

The execution-cache harness supplies its production extractor, loader and original
assertions. Summary/report traversal, reference parsing, containment, bounded text
reads and signal detection also compile from production. Only unrelated record/UI
metadata is controlled. Observations are added at real read/signature leaves; the
signature's Date() leaves use a fixture clock so budget edges do not depend on CPU
speed. No alternate traversal algorithm or product test hook is introduced.
"""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method
from script.tests.test_web_compat_parity import source_block
from script.tests.test_web_runtime_cache import harness_source as cache_harness_source


ROOT = Path(__file__).resolve().parents[2]
WEB = ROOT / "MyWallpaperX/Modules/SteamWorkshop/Web/Core"


SUPPORT = r'''
final class TraversalTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URL] = []
    func record(_ url: URL) { lock.lock(); values.append(url); lock.unlock() }
    func reset() { lock.lock(); values.removeAll(); lock.unlock() }
    var paths: [String] {
        lock.lock(); defer { lock.unlock() }
        return values.map(\.lastPathComponent)
    }
}
enum TraversalAudit {
    static let reads = TraversalTrace()
    static let signatures = TraversalTrace()
}
final class TraversalClock: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [TimeInterval] = [0]
    private var index = 0
    private static let shared = TraversalClock()
    static func reset(_ values: [TimeInterval] = [0]) {
        shared.lock.lock(); defer { shared.lock.unlock() }
        shared.values = values; shared.index = 0
    }
    static func now() -> Date {
        shared.lock.lock(); defer { shared.lock.unlock() }
        let value = shared.values[min(shared.index, shared.values.count - 1)]
        shared.index += 1
        return Date(timeIntervalSince1970: value)
    }
    static var calls: Int {
        shared.lock.lock(); defer { shared.lock.unlock() }
        return shared.index
    }
}
enum ContentType { case web }
typealias SteamWorkshopWebPropertyDefinition = PropertyDefinition
extension PropertyDefinition { var directoryMode: String? { nil } }
extension ResolvedWebProjectDescriptor {
    var sampleStructure: SteamWorkshopWebSampleStructure { .basicHTMLWeb }
    var propertySource: SteamWorkshopWebPropertySource { .ownProject }
    var presetOverrideMap: [String: String] { [:] }
    var resolvedEntryRelativePath: String { resolvedEntryURL.lastPathComponent }
    // Report checks deliberately exercise the descriptor-absent scan path.
    var staticContentSummary: ResolvedWebStaticContentSummary { fatalError("unused descriptor") }
}
struct CachedWebValidationReport {
    let signature: String
    let report: SteamWorkshopWebValidationReport
}
struct ResolvedWebRuntimePrecondition {}
extension SteamWorkshopService {
    func webValidationSignature(for record: SteamWorkshopDownloadRecord) -> String { record.id }
    func resolvedWebProjectDescriptor(for record: SteamWorkshopDownloadRecord) -> ResolvedWebProjectDescriptor? { nil }
    func webSampleStructure(for record: SteamWorkshopDownloadRecord) -> SteamWorkshopWebSampleStructure { .basicHTMLWeb }
    func webPropertyDefinitionSourceRecord(for record: SteamWorkshopDownloadRecord) -> SteamWorkshopDownloadRecord? { record }
    func webPresetValues(for record: SteamWorkshopDownloadRecord) -> [String: String] { [:] }
    func declaredWebEntryRelativePath(for record: SteamWorkshopDownloadRecord) -> String? { nil }
    nonisolated func effectiveWebRootURL(for record: SteamWorkshopDownloadRecord, entryURL: URL) -> URL { record.folderURL }
    func effectiveWebPropertyValues(for record: SteamWorkshopDownloadRecord,
        definitions: [PropertyDefinition]) -> [String: String] { [:] }
    func resolvedWebRuntimePreconditions(for record: SteamWorkshopDownloadRecord,
        definitions: [PropertyDefinition], effectiveValues: [String: String]) -> [ResolvedWebRuntimePrecondition] { [] }
    func resolvedWebStructuralRiskFlags(for record: SteamWorkshopDownloadRecord,
        sampleStructure: SteamWorkshopWebSampleStructure) -> [Int] { [] }
    func resolvedWebStaticContentRiskFlags(from summary: ResolvedWebStaticContentSummary) -> [Int] { [] }
    func appendWebPropertyPreconditionIssues(preconditions: [ResolvedWebRuntimePrecondition],
        sampleStructure: SteamWorkshopWebSampleStructure,
        appendIssue: (SteamWorkshopWebValidationSeverity, SteamWorkshopWebValidationLevel, String) -> Void) {}
    func appendHighLoadWebSampleIssue(riskFlags: [Int],
        appendIssue: (SteamWorkshopWebValidationSeverity, SteamWorkshopWebValidationLevel, String) -> Void) {}
    func appendScannedWebRuntimeRiskIssues(riskFlags: [Int],
        appendIssue: (SteamWorkshopWebValidationSeverity, SteamWorkshopWebValidationLevel, String) -> Void) {}
    func isDependencyShellPreconditionResourcePath(_ path: String) -> Bool { false }
    func webPlaybackFailureMessage(for record: SteamWorkshopDownloadRecord) -> String? { nil }
    func webPlaybackFailureIssue(for message: String) -> SteamWorkshopWebValidationIssue {
        .init(severity: .warning, level: .warning, message: message)
    }
}
'''


RECORD = r'''
struct SteamWorkshopDownloadRecord {
    let id: String
    var rootURL: URL? = nil
    var folderURL: URL { rootURL! }
    var webEntryURL: URL? { folderURL.appendingPathComponent("entry.html") }
    var contentType: ContentType { .web }
    var dependencyStatus: SteamWorkshopWebDependencyStatus { .none }
    var isDependencyBackedWeb: Bool { false }
    var hasPlayableDependencyWebHost: Bool { true }
    var dependencyItemID: String? { nil }
    var webOwnEntryURL: URL? { nil }
}
'''


CHECKS = r'''
@MainActor func traversalChecks(service: SteamWorkshopService, root: URL) throws {
    let fm = FileManager.default
    func project(_ name: String) throws -> (URL, SteamWorkshopDownloadRecord) {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, .init(id: name, rootURL: directory))
    }
    func write(_ text: String, _ name: String, _ directory: URL) throws {
        try Data(text.utf8).write(to: directory.appendingPathComponent(name))
    }
    func summary(_ record: SteamWorkshopDownloadRecord) -> ResolvedWebStaticContentSummary {
        TraversalAudit.reads.reset()
        return service.resolvedWebStaticContentSummary(for: record, entryURL: record.webEntryURL!,
            rootURL: record.folderURL, propertyDefinitions: [])
    }
    func report(_ record: SteamWorkshopDownloadRecord) -> SteamWorkshopWebValidationReport {
        service.webValidationReportCache.removeAll()
        TraversalAudit.reads.reset()
        return service.webValidationReport(for: record)!
    }
    func signature(_ record: SteamWorkshopDownloadRecord,
                   clock: [TimeInterval] = [0]) -> SteamWorkshopWebRuntimeResourceSignature {
        TraversalAudit.signatures.reset()
        TraversalClock.reset(clock)
        return service.webRuntimeResourceSignature(entryURL: record.webEntryURL!, rootURL: record.folderURL)!
    }

    // Initial breadth order differs from depth order; two forms of a root escape,
    // a missing reference, invalid UTF-8 and a directory named .js stay local.
    let (graph, graphRecord) = try project("renamed-graph")
    try write("""
        <script src='first.js'></script><script src='first.js'></script>
        <script src='second.js'></script><script src='bad.js'></script>
        <script src='folder.js'></script><script src='missing.js'></script>
        <script src='../outside.js'></script><script src='escaped.js'></script>
        """, "entry.html", graph)
    try write("import 'entry.html'; import 'leaf.json'; const a = 'https://alpha.example/info';", "first.js", graph)
    try write("import 'first.js'; const b = 'https://beta.example/info';", "second.js", graph)
    try write("localStorage; properties.fps;", "leaf.json", graph)
    try Data([0xff, 0xfe, 0xff]).write(to: graph.appendingPathComponent("bad.js"))
    try fm.createDirectory(at: graph.appendingPathComponent("folder.js"), withIntermediateDirectories: true)
    try write("navigator.serviceWorker.register('wrong.js');", "outside.js", root)
    try fm.createSymbolicLink(at: graph.appendingPathComponent("escaped.js"),
        withDestinationURL: root.appendingPathComponent("outside.js"))
    let graphOrder = ["entry.html", "first.js", "second.js", "bad.js", "folder.js", "leaf.json"]
    let graphSummary = summary(graphRecord)
    check(TraversalAudit.reads.paths == graphOrder, "summary changed BFS order, duplicate or cycle handling")
    check(graphSummary.usesPersistentBrowserStorage && graphSummary.usesGeneralFPS,
        "summary lost signals after repeated/cyclic dependencies")
    check(graphSummary.hasUncertainUserPropertyUsage && !graphSummary.usesServiceWorkerRegistration,
        "read/path failure did not remain local or escaped a root")
    check(graphSummary.externalDependencyHosts == ["alpha.example", "beta.example"], "external host summary changed")
    let graphReport = report(graphRecord)
    check(TraversalAudit.reads.paths == graphOrder && graphReport.scannedFileCount == graphOrder.count,
        "report changed read order or counted duplicate/missing/escaped resources")
    let traversalIssues = graphReport.issues.map(\.message).filter {
        $0.hasPrefix("本地资源缺失：") || $0.hasPrefix("发现越界或无法解析")
            || $0.hasPrefix("依赖外部资源：") || $0.hasPrefix("无法读取文件：")
    }
    check(traversalIssues == ["本地资源缺失：missing.js",
        "发现越界或无法解析的资源路径：../outside.js", "发现越界或无法解析的资源路径：escaped.js",
        "依赖外部资源：https://alpha.example/info", "依赖外部资源：https://beta.example/info",
        "无法读取文件：bad.js", "无法读取文件：folder.js"], "report changed diagnostic order or de-duplication")
    check(graphReport.issues.first { $0.message == "本地资源缺失：missing.js" }?.level == .runtimeBlocking,
        "missing script no longer reports its existing failure level")
    let warmReport = service.webValidationReport(for: graphRecord)
    check(warmReport == graphReport && TraversalAudit.reads.paths == graphOrder,
        "warm report unexpectedly traversed again or changed output")
    let graphSignature = signature(graphRecord)
    check(TraversalAudit.signatures.paths == graphOrder && graphSignature.scannedFileCount == graphOrder.count,
        "signature changed BFS order or failed to include unreadable existing resources")
    check(!graphSignature.truncated && graphSignature.entries.map(\.relativePath) == graphOrder.sorted(),
        "signature stopped sorting paths or changed failed-resource inclusion")
    try write("localStorage; properties.fps; const additionalBytes = 12345;", "leaf.json", graph)
    check(signature(graphRecord) != graphSignature, "deep dependency edit did not invalidate its signature")

    // Many duplicate edges at every depth must keep later siblings in FIFO
    // order, then release each completed layer without losing a late signal.
    let (deep, deepRecord) = try project("deep-repeated-graph")
    let depth = 40
    var deepOrder = ["entry.html"]
    for level in 0..<depth {
        let layer = String(format: "layer%03d.js", level)
        let side = String(format: "side%03d.json", level)
        let references = String(repeating: "import '\(layer)';", count: 128) + "import '\(side)';"
        if level == 0 { try write(references, "entry.html", deep) }
        else { try write("import 'entry.html';" + references, String(format: "layer%03d.js", level - 1), deep) }
        try write(level == depth - 1 ? "properties.fps; localStorage;" : "const side = 1;", side, deep)
        deepOrder += [layer, side]
    }
    try write("import 'entry.html';", String(format: "layer%03d.js", depth - 1), deep)
    let deepSummary = summary(deepRecord)
    check(TraversalAudit.reads.paths == deepOrder && deepSummary.usesGeneralFPS
        && deepSummary.usesPersistentBrowserStorage, "summary lost a deep repeated-edge sibling or signal")
    let deepReport = report(deepRecord)
    check(TraversalAudit.reads.paths == deepOrder && deepReport.scannedFileCount == deepOrder.count
        && deepReport.issues.contains { $0.message.contains("properties.fps") }, "report changed layer/FIFO ordering")
    let deepSignature = signature(deepRecord)
    check(TraversalAudit.signatures.paths == deepOrder && deepSignature.scannedFileCount == deepOrder.count
        && !deepSignature.truncated, "signature changed deep repeated-edge traversal")

    // Summary is intentionally uncapped; report has exactly 200 unique files.
    let (wide, wideRecord) = try project("wide-graph")
    let names = (0..<205).map { String(format: "node%03d.js", $0) }
    try write("<script src='node000.js'></script>" + names.map { "<script src='\($0)'></script>" }.joined(), "entry.html", wide)
    for (index, name) in names.enumerated() {
        var content = "import 'entry.html';"
        if index == 198 { content += "properties.fps;" }
        if index == 199 { content += "navigator.serviceWorker.register('worker');" }
        if index == 204 { content += "localStorage; const movie = 'tail.webm';" }
        try write(content, name, wide)
    }
    let wideSummary = summary(wideRecord)
    check(TraversalAudit.reads.paths == ["entry.html"] + names, "uncapped summary lost breadth order or late files")
    check(wideSummary.usesGeneralFPS && wideSummary.usesServiceWorkerRegistration
        && wideSummary.usesPersistentBrowserStorage && wideSummary.usesWebMResource,
        "uncapped summary omitted a boundary/late signal")
    let wideReport = report(wideRecord)
    check(wideReport.scannedFileCount == 200 && TraversalAudit.reads.paths == ["entry.html"] + Array(names.prefix(199)),
        "report changed its 200-file boundary")
    check(wideReport.issues.contains { $0.message.contains("properties.fps") }
        && !wideReport.issues.contains { $0.message.contains("Service Worker 注册") },
        "report included an excluded file signal or lost its last included signal")
    let wideSignature = signature(wideRecord)
    check(wideSignature.scannedFileCount == 120 && wideSignature.truncated,
        "signature changed its 120-file budget")
    check(TraversalAudit.signatures.paths == ["entry.html"] + Array(names.prefix(119)), "signature changed retained breadth prefix")

    // A pending duplicate still encounters the budget check before de-duplication.
    let (exact, exactRecord) = try project("exact-budget")
    let exactNames = Array(names.prefix(119))
    for name in exactNames { try write("const value = 1;", name, exact) }
    let exactReferences = exactNames.map { "<script src='\($0)'></script>" }.joined()
    try write(exactReferences, "entry.html", exact)
    let exactSignature = signature(exactRecord)
    check(exactSignature.scannedFileCount == 120 && !exactSignature.truncated,
        "exactly exhausted queue must not be marked truncated")
    try write(exactReferences + "<script src='node118.js'></script>", "entry.html", exact)
    let duplicateTail = signature(exactRecord)
    check(duplicateTail.scannedFileCount == 120 && duplicateTail.truncated,
        "capacity check moved after duplicate elimination")
    check(TraversalClock.calls == 121, "capacity no longer short-circuits before reading the clock")

    // Initial clock read creates the deadline. Equality rejects the next file;
    // a queued duplicate also checks the clock before it can be discarded.
    let (timed, timedRecord) = try project("timed-graph")
    try write("<script src='one.js'></script><script src='one.js'></script><script src='two.js'></script>", "entry.html", timed)
    try write("const one = 1;", "one.js", timed)
    try write("const two = 2;", "two.js", timed)
    let equalDeadline = signature(timedRecord, clock: [0, 0, 0.20])
    check(equalDeadline.truncated && TraversalAudit.signatures.paths == ["entry.html"] && TraversalClock.calls == 3,
        "deadline equality or pre-read budget check changed")
    let duplicateDeadline = signature(timedRecord, clock: [0, 0, 0, 0, 0.20])
    check(duplicateDeadline.truncated && TraversalAudit.signatures.paths == ["entry.html", "one.js"]
        && TraversalClock.calls == 5, "deadline check moved after queued duplicate elimination")
    let immediateDeadline = signature(timedRecord, clock: [0, 0.20])
    check(immediateDeadline.truncated && immediateDeadline.entries.isEmpty, "expired budget read the entry")

    // Bounded text reads retain prefix/suffix analysis and the service-worker
    // streaming fallback in a middle region omitted from those fragments.
    let (large, largeRecord) = try project("large-graph")
    var bytes = Data(repeating: 97, count: 300_000)
    let middle = Data("navigator.serviceWorker.register".utf8)
    bytes.replaceSubrange(150_000..<(150_000 + middle.count), with: middle)
    bytes.append(Data("; applyGeneralProperties; import 'late.json';".utf8))
    try bytes.write(to: largeRecord.webEntryURL!)
    try write("properties.fps;", "late.json", large)
    let largeSummary = summary(largeRecord)
    check(largeSummary.hasTruncatedStaticAnalysis && largeSummary.hasUncertainUserPropertyUsage
        && largeSummary.usesServiceWorkerRegistration && largeSummary.usesApplyGeneralProperties
        && largeSummary.usesGeneralFPS, "bounded summary lost fragment/fallback/dependency output")
    check(TraversalAudit.reads.paths == ["entry.html", "late.json"], "fragment dependency order changed")
    let largeReport = report(largeRecord)
    check(largeReport.scannedFileCount == 2 && largeReport.issues.contains { $0.message.contains("1 个文件仅扫描了首尾片段") }
        && largeReport.issues.contains { $0.message.contains("Service Worker 注册") }, "report lost truncation output/fallback")

    let (_, absentRecord) = try project("absent-entry")
    check(summary(absentRecord).hasUncertainUserPropertyUsage, "missing summary entry changed its failure radius")
    let absentReport = report(absentRecord)
    check(absentReport.scannedFileCount == 1 && absentReport.fatalIssue?.message == "入口文件不存在：entry.html"
        && absentReport.issues.contains { $0.message == "无法读取文件：entry.html" }, "missing report entry diagnostics changed")
    let absentSignature = signature(absentRecord)
    check(absentSignature.scannedFileCount == 1 && !absentSignature.truncated
        && absentSignature.entries.first?.modifiedAt == nil && absentSignature.entries.first?.size == nil,
        "missing signature entry no longer retains its nil metadata")
}
'''


def harness_source() -> str:
    source = cache_harness_source()
    source = source.replace("struct SteamWorkshopDownloadRecord { let id: String }", RECORD)
    source = source.replace("@MainActor final class SteamWorkshopService {",
                            "@MainActor final class SteamWorkshopService {\n"
                            "    var webValidationReportCache: [String: CachedWebValidationReport] = [:]")
    cache = (WEB / "SteamWorkshopService+WebRuntimeCache.swift").read_text()
    scanner = method(cache, "nonisolated func webRuntimeResourceSignature(\n        entryURL:")
    observed_scanner = scanner.replace("{", "{\n        scanCounter.record()", 1)
    timed_scanner = observed_scanner.replace("Date()", "TraversalClock.now()")
    timed_scanner = timed_scanner.replace("let resourceValues = try? normalizedURL.resourceValues(",
                                        "TraversalAudit.signatures.record(normalizedURL)\n"
                                        "            let resourceValues = try? normalizedURL.resourceValues(")
    if source.count(observed_scanner) != 1:
        raise AssertionError("execution-cache extractor no longer supplies the production signature leaf")
    source = source.replace(observed_scanner, timed_scanner)
    model = (WEB / "SteamWorkshopWebResolvedRuntimeModelTypes.swift").read_text()
    properties = (WEB / "SteamWorkshopWebPropertyModels.swift").read_text()
    declarations = source_block(model, "nonisolated struct ResolvedWebStaticContentSummary")
    declarations += "\n" + source_block(properties, "nonisolated enum SteamWorkshopWebPropertySource")
    signals = (WEB / "SteamWorkshopService+WebValidationContentSignals.swift").read_text()
    signal_names = ["webStaticAnalysisContent", "webFileContainsServiceWorkerRegistration",
                    "webContentUsesWebMResource", "webContentUsesHoverOnlyInteraction",
                    "webContentUsesApplyGeneralProperties", "webContentUsesGeneralFPS",
                    "webContentReferencesSchemeColorUserProperty", "webContentHasUncertainUserPropertyUsage",
                    "webContentUsesPluginBridge", "webContentUsesPersistentBrowserStorage",
                    "webContentUsesServiceWorkerRegistration", "webContentUsesESModuleDependency",
                    "webContentUsesDynamicImport", "webContentUsesWASMResource", "webContentUsesWASMStreaming",
                    "webContentUsesCustomSchemeSensitiveWebGL", "webContentUsesIframeCrossFrameAccess"]
    members = [next(line for line in signals.splitlines() if "nonisolated static let webStaticAnalysisMaximumFileBytes =" in line)]
    for name in signal_names:
        leaf = method(signals, "nonisolated static func " + name + "(")
        if name == "webStaticAnalysisContent":
            leaf = leaf.replace("{", "{\n        TraversalAudit.reads.record(fileURL)", 1)
        members.append(leaf)
    diagnostics = (WEB / "SteamWorkshopWebResolvedRuntimeDiagnostics.swift").read_text()
    validation = (WEB / "SteamWorkshopService+WebValidation.swift").read_text()
    support = (WEB / "SteamWorkshopService+WebValidationSupport.swift").read_text()
    members += [method(diagnostics, "nonisolated func resolvedWebStaticContentSummary("),
                method(validation, "func webValidationReport("),
                method(support, "func appendWebExternalDependencyIssues("),
                method(support, "func webValidationLevelForMissingResource("),
                method(support, "func webValidationMessageForMissingResource(")]
    source += "\n" + declarations + "\n" + (WEB / "SteamWorkshopWebValidationModels.swift").read_text()
    source += "\n" + SUPPORT + "\nextension SteamWorkshopService {\n" + "\n".join(members) + "\n}\n" + CHECKS
    source = source.replace('print("web-runtime-cache-pass")',
                            'try traversalChecks(service: service, root: root)\n'
                            '        print("web-dependency-traversal-pass")')
    return source


class WebDependencyTraversalTests(unittest.TestCase):
    def test_real_traversals_preserve_order_failures_budgets_and_cache_signatures(self):
        with tempfile.TemporaryDirectory(prefix="mwx-web-traversal-") as temporary:
            task = Path(temporary)
            source = task / "Harness.swift"
            source.write_text(harness_source())
            scanner = WEB / "WebStaticFileSignalScanner.swift"
            compiled = subprocess.run(["xcrun", "swiftc", "-D", "DEBUG", "-parse-as-library",
                str(source), str(scanner), "-module-cache-path", str(task / "modules"), "-o", str(task / "harness")],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            home, scratch = task / "home", task / "tmp"
            home.mkdir(); scratch.mkdir()
            environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home), TMPDIR=str(scratch) + "/")
            result = subprocess.run([str(task / "harness")], cwd=task, env=environment,
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("web-dependency-traversal-pass", result.stdout)


if __name__ == "__main__":
    unittest.main()
