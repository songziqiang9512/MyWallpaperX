"""Package value projection through the real typed registry/publication owner.

Uses a real Metal allocation, without rendering or loading author resources.
The Root/Reader opened-file/range gates live in package_resource_backing.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_frame_texture_registry import SWIFT_SOURCES

ROOT = Path(__file__).resolve().parents[2]
HARNESS = r'''
import Foundation
import Metal

enum SceneTextureLoadOutcome {
    case loaded(MTLTexture)
    case decodeFailed(String)
    case textureAllocationFailed(width: Int, height: Int)
}

@main enum PackagePublicationProbe {
    static func identity(package: String = "/library/scene.pkg", entry: String = "materials\\renamed.tex") -> SceneTexturePackageIdentity {
        .init(packagePath: package, rawEntryPath: entry)
    }
    static func revision(device: UInt64 = 1, inode: UInt64 = 2, fileSize: UInt64 = 100,
                         modified: Int64 = 3, modifiedNanos: Int64 = 4, changed: Int64 = 5, changedNanos: Int64 = 6,
                         dataStart: UInt64 = 11, offset: UInt32 = 13, size: UInt32 = 17) -> SceneTexturePackageRevision {
        .init(fileSystemID: device, fileID: inode, fileByteCount: fileSize,
            modifiedSeconds: modified, modifiedNanoseconds: modifiedNanos,
            changedSeconds: changed, changedNanoseconds: changedNanos,
            dataStartOffset: dataStart, offset: offset, byteCount: size)
    }
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw NSError(domain: "PackagePublication", code: 1) }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 4, height: 4, mipmapped: false)
        descriptor.usage = [.shaderRead, .renderTarget]
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw NSError(domain: "PackagePublication", code: 2) }
        let asset = SceneAssetTextureIdentity(virtualPath: "materials/renamed.tex", purpose: .premultipliedColor)!
        let request = SceneFrameTextureIdentity.asset(asset)
        func atom(_ resourceIdentity: SceneTextureResourceIdentity = .package(identity()),
                  _ generation: SceneTextureResourceGeneration = .package(revision())) -> SceneTextureProviderPublication {
            .init(requestIdentity: request,
                candidate: .init(texture: texture, identity: resourceIdentity, generation: generation,
                    purpose: .premultipliedColor, content: .color(.resolved(.premultipliedAlpha)),
                    physicalSize: .init(width: 4, height: 4), mappedSize: .init(width: 4, height: 4),
                    uvTransform: .identity, sampling: .linearClamp), contentGeneration: 5)
        }
        let original = atom()
        let logicalVariants = [identity(package: "/library/renamed.pkg"), identity(entry: "materials/renamed-again.tex")]
        let revisionVariants = [revision(device: 9), revision(inode: 9), revision(fileSize: 101),
            revision(modified: 9), revision(modifiedNanos: 9), revision(changed: 9), revision(changedNanos: 9),
            revision(dataStart: 12), revision(offset: 14), revision(size: 18)]
        let variants = logicalVariants.map { atom(.package($0)) }
            + revisionVariants.map { atom(.package(identity()), .package($0)) }
        var result: [String: Bool] = [:]
        result["typedPackagePublicationIsComplete"] = original.isComplete && original.generationIsCurrent
        result["sameValuePreservesAtomAndLifecycle"] = original.isSameAtom(as: atom())
            && original.lifecycleIdentity == atom().lifecycleIdentity
        result["everyPackageRevisionAndRangeChangesAtom"] = variants.allSatisfy {
            $0.isComplete && !original.isSameAtom(as: $0) && original.lifecycleIdentity != $0.lifecycleIdentity
        }
        result["allProjectedFieldsParticipateInHashAndEquality"] = Set(([original] + variants).map(\.lifecycleIdentity)).count == variants.count + 1
        let registry = SceneFrameTextureRegistry()
        _ = registry.beginFrame(frameIndex: 1, layerSources: [:])
        registry.set(original, for: request)
        let first = registry.resource(for: request)!
        registry.set(atom(), for: request)
        result["registryReusesSameValue"] = registry.resource(for: request)?.resourceGeneration == first.resourceGeneration
        var previous = first.resourceGeneration
        var changed = true
        for variant in variants {
            registry.set(variant, for: request)
            guard let accepted = registry.resource(for: request) else { changed = false; continue }
            changed = changed && accepted.resourceGeneration > previous && accepted.publication.isSameAtom(as: variant)
            previous = accepted.resourceGeneration
        }
        result["registryDoesNotReuseDifferentValue"] = changed
        let wrongGeneration = atom(.package(identity()), .immutable(revision: 5))
        let wrongIdentity = atom(.file(path: "/real/external/file.tex"), .package(revision()))
        result["packageAndFileOrBuiltinGenerationsCannotCross"] = !wrongGeneration.isComplete && !wrongIdentity.isComplete
        let malformed = atom(.package(identity()), .package(revision(fileSize: 0)))
        registry.set(malformed, for: request)
        result["outOfRangeRevisionNeverBecomesReady"] = !malformed.isComplete && registry.resource(for: request) == nil
        let layer = original.publication(for: .layerSource(8))
        result["packageIsAVersionedLayerSource"] = SceneLayerSourcePublication(layerID: 8, publication: layer) != nil
            && SceneLayerSourcePublication.supportsDirectTextureLane(layerID: 8, publication: layer)
        let wrongLayer = original.publication(for: .layerSource(9))
        result["packageCannotCrossLogicalLayerRequest"] = SceneLayerSourcePublication(layerID: 8, publication: wrongLayer) == nil
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class ScenePackageTexturePublicationTests(unittest.TestCase):
    def test_real_registry_preserves_typed_package_atom_and_failure_boundaries(self):
        if not shutil.which("swiftc"):
            self.skipTest("swiftc unavailable")
        before = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in SWIFT_SOURCES}
        with tempfile.TemporaryDirectory(prefix="mwx-package-publication-") as temporary:
            base = Path(temporary)
            harness = base / "Harness.swift"
            harness.write_text(HARNESS)
            binary = base / "publication"
            command = ["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                       "-default-isolation", "MainActor", *map(str, SWIFT_SOURCES), str(harness), "-o", str(binary)]
            compile_result = subprocess.run(command, capture_output=True, text=True, timeout=120)
            self.assertEqual(compile_result.returncode, 0, compile_result.stdout + compile_result.stderr)
            completed = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            result = json.loads(completed.stdout)
            self.assertTrue(result and all(result.values()), result)
        after = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in SWIFT_SOURCES}
        self.assertEqual(before, after, "typed publication sources changed")
        if evidence := os.environ.get("MWX_PACKAGE_PUBLICATION_TEST_EVIDENCE"):
            output = Path(evidence)
            output.mkdir(parents=True, exist_ok=True)
            (output / "result.json").write_text(json.dumps({"sourceBefore": before, "sourceAfter": after,
                "command": command, "checks": result}, indent=2) + "\n")


if __name__ == "__main__":
    unittest.main()
