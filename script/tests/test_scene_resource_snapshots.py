"""Validated Scene directory snapshots and explicit external-file inputs; CPU only."""
from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
ASSETS = REPO / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets"
SOURCES = [REPO / "MyWallpaperX/Core/SteamWorkshopStorage/ScenePlaybackSource.swift",
           REPO / "MyWallpaperX/Core/SteamWorkshopScene/Format/ScenePkgReader.swift",
           *[ASSETS / name for name in ("SceneResourceIdentity.swift", "SceneResourceIndex.swift",
                                      "SceneResourceView.swift", "SceneResourceView+Backing.swift")]]

HARNESS = r'''
import Foundation
import Darwin

@main enum SnapshotProbe {
    enum Cancel: Error { case requested }
    static func put(_ url: URL, _ bytes: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url, options: .atomic)
    }
    static func opened(_ url: URL) -> Bool {
        let expected = url.resolvingSymlinksInPath().standardizedFileURL.path
        for fd: Int32 in 0..<512 {
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            if fcntl(fd, F_GETPATH, &path) == 0,
               URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().standardizedFileURL.path == expected {
                return true
            }
        }
        return false
    }
    static func main() throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1])
        let author = base.appendingPathComponent("author"), outside = base.appendingPathComponent("external")
        let file = author.appendingPathComponent("images/selected.bin")
        let first = Data(repeating: 0x31, count: 150_000)
        try put(file, first)
        let root = SceneResourceView.Root(source: .loose, url: author)
        let handle = root.handle(relativePath: "images/selected.bin")!
        let input = SceneResourceView.FileInput.resource(handle)
        let key = try input.currentIdentity()
        let snapshot = try input.readSnapshot(expectedIdentity: key)
        var checks = [
            "snapshotBytesBelongToExpectedIdentity": snapshot.data == first && snapshot.identity == key,
            "directoryRevisionMatchesActualExternalFileRevision": try SceneResourceView.FileInput.externalFile(file).currentIdentity() == snapshot.identity,
            "resourceInputRetainsSameSelectedOwner": input == .resource(handle),
            "inputDomainsAreDistinct": input != .externalFile(file),
            "sourceReferenceIdentityDoesNotCertifyEqualDirectoryObjects": input != .resource(
                SceneResourceView.Root(source: .loose, url: author).handle(relativePath: "images/selected.bin")!),
            "diagnosticDoesNotChangeSelectedBytes": input.pathExtension == "bin" && input.lastPathComponent == "selected.bin",
            "snapshotClosesOwnedDescriptor": !opened(file),
        ]
        var chunks = Data(), chunkSizes: [Int] = []
        let streamedIdentity = try handle.readChunks { chunk in
            chunks.append(chunk); chunkSizes.append(chunk.count)
        }
        checks["streamAndSnapshotUseSameOpenedRevisionAndBytes"] = chunks == snapshot.data && streamedIdentity == key
        checks["streamAllocationIsBoundedTo64KiB"] = chunkSizes.count >= 3
            && chunkSizes.allSatisfy { $0 > 0 && $0 <= 65_536 }
        checks["streamClosesOwnedDescriptor"] = !opened(file)
        do {
            _ = try handle.readChunks { _ in throw Cancel.requested }
            checks["streamSinkErrorPropagatesUnchanged"] = false
        } catch Cancel.requested { checks["streamSinkErrorPropagatesUnchanged"] = true }
        checks["sinkFailureClosesOwnedDescriptor"] = !opened(file)
        var streamedBeforeCancellation = 0
        do {
            _ = try handle.readChunks(checkCancellation: {
                if streamedBeforeCancellation > 0 { throw Cancel.requested }
            }) { streamedBeforeCancellation += $0.count }
            checks["streamCancellationAfterFirstChunkPropagates"] = false
        } catch Cancel.requested {
            checks["streamCancellationAfterFirstChunkPropagates"] = (1...65_536).contains(streamedBeforeCancellation)
        }
        checks["streamCancellationClosesOwnedDescriptor"] = !opened(file)
        var budgetSinkCalled = false
        do {
            _ = try handle.readChunks(maximumBytes: first.count - 1) { _ in budgetSinkCalled = true }
            checks["streamBudgetRejectsBeforeSink"] = false
        } catch SceneResourceView.ReadError.fileTooLarge {
            checks["streamBudgetRejectsBeforeSink"] = !budgetSinkCalled
        }
        var replacedDuringStream = false
        do {
            _ = try handle.readChunks { _ in
                if !replacedDuringStream {
                    try put(file, first); replacedDuringStream = true
                }
            }
            checks["streamCannotCertifyBytesAfterSelectedPathReplacement"] = false
        } catch SceneResourceView.ReadError.sourceChanged {
            checks["streamCannotCertifyBytesAfterSelectedPathReplacement"] = replacedDuringStream
        }
        checks["streamSourceChangeClosesOwnedDescriptor"] = !opened(file)
        // The next original snapshot checks still use the actual initial key.
        // A failed streaming consumer must not mutate any already returned data.
        checks["failedStreamDoesNotMutatePriorSnapshot"] = snapshot.data == first
        let next = Data(repeating: 0x32, count: first.count)
        try put(file, next)
        let changed = try input.currentIdentity()
        checks["sameSizeReplacementChangesRevision"] = changed != key && changed.size == key.size
        do {
            _ = try input.readSnapshot(expectedIdentity: key)
            checks["oldCacheKeyCannotLabelNewBytes"] = false
        } catch SceneResourceView.ReadError.sourceChanged { checks["oldCacheKeyCannotLabelNewBytes"] = true }
        let refreshed = try input.readSnapshot(expectedIdentity: changed)
        checks["nextRequestRecoversWithoutPoisonedRoot"] = refreshed.data == next && refreshed.identity == changed
        let snapshotBeforeEdit = refreshed
        try put(file, Data("shorter".utf8))
        checks["returnedSnapshotOwnsItsBytesAcrossLaterEdit"] = snapshotBeforeEdit.data == next
        do {
            _ = try input.readSnapshot(maximumBytes: 6)
            checks["explicitReadBudgetRejectsOversize"] = false
        } catch SceneResourceView.ReadError.fileTooLarge { checks["explicitReadBudgetRejectsOversize"] = true }
        var didCancelOnFD = false
        do {
            _ = try input.readSnapshot(checkCancellation: {
                if opened(file) { didCancelOnFD = true; throw Cancel.requested }
            })
            checks["originalCancellationAfterOpenPropagates"] = false
        } catch Cancel.requested { checks["originalCancellationAfterOpenPropagates"] = didCancelOnFD }
        checks["cancelClosesOwnedDescriptor"] = !opened(file)
        checks["cancelDoesNotPoisonNextRequest"] = try input.readSnapshot().data == Data("shorter".utf8)
        var changedOnFD = false
        do {
            _ = try input.readSnapshot(checkCancellation: {
                if !changedOnFD && opened(file) {
                    try put(file, Data("new selected path".utf8)); changedOnFD = true
                }
            })
            checks["openedPathReplacementCannotPublishSnapshot"] = false
        } catch SceneResourceView.ReadError.sourceChanged {
            checks["openedPathReplacementCannotPublishSnapshot"] = changedOnFD
        }
        checks["sourceChangeClosesOwnedDescriptor"] = !opened(file)
        let siblingFile = author.appendingPathComponent("images/selected.bin-json")
        try put(siblingFile, Data("same root sibling".utf8))
        let sibling = try input.sibling(appendingSuffix: "-json")
        checks["fileInputSiblingUsesSameRootReadOwner"] = try sibling.readSnapshot().data == Data("same root sibling".utf8)
        let outsideFile = outside.appendingPathComponent("real.bin")
        try put(outsideFile, Data("authorized outside file".utf8))
        let alias = author.appendingPathComponent("images/external-link.bin")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: outsideFile)
        let external = SceneResourceView.FileInput.externalFile(alias)
        let externalSnapshot = try external.readSnapshot()
        if case let .file(fileIdentity) = externalSnapshot.identity {
            checks["explicitExternalInputKeepsExistingSymlinkSemantics"] = externalSnapshot.data == Data("authorized outside file".utf8)
                && fileIdentity.path == outsideFile.resolvingSymlinksInPath().standardizedFileURL.path
        } else { checks["explicitExternalInputKeepsExistingSymlinkSemantics"] = false }
        do {
            _ = try root.handle(relativePath: "images/external-link.bin", exact: true)!.readSnapshot()
            checks["externalAdapterDoesNotAuthorizeAuthoredEscape"] = false
        } catch SceneResourceView.ReadError.symlinkEscape {
            checks["externalAdapterDoesNotAuthorizeAuthoredEscape"] = true
        }
        let externalSidecar = outside.appendingPathComponent("real.bin-json")
        try put(externalSidecar, Data("external metadata".utf8))
        checks["externalSiblingPreservesLiteralAliasPath"] = try external.sibling(appendingSuffix: "-json").diagnosticPath == alias.path + "-json"
        do {
            _ = try SceneResourceView.FileInput.externalFile(outside.appendingPathComponent("missing.bin")).readSnapshot()
            checks["ordinaryExternalMissingIsUnreadable"] = false
        } catch SceneResourceView.ReadError.unreadable { checks["ordinaryExternalMissingIsUnreadable"] = true }
        do {
            _ = try external.readSnapshot(checkCancellation: { throw Cancel.requested })
            checks["externalCancellationIsNotTranslatedToReadFailure"] = false
        } catch Cancel.requested { checks["externalCancellationIsNotTranslatedToReadFailure"] = true }
        try put(author.appendingPathComponent("inner/child/placeholder"), Data())
        try put(author.appendingPathComponent("inner/node.bin"), Data("kernel target".utf8))
        try put(author.appendingPathComponent("node.bin"), Data("lexical peer".utf8))
        let pivot = author.appendingPathComponent("pivot")
        try FileManager.default.createSymbolicLink(at: pivot, withDestinationURL: author.appendingPathComponent("inner/child"))
        let literal = SceneResourceView.FileInput.resource(try root.existingLiteralHandle(relativePath: "pivot/../node.bin")!)
        do {
            let literalKey = try literal.currentIdentity()
            let literalSnapshot = try literal.readSnapshot(expectedIdentity: literalKey)
            if case let .file(fileIdentity) = literalKey {
                checks["literalDotIdentityAndSnapshotDescribeActualKernelTarget"] =
                    literalSnapshot.data == Data("kernel target".utf8) && literalSnapshot.identity == literalKey
                    && fileIdentity.path == author.appendingPathComponent("inner/node.bin").resolvingSymlinksInPath().standardizedFileURL.path
            } else { checks["literalDotIdentityAndSnapshotDescribeActualKernelTarget"] = false }
        } catch { checks["literalDotIdentityAndSnapshotDescribeActualKernelTarget"] = false }
        try put(outside.appendingPathComponent("child/placeholder"), Data())
        try put(outside.appendingPathComponent("node.bin"), Data("outside target".utf8))
        try FileManager.default.removeItem(at: pivot)
        try FileManager.default.createSymbolicLink(at: pivot, withDestinationURL: outside.appendingPathComponent("child"))
        do {
            _ = try literal.currentIdentity()
            checks["literalDotMetadataCannotAuthorizeActualRootEscape"] = false
        } catch SceneResourceView.ReadError.symlinkEscape {
            checks["literalDotMetadataCannotAuthorizeActualRootEscape"] = true
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneResourceSnapshotTests(unittest.TestCase):
    def test_real_identity_byte_snapshot_and_external_boundary(self):
        if shutil.which("xcrun") is None:
            self.skipTest("Xcode tools unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-resource-snapshot-") as temporary:
            work = Path(temporary)
            harness, binary = work / "Harness.swift", work / "probe"
            harness.write_text(HARNESS)
            built = subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                *map(str, SOURCES), str(harness), "-module-cache-path", str(work / "module-cache"), "-o", str(binary)],
                cwd=REPO, capture_output=True, text=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            ran = subprocess.run([str(binary), str(work / "fixtures")], capture_output=True, text=True, timeout=30)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            result = json.loads(ran.stdout)
            self.assertGreaterEqual(len(result), 20)
            for name, passed in result.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True)


if __name__ == "__main__":
    unittest.main()
