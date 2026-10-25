"""Real single-pass author summary, late dependency and bounded text reads."""
from __future__ import annotations

import unittest
from script.tests.test_web_author_preparation import CHECKS, harness_source, run_harness

TRAVERSAL = r'''
@main enum TraversalHarness {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: fm.currentDirectoryPath).resolvingSymlinksInPath()
        let service = SteamWorkshopService(); service.steamDownloadLibraryRootURL = root.appendingPathComponent("library")
        func fixture(_ name: String) throws -> SteamWorkshopDownloadRecord {
            let folder = root.appendingPathComponent(name); try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            return SteamWorkshopDownloadRecord(id: name, folderURL: folder, entryURL: folder.appendingPathComponent("index.html"))
        }
        func write(_ text: String, _ name: String, _ r: SteamWorkshopDownloadRecord) throws { try Data(text.utf8).write(to: r.folderURL.appendingPathComponent(name)) }
        func capture(_ r: SteamWorkshopDownloadRecord) -> SteamWorkshopService.WebCapturedAuthorInput {
            let source = service.webPropertyDefinitionSource(for: r)
            return service.captureWebAuthorInput(record: r, source: source,
                inputs: service.webRuntimeCacheManifestInputs(for: r, source: source))!
        }
        let long = try fixture("deep")
        try write("<script src='node0.js'></script>", "index.html", long)
        for i in 0..<205 {
            var text = i < 204 ? "import 'node\(i + 1).js';" : "localStorage.setItem('x',1); const movie='tail.webm';"
            if i == 198 { text += "WebAssembly.instantiateStreaming(fetch('addon.wasm'));" }
            if i == 199 { text += "navigator.serviceWorker.register('sw.js');" }
            try write(text, "node\(i).js", long)
        }
        trace.reset(); let deep = capture(long)
        let deepProduct = service.parseWebProjectDescriptorCore(record: long, captured: deep)!
        check(deepProduct.staticContentSummary.usesWASMStreaming && deepProduct.staticContentSummary.usesServiceWorkerRegistration
            && deepProduct.staticContentSummary.usesPersistentBrowserStorage && deepProduct.staticContentSummary.usesWebMResource,
            "single summary reaches author signals at 198/199/204")
        check(trace.rows.count == 206 && Set(trace.rows.map { $0.0 }).count == 206, "each actual dependency is read once without a certification traversal")

        let large = try fixture("fragments")
        let prefix = "<script>" + String(repeating: "x", count: 150_000)
        let middle = "navigator.serviceWorker.register('sw.js'); import 'middle.js';"
        let suffix = String(repeating: "x", count: 150_000) + "import 'late.json';</script>"
        try write(prefix + middle + suffix, "index.html", large)
        try write("localStorage.setItem('must-not-expand-summary',1);", "middle.js", large)
        try write("WebAssembly.instantiateStreaming(fetch('addon.wasm'));", "late.json", large)
        let fragmented = capture(large)
        let flags = service.parseWebProjectDescriptorCore(record: large, captured: fragmented)!.staticContentSummary
        check(flags.hasTruncatedStaticAnalysis && flags.hasUncertainUserPropertyUsage && flags.usesServiceWorkerRegistration
            && flags.usesWASMStreaming, "128KiB prefix/suffix plus <=1MiB middle SW scan")
        check(!flags.usesPersistentBrowserStorage, "sampled fragments keep the original summary graph")
        try write(String(repeating: "x", count: 600_000) + middle + String(repeating: "x", count: 600_000) + "WebAssembly.instantiateStreaming(fetch('addon.wasm'));", "index.html", large)
        let overOne = capture(large)
        check(!overOne.summary.usesServiceWorkerRegistration && overOne.summary.usesWASMStreaming, ">1MiB never gains a middle-only SW signal")
        try write(String(repeating: "x", count: 4 * 1024 * 1024 + 1) + "WebAssembly.instantiateStreaming(fetch('addon.wasm'));", "index.html", large)
        let overFour = capture(large)
        check(overFour.summary.usesWASMStreaming, "large author files keep bounded prefix/suffix summary")

        let total = try fixture("total")
        try write((0..<5).map { "<script src='p\($0).js'></script>" }.joined(), "index.html", total)
        for i in 0..<5 { try write(String(repeating: "x", count: 4 * 1024 * 1024 - 32) + "WebAssembly.instantiateStreaming(fetch('addon.wasm'));", "p\(i).js", total) }
        let totalCapture = capture(total)
        check(totalCapture.summary.usesWASMStreaming, "large aggregate dependency input retains late summary signals")

        var bigProject = try fixture("project-budget")
        bigProject.projectFileURL = bigProject.folderURL.appendingPathComponent("project.json")
        try write("<html></html>", "index.html", bigProject)
        try write("{\"file\":\"index.html\",\"preset\":{\"kept\":42},\"padding\":\"" + String(repeating: "x", count: 4 * 1024 * 1024) + "\"}", "project.json", bigProject)
        let bigCapture = capture(bigProject)
        check(service.parseWebProjectDescriptorCore(record: bigProject, captured: bigCapture)!.presetOverrides["kept"] == .number(42), "large author project retains original parse")


        let malformed = try fixture("malformed-text")
        var malformedData = Data(String(repeating: "x", count: 150_000).utf8)
        malformedData.append(255); malformedData.append(Data(String(repeating: "x", count: 150_000).utf8))
        malformedData.append(Data("import 'late.json';".utf8))
        try malformedData.write(to: malformed.folderURL.appendingPathComponent("index.html"))
        try write("localStorage.setItem('late',1)", "late.json", malformed)
        let malformedCapture = capture(malformed)
        check(malformedCapture.summary.usesPersistentBrowserStorage,
            "lossy fragments retain late summary dependency signals")

        let missing = try fixture("missing")
        try write("<script src='absent.js'></script><script src='../escape.js'></script>", "index.html", missing)
        let missingCapture = capture(missing)
        check(missingCapture.summary.hasUncertainUserPropertyUsage,
            "missing/escaped optional dependencies remain local uncertainty")
        print("web-dependency-traversal-pass")
    }
}
'''


class WebDependencyTraversalTests(unittest.TestCase):
    def test_real_single_summary_and_bounded_file_reads(self):
        source = harness_source().removesuffix(CHECKS)
        run_harness(self, source + TRAVERSAL, 'web-dependency-traversal-pass')


if __name__ == '__main__': unittest.main()
