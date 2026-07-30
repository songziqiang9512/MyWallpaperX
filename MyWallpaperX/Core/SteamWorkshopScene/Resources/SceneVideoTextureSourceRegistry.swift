import Foundation
import Metal

final class SceneVideoTextureSourceRegistry {
    private struct SourceIdentity: Hashable {
        let layerID: Int
        let source: SceneTextureLoader.SourceKey
        let deviceRegistryID: UInt64
    }

    private let epoch: UInt64
    private var sources: [SourceIdentity: SceneVideoTextureSource] = [:]
    private var rebuildingSourceIdentities: Set<SourceIdentity>?

    init(epoch: UInt64) {
        self.epoch = epoch
    }

    func source(
        from url: URL,
        layerID: Int,
        cacheDirectory: URL,
        device: MTLDevice,
        loader: SceneTextureLoader
    ) -> SceneVideoTextureSource? {
        let identity = SourceIdentity(
            layerID: layerID,
            source: loader.sourceKey(for: url),
            deviceRegistryID: device.registryID
        )
        rebuildingSourceIdentities?.insert(identity)
        if let source = sources[identity] {
            return source
        }
        guard let source = loader.makeVideoTextureSourceIfNeeded(
            from: url,
            layerID: layerID,
            cacheDirectory: cacheDirectory,
            device: device
        ) else {
            return nil
        }
        source.adoptLifecycleEpoch(epoch)
        sources[identity] = source
        return source
    }

    func pause(sceneTime: TimeInterval, hostTime: TimeInterval) {
        sources.values.forEach {
            $0.pause(sceneTime: sceneTime, hostTime: hostTime)
        }
    }

    func resume(sceneTime: TimeInterval, hostTime: TimeInterval) {
        sources.values.forEach {
            $0.resume(sceneTime: sceneTime, hostTime: hostTime)
        }
    }

    func beginSurfaceRebuild(
        sceneTime: TimeInterval,
        hostTime: TimeInterval
    ) {
        rebuildingSourceIdentities = []
        sources.values.forEach {
            $0.rebuild(sceneTime: sceneTime, hostTime: hostTime)
        }
    }

    func completeSurfaceRebuild() {
        guard let rebuildingSourceIdentities else { return }
        let obsoleteIdentities = sources.keys.filter {
            !rebuildingSourceIdentities.contains($0)
        }
        for identity in obsoleteIdentities {
            sources.removeValue(forKey: identity)?.stop()
        }
        self.rebuildingSourceIdentities = nil
    }

    func stop() {
        sources.values.forEach { $0.stop() }
        sources.removeAll()
        rebuildingSourceIdentities = nil
    }

    deinit {
        stop()
    }
}
