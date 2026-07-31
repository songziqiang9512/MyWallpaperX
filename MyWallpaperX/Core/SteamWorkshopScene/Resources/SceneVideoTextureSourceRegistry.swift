import Foundation
import Metal

extension SceneTextureLoader {
    func makeVideoTextureSourceIfNeeded(
        from url: URL,
        source: SourceKey,
        layerID: Int,
        cacheDirectory: URL,
        device: MTLDevice
    ) -> SceneVideoTextureSource? {
        guard url.pathExtension.lowercased() == "tex",
              sourceKey(for: url) == source,
              let container = texContainer(from: url, source: source),
              container.format == 0,
              let payload = container.mips.first?.data,
              container.isVideoMp4 || Self.isMP4Payload(payload),
              sourceKey(for: url) == source else {
            return nil
        }
        return SceneVideoTextureSource(
            layerID: layerID,
            mp4PayloadData: payload,
            cacheDirectory: cacheDirectory,
            device: device
        )
    }
}

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
        guard let sourceKey = loader.sourceKey(for: url) else {
            return nil
        }
        let identity = SourceIdentity(
            layerID: layerID,
            source: sourceKey,
            deviceRegistryID: device.registryID
        )
        if let source = sources[identity] {
            guard loader.sourceKey(for: url) == sourceKey else { return nil }
            rebuildingSourceIdentities?.insert(identity)
            return source
        }
        guard let source = loader.makeVideoTextureSourceIfNeeded(
            from: url,
            source: sourceKey,
            layerID: layerID,
            cacheDirectory: cacheDirectory,
            device: device
        ),
              loader.sourceKey(for: url) == sourceKey else {
            return nil
        }
        rebuildingSourceIdentities?.insert(identity)
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
