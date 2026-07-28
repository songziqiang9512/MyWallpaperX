import Foundation
import Metal

final class SceneParticlePlaybackState {
    let pipeline: SceneParticleMetalPipeline
    private let runtime: SceneParticleRuntime
    private(set) var batches: [SceneParticleDrawBatch]

    init?(
        descriptor: SceneRenderDescriptor,
        cacheDirectory: URL,
        device: MTLDevice,
        resourceView: SceneResourceView? = nil,
        textureLoader: SceneTextureLoader = SceneTextureLoader()
    ) {
        guard let pipeline = SceneParticleMetalPipeline(device: device) else { return nil }
        self.pipeline = pipeline
        self.runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: cacheDirectory,
            device: device,
            resourceView: resourceView,
            textureLoader: textureLoader
        )
        self.batches = runtime.advance(by: 0)
    }

    func advance(by frameDelta: TimeInterval) -> [SceneParticleDrawBatch] {
        batches.removeAll(keepingCapacity: true)
        batches = runtime.advance(by: min(max(frameDelta, 0), 0.25))
        return batches
    }

    func loadReportLines(descriptor: SceneRenderDescriptor) -> [String] {
        let particleLayers = descriptor.layers.filter { $0.contentKind == "particle" }
        let visibleIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let visibleLayers = particleLayers.filter { visibleIDs.contains($0.id) }
        let renderableLayers = visibleLayers.filter {
            $0.particleInstanceOverride?.alpha?.isStaticZeroScalar != true
        }
        let batchesByID = Dictionary(grouping: batches, by: \.layerID)
        var lines = [
            "particle authored: \(particleLayers.count)",
            "particle visible: \(visibleLayers.count)"
        ]

        for layer in particleLayers {
            let name = layer.name ?? "(unnamed)"
            guard visibleIDs.contains(layer.id) else {
                lines.append("particle layer \(layer.id) \"\(name)\": skipped hidden")
                continue
            }
            guard layer.particleInstanceOverride?.alpha?.isStaticZeroScalar != true else {
                lines.append("particle layer \(layer.id) \"\(name)\": skipped transparent")
                continue
            }
            guard let batch = batchesByID[layer.id]?.first else {
                lines.append("particle layer \(layer.id) \"\(name)\": unavailable")
                continue
            }
            lines.append(
                "particle layer \(layer.id) \"\(name)\": OK \(batch.texture.width)x\(batch.texture.height) "
                    + "blend=\(batch.blendMode == .additive ? "additive" : "translucent") "
                    + "initial=\(batch.instances.count) perspective=\(batch.usesPerspective) "
                    + "refract=\(batch.refraction != nil)"
            )
        }
        for value in runtime.diagnostics {
            lines.append(
                "particle diagnostic \(value.kind.rawValue) layer=\(value.layerID.map(String.init) ?? "nil") "
                    + "path=\(value.particlePath) detail=\(value.detail ?? "")"
            )
        }
        lines.append(Self.loadedSummaryLine(
            batchLayerIDs: batches.map(\.layerID),
            visibleLayerCount: renderableLayers.count
        ))
        lines.append(
            "particle refract loaded: \(Set(batches.filter { $0.refraction != nil }.map(\.layerID)).count)"
        )
        lines.append("particle initial live: \(batches.reduce(0) { $0 + $1.instances.count })")
        lines.append("particle skipped hidden: \(particleLayers.count - visibleLayers.count)")
        lines.append("particle skipped transparent: \(visibleLayers.count - renderableLayers.count)")
        return lines
    }

    nonisolated static func loadedSummaryLine(
        batchLayerIDs: [Int],
        visibleLayerCount: Int
    ) -> String {
        "particle loaded: \(Set(batchLayerIDs).count) / \(visibleLayerCount)"
    }
}
