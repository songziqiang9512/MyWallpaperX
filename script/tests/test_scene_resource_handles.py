"""Real directory handles and shader selection/failure behavior; no App or GPU."""
from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.scene_swift_source_sets import scene_swift_sources


REPO = Path(__file__).resolve().parents[2]
SOURCES = scene_swift_sources("shader_contract_resource_resolution")

HARNESS = r'''
import Foundation
import Darwin

@main enum ResourceHandlesProbe {
    static func write(_ root: URL, _ path: String, _ data: Data) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static func isOpen(_ url: URL) -> Bool {
        let expected = url.resolvingSymlinksInPath().standardizedFileURL.path
        for descriptor: Int32 in 0..<512 {
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            if fcntl(descriptor, F_GETPATH, &path) == 0,
               URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().standardizedFileURL.path == expected {
                return true
            }
        }
        return false
    }
    static func mutateOnceWhenOpened(_ url: URL, changed: inout Bool) throws {
        guard !changed, isOpen(url) else { return }
        try Data("// replacement\nvoid main() {}".utf8).write(to: url, options: .atomic)
        changed = true
    }

    static func handles(_ root: URL) throws -> [String: Bool] {
        let package = root.appendingPathComponent("package")
        let loose = root.appendingPathComponent("loose")
        let path = "materials/renamed texture.tex"
        try write(package, path, Data("package".utf8))
        try write(loose, path, Data("loose".utf8))
        try write(loose, path + "-json", Data("wrong root sidecar".utf8))
        let view = SceneResourceView(projectRootURL: loose, packageRootURL: package,
                                     stockAssetsRootURL: nil)
        let owner = view.roots[0], other = view.roots[1]
        let handle = view.resolvedResource(relativePath: path.uppercased())!
        let originalData = try handle.readBytes()
        var checks = ["directoryLookupPreservesRootAndAuthoredCase": handle.source == .package
            && handle.relativePath == path && owner.owns(handle)
            && originalData == Data("package".utf8)]
        try write(package, path, Data("new mutable bytes".utf8))
        checks["ordinaryEntryEditBeforeReadRemainsReadable"] = try handle.readBytes() == Data("new mutable bytes".utf8)
        try write(package, path, Data("package".utf8))
        let sibling = try owner.sibling(of: handle, appendingSuffix: "-json")
        do {
            _ = try owner.readBytes(sibling)
            checks["missingSiblingDoesNotResolveLowerRoot"] = false
        } catch SceneResourceView.ReadError.missing {
            checks["missingSiblingDoesNotResolveLowerRoot"] = true
        }
        try write(package, path + "-json", Data("same root".utf8))
        checks["siblingUsesSameRootExactPath"] = try owner.readBytes(sibling) == Data("same root".utf8)
        do {
            _ = try other.readBytes(handle)
            checks["foreignRootCannotReadHandle"] = false
        } catch SceneResourceView.ReadError.invalidHandle {
            checks["foreignRootCannotReadHandle"] = true
        }
        do {
            _ = try owner.sibling(of: handle, appendingSuffix: "/../escape")
            checks["siblingRejectsTraversal"] = false
        } catch SceneResourceView.ReadError.invalidPath { checks["siblingRejectsTraversal"] = true }
        checks["invalidLookupDoesNotCreateHandle"] = view.resolvedResource(relativePath: "../escape") == nil
        checks["exactBudgetBoundary"] = try owner.readBytes(handle, maximumBytes: 7).count == 7
        do {
            _ = try owner.readBytes(handle, maximumBytes: 6)
            checks["overBudgetFailsBeforeRead"] = false
        } catch SceneResourceView.ReadError.fileTooLarge { checks["overBudgetFailsBeforeRead"] = true }
        var changed = false
        do {
            _ = try owner.readBytes(handle, checkCancellation: {
                try mutateOnceWhenOpened(package.appendingPathComponent(path), changed: &changed)
            })
            checks["openedPathReplacementIsTypedFailure"] = false
        } catch SceneResourceView.ReadError.sourceChanged {
            checks["openedPathReplacementIsTypedFailure"] = changed
        }
        checks["sameRootRecoversOnNextRead"] = try owner.readBytes(handle).starts(with: Data("// replacement".utf8))
        do {
            _ = try owner.readBytes(handle, checkCancellation: { throw CancellationError() })
            checks["cancellationPropagates"] = false
        } catch is CancellationError { checks["cancellationPropagates"] = true }
        checks["cancelDoesNotPoisonSharedRoot"] = try owner.readBytes(handle).starts(with: Data("// replacement".utf8))
        return checks
    }

    static func selectedRawNames(_ root: URL) throws -> [String: Bool] {
        let package = root.appendingPathComponent("package"), loose = root.appendingPathComponent("loose")
        let raw = "materials\\selected.tex"
        try write(package, raw, Data("raw selected".utf8))
        try write(package, raw + "-json", Data("raw sibling".utf8))
        try write(loose, "materials/selected.tex", Data("healthy lower peer".utf8))
        try write(loose, "materials/selected.tex-json", Data("wrong lower sibling".utf8))
        let view = SceneResourceView(projectRootURL: loose, packageRootURL: package, stockAssetsRootURL: nil)
        var checks: [String: Bool] = [:]
        let chosen = view.resolvedResource(relativePath: "materials/selected.tex")!
        do {
            checks["defaultIndexedHandleReadsSelectedRawBackslashLeaf"] =
                try chosen.relativePath == raw && chosen.readBytes() == Data("raw selected".utf8)
        } catch { checks["defaultIndexedHandleReadsSelectedRawBackslashLeaf"] = false }
        do {
            let sibling = try view.roots[0].sibling(of: chosen, appendingSuffix: "-json")
            checks["defaultIndexedSiblingReadsRawNameInSameRoot"] =
                try sibling.readBytes() == Data("raw sibling".utf8)
        } catch { checks["defaultIndexedSiblingReadsRawNameInSameRoot"] = false }
        do {
            let author = view.authorHandles.first { $0.relativePath == raw }!
            checks["mergedAuthorHandleKeepsRawIndexedLeaf"] = try author.readBytes() == Data("raw selected".utf8)
        } catch { checks["mergedAuthorHandleKeepsRawIndexedLeaf"] = false }
        do {
            let rootLookup = view.roots[0].handle(relativePath: "materials/selected.tex")!
            checks["rootDefaultHandleKeepsRawIndexedLeaf"] = try rootLookup.readBytes() == Data("raw selected".utf8)
        } catch { checks["rootDefaultHandleKeepsRawIndexedLeaf"] = false }
        do {
            _ = try view.roots[0].handle(relativePath: "materials/selected.tex", exact: true)!.readBytes()
            checks["exactProbeDoesNotReselectRawIndexedPeer"] = false
        } catch SceneResourceView.ReadError.missing {
            checks["exactProbeDoesNotReselectRawIndexedPeer"] = true
        }
        let outside = root.appendingPathComponent("outside.bin")
        try write(root, "outside.bin", Data("outside bytes must not be read".utf8))
        try FileManager.default.removeItem(at: package.appendingPathComponent(raw))
        try FileManager.default.createSymbolicLink(at: package.appendingPathComponent(raw), withDestinationURL: outside)
        do {
            _ = try chosen.readBytes()
            checks["indexedRawSymlinkReplacementCannotEscapeRoot"] = false
        } catch SceneResourceView.ReadError.symlinkEscape {
            checks["indexedRawSymlinkReplacementCannotEscapeRoot"] = true
        }
        return checks
    }

    static func namespace(_ root: URL) throws -> [String: Bool] {
        let package = root.appendingPathComponent("package")
        let loose = root.appendingPathComponent("loose")
        let stock = root.appendingPathComponent("stock")
        try write(package, "models/shared.json", Data("package model".utf8))
        try write(package, "materials/choice.json", Data("package material".utf8))
        try write(loose, "models/shared.json", Data("shadowed model".utf8))
        try write(loose, "models/dynamic-unreferenced.json", Data("loose model".utf8))
        try write(loose, "choice.json", Data("literal candidate".utf8))
        try write(stock, "materials/stock-only.json", Data("stock".utf8))
        let view = SceneResourceView(projectRootURL: loose, packageRootURL: package,
                                     stockAssetsRootURL: stock)
        let handles = view.authorHandles
        let selected = view.resolvedResource(relativePath: "MODELS/SHARED.JSON")!
        let reference = view.resolvedResource(forReference: "choice")!
        let explicitStock = view.resolvedResource(forReference: "assets/materials/stock-only")!
        var checks = [
            "authorHandlesKeepFullOrderedNamespace": handles.map(\.relativePath) == [
                "materials/choice.json", "models/shared.json", "choice.json", "models/dynamic-unreferenced.json"],
            "authorHandleMetadataProjectionKeepsLegacyResults": handles.map(\.relativePath)
                == view.authorResources.map(\.relativePath),
            "authorNamespaceExcludesUnreferencedStock": handles.allSatisfy { $0.source != .stock },
            "referenceCandidatePriorityPrecedesRootPriority": reference.source == .loose
                && reference.relativePath == "choice.json",
            "explicitStockAliasKeepsItsActualRelativePath": explicitStock.source == .stock
                && explicitStock.relativePath == "materials/stock-only.json",
        ]
        checks["mergedHandleReadsTheChosenRoot"] = try selected.readBytes() == Data("package model".utf8)
        checks["referenceHandleReadsTheChosenCandidate"] = try reference.readBytes() == Data("literal candidate".utf8)
        checks["stockReferenceHandleReadsWithoutAFileURL"] = try explicitStock.readBytes() == Data("stock".utf8)
        try FileManager.default.moveItem(at: package.appendingPathComponent("models/shared.json"),
            to: package.appendingPathComponent("models/renamed.json"))
        do {
            _ = try selected.readBytes()
            checks["selectedDeletedHandleDoesNotResolveTheLowerRoot"] = false
        } catch SceneResourceView.ReadError.missing {
            checks["selectedDeletedHandleDoesNotResolveTheLowerRoot"] = true
        }
        let fresh = SceneResourceView(projectRootURL: loose, packageRootURL: package,
                                      stockAssetsRootURL: stock)
        checks["nextNamespaceSeesRenameAndNewlyUnshadowedResource"] =
            fresh.authorHandles.filter { $0.kind == .model }.map(\.relativePath) == [
                "models/renamed.json", "models/dynamic-unreferenced.json", "models/shared.json"]
        return checks
    }

    static func rootAlias(_ root: URL) throws -> [String: Bool] {
        let a = root.appendingPathComponent("A"), b = root.appendingPathComponent("B")
        let alias = root.appendingPathComponent("author-root")
        let path = "shaders/probe.frag"
        try write(a, path, Data("A".utf8)); try write(b, path, Data("B".utf8))
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: a)
        let owner = SceneResourceView.Root(source: .loose, url: alias,
            index: SceneResourceIndexBuilder().build(rootURL: a))
        let handle = owner.handle(relativePath: path)!
        try FileManager.default.removeItem(at: alias)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: b)
        var checks: [String: Bool] = [:]
        do {
            _ = try owner.readBytes(handle)
            checks["rootAliasMoveAfterIndexIsTypedFailure"] = false
        } catch SceneResourceView.ReadError.sourceChanged {
            checks["rootAliasMoveAfterIndexIsTypedFailure"] = true
        }
        do {
            _ = try SceneShaderContractLoader().loadRootStageProjection(shaderReferences: ["probe"], root: owner)
            checks["rootAliasFailureEscapesRawProjection"] = false
        } catch SceneResourceView.ReadError.sourceChanged {
            checks["rootAliasFailureEscapesRawProjection"] = true
        }
        let fresh = SceneResourceView.Root(source: .loose, url: alias,
            index: SceneResourceIndexBuilder().build(rootURL: b))
        checks["freshRootMayReadNewCanonicalSource"] = try fresh.readBytes(
            fresh.handle(relativePath: path)!) == Data("B".utf8)
        try FileManager.default.removeItem(at: alias)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: a)
        checks["originalCanonicalRootCanBeReadAgain"] = try owner.readBytes(handle) == Data("A".utf8)
        return checks
    }

    static func literalEntries(_ root: URL) throws -> [String: Bool] {
        let package = root.appendingPathComponent("package")
        let loose = root.appendingPathComponent("loose")
        let stock = root.appendingPathComponent("stock")
        let path = ".authored/Entry.JSON"
        try write(package, path, Data("selected invalid document".utf8))
        try write(loose, path, Data("lower valid document".utf8))
        try write(stock, "stock-only.json", Data("stock is not an entry".utf8))
        let existingRoot = SceneResourceView.Root(source: .loose, url: loose)
        try write(loose, "later.json", Data("new entry".utf8))
        let reused = SceneResourceView(projectRoot: existingRoot, packageRootURL: package)
        var checks = [
            "entryPreparationReusesExactLooseRoot": reused.roots.contains { $0 === existingRoot },
            "entryPreparationDoesNotRebuildLooseNamespace": reused.roots.first { $0.source == .loose }?
                .resource(relativePath: "later.json") == nil,
            "hiddenLiteralEntryIsAbsentFromIndex": reused.roots[0].resource(relativePath: path) == nil,
        ]
        try write(package, "C:/inside.txt", Data("colon relative".utf8))
        try write(package, "file:inside.bin", Data("typed colon relative".utf8))
        checks["driveSpellingOnlyNamesThisRootRelativeFile"] = try reused.literalEntry(
            relativePath: "C:/inside.txt")?.readBytes() == Data("colon relative".utf8)
        checks["typedColonOnlyNamesThisRootRelativeFile"] = try reused.literalEntry(
            relativePath: "file:inside.bin")?.readBytes() == Data("typed colon relative".utf8)
        let selected = try reused.literalEntry(relativePath: path)!
        let selectedBytes = try selected.readBytes()
        checks["hiddenLiteralEntryUsesPackageBeforeLoose"] = selected.source == .package
            && selectedBytes == Data("selected invalid document".utf8)
        checks["literalEntryDoesNotSkipMissingDotComponent"] = try reused.literalEntry(
            relativePath: "ignored/../" + path) == nil
        try FileManager.default.createDirectory(at: package.appendingPathComponent("ignored"), withIntermediateDirectories: true)
        checks["literalEntryPreservesInRootDotComponents"] = try reused.literalEntry(
            relativePath: "ignored/../" + path)?.readBytes() == selectedBytes
        checks["literalEntryCanReadUnindexedLooseFile"] = try reused.literalEntry(
            relativePath: "later.json")?.readBytes() == Data("new entry".utf8)
        do {
            _ = try reused.literalEntry(relativePath: "../escape.json")
            checks["literalEntryRejectsTraversalOutsideRoot"] = false
        } catch SceneResourceView.ReadError.symlinkEscape {
            checks["literalEntryRejectsTraversalOutsideRoot"] = true
        }
        try FileManager.default.removeItem(at: package.appendingPathComponent(path))
        do {
            _ = try selected.readBytes()
            checks["selectedEntryDeletionDoesNotFallback"] = false
        } catch SceneResourceView.ReadError.missing {
            checks["selectedEntryDeletionDoesNotFallback"] = true
        }
        checks["nextEntrySelectionMayUseNowUnshadowedLoose"] = try reused.literalEntry(
            relativePath: path)?.source == .loose
        let custom = SceneResourceView(projectRootURL: loose, packageRootURL: nil,
            stockAssetsRootURL: stock)
        checks["literalEntryNeverSelectsStockOrExtensionGuess"] = try custom.literalEntry(
            relativePath: "stock-only.json") == nil && custom.literalEntry(relativePath: "later") == nil
        try write(loose, "CaseOnly.JSON", Data("authored case".utf8))
        checks["literalEntryCaseMatchesFilesystemInsteadOfIndexFold"] = try (custom.literalEntry(
            relativePath: "caseonly.json") != nil) == FileManager.default.fileExists(
                atPath: loose.appendingPathComponent("caseonly.json").path)
        let outside = root.appendingPathComponent("outside")
        try write(outside, "child/placeholder", Data())
        try write(outside, "escape.json", Data("outside".utf8))
        try FileManager.default.createSymbolicLink(at: package.appendingPathComponent("file:"),
            withDestinationURL: outside)
        try write(loose, "file:/escape.json", Data("lower peer must not hide escape".utf8))
        do {
            _ = try reused.literalEntry(relativePath: "file:/escape.json")?.readBytes()
            checks["colonRelativeSymlinkCannotReadOutsideOrFallToLoose"] = false
        } catch SceneResourceView.ReadError.symlinkEscape {
            checks["colonRelativeSymlinkCannotReadOutsideOrFallToLoose"] = true
        }

        try write(loose, "escape.json", Data("inside lexical peer".utf8))
        try FileManager.default.createSymbolicLink(at: loose.appendingPathComponent("pivot"),
            withDestinationURL: outside.appendingPathComponent("child"))
        do {
            _ = try custom.literalEntry(relativePath: "pivot/../escape.json")
            checks["literalSymlinkDotCannotSelectOutsideRoot"] = false
        } catch SceneResourceView.ReadError.symlinkEscape {
            checks["literalSymlinkDotCannotSelectOutsideRoot"] = true
        }
        try FileManager.default.removeItem(at: loose.appendingPathComponent("pivot"))
        try write(loose, "inner/child/placeholder", Data())
        try write(loose, "inner/escape.json", Data("actual filesystem peer".utf8))
        try FileManager.default.createSymbolicLink(at: loose.appendingPathComponent("pivot"),
            withDestinationURL: loose.appendingPathComponent("inner/child"))
        checks["literalSymlinkDotReadsActualInRootTarget"] = try custom.literalEntry(
            relativePath: "pivot/../escape.json")?.readBytes() == Data("actual filesystem peer".utf8)
        return checks
    }

    static func shaders(_ root: URL) throws -> [String: Bool] {
        let package = root.appendingPathComponent("package")
        let loose = root.appendingPathComponent("loose")
        let path = "shaders/renamed/probe.frag"
        let selected = Data("// selected\nvoid main() {}".utf8)
        try write(package, path, selected)
        try write(loose, path, Data("// lower\nvoid main() {}".utf8))
        let view = SceneResourceView(projectRootURL: loose, packageRootURL: package,
                                     stockAssetsRootURL: nil)
        let resolver = SceneShaderSourceResolver()
        func graph(_ check: (() throws -> Void)? = nil) throws -> SceneShaderSourceGraph {
            try SceneShaderSourceGraphBuilder().build(roots: [.init(label: "fragment", virtualPath: path)],
                resourceView: view, checkCancellation: check)
        }
        var checks: [String: Bool] = [:]
        var changed = false
        do {
            _ = try resolver.resolveWithEvidence(virtualPath: path, resourceView: view, maximumBytes: 1024,
                checkCancellation: {
                    try mutateOnceWhenOpened(package.appendingPathComponent(path), changed: &changed)
                })
            checks["selectedChangedDoesNotFallThrough"] = false
        } catch SceneResourceView.ReadError.sourceChanged {
            checks["selectedChangedDoesNotFallThrough"] = changed
        }
        let recovered = try resolver.resolveWithEvidence(virtualPath: path, resourceView: view, maximumBytes: 1024)
        if case let .resolved(file) = recovered.selected {
            checks["nextResolveDoesNotRetainFailure"] = file.provenance == .package
                && file.source.hasPrefix("// replacement")
        } else { checks["nextResolveDoesNotRetainFailure"] = false }
        try write(package, path, selected)
        let before = try graph()
        changed = false
        let optionalFailure = try graph {
            try mutateOnceWhenOpened(loose.appendingPathComponent(path), changed: &changed)
        }
        checks["unselectedRootPayloadIsNeverOpened"] = !changed
            && optionalFailure.nodes.count == 1 && optionalFailure.nodes[0].source == String(decoding: selected, as: UTF8.self)
        checks["unselectedRootDoesNotEnterDependencyEvidence"] = optionalFailure.edges[0].candidates.allSatisfy {
            $0.provenance != .loose
        }
        try write(loose, path, Data("// changed lower content".utf8))
        let after = try graph()
        checks["unselectedChangesDoNotInvalidateSelectedProgram"] = optionalFailure.dependencySHA256 == before.dependencySHA256
            && before.dependencySHA256 == after.dependencySHA256
        let encoded = try JSONEncoder().encode(optionalFailure)
        checks["selectedDependencySnapshotRoundTrips"] = try JSONDecoder().decode(SceneShaderSourceGraph.self,
            from: encoded) == optionalFailure

        try FileManager.default.removeItem(at: loose.appendingPathComponent(path))
        precondition(mkfifo(loose.appendingPathComponent(path).path, 0o600) == 0)
        let unreadable = try resolver.resolveWithEvidence(virtualPath: path, resourceView: view, maximumBytes: 1024)
        checks["unselectedNonRegularFileNeedsNoReadOrEvidence"] = unreadable.candidates.count == 1
            && unreadable.candidates[0].provenance == .package
        if case let .resolved(file) = unreadable.selected {
            checks["unselectedOrdinaryFailureKeepsSelectedSource"] = file.provenance == .package
        } else { checks["unselectedOrdinaryFailureKeepsSelectedSource"] = false }
        do {
            _ = try graph { throw CancellationError() }
            checks["graphCancellationAlwaysPropagates"] = false
        } catch is CancellationError { checks["graphCancellationAlwaysPropagates"] = true }

        try FileManager.default.removeItem(at: package.appendingPathComponent(path))
        try FileManager.default.removeItem(at: loose.appendingPathComponent(path))
        try write(loose, path, Data("// lower should not replace selected missing".utf8))
        checks["selectedIndexedMissingDoesNotFallThrough"] = try resolver.resolve(
            virtualPath: path, resourceView: view, maximumBytes: 1024) == .failed(.missing)
        try write(package, "shaders/repeated.frag", Data("#include \"shared.glsl\"\n#include \"shared.glsl\"\nvoid main() {}".utf8))
        let includePath = package.appendingPathComponent("shaders/shared.glsl")
        try write(package, "shaders/shared.glsl", Data("// captured include".utf8))
        let repeatedView = SceneResourceView(projectRootURL: loose, packageRootURL: package, stockAssetsRootURL: nil)
        var observedOpen = false, closedAfterRead = false, reopened = false
        let builder = SceneShaderSourceGraphBuilder()
        let roots = [SceneShaderSourceGraph.RootRequest(label: "fragment", virtualPath: "shaders/repeated.frag")]
        let first = try builder.build(roots: roots, resourceView: repeatedView, checkCancellation: {
            if isOpen(includePath) {
                reopened = reopened || closedAfterRead
                observedOpen = true
            } else if observedOpen { closedAfterRead = true }
        })
        checks["repeatedIncludeUsesOneCapturedRead"] = observedOpen && !reopened
            && first.nodes.filter { $0.virtualPath == "shaders/shared.glsl" }.count == 1
        try write(package, "shaders/shared.glsl", Data("// next attempt include".utf8))
        let next = try builder.build(roots: roots, resourceView: repeatedView)
        checks["nextGraphReadsChangedSelectedInclude"] = first.dependencySHA256 != next.dependencySHA256
            && next.node(at: "shaders/shared.glsl")?.source == "// next attempt include"
        return checks
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        var checks = try handles(root.appendingPathComponent("handles"))
        checks.merge(try namespace(root.appendingPathComponent("namespace"))) { _, value in value }
        checks.merge(try selectedRawNames(root.appendingPathComponent("raw"))) { _, value in value }
        checks.merge(try shaders(root.appendingPathComponent("shaders"))) { _, value in value }
        checks.merge(try rootAlias(root.appendingPathComponent("alias"))) { _, value in value }
        checks.merge(try literalEntries(root.appendingPathComponent("entries"))) { _, value in value }
        let grouped = root.appendingPathComponent("grouped")
        let package = grouped.appendingPathComponent("package"), loose = grouped.appendingPathComponent("loose")
        try write(package, "shaders/effects/probe.frag", Data("package fragment".utf8))
        try write(loose, "shaders/effects/probe.vert", Data("loose vertex".utf8))
        try write(loose, "shaders/effects/probe.frag", Data("loose fragment".utf8))
        let view = SceneResourceView(projectRootURL: loose, packageRootURL: package, stockAssetsRootURL: nil)
        let contracts = try SceneShaderContractLoader().load(
            shaderReferences: ["effects/probe", "effects/./probe"], resourceView: view)
        checks["normalizedReferenceGroupsKeepDirectoryOrderAndSameRootPair"] = contracts.map { $0.stages.map(\.source) }
            == [["loose vertex", "loose fragment"], ["package fragment"]]
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneResourceHandleTests(unittest.TestCase):
    def test_real_directory_handles_and_shader_failure_selection(self):
        if shutil.which("xcrun") is None:
            self.skipTest("Xcode tools unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-resource-handles-") as temporary:
            work = Path(temporary)
            harness, binary = work / "Harness.swift", work / "probe"
            harness.write_text(HARNESS)
            built = subprocess.run(["xcrun", "swiftc", "-swift-version", "5",
                "-default-isolation", "MainActor", *map(str, SOURCES), str(harness),
                "-module-cache-path", str(work / "module-cache"), "-o", str(binary)],
                cwd=REPO, capture_output=True, text=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            ran = subprocess.run([str(binary), str(work / "fixtures")],
                capture_output=True, text=True, timeout=30)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            result = json.loads(ran.stdout)
            self.assertGreaterEqual(len(result), 20)
            for name, passed in result.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True)


if __name__ == "__main__":
    unittest.main()
