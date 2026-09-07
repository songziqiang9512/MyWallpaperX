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
    /// Source order is a topology fact, not a frame-varying provider value.
    /// Keep the existing deterministic layer/device ordering, but only sort
    /// after a source is added or removed instead of on every SceneScript
    /// snapshot request.
    private var orderedSourceIdentities: [SourceIdentity]?
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
        orderedSourceIdentities = nil
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
        if orderedSourceIdentities == nil {
            orderedSourceIdentities = sources.keys.sorted { lhs, rhs in
                if lhs.layerID != rhs.layerID {
                    return lhs.layerID < rhs.layerID
                }
                return lhs.deviceRegistryID < rhs.deviceRegistryID
            }
        }
        return (orderedSourceIdentities ?? []).reduce(
            into: [Int: SceneScriptVideoPlaybackSnapshot]()
        ) { result, identity in
            guard let source = sources[identity] else { return }
            let snapshot = source.playbackSnapshot(sceneTime: sceneTime)
            if result[snapshot.layerID] == nil {
                result[snapshot.layerID] = snapshot
            }
        }
    }

    func apply(
        _ commands: [SceneScriptVideoCommand],
        timing: SceneFrameTiming
    ) -> Result<Void, SceneVideoCommandApplicationFailure> {
        switch validatedSources(for: commands, timing: timing) {
        case let .success(sourcesByLayer):
            for command in commands {
                sourcesByLayer[command.layerID]?.forEach {
                    $0.apply(command, timing: timing)
                }
            }
            return .success(())
        case let .failure(failure):
            return .failure(failure)
        }
    }

    func validate(
        _ commands: [SceneScriptVideoCommand],
        timing: SceneFrameTiming
    ) -> Result<Void, SceneVideoCommandApplicationFailure> {
        switch validatedSources(for: commands, timing: timing) {
        case .success: .success(())
        case let .failure(failure): .failure(failure)
        }
    }

    private func validatedSources(
        for commands: [SceneScriptVideoCommand],
        timing: SceneFrameTiming
    ) -> Result<[Int: [SceneVideoTextureSource]], SceneVideoCommandApplicationFailure> {
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
        return .success(sourcesByLayer)
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
        orderedSourceIdentities = nil
        self.rebuildingSourceIdentities = nil
    }

    func stop() {
        sources.values.forEach { $0.stop() }
        sources.removeAll()
        orderedSourceIdentities = nil
        rebuildingSourceIdentities = nil
    }

    deinit {
        stop()
    }
}
