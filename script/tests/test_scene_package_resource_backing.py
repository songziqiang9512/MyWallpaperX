"""Current-file package mounts through the real Reader, Root and shader loader.

These CPU gates do not assert App startup timing, Metal output or AV drain.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest

from script.scene_swift_source_sets import scene_swift_sources
from script.tests.scene_pkg_fixture import make_package

ROOT = Path(__file__).resolve().parents[2]
SOURCES = scene_swift_sources("shader_contract_resource_resolution")
IO_OBSERVER = ROOT / "script/tests/fixtures/SceneVideoPackageReadObserver.c"

HARNESS = r'''
import Foundation
import Darwin

@_silgen_name("mwx_video_entry_observe")
func observeEntry(_ descriptor: Int32, _ begin: UInt64, _ length: UInt64) -> Int32
@_silgen_name("mwx_video_entry_bytes") func observedBytes() -> UInt64
@_silgen_name("mwx_video_entry_calls") func observedCalls() -> UInt64

@main enum PackageBackingProbe {
    enum Stop: Error { case requested, sink }
    static func put(_ root: URL, _ path: String, _ bytes: Data) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url, options: .atomic)
    }
    static func rejects(_ body: () throws -> Void, matching: (any Error) -> Bool = { _ in true }) -> Bool {
        do { try body(); return false } catch { return matching(error) }
    }
    static func hard(_ error: any Error) -> Bool {
        if case SceneResourceView.ReadError.sourceChanged = error { return true }
        if case ScenePkgReader.ReadError.sourceChanged = error { return true }
        return false
    }
    static func mount(_ url: URL) throws -> SceneResourceView.Root {
        try .package(openedPackage: ScenePkgReader().openPackage(packageURL: url))
    }
    static func observePayload(_ package: ScenePkgReader.OpenPackage) throws {
        let target = URL(fileURLWithPath: package.packagePath).resolvingSymlinksInPath().standardizedFileURL
        for descriptor in 3..<1_024 {
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            if fcntl(Int32(descriptor), F_GETPATH, &path) == 0,
               URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().standardizedFileURL == target {
                let payloadSize = package.index.fileSize - package.index.dataStartOffset
                guard observeEntry(Int32(descriptor), UInt64(package.index.dataStartOffset), UInt64(max(1, payloadSize))) == 0 else {
                    throw Stop.sink
                }
                return
            }
        }
        throw Stop.sink
    }
    static func unreadable(_ error: any Error) -> Bool {
        if case SceneResourceView.ReadError.unreadable = error { return true }
        return false
    }
    static func main() throws {
        let mode = CommandLine.arguments[1]
        let packageURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let base = packageURL.deletingLastPathComponent()
        let loose = base.appendingPathComponent("loose")
        try FileManager.default.createDirectory(at: loose, withIntermediateDirectories: true)
        var result: [String: Bool] = [:]
        switch mode {
        case "mount":
            let root = try mount(packageURL)
            try put(loose, "materials/odd.tex", Data("lower root".utf8))
            try put(loose, "materials/odd.tex-json", Data("wrong sidecar".utf8))
            let view = SceneResourceView(projectRoot: .init(source: .loose, url: loose), packageRoot: root, stockRoot: nil)
            let handle = view.resolvedResource(relativePath: "MATERIALS/ODD.TEX")!
            let snapshot = try handle.readSnapshot()
            result["packageHasNoPhysicalResourceOrRootURL"] = root.directoryURL == nil
                && root.index.directoryURL == nil && root.index.resources.allSatisfy { $0.directoryURL == nil }
            result["ordinaryNamespaceIncludesNonExtractorKinds"] = ["unlisted/unusual.bin", "fonts/custom.ttf"]
                .allSatisfy { view.availableRelativePaths.contains($0) }
            result["hiddenNamespaceIsLiteralOnly"] = try !view.availableRelativePaths.contains(".hidden/author.raw")
                && root.resource(relativePath: ".hidden/author.raw") == nil
                && root.invariantHandle(relativePath: ".hidden/author.raw") == nil
                && (try root.existingLiteralHandle(relativePath: ".hidden/author.raw")?.readBytes()) == Data("hidden".utf8)
            result["packagePrecedesLooseAndPreservesSelectedRawTableIdentity"] = {
                guard case let .package(identity) = snapshot.identity else { return false }
                return handle.source == .package && snapshot.data == Data("raw backslash".utf8)
                    && identity.rawEntryPath == "materials\\odd.tex" && URL(fileURLWithPath: identity.packagePath).resolvingSymlinksInPath().standardizedFileURL == packageURL.resolvingSymlinksInPath().standardizedFileURL
                    && Int(identity.byteCount) == snapshot.data.count && identity.isValid
            }()
            let sibling = try handle.sibling(appendingSuffix: "-json")
            result["sidecarStaysInSelectedPackage"] = try sibling.readBytes() == Data("package sidecar".utf8)
            result["foreignRootRejected"] = rejects({ _ = try view.roots[1].readBytes(handle) }, matching: {
                if case SceneResourceView.ReadError.invalidHandle = $0 { return true }; return false
            })
            result["entryBudgetIsExact"] = try handle.readBytes(maximumBytes: snapshot.data.count) == snapshot.data
            for budget in [-1, snapshot.data.count - 1] {
                var prepared = false, consumed = false
                result["budget\(budget)RejectsBeforePrepareOrConsume"] = rejects({
                    _ = try handle.readChunks(maximumBytes: budget, prepare: { _ in prepared = true }) { _ in consumed = true }
                }, matching: { if case SceneResourceView.ReadError.fileTooLarge = $0 { return true }; return false })
                    && !prepared && !consumed
            }
            result["invalidTraversalNeverSelectsAResource"] = view.resolvedResource(relativePath: "../materials/odd.tex") == nil
            let input = SceneResourceView.FileInput.resource(handle)
            result["inputAndHandleShareTypedIdentity"] = try input.currentIdentity() == snapshot.identity
            let other = try view.resolvedResource(relativePath: "unlisted/unusual.bin")!.currentIdentity()
            result["anotherEntryCannotLabelThisSnapshot"] = rejects({ _ = try handle.readSnapshot(expectedIdentity: other) }, matching: hard)
        case "stream":
            var root: SceneResourceView.Root? = try mount(packageURL)
            var handle: SceneResourceView.Handle? = root!.handle(relativePath: "unlisted/large.bin")
            weak var reader = root!.packageBacking!.opened
            let expected = try handle!.readBytes()
            var chunks: [Int] = [], bytes = Data(), preparedIdentity: SceneResourceView.ContentIdentity?
            var preparedBeforeConsume = true
            let identity = try handle!.readChunks(prepare: { preparedIdentity = $0 }) { chunk in
                preparedBeforeConsume = preparedBeforeConsume && preparedIdentity != nil
                chunks.append(chunk.count); bytes.append(chunk)
            }
            result["prepareUsesSameOpenedIdentityBeforeAnyConsumerBytes"] = preparedBeforeConsume && preparedIdentity == identity
            result["streamAndSnapshotReadSameBytesAndRevision"] = try bytes == expected && identity == handle!.currentIdentity()
            result["streamIsBounded"] = chunks.count > 1 && chunks.allSatisfy { $0 <= 64 * 1_024 }
            result["sinkErrorIdentityIsPreserved"] = rejects({
                _ = try handle!.readChunks { _ in throw Stop.sink }
            }, matching: { if case Stop.sink = $0 { return true }; return false })
            var consumedBeforeCancel = 0
            result["cancelErrorIdentityIsPreserved"] = rejects({
                _ = try handle!.readChunks(checkCancellation: { if consumedBeforeCancel > 0 { throw Stop.requested } }) { _ in
                    consumedBeforeCancel += 1
                }
            }, matching: { if case Stop.requested = $0 { return true }; return false })
            result["cancelHappensAfterActualFirstChunk"] = consumedBeforeCancel == 1
            result["cancelledReadDoesNotPoisonNextBorrower"] = try handle!.readBytes() == expected
            root = nil
            result["handleKeepsPackageFDAlive"] = reader != nil
            handle = nil
            result["lastHandleClosesPackageFD"] = reader == nil
        case "literal":
            let root = try mount(packageURL)
            func read(_ path: String) throws -> String? {
                guard let handle = try root.existingLiteralHandle(relativePath: path) else { return nil }
                return String(decoding: try handle.readBytes(), as: UTF8.self)
            }
            result["caseRenamedDirectoryAndLeafUseSameNamespace"] = try read("SHADERS/RENAMED.VERT") == "upper named"
            result["exactCaseConflictWinsBeforeFoldedLookup"] = try read("shaders/probe.frag") == "lower exact"
                && read("Shaders/Probe.frag") == "upper exact"
            let fallback = try root.existingLiteralHandle(relativePath: "SHADERS/PROBE.FRAG")!
            let first = root.resource(relativePath: "SHADERS/PROBE.FRAG")!
            result["nonExactCaseConflictUsesSortedFirstWins"] = fallback.relativePath == first.relativePath
            result["existingDirectoryDotAndParentAreAccepted"] = try read("SHADERS/./renamed.vert") == "upper named"
                && read("Shaders/inner/../renamed.vert") == "upper named"
            result["missingDirectoryCannotDisappearBeforeParentTraversal"] = try read("absent/../Shaders/renamed.vert") == nil
            result["directoryCannotEscapePackage"] = rejects({ _ = try read("Shaders/../../escape") })
            let exact = root.handle(relativePath: "SHADERS/RENAMED.VERT", exact: true)!
            result["exactProbeRetainsSelectedRealEntry"] = try exact.readBytes() == Data("upper named".utf8)
            result["missingLiteralDoesNotReadAnotherRoot"] = try read("not-present/entry.bin") == nil
            result["caseRenamedShaderBoundaryUsesSameLogicalNamespace"] = try exact.readBytes(within: "shaders") == Data("upper named".utf8)
            let upper = root.handle(relativePath: "Shaders/Probe.frag", exact: true)!
            let lower = root.handle(relativePath: "shaders/probe.frag", exact: true)!
            result["boundaryDoesNotChangeExactCaseConflictSelection"] = try upper.readBytes(within: "SHADERS") == Data("upper exact".utf8)
                && lower.readBytes(within: "SHADERS") == Data("lower exact".utf8)
            let adjacent = root.handle(relativePath: "ShadersElse/peer.vert", exact: true)!
            result["logicalBoundaryDoesNotAcceptAdjacentDirectoryPrefix"] = rejects({
                _ = try adjacent.readBytes(within: "shaders")
            }, matching: { if case SceneResourceView.ReadError.symlinkEscape = $0 { return true }; return false })
            result["boundaryCannotAcquireDotTraversal"] = rejects({ _ = try exact.readBytes(within: "shaders/../Shaders") })
        case "namespace":
            let root = try mount(packageURL)
            let packageEntries = root.packageBacking!.orderedEntries
            for entry in packageEntries {
                let bytes = try root.existingLiteralHandle(relativePath: entry.path)!.readBytes()
                try put(loose, entry.path, bytes)
            }
            let flagged = loose.appendingPathComponent("flag-hidden.bin")
            let bytes = Data("flag hidden".utf8)
            try bytes.write(to: flagged)
            guard chflags(flagged.path, UInt32(UF_HIDDEN)) == 0 else { throw POSIXError(.EIO) }
            defer { _ = chflags(flagged.path, 0) }
            let author = SceneResourceView.Root(source: .loose, url: loose)
            let original = SceneResourceIndexBuilder().build(rootURL: loose)
            let expected = Set(["ordinary/leaf.bin", "opaque.framework/leaf.bin", "opaque.scnassets/leaf.bin", "opaque.unknownext/leaf.bin"])
            result["packageOrdinaryProjectionUsesPublicDirectoryTypeFacts"] = Set(root.index.resources.map(\.relativePath)) == expected
            result["directoryKeepsActualFileManagerProjection"] = author.index.resources.map(\.relativePath) == original.resources.map(\.relativePath)
                && Set(author.index.resources.map(\.relativePath)) == expected
            result["completeTableAndLiteralCapabilityAreNotPruned"] = root.packageBacking!.entries.count == packageEntries.count
                && packageEntries.allSatisfy { entry in (try? root.existingLiteralHandle(relativePath: entry.path)?.readBytes()) == Data(entry.path.utf8) }
            result["hiddenAndOpaqueOrdinaryAndInvariantMiss"] = [".hidden/leaf.bin", "opaque.bundle/leaf.bin", "opaque.app/leaf.bin"].allSatisfy {
                root.resource(relativePath: $0) == nil && root.invariantHandle(relativePath: $0) == nil
                    && author.resource(relativePath: $0) == nil && author.invariantHandle(relativePath: $0) == nil
            }
            result["actualHiddenFlagOnlyAffectsDirectoryOrdinaryProjection"] = try author.resource(relativePath: flagged.lastPathComponent) == nil
                && author.invariantHandle(relativePath: flagged.lastPathComponent) == nil
                && (try author.existingLiteralHandle(relativePath: flagged.lastPathComponent)?.readBytes()) == bytes
        case "shader":
            let root = try mount(packageURL)
            let vertex = Data("// loose vertex\nvoid main() {}".utf8)
            let fragment = Data("// loose fragment\nvoid main() {}".utf8)
            try put(loose, "shaders/effects/renamed.vert", vertex)
            try put(loose, "shaders/effects/renamed.frag", fragment)
            let author = SceneResourceView.Root(source: .loose, url: loose)
            let view = SceneResourceView(projectRoot: author, packageRoot: root, stockRoot: nil)
            let contracts = try SceneShaderContractLoader().load(shaderReferences: ["effects/renamed", "effects/./renamed"], resourceView: view)
            result["mountedGroupsUsePackageThenLooseTypedOrder"] = contracts.count == 2
                && contracts[0].stages.map(\.source) == ["// package fragment\nvoid main() {}"]
                && contracts[1].stages.map(\.source) == [String(decoding: vertex, as: UTF8.self), String(decoding: fragment, as: UTF8.self)]
            result["shaderStagePairNeverSplicesAcrossRoots"] = contracts.count == 2
                && contracts[0].stages.map(\.kind) == [.fragment]
                && contracts[1].stages.map(\.kind) == [.vertex, .fragment]
            let duplicate = try SceneShaderContractLoader().load(shaderReferences: ["effects/renamed", "effects/renamed.vert"], resourceView: view)
            result["normalizedDuplicateWithinSameRootKeepsOneStagePair"] = duplicate.count == 1
                && duplicate[0].stages.map(\.kind) == [.vertex, .fragment]
                && duplicate[0].diagnostics.contains { $0.code == .duplicateIdentity }
            let renamed = try SceneShaderContractLoader().load(shaderReferences: ["CASE/RENAMED"], resourceView: view)
            result["rawShaderCaseVariantUsesActualPackageEntry"] = renamed.count == 1
                && renamed[0].stages.map(\.source) == ["// renamed vertex\nvoid main() {}"]
        case "revision":
            let root = try mount(packageURL), selected = root.handle(relativePath: "materials/bad.tex")!
            let before = try selected.readSnapshot()
            let package = root.packageBacking!.opened
            let entry = package.index.entries[0]
            let writer = try FileHandle(forWritingTo: packageURL)
            try writer.seek(toOffset: UInt64(package.index.dataStartOffset) + UInt64(entry.offset))
            let changed = Data(repeating: 88, count: Int(entry.size))
            try writer.write(contentsOf: changed); try writer.close()
            result["staleOpenRejectsReadAndCacheIdentity"] = rejects({ _ = try selected.readBytes() }, matching: hard)
                && rejects({ _ = try selected.currentIdentity() }, matching: hard)
            let current = try mount(packageURL).handle(relativePath: "materials/bad.tex")!.readSnapshot()
            result["freshRevisionReadsCurrentPlayableBytes"] = current.data == changed && current.identity != before.identity
        case "directory":
            try put(loose, "materials/current.tex", Data("first".utf8))
            let root = SceneResourceView.Root(source: .loose, url: loose)
            let handle = root.handle(relativePath: "materials/current.tex")!
            let before = try handle.readSnapshot()
            try put(loose, "preview-cache/new.png", Data("unrelated".utf8))
            result["unrelatedNewFilesDoNotBlockPlayback"] = try handle.readBytes() == before.data
            try put(loose, "materials/current.tex", Data("other".utf8))
            result["currentBytesArePlayableWithoutOldImportDigest"] = try handle.readBytes() == Data("other".utf8)
            result["staleExpectedRevisionStillRejected"] = rejects({ _ = try handle.readSnapshot(expectedIdentity: before.identity) }, matching: hard)
            let outside = base.appendingPathComponent("outside.tex")
            try Data("outside".utf8).write(to: outside)
            try FileManager.default.createSymbolicLink(at: loose.appendingPathComponent("escape.tex"), withDestinationURL: outside)
            result["outsidePathCannotBecomeResource"] = rejects({ _ = try root.handle(relativePath: "escape.tex")!.readBytes() }, matching: {
                if case SceneResourceView.ReadError.symlinkEscape = $0 { return true }; return false
            })
        case "first-wins", "first-wins-invalid":
            let opened = try ScenePkgReader().openPackage(packageURL: packageURL)
            try observePayload(opened)
            let root = try SceneResourceView.Root.package(openedPackage: opened)
            result["rootNamespaceBuildAfterIndexReadsNoPayload"] = observedBytes() == 0 && observedCalls() == 0
            let reference = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
            let rawPath = CommandLine.arguments[4]
            let projected = rawPath.replacingOccurrences(of: "\\", with: "/")
            let first = try root.existingLiteralHandle(relativePath: projected)!
            let snapshot = try first.readSnapshot()
            result["onlyOneLeafForEquivalentTargets"] = root.packageBacking!.entries.count == 1
            result["firstPayloadWinsWithoutReadingDifferentLaterPayloads"] = snapshot.data == reference
                && observedBytes() == UInt64(reference.count)
            let identity = try first.currentIdentity()
            result["identityUsesFirstRawTableSpellingAndRange"] = {
                guard case let .package(selected) = identity else { return false }
                let position = CommandLine.arguments.count > 5 ? Int(CommandLine.arguments[5])! : 0
                let entry = opened.index.entries[position]
                return Array(selected.rawEntryPath.utf8) == Array(rawPath.utf8)
                    && selected.offset == entry.offset && selected.byteCount == entry.size
                    && selected.fileRevision == opened.fileRevision
            }()
            let equivalent = projected.precomposedStringWithCanonicalMapping.replacingOccurrences(of: "/", with: "\\")
            let second = try root.existingLiteralHandle(relativePath: equivalent)!
            let secondBytes = try second.readBytes()
            let secondIdentity = try second.currentIdentity()
            result["canonicalAndSeparatorQueriesKeepSameChosenEntry"] = secondBytes == reference
                && secondIdentity == identity
            result["onlySelectedRangeIsReadOnBothRequests"] = observedBytes() == UInt64(reference.count * 2)
                && (reference.isEmpty ? observedCalls() == 0 : observedCalls() > 0)
            if mode == "first-wins-invalid" {
                try put(loose, projected, Data("{}".utf8))
                let view = SceneResourceView(projectRoot: .init(source: .loose, url: loose), packageRoot: root, stockRoot: nil)
                let selected = try view.literalEntry(relativePath: projected)!
                let bytes = try selected.readBytes()
                result["invalidFirstDoesNotRetryLaterOrLoose"] = selected.source == .package && bytes == reference
                    && rejects({ _ = try JSONSerialization.jsonObject(with: bytes) })
                    && observedBytes() == UInt64(reference.count * 3)
            }
        case "namespace-local":
            let opened = try ScenePkgReader().openPackage(packageURL: packageURL)
            try observePayload(opened)
            let root = try SceneResourceView.Root.package(openedPackage: opened)
            result["badUnconsumedNamesDoNotReadAnyPayload"] = observedBytes() == 0
            let names = Set(["scene.json", "materials/ok.tex"])
            result["badNamesAreOmittedWithoutDiscardingPackage"] = Set(root.packageBacking!.entries.keys) == names
                && Set(root.index.resources.map(\.relativePath)) == names
                && opened.index.entries.count > names.count
            result["unrelatedValidEntryStillPlays"] = try root.existingLiteralHandle(relativePath: "scene.json")!.readBytes() == Data("{}".utf8)
                && observedBytes() == 2
            result["unsafeQueryCannotReachOutsidePackage"] = rejects({
                _ = try root.existingLiteralHandle(relativePath: "../escape.bin")
            }, matching: { if case SceneResourceView.ReadError.symlinkEscape = $0 { return true }; return false })
        case "virtual-paths":
            let root = try mount(packageURL)
            try put(loose, "parent", Data("loose file".utf8))
            try put(loose, "only-dir", Data("loose directory substitute".utf8))
            try put(loose, "C:/folder/resource.bin", Data("loose drive name".utf8))
            try put(loose, "file:author.bin", Data("loose colon name".utf8))
            let author = SceneResourceView.Root(source: .loose, url: loose)
            let view = SceneResourceView(projectRoot: author, packageRoot: root, stockRoot: nil)
            result["fileAndDirectoryCanShareVirtualPrefix"] = try view.literalEntry(relativePath: "parent")!.readBytes() == Data("file".utf8)
                && view.literalEntry(relativePath: "parent/child.bin")!.readBytes() == Data("child".utf8)
            var directoriesStaySelected = true
            for path in ["parent/", "parent/.", "parent/sub/..", "parent/sub/../", "only-dir/"] {
                guard let selected = try view.literalEntry(relativePath: path) else { directoriesStaySelected = false; continue }
                directoriesStaySelected = directoriesStaySelected && selected.source == .package
                    && rejects({ _ = try selected.readBytes() }, matching: unreadable)
                    && rejects({ _ = try selected.currentIdentity() }, matching: unreadable)
            }
            result["directoryIntentNeverReadsSameNamedFileOrLowerRoot"] = directoriesStaySelected
            let bareDirectory = try root.existingLiteralHandle(relativePath: "only-dir")
            result["barePackageDirectoryDoesNotHideActualLooseFile"] = try bareDirectory != nil
                && rejects({ _ = try bareDirectory!.readBytes() }, matching: unreadable)
                && view.literalEntry(relativePath: "only-dir")?.source == .loose
                && view.literalEntry(relativePath: "only-dir")?.readBytes() == Data("loose directory substitute".utf8)
            let drive = view.resolvedResource(relativePath: "C:/folder/resource.bin")!
            let colon = view.resolvedResource(relativePath: "file:author.bin")!
            result["driveAndURLLikeNamesAreOnlyRelativePackageLeaves"] = try drive.source == .package
                && drive.readBytes(within: "C:") == Data("drive".utf8)
                && colon.source == .package && colon.readBytes() == Data("colon".utf8)
            result["sameNamesRemainRelativeInDirectoryRoot"] = try author.handle(relativePath: "C:/folder/resource.bin")!.readBytes() == Data("loose drive name".utf8)
                && author.handle(relativePath: "file:author.bin")!.readBytes() == Data("loose colon name".utf8)
            let outside = base.appendingPathComponent("external.bin")
            try Data("must not borrow".utf8).write(to: outside)
            let miss: (any Error) -> Bool = { if case SceneResourceView.ReadError.missing = $0 { return true }; return false }
            result["URLLikeSpellingCannotBorrowRootExternalFile"] = ["file:" + outside.path, "C:" + outside.path].allSatisfy { path in
                guard let handle = root.handle(relativePath: path) else { return false }
                return rejects({ _ = try handle.readBytes() }, matching: miss)
            }
            result["absoluteAndParentQueriesRemainOutsideNamespace"] = root.handle(relativePath: outside.path) == nil
                && root.handle(relativePath: "../external.bin") == nil
            try FileManager.default.createSymbolicLink(at: loose.appendingPathComponent("file:escape.bin"), withDestinationURL: outside)
            result["relativeColonDoesNotBypassDirectorySymlinkBoundary"] = rejects({
                _ = try author.handle(relativePath: "file:escape.bin")!.readBytes()
            }, matching: { if case SceneResourceView.ReadError.symlinkEscape = $0 { return true }; return false })
        case "range-local", "range-only-bad":
            let opened = try ScenePkgReader().openPackage(packageURL: packageURL)
            try observePayload(opened)
            let root = try SceneResourceView.Root.package(openedPackage: opened)
            result["mountProjectionReadsNoPayload"] = observedBytes() == 0 && observedCalls() == 0
            let safe = mode == "range-local" ? Set(["scene.json", "kept.bin", "zero-eof.bin"]) : Set<String>()
            result["onlySafeRangesReachEntriesAndIndex"] = Set(root.packageBacking!.entries.keys) == safe
                && Set(root.index.resources.map(\.relativePath)) == safe
            result["omittedRangesDoNotCreateDirectories"] = try root.packageBacking!.directories.isEmpty
                && root.existingLiteralHandle(relativePath: "bad") == nil
                && root.existingLiteralHandle(relativePath: "bad/") == nil
            var prepared = 0, consumed = 0
            for entry in opened.index.entries where !safe.contains(entry.path) {
                result["omitted-" + entry.path] = try root.existingLiteralHandle(relativePath: entry.path) == nil
                    && root.resource(relativePath: entry.path) == nil
                let probe = root.handle(relativePath: entry.path)!
                let missing: (any Error) -> Bool = { if case SceneResourceView.ReadError.missing = $0 { return true }; return false }
                result["no-identity-" + entry.path] = rejects({ _ = try probe.currentIdentity() }, matching: missing)
                result["no-read-" + entry.path] = rejects({
                    _ = try probe.readChunks(prepare: { _ in prepared += 1 }) { _ in consumed += 1 }
                }, matching: missing)
            }
            result["invalidRangesNeverPrepareReserveOrConsume"] = prepared == 0 && consumed == 0
                && observedBytes() == 0 && observedCalls() == 0
            if mode == "range-local" {
                result["validMainAndPeerRemainReadable"] = try root.existingLiteralHandle(relativePath: "scene.json")!.readBytes() == Data("{}".utf8)
                    && root.handle(relativePath: "kept.bin")!.readBytes() == Data("safe".utf8)
                let before = observedBytes(), calls = observedCalls()
                let empty = try root.existingLiteralHandle(relativePath: "zero-eof.bin")!
                let identity = try empty.currentIdentity()
                result["zeroBytesAtEOFRemainRealEntry"] = try identity.size == 0 && empty.readBytes().isEmpty
                    && observedBytes() == before && observedCalls() == calls
                result["ordinaryReadsTouchOnlySelectedValidRanges"] = observedBytes() == 6
            } else {
                let view = SceneResourceView(projectRoot: .init(source: .loose, url: loose), packageRoot: root, stockRoot: nil)
                result["badOnlyRootHasNoProjectedResourceOrDirectory"] = view.availableRelativePaths.isEmpty
                    && view.authorHandles.isEmpty && root.packageBacking!.entries.isEmpty
                    && root.packageBacking!.directories.isEmpty
            }
        case "stream-mutation":
            let root = try mount(packageURL)
            let handle = root.handle(relativePath: "unlisted/large.bin")!
            let package = root.packageBacking!.opened
            var chunks = 0
            result["readInFlightChangeIsHardFailure"] = rejects({
                _ = try handle.readChunks { _ in
                    chunks += 1
                    if chunks == 1 {
                        let writer = try FileHandle(forWritingTo: packageURL)
                        try writer.seek(toOffset: UInt64(package.index.dataStartOffset))
                        try writer.write(contentsOf: Data([0x58])); try writer.close()
                    }
                }
            }, matching: hard)
            result["mutationReachedActualStreamConsumer"] = chunks > 0
        case "overlap":
            let root = try mount(packageURL)
            let a = root.handle(relativePath: "first.bin")!, b = root.handle(relativePath: "second.bin")!
            result["overlappingRangesReadExactBytes"] = try a.readBytes() == Data("bytes".utf8) && b.readBytes() == Data("bytes".utf8)
            result["entryPathParticipatesInIdentity"] = try a.currentIdentity() != b.currentIdentity()
        default: fatalError("unknown mode")
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''



class ScenePackageResourceBackingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("swiftc"):
            raise unittest.SkipTest("swiftc unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-package-root-")
        cls.base = Path(cls.temporary.name)
        harness = cls.base / "Harness.swift"
        harness.write_text(HARNESS)
        cls.binary = cls.base / "probe"
        cls.source_hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in [*SOURCES, IO_OBSERVER, Path(make_package.__code__.co_filename).resolve()]}
        observer = cls.base / "entry-read-observer.dylib"
        cls.observer_command = ["xcrun", "clang", "-dynamiclib", "-std=c11", "-Wall", "-Wextra", "-Werror",
                                str(IO_OBSERVER), "-o", str(observer)]
        compiled_observer = subprocess.run(cls.observer_command, capture_output=True, text=True, timeout=60)
        if compiled_observer.returncode:
            cls.temporary.cleanup()
            raise AssertionError(compiled_observer.stdout + compiled_observer.stderr)
        cls.command = ["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                       "-default-isolation", "MainActor", "-parse-as-library", *map(str, SOURCES), str(harness),
                       str(observer), "-o", str(cls.binary)]
        completed = subprocess.run(cls.command, capture_output=True, text=True, timeout=120)
        if completed.returncode:
            cls.temporary.cleanup()
            raise AssertionError(completed.stdout + completed.stderr)
        cls.results = {}

    @classmethod
    def tearDownClass(cls):
        changed = [p for p, digest in cls.source_hashes.items() if hashlib.sha256((ROOT / p).read_bytes()).hexdigest() != digest]
        evidence = os.environ.get("MWX_PACKAGE_BACKING_TEST_EVIDENCE")
        if evidence:
            output = Path(evidence)
            output.mkdir(parents=True, exist_ok=True)
            (output / "result.json").write_text(json.dumps({"sourceHashes": cls.source_hashes,
                "changedPaths": changed, "observerCommand": cls.observer_command,
                "command": cls.command, "results": cls.results}, indent=2) + "\n")
        cls.temporary.cleanup()
        if changed:
            raise AssertionError(f"package backing inputs changed: {changed}")

    def check(self, mode, entries=None, package_bytes=None, first=None, reference_index=0):
        with tempfile.TemporaryDirectory(prefix="mwx-package-input-") as temporary:
            path = Path(temporary) / "scene.pkg"
            path.write_bytes(package_bytes if package_bytes is not None else make_package(entries or [("scene.json", b"{}")] ))
            command = [str(self.binary), mode, str(path)]
            if mode in ("first-wins", "first-wins-invalid"):
                raw_path, payload = first if first is not None else entries[0]
                expected = Path(temporary) / "expected.bin"
                expected.write_bytes(payload)
                command.extend([str(expected), raw_path, str(reference_index)])
            completed = subprocess.run(command, capture_output=True, text=True, timeout=25)
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            result = json.loads(completed.stdout)
            self.results.setdefault(mode, []).append(result)
            self.assertTrue(result and all(result.values()), result)

    def test_complete_namespace_typed_identity_root_precedence_and_sidecar(self):
        self.check("mount", [("materials\\odd.tex", b"raw backslash"),
            ("materials/odd.tex-json", b"package sidecar"), (".hidden/author.raw", b"hidden"),
            ("unlisted/unusual.bin", b"arbitrary"), ("fonts/custom.ttf", b"font")])

    def test_streaming_integrity_callback_identity_cancellation_and_fd_borrower(self):
        self.check("stream", [("unlisted/large.bin", b"abcdef" * 50_000)])

    def test_case_renames_conflicts_and_literal_dot_adjacency(self):
        self.check("literal", [("Shaders/renamed.vert", b"upper named"),
            ("Shaders/Probe.frag", b"upper exact"), ("shaders/probe.frag", b"lower exact"),
            ("Shaders/inner/proof.bin", b"directory"), ("ShadersElse/peer.vert", b"adjacent"),
            ("unused\\collision.bin", b"first ignored"), ("unused/collision.bin", b"different ignored content")])

    def test_current_package_revision_rejects_stale_and_accepts_new_bytes(self):
        self.check("revision", [("materials/bad.tex", b"original"), ("unlisted/still-valid.bin", b"unaffected")])

    def test_directory_current_bytes_unrelated_files_and_path_boundary(self):
        self.check("directory")

    def test_hidden_and_opaque_namespace_projection_retains_literal_reads(self):
        paths = [".hidden/leaf.bin", "opaque.bundle/leaf.bin", "opaque.app/leaf.bin",
                 "ordinary/leaf.bin", "opaque.framework/leaf.bin", "opaque.scnassets/leaf.bin", "opaque.unknownext/leaf.bin"]
        self.check("namespace", [(path, path.encode()) for path in paths])

    def test_managed_shader_groups_keep_same_root_stages_and_typed_source_order(self):
        self.check("shader", [("shaders/effects/renamed.frag", b"// package fragment\nvoid main() {}"),
            ("Shaders/CASE/renamed.vert", b"// renamed vertex\nvoid main() {}")])

    def test_same_target_aliases_use_first_entry_without_reading_later_payloads(self):
        groups = [[("renamed\\value.bin", b"first"), ("renamed/value.bin", b"later")],
                  [("renamed/value.bin", b"different size first"), ("renamed\\value.bin", b"x")],
                  [("textures/e\u0301.tex", b"decomposed first"), ("textures/é.tex", b"composed later")],
                  [("textures/é.tex", b"composed first"), ("textures/e\u0301.tex", b"decomposed later")],
                  [("empty.bin", b""), ("empty.bin", b"later nonempty")],
                  [("nonempty.bin", b"first"), ("nonempty.bin", b"")],
                  [("all-empty.bin", b""), ("all-empty.bin", b"")],
                  [("large\\picked.bin", b"a" * (192 * 1024 + 17)), ("large/picked.bin", b"b" * (320 * 1024))]]
        for entries in groups:
            for ordered in [entries, list(reversed(entries))]:
                with self.subTest(first=ordered[0][0], sizes=[len(payload) for _, payload in ordered]):
                    self.check("first-wins", ordered)

    def test_first_invalid_content_is_not_replaced_by_later_entry_or_loose_file(self):
        self.check("first-wins-invalid", [("scene.json", b"invalid json"), ("scene.json", b"{}")])

    def test_same_target_aliases_sharing_one_range_do_not_duplicate_reads(self):
        names = [b"renamed\\value.bin", b"renamed/value.bin", b"renamed/value.bin"]
        table = struct.pack("<I", 7) + b"PKGV001" + struct.pack("<I", len(names))
        for name in names:
            table += struct.pack("<I", len(name)) + name + struct.pack("<II", 0, 5)
        self.check("first-wins", package_bytes=table + b"bytes", first=(names[0].decode(), b"bytes"))

    def test_unsafe_stored_names_are_omitted_without_hiding_valid_entries(self):
        unsafe = ["../escape.bin", "/absolute.bin", "\\absolute.bin", "a//empty.bin",
                  "a/./dot.bin", "a/../parent.bin", "nul\0leaf.bin", "trailing/"]
        for safe_first in (False, True):
            safe = [("scene.json", b"{}"), ("materials/ok.tex", b"playable")]
            ignored = [(path, b"ignored payload") for path in unsafe]
            self.check("namespace-local", safe + ignored if safe_first else ignored + safe)

    def test_virtual_file_directory_conflicts_and_url_like_relative_names_keep_root_boundaries(self):
        entries = [("parent", b"file"), ("parent/child.bin", b"child"), ("parent/sub/proof.bin", b"proof"),
                   ("only-dir/child.bin", b"directory"), ("C:/folder/resource.bin", b"drive"), ("file:author.bin", b"colon")]
        for ordered in [entries, list(reversed(entries))]:
            self.check("virtual-paths", ordered)

    @staticmethod
    def payload_ranges(entries, overrides):
        data = bytearray(make_package(entries))
        cursor = 4 + struct.unpack_from("<I", data, 0)[0] + 4
        for position, (path, _) in enumerate(entries):
            length = struct.unpack_from("<I", data, cursor)[0]
            cursor += 4 + length
            if position in overrides:
                struct.pack_into("<II", data, cursor, *overrides[position])
            cursor += 8
        return bytes(data)

    def test_unavailable_payload_ranges_are_omitted_before_namespace_identity_and_prepare(self):
        bad = [("bad/offset.bin", b"unused"), ("bad/size.bin", b"unused"),
               ("bad/both.bin", b"unused"), ("bad/past-eof.bin", b"unused")]
        for has_safe in (False, True):
            entries = ([("scene.json", b"{}"), ("kept.bin", b"safe")] if has_safe else []) + bad + (
                [("zero-eof.bin", b"")] if has_safe else [])
            payload_size = sum(len(payload) for _, payload in entries)
            first = 2 if has_safe else 0
            overrides = {first: (payload_size + 1, 0), first + 1: (0, payload_size + 1),
                         first + 2: (0xFFFFFFFF, 0xFFFFFFFF), first + 3: (payload_size, 1)}
            self.check("range-local" if has_safe else "range-only-bad",
                       package_bytes=self.payload_ranges(entries, overrides))

    def test_first_safe_alias_wins_after_unreadable_metadata_without_reading_other_payloads(self):
        entries = [("renamed\\value.bin", b"bad metadata payload"), ("renamed/value.bin", b"safe"),
                   ("renamed\\value.bin", b"later safe alias")]
        data = self.payload_ranges(entries, {0: (0xFFFFFFFF, 1)})
        self.check("first-wins", package_bytes=data, first=entries[1], reference_index=1)

    def test_streaming_source_change_is_not_downgraded_to_an_ordinary_resource_error(self):
        self.check("stream-mutation", [("unlisted/large.bin", b"a" * (192 * 1024))])

    def test_overlapping_ranges_remain_independent_resources(self):
        names = [b"first.bin", b"second.bin"]
        table = struct.pack("<I", 7) + b"PKGV001" + struct.pack("<I", 2)
        for name in names:
            table += struct.pack("<I", len(name)) + name + struct.pack("<II", 0, 5)
        self.check("overlap", package_bytes=table + b"bytes")



if __name__ == "__main__":
    unittest.main()
