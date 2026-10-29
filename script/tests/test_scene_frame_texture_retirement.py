"""Committed logical-layer retirement, resource leases, and frame rollback."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest

from .test_scene_frame_texture_registry import REGISTRY_SOURCE, SWIFT_SOURCES, TEST_ACCESS_SOURCE


HARNESS_SOURCE = r'''
import Foundation
import Metal

enum SceneTextureLoadOutcome {
    case loaded(MTLTexture)
    case decodeFailed(String)
    case textureAllocationFailed(width: Int, height: Int)
}

@main enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "SceneFrameTextureRetirementTests", code: 1)
        }
        func texture() -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
            descriptor.usage = [.shaderRead, .renderTarget]
            return device.makeTexture(descriptor: descriptor)!
        }
        func publication(_ texture: MTLTexture, generation: UInt64,
                         requestIdentity: SceneFrameTextureIdentity,
                         identity: SceneTextureResourceIdentity = .provider(.dynamicText(layerID: 8))) -> SceneTextureProviderPublication {
            let size = CGSize(width: texture.width, height: texture.height)
            return .init(requestIdentity: requestIdentity, candidate: .init(texture: texture,
                identity: identity, generation: .provider(contentGeneration: generation),
                purpose: .premultipliedColor, content: .color(.resolved(.premultipliedAlpha)),
                physicalSize: size, mappedSize: size, uvTransform: .identity, sampling: .linearClamp),
                contentGeneration: generation)
        }
        let named = SceneFrameTextureIdentity.namedLayerTarget(.init(providerLayerID: 7, variant: .primary))
        let persistentProperty = SceneFrameTextureIdentity.userProperty("retirement-neighbor")
        let namedTexture = texture()
        func layerRetirementChecks() -> [String: Bool] {
            let registry = SceneFrameTextureRegistry()
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
            descriptor.usage = [.shaderRead, .renderTarget]
            let bytes = device.heapTextureSizeAndAlign(descriptor: descriptor).size
            let budget = SceneResourceBudget(maximumBytes: bytes * 3)
            let empty: [Int: Bool] = [:]
            func graph(_ id: Int) -> SceneFrameTextureIdentity {
                .graph(.init(kind: .layerSource, layerID: id, effect: nil, name: nil))
            }
            func video(_ image: MTLTexture, _ id: Int, _ generation: UInt64) -> SceneTextureProviderPublication {
                publication(image, generation: generation, requestIdentity: .layerSource(id),
                    identity: .provider(.video(layerID: id, lifecycleEpoch: 70)))
            }
            weak var previous: MTLTexture?
            var previousID: Int?
            var bounded = true, aliasesRetire = true
            for index in 0..<128 {
                let id = -31_000 - index, live = [-31_000 - index: true]
                registry.retireLayerSources(keeping: live.keys)
                bounded = bounded && previous == nil && budget.snapshot.residentBytes == 0
                if let previousID {
                    aliasesRetire = aliasesRetire && registry.lookup(.layerSource(previousID)) == nil
                        && registry.lookup(graph(previousID)) == nil
                }
                autoreleasepool {
                    guard let image = device.makeSceneTexture(descriptor: descriptor, budget: budget) else {
                        bounded = false; return
                    }
                    previous = image
                    registry.beginFrame(layerSources: [id: image], explicitLayerSources: [id: video(image, id, 1)])
                    aliasesRetire = aliasesRetire && registry.resource(for: graph(id))?.publication.texture === image
                    registry.commitFramePublication()
                }
                bounded = bounded && previous != nil && budget.snapshot.residentBytes == bytes
                previousID = id
                if !bounded { break }
            }
            registry.retireLayerSources(keeping: empty.keys)
            var checks = [
                "birthRetire128KeepsOneLease": bounded && previous == nil
                    && budget.snapshot.residentBytes == 0 && budget.snapshot.rejectionCount == 0,
                "layerAndGraphAliasesRetireTogether": aliasesRetire,
            ]

            let liveID = -32_000, deadID = -32_001
            weak var liveTexture: MTLTexture?, deadTexture: MTLTexture?
            var acceptedGeneration: UInt64 = 0
            autoreleasepool {
                let live = device.makeSceneTexture(descriptor: descriptor, budget: budget)!
                let dead = device.makeSceneTexture(descriptor: descriptor, budget: budget)!
                liveTexture = live; deadTexture = dead
                registry.beginFrame(layerSources: [liveID: live, deadID: dead], explicitLayerSources: [
                    liveID: video(live, liveID, 40), deadID: video(dead, deadID, 40)])
                acceptedGeneration = registry.resource(for: .layerSource(liveID))!.resourceGeneration
                registry.commitFramePublication()
            }
            registry.beginFrame(layerSources: [:])
            registry.set(.pending, for: .layerSource(liveID))
            registry.set(.pending, for: graph(liveID))
            let live = [liveID: true]
            registry.retireLayerSources(keeping: live.keys)
            if case .pending = registry.lookup(.layerSource(liveID)) {
                checks["livePendingKeepsAcceptedLease"] = liveTexture != nil && deadTexture == nil
                    && budget.snapshot.residentBytes == bytes
            } else { checks["livePendingKeepsAcceptedLease"] = false }
            registry.discardFramePublication()
            checks["drawableDiscardCannotReviveRetiredLease"] = deadTexture == nil
                && budget.snapshot.residentBytes == bytes
            autoreleasepool {
                let stale = device.makeSceneTexture(descriptor: descriptor, budget: budget)!
                registry.beginFrame(layerSources: [liveID: stale], explicitLayerSources: [liveID: video(stale, liveID, 39)])
                let restored = registry.resource(for: .layerSource(liveID))!
                let alias = registry.resource(for: graph(liveID))!
                checks["liveGenerationGuardSurvivesDiscard"] = restored.publication.texture === liveTexture
                    && restored.resourceGeneration == acceptedGeneration && restored.publication.contentGeneration == 40
                    && alias.publication.texture === liveTexture && alias.publication.contentGeneration == 40
                    && registry.lookup(.layerSource(deadID)) == nil && registry.lookup(graph(deadID)) == nil
                registry.commitFramePublication()
            }
            let unrelated: [SceneFrameTextureIdentity] = [named, persistentProperty,
                .asset(.init(virtualPath: "retirement-neighbor.png", purpose: .premultipliedColor)!),
                .graph(.init(kind: .effectOutput, layerID: deadID, effect: nil, name: "history"))]
            for identity in unrelated {
                registry.set(publication(namedTexture, generation: 1, requestIdentity: identity), for: identity)
            }
            registry.retireLayerSources(keeping: empty.keys)
            checks["otherResourceDomainsSurviveLayerRetirement"] = unrelated.allSatisfy {
                registry.resource(for: $0)?.publication.texture === namedTexture
            }
            checks["lastConsumerReleasesLease"] = liveTexture == nil && budget.snapshot.residentBytes == 0

            // A command buffer owns its encoded input independently of the
            // logical layer. Reclaiming the ID must preserve that GPU lifetime.
            weak var encodedTexture: MTLTexture?
            var command: MTLCommandBuffer?
            let queue = device.makeCommandQueue()!
            autoreleasepool {
                let image = device.makeSceneTexture(descriptor: descriptor, budget: budget)!
                let destination = texture()
                let buffer = queue.makeCommandBuffer()!, blit = buffer.makeBlitCommandEncoder()!
                blit.copy(from: image, sourceSlice: 0, sourceLevel: 0,
                    sourceOrigin: .init(x: 0, y: 0, z: 0), sourceSize: .init(width: 4, height: 4, depth: 1),
                    to: destination, destinationSlice: 0, destinationLevel: 0, destinationOrigin: .init(x: 0, y: 0, z: 0))
                blit.endEncoding()
                command = buffer; encodedTexture = image
                registry.beginFrame(layerSources: [-33_000: image],
                    explicitLayerSources: [-33_000: video(image, -33_000, 1)])
                registry.commitFramePublication()
            }
            registry.retireLayerSources(keeping: empty.keys)
            checks["encodedGPUWorkKeepsRetiredLease"] = encodedTexture != nil && budget.snapshot.residentBytes == bytes
            autoreleasepool {
                command!.commit(); command!.waitUntilCompleted()
                checks["encodedGPUWorkCompletes"] = command!.status == .completed
                command = nil
            }
            checks["GPUDrainReleasesRetiredLease"] = encodedTexture == nil && budget.snapshot.residentBytes == 0
            return checks
        }

        let data = try JSONSerialization.data(withJSONObject: layerRetirementChecks(), options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneFrameTextureRetirementTests(unittest.TestCase):
    def test_committed_layer_retirement_releases_leases_and_survives_drawable_discard(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-frame-texture-retirement-") as directory:
            root = Path(directory)
            registry = root / REGISTRY_SOURCE.name
            registry.write_text(REGISTRY_SOURCE.read_text() + TEST_ACCESS_SOURCE)
            harness = root / "Harness.swift"
            harness.write_text(HARNESS_SOURCE)
            binary = root / "checks"
            sources = [registry if source == REGISTRY_SOURCE else source for source in SWIFT_SOURCES]
            compiled = subprocess.run(["xcrun", "--sdk", "macosx", "swiftc",
                *map(str, sources), str(harness), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            facts = json.loads(run.stdout)
            for name, passed in facts.items():
                with self.subTest(fact=name):
                    self.assertTrue(passed)


if __name__ == "__main__":
    unittest.main()
