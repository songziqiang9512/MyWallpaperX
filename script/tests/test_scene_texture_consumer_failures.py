"""Execute preparation/deferred owners with real Root and controlled decode/Metal.

No Metal framework/device, GPU command, App or decoder is used. The existing
preparation fixture supplies controlled products; the entire production owner
and resolver execute against the actual Root/Index identity implementation.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_prepared_base_image_resources as prepared


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"

METAL = r'''
import Foundation
extension CGSize {
    init(width: Int, height: Int) { self.init(width: Double(width), height: Double(height)) }
}
enum MTLPixelFormat { case rgba8Unorm, rgba16Float }
enum MTLColorWriteMask { case all }
enum TestStorage { case shared }
final class MTLTextureDescriptor {
    let width: Int, height: Int
    var storageMode = TestStorage.shared
    init(_ width: Int, _ height: Int) { self.width = width; self.height = height }
    static func texture2DDescriptor(pixelFormat: MTLPixelFormat, width: Int,
        height: Int, mipmapped: Bool) -> MTLTextureDescriptor { .init(width, height) }
}
final class MTLTexture {
    let width: Int, height: Int
    init(_ descriptor: MTLTextureDescriptor) { width = descriptor.width; height = descriptor.height }
}
final class MTLDevice {
    let registryID: UInt64 = 7
    func makeTexture(descriptor: MTLTextureDescriptor) -> MTLTexture? { .init(descriptor) }
}
'''

HARNESS = r'''
import Foundation

@main enum ConsumerChecks {
    enum Cancel: Error { case requested }
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let device = MTLDevice()
        var checks: [String: Bool] = [:]
        let descriptor = SceneRenderDescriptor(layers: [.init(id: 1)], materialPasses: [
            .init(materialPath: "materials/shared.json", texturePaths: ["materials/canonical.png"],
                  textureSlots: ["materials/canonical.png"])
        ])
        func folder(_ name: String, file: String = "canonical.png") throws -> URL {
            let value = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: value.appendingPathComponent("materials"),
                withIntermediateDirectories: true)
            try Data("A".utf8).write(to: value.appendingPathComponent("materials/" + file))
            return value
        }
        func prepare(_ view: SceneResourceView, deferred: Set<Int> = [],
                     descriptor value: SceneRenderDescriptor? = nil,
                     cancel: () throws -> Void = {}) throws -> ScenePreparedBaseImageResources {
            try ScenePreparedBaseImageResources.prepare(descriptor: value ?? descriptor, resourceView: view,
                device: device, spriteTextureLoader: .init(), sceneGeneration: 1,
                deferredBaseImageLayerIDs: deferred, cancellationCheck: cancel)
        }
        func input(_ view: SceneResourceView) -> SceneResourceView.FileInput {
            SceneTexturePathResolver(resourceView: view, descriptor: descriptor)
                .resolvePrimaryTexture(for: descriptor.layers[0])!
        }
        func resourceFailure(_ outcome: SceneBaseImageTextureLoad.Outcome?) -> Bool {
            guard case .failed(.resourceReadFailed)? = outcome else { return false }
            return true
        }
        let a = try folder("A"), b = try folder("B")
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: a)
        let aliasedRoot = SceneResourceView.Root(source: .loose, url: alias,
            index: SceneResourceIndexBuilder().build(rootURL: a))
        let aliased = SceneResourceView(projectRoot: aliasedRoot, packageRootURL: nil)
        let beforeAliasLoads = SceneTextureLoader.totalLoadCount
        SceneTextureLoader.sourceHook = {
            SceneTextureLoader.sourceHook = nil
            try FileManager.default.removeItem(at: alias)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: b)
        }
        do { _ = try prepare(aliased); checks["realRootAliasFailureEscapesPrepare"] = false }
        catch SceneResourceView.ReadError.sourceChanged { checks["realRootAliasFailureEscapesPrepare"] = true }
        checks["aliasFailureDoesNotStartInlineDecode"] = SceneTextureLoader.totalLoadCount == beforeAliasLoads

        let stable = try folder("stable")
        let view = SceneResourceView(projectRootURL: stable, packageRootURL: nil, stockAssetsRootURL: nil)
        do { _ = try prepare(view, cancel: { throw Cancel.requested }); checks["originalCancelEscapesPrepare"] = false }
        catch Cancel.requested { checks["originalCancelEscapesPrepare"] = true }
        let healthy = try prepare(view)
        let old = healthy.outcome(for: 1, url: input(view), device: device)
        checks["healthyPreparePublishes"] = { if case .loaded? = old { return true }; return false }()
        try Data("B changed".utf8).write(to: stable.appendingPathComponent("materials/canonical.png"), options: .atomic)
        checks["completedProductSurvivesLaterAuthorWrite"] = {
            if case .loaded? = healthy.outcome(for: 1, url: input(view), device: device) { return true }; return false
        }()
        checks["failedLookupDoesNotMutateCompletedProduct"] = {
            if case let .loaded(value)? = old { return value.texture.width == 2 }; return false
        }()

        let racing = try folder("racing")
        let racingView = SceneResourceView(projectRootURL: racing, packageRootURL: nil, stockAssetsRootURL: nil)
        SceneTextureLoader.loadHook = {
            SceneTextureLoader.loadHook = nil
            try! Data("new source during decode".utf8).write(
                to: racing.appendingPathComponent("materials/canonical.png"), options: .atomic)
        }
        let racingProduct = try prepare(racingView)
        checks["completedCaptureSurvivesAuthorWriteDuringUpload"] = {
            if case .loaded? = racingProduct.outcome(for: 1, url: input(racingView), device: device) { return true }; return false
        }()

        let deferredRoot = try folder("deferred")
        let deferredView = SceneResourceView(projectRootURL: deferredRoot, packageRootURL: nil, stockAssetsRootURL: nil)
        let deferred = try prepare(deferredView, deferred: [1])
        let beforeDeferred = SceneTextureLoader.totalLoadCount
        try Data("new deferred revision".utf8).write(
            to: deferredRoot.appendingPathComponent("materials/canonical.png"), options: .atomic)
        _ = deferred.requestDeferredBaseImage(layerID: 1, requestGeneration: 2)
        let deadline = Date().addingTimeInterval(2)
        while deferred.deferredStatus(for: 1) == .pending || deferred.deferredStatus(for: 1) == .loading {
            if Date() > deadline { break }; Thread.sleep(forTimeInterval: 0.001)
        }
        checks["staleDeferredRejectsBeforeDecode"] = deferred.deferredStatus(for: 1) == .failed("resource-read-failed")
            && SceneTextureLoader.totalLoadCount == beforeDeferred
        checks["staleDeferredRemainsWithDeferredOwner"] = deferred.deferredLayerIDs.contains(1)
            && deferred.outcome(for: 1, url: input(deferredView), device: device) == nil
        deferred.cancelDeferredPreparation()

        let readyRoot = try folder("ready")
        let readyView = SceneResourceView(projectRootURL: readyRoot, packageRootURL: nil, stockAssetsRootURL: nil)
        let ready = try prepare(readyView, deferred: [1])
        _ = ready.requestDeferredBaseImage(layerID: 1, requestGeneration: 3)
        let readyDeadline = Date().addingTimeInterval(2)
        while ready.deferredStatus(for: 1) != .ready && Date() < readyDeadline { Thread.sleep(forTimeInterval: 0.001) }
        checks["readyDeferredIsNotMaskedByMetadataEntry"] = {
            if case .loaded? = ready.outcome(for: 1, url: input(readyView), device: device) { return true }; return false
        }()
        ready.cancelDeferredPreparation()
        var multi = descriptor
        multi.layers += [.init(id: 2), .init(id: 3)]
        var liveAtUpload: [Int] = []
        SceneTextureLoader.loadHook = { liveAtUpload.append(SceneTextureLoader.livePreparedDirectSources) }
        let beforePreparedLoads = SceneTextureLoader.preparedDirectLoads
        _ = try prepare(readyView, descriptor: multi)
        SceneTextureLoader.loadHook = nil
        checks["gpuLoopConsumesOnePreparedRequestAtATime"] = liveAtUpload == [3, 2, 1]
        checks["admittedSourceIsPassedToTheExistingLoad"] = SceneTextureLoader.preparedDirectLoads - beforePreparedLoads == 3
        checks["preparedRequestValuesReleaseAtPassExit"] = SceneTextureLoader.livePreparedDirectSources == 0
        SceneTextureLoader.preparationAdmissionAllowed = false
        var liveOnDeniedUpload = -1
        SceneTextureLoader.loadHook = { liveOnDeniedUpload = SceneTextureLoader.livePreparedDirectSources }
        let deniedLoads = SceneTextureLoader.preparedDirectLoads
        _ = try prepare(readyView)
        SceneTextureLoader.loadHook = nil
        SceneTextureLoader.preparationAdmissionAllowed = true
        checks["budgetDeniedKeepsOnlyActiveCapture"] = (0...1).contains(liveOnDeniedUpload)
            && SceneTextureLoader.preparedDirectLoads == deniedLoads
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneTextureConsumerFailureTests(unittest.TestCase):
    def test_real_preparation_and_deferred_source_boundaries_without_gpu(self):
        if not shutil.which("swiftc"):
            self.skipTest("swiftc unavailable")
        sources = [prepared.PREPARATION, prepared.SOURCE_MATERIALS, prepared.RESOLVER,
            prepared.BUILTIN, prepared.RENDER_STATE, prepared.RENDER_STATE_COMPILATION,
            SCENE / "Format/SceneJSONValue.swift", SCENE / "Resources/Assets/SceneModelResourceIdentity.swift",
            SCENE / "Compilation/Material/ScenePreparedImageMaterialCatalog.swift",
            SCENE / "Resources/Assets/SceneResourceIndex.swift", SCENE / "Resources/Assets/SceneResourceView.swift",
            SCENE / "../SteamWorkshopStorage/ScenePlaybackSource.swift", SCENE / "Format/ScenePkgReader.swift",
            SCENE / "Resources/Assets/SceneResourceIdentity.swift", SCENE / "Resources/Assets/SceneResourceView+Backing.swift"]
        identities = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
        with tempfile.TemporaryDirectory(prefix="mwx-texture-consumers-") as temporary:
            work = Path(temporary)
            copies = []
            for source in sources:
                copy = work / source.name
                copy.write_text(source.read_text().replace("import Metal\n", ""))
                copies.append(copy)
            fixture = work / "Controlled.swift"
            fixture.write_text(METAL + prepared.FIXTURE.read_text().split("@main", 1)[0]
                .replace("import Metal\n", ""))
            harness = work / "Checks.swift"
            harness.write_text(HARNESS)
            binary = work / "checks"
            compiled = subprocess.run(["swiftc", "-swift-version", "5", *map(str, copies),
                str(fixture), str(harness), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            ran = subprocess.run([str(binary), str(work / "input")], capture_output=True, text=True, timeout=20)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            checks = json.loads(ran.stdout)
            self.assertEqual(len(checks), 14)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)
        for source, identity in identities.items():
            self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), identity, str(source))


if __name__ == "__main__":
    unittest.main()
