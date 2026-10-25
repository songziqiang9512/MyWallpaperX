"""Real directory/external texture byte identity; CPU only, no Metal device."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from .test_scene_image_upload_completion import LOADER_SOURCES, RESAMPLE_SOURCE, SOURCE

SOURCES = [*LOADER_SOURCES, SOURCE, RESAMPLE_SOURCE]
HARNESS = r'''
import Foundation
import CoreGraphics
import ImageIO
import Darwin

enum TextureMetadataProbe { static var calls = 0 }

@main enum Checks {
    enum Stop: Error { case cancelled }
    static func opened(_ url: URL) -> Bool {
        let target = url.resolvingSymlinksInPath().standardizedFileURL.path
        for descriptor in 3..<256 {
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            if fcntl(Int32(descriptor), F_GETPATH, &buffer) == 0,
               URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath().standardizedFileURL.path == target { return true }
        }
        return false
    }
    static func png(width: Int, height: Int) throws -> Data {
        let bytes = Data(repeating: 255, count: width * height * 4)
        let image = CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: CGDataProvider(data: bytes as CFData)!, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent)!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }
    static func tex(payload: Data = Data(repeating: 40, count: 16)) -> Data {
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        func append(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        for value: UInt32 in [0, 2, 2, 2, 2, 2, 0] { append(value) }
        data.append(Data("TEXB0001\0".utf8))
        for value: UInt32 in [1, 1, 2, 2, UInt32(payload.count)] { append(value) }
        data.append(payload)
        return data
    }
    static func changed(_ operation: () throws -> Void) -> Bool {
        do { try operation(); return false }
        catch SceneResourceView.ReadError.sourceChanged { return true }
        catch { return false }
    }
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let fm = FileManager.default
        let author = directory.appendingPathComponent("author")
        let lower = directory.appendingPathComponent("lower")
        try fm.createDirectory(at: author, withIntermediateDirectories: true)
        try fm.createDirectory(at: lower, withIntermediateDirectories: true)
        let url = author.appendingPathComponent("renamed-Ä.tex")
        let bytes = tex()
        try bytes.write(to: url)
        try tex(payload: Data(repeating: 90, count: 16)).write(to: lower.appendingPathComponent(url.lastPathComponent))
        let view = SceneResourceView(projectRootURL: lower, packageRootURL: author, stockAssetsRootURL: nil)
        let input = SceneTextureLoader.Input.resource(view.resolvedResource(relativePath: url.lastPathComponent)!)
        let budget = SceneTextureDecodeCacheBudget(maximumBytes: 0)
        let queue = SceneTextureUploadCommandQueue()
        let loader = SceneTextureLoader(uploadCommandQueue: queue, decodeCacheBudget: budget)
        var result: [String: Bool] = [:]
        let source = try loader.sourceKey(for: input)!
        let snapshot = try input.readSnapshot(expectedIdentity: source)
        result["snapshotIdentityAndBytes"] = snapshot.identity == source && snapshot.data == bytes
        TextureMetadataProbe.calls = 0
        let prepared = try loader.prepareTexSource(from: input)!
        result["texPreparationQueriesIdentityOnce"] = TextureMetadataProbe.calls == 1
        result["deniedAdmissionStillServesRequest"] = prepared.source == source &&
            prepared.input == input && prepared.container?.mips.first?.data == Data(repeating: 40, count: 16) &&
            budget.residentBytes == 0 && budget.rejectionCount == 1
        result["preparedVideoProbeDoesNotReparse"] = try loader.videoSourceDeclaration(from: prepared) == nil
            && budget.rejectionCount == 1 && TextureMetadataProbe.calls == 1
        try bytes.write(to: url, options: .atomic)
        result["completedSnapshotDoesNotRequeryLaterAuthorRevision"] =
            try loader.videoSourceDeclaration(from: prepared) == nil && TextureMetadataProbe.calls == 1
        result["staleExpectedHardFailure"] = changed { _ = try loader.prepareTexSource(from: input, source: source) }
        result["newOperationRecovers"] = try loader.texContainer(from: input)?.mips.first?.data == Data(repeating: 40, count: 16)
        try Data("malformed author TEX".utf8).write(to: url, options: .atomic)
        let invalid = try loader.prepareTexSource(from: input)
        result["selectedInvalidNeverFallsBack"] = invalid != nil && invalid?.container == nil
        let missing = SceneTextureLoader.Input.resource(view.roots[0].handle(relativePath: "missing.tex")!)
        result["missingIsLocal"] = try loader.sourceKey(for: missing) == nil && loader.texContainer(from: missing) == nil
        do { _ = try loader.prepareTexSource(from: input, checkCancellation: { throw Stop.cancelled }) }
        catch Stop.cancelled { result["originalCancellationPropagates"] = true }
        do { try SceneTextureLoadOutcome.resourceReadFailed(Stop.cancelled).rethrowResourceReadFailure() }
        catch Stop.cancelled { result["outcomeTransportsOriginalError"] = true }
        try SceneTextureLoadOutcome.decodeFailed("ordinary").rethrowResourceReadFailure()
        result["ordinaryOutcomeIsLocal"] = true
        let imageURL = author.appendingPathComponent("other-name.png")
        let imageBytes = try png(width: 20, height: 10)
        try imageBytes.write(to: imageURL)
        let imageInput = SceneTextureLoader.Input.resource(view.roots[0].handle(relativePath: imageURL.lastPathComponent)!)
        let imageSource = try loader.sourceKey(for: imageInput)!
        let native = try loader.preparedNaturalImageSize(from: imageInput, source: imageSource)
        var warmOpenedPayload = false
        let again = try loader.preparedNaturalImageSize(from: imageInput, source: imageSource,
            checkCancellation: { warmOpenedPayload = warmOpenedPayload || opened(imageURL) })
        result["naturalHeaderCacheWithoutPayloadOpen"] = native == CGSize(width: 20, height: 10) &&
            again == native && !warmOpenedPayload && loader.directImageDecodeAttemptCount == 0
        TextureMetadataProbe.calls = 0
        let direct = try loader.prepareDirectImageSource(from: imageInput, source: imageSource)!
        result["directPreparationQueriesIdentityOnce"] = TextureMetadataProbe.calls == 1
        var preparedOpenedPayload = false
        let directSize = try loader.preparedNaturalImageSize(from: direct,
            checkCancellation: { preparedOpenedPayload = preparedOpenedPayload || opened(imageURL) })
        result["directPreparedHeaderSharesCapture"] = direct.input == imageInput && direct.source == imageSource &&
            directSize == native && !preparedOpenedPayload && loader.directImageDecodeAttemptCount == 0
            && TextureMetadataProbe.calls == 1
        result["directDeniedRetentionStillHasCurrentHeader"] = !direct.admitForPreparation() &&
            budget.residentBytes == 0 && directSize == CGSize(width: 20, height: 10)
        let retainedBudget = SceneTextureDecodeCacheBudget(maximumBytes: imageBytes.count)
        let retainedLoader = SceneTextureLoader(decodeCacheBudget: retainedBudget)
        var retained: SceneTextureLoader.PreparedDirectImageSource? = try retainedLoader.prepareDirectImageSource(from: imageInput)
        let admitted = retained!.admitForPreparation()
        let readmitted = retained!.admitForPreparation()
        result["retainedSourceBytesAdmittedOnce"] = admitted && readmitted && retainedBudget.residentBytes == imageBytes.count
        retained = nil
        result["retainedSourceLeaseReleased"] = retainedBudget.residentBytes == 0
        loader.evictDecodedCaches()
        var replaced = false
        result["openedFDReplacementRejectsHeader"] = changed {
            _ = try loader.preparedNaturalImageSize(from: imageInput, source: imageSource,
                checkCancellation: {
                    if !replaced && opened(imageURL) {
                        replaced = true
                        try png(width: 30, height: 15).write(to: imageURL, options: .atomic)
                    }
                })
        } && replaced
        TextureMetadataProbe.calls = 0
        result["completedDirectHeaderSurvivesLaterAuthorRevision"] =
            try loader.preparedNaturalImageSize(from: direct) == CGSize(width: 20, height: 10)
            && TextureMetadataProbe.calls == 0
        let renewed = try loader.sourceKey(for: imageInput)!
        result["headerRecoversWithNewIdentity"] = try loader.preparedNaturalImageSize(from: imageInput, source: renewed) == CGSize(width: 30, height: 15)
        let external = SceneTextureLoader.Input.externalFile(imageURL)
        result["explicitExternalDomain"] = try loader.sourceKey(for: external) == renewed &&
            loader.preparedNaturalImageSize(from: external, source: renewed) == CGSize(width: 30, height: 15)
        try Data("bad PNG".utf8).write(to: imageURL, options: .atomic)
        result["invalidImageHeaderIsLocal"] = try loader.preparedNaturalImageSize(from: imageInput,
            source: loader.sourceKey(for: imageInput)!) == nil
        let alias = directory.appendingPathComponent("root-alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: author)
        let aliasRoot = SceneResourceView.Root(source: .loose, url: alias)
        let aliasInput = SceneTextureLoader.Input.resource(aliasRoot.handle(relativePath: url.lastPathComponent)!)
        _ = try loader.sourceKey(for: aliasInput)
        try fm.removeItem(at: alias)
        try fm.createSymbolicLink(at: alias, withDestinationURL: lower)
        result["selectedRootRetargetNeverFallsBack"] = changed { _ = try loader.texContainer(from: aliasInput) }
        let escape = author.appendingPathComponent("escape.tex")
        try fm.createSymbolicLink(at: escape, withDestinationURL: lower.appendingPathComponent(url.lastPathComponent))
        do { _ = try loader.texContainer(from: .resource(view.roots[0].handle(relativePath: "escape.tex")!)) }
        catch SceneResourceView.ReadError.symlinkEscape { result["escapeIsHard"] = true }
        // Physical revision keys permit current author bytes across independent
        // handles without letting a previous revision label a new cache fill.
        let shared = author.appendingPathComponent("certified.tex")
        let approved = tex(payload: Data(repeating: 40, count: 16))
        let changedBytes = tex(payload: Data(repeating: 90, count: 16))
        try approved.write(to: shared)
        let currentRoot = SceneResourceView.Root(source: .loose, url: author)
        let currentInput = SceneTextureLoader.Input.resource(currentRoot.handle(relativePath: shared.lastPathComponent)!)
        let cachedLoader = SceneTextureLoader(decodeCacheBudget: .init(maximumBytes: 4_096))
        let keyA = try cachedLoader.sourceKey(for: currentInput)!
        let externalA = try cachedLoader.texContainer(from: .externalFile(shared))
        let acceptedA = try cachedLoader.texContainer(from: currentInput)
        result["samePhysicalRevisionSharesCurrentCache"] = externalA?.mips.first?.data == Data(repeating: 40, count: 16)
            && acceptedA?.mips.first?.data == externalA?.mips.first?.data
        try changedBytes.write(to: shared, options: .atomic)
        let externalB = try cachedLoader.texContainer(from: .externalFile(shared))
        result["sameLengthReplacementHasNewRevision"] = try approved.count == changedBytes.count
            && externalB?.mips.first?.data == Data(repeating: 90, count: 16)
            && cachedLoader.sourceKey(for: currentInput) != keyA
        result["staleExpectedRevisionCannotHitNewPayload"] = changed {
            _ = try cachedLoader.prepareTexSource(from: currentInput, source: keyA)
        }
        result["currentAuthorRevisionIsPlayable"] = try cachedLoader.texContainer(from: currentInput)?.mips.first?.data == Data(repeating: 90, count: 16)
        TextureMetadataProbe.calls = 0
        _ = try cachedLoader.prepareTexSource(from: currentInput)
        result["warmTexPreparationQueriesIdentityOnce"] = TextureMetadataProbe.calls == 1
        let videoURL = author.appendingPathComponent("captured-video.tex")
        let videoPayload = Data([0, 0, 0, 20, 102, 116, 121, 112]) + Data(repeating: 0, count: 16)
        try tex(payload: videoPayload).write(to: videoURL)
        let video = try loader.prepareTexSource(from: videoURL)!
        try Data("later author contents".utf8).write(to: videoURL, options: .atomic)
        TextureMetadataProbe.calls = 0
        let declaration = try loader.videoSourceDeclaration(from: video)
        result["completedVideoPayloadUsesCapturedBytesWithoutMetadata"] = declaration?.payload == videoPayload
            && declaration?.source == video.source && TextureMetadataProbe.calls == 0
        result["noGPUOrDecodedImage"] = queue.creationAttemptCount == 0 && loader.directImageDecodeAttemptCount == 0
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneTextureResourceInputTests(unittest.TestCase):
    def test_actual_loader_reads_selected_input_with_typed_failures(self):
        before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCES}
        with tempfile.TemporaryDirectory(prefix="mwx-texture-resource-input-") as directory:
            root = Path(directory)
            harness = root / "Checks.swift"
            harness.write_text(HARNESS)
            loader_source = next(path for path in SOURCES if path.name == "SceneTextureLoader.swift")
            counted_loader = root / loader_source.name
            counted_loader.write_text(loader_source.read_text().replace(
                "static func currentSourceKey(for input: Input, checkCancellation: (() throws -> Void)? = nil) throws -> SourceKey? {",
                "static func currentSourceKey(for input: Input, checkCancellation: (() throws -> Void)? = nil) throws -> SourceKey? {\n        TextureMetadataProbe.calls += 1", 1))
            sources = [counted_loader if path == loader_source else path for path in SOURCES]
            binary = root / "checks"
            build = subprocess.run(["xcrun", "swiftc", *map(str, sources), str(harness),
                "-module-cache-path", str(root / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary), str(root / "inputs")], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            facts = json.loads(run.stdout)
            required = {"snapshotIdentityAndBytes", "naturalHeaderCacheWithoutPayloadOpen",
                        "selectedInvalidNeverFallsBack", "currentAuthorRevisionIsPlayable"}
            self.assertTrue(required.issubset(facts), facts)
            self.assertTrue(all(facts.values()), facts)
        self.assertEqual(before, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCES})
