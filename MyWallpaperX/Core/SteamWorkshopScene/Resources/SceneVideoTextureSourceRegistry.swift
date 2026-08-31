import Foundation
import Metal

nonisolated enum SceneVideoCommandApplicationFailure: Error, Equatable {
    case commandBudgetExceeded
    case unavailableLayer(Int)
    case invalidCommand(Int)
}

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

    func sceneScriptSnapshots(
        sceneTime: TimeInterval
    ) -> [Int: SceneScriptVideoPlaybackSnapshot] {
        let ordered = sources.sorted { lhs, rhs in
            if lhs.key.layerID != rhs.key.layerID {
                return lhs.key.layerID < rhs.key.layerID
            }
            return lhs.key.deviceRegistryID < rhs.key.deviceRegistryID
        }
        return ordered.reduce(
            into: [Int: SceneScriptVideoPlaybackSnapshot]()
        ) { result, entry in
            let snapshot = entry.value.playbackSnapshot(sceneTime: sceneTime)
            if result[snapshot.layerID] == nil {
                result[snapshot.layerID] = snapshot
            }
        }
    }

    func apply(
        _ commands: [SceneScriptVideoCommand],
        timing: SceneFrameTiming
    ) -> Result<Void, SceneVideoCommandApplicationFailure> {
        guard commands.count <= 64 else {
            return .failure(.commandBudgetExceeded)
        }
        let sourcesByLayer = Dictionary(grouping: sources.values) {
            $0.playbackSnapshot(sceneTime: timing.sceneTime).layerID
        }
        for (index, command) in commands.enumerated() {
            guard let targets = sourcesByLayer[command.layerID],
                  !targets.isEmpty else {
                return .failure(.unavailableLayer(command.layerID))
            }
            guard targets.allSatisfy({ $0.canApply(command) }) else {
                return .failure(.invalidCommand(index))
            }
        }
        for command in commands {
            sourcesByLayer[command.layerID]?.forEach {
                $0.apply(command, timing: timing)
            }
        }
        return .success(())
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
