import Foundation
import Metal

nonisolated enum SceneVideoCommandApplicationFailure: Error, Equatable {
    case commandBudgetExceeded
    case unavailableLayer(Int)
    case invalidCommand(Int)
}

final class SceneVideoTextureSourceRegistry {
    private struct SourceIdentity: Hashable {
        let owner: SceneVideoTexturePlaybackOwner
        let source: SceneTextureLoader.SourceKey
        let deviceRegistryID: UInt64
    }

    private let epoch: UInt64
    private let capturesLifecycleObservations: Bool
    private var sources: [SourceIdentity: SceneVideoTextureSource] = [:]
    /// Source order is a topology fact, not a frame-varying provider value.
    /// Keep the existing deterministic layer/device ordering, but only sort
    /// after a source is added or removed instead of on every SceneScript
    /// snapshot request.
    private var orderedSourceIdentities: [SourceIdentity]?
    private var rebuildingSourceIdentities: Set<SourceIdentity>?

    init(
        epoch: UInt64,
        capturesLifecycleObservations: Bool = false
    ) {
        self.epoch = epoch
        self.capturesLifecycleObservations = capturesLifecycleObservations
    }

    func source(
        from url: URL,
        layerID: Int,
        cacheDirectory: URL,
        device: MTLDevice,
        loader: SceneTextureLoader
    ) -> SceneVideoTextureSource? {
        guard let declaration = loader.videoSourceDeclaration(from: url) else { return nil }
        return source(declaration: declaration, owner: .layer(layerID),
            cacheDirectory: cacheDirectory, device: device, loader: loader)
    }

    func source(
        declaration: SceneTextureLoader.VideoSourceDeclaration,
        owner: SceneVideoTexturePlaybackOwner,
        cacheDirectory: URL,
        device: MTLDevice,
        loader: SceneTextureLoader
    ) -> SceneVideoTextureSource? {
        let sourceKey = declaration.source
        let url = declaration.url
        guard loader.sourceKey(for: url) == sourceKey else { return nil }
        let identity = SourceIdentity(
            owner: owner,
            source: sourceKey,
            deviceRegistryID: device.registryID
        )
        if let source = sources[identity] {
            guard loader.sourceKey(for: url) == sourceKey else { return nil }
            rebuildingSourceIdentities?.insert(identity)
            return source
        }
        guard let source = SceneVideoTextureSource(
            owner: owner,
            mp4PayloadData: declaration.payload,
            isWebM: declaration.isWebM,
            cacheDirectory: cacheDirectory,
            device: device,
            capturesLifecycleObservations: capturesLifecycleObservations
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
            orderedSourceIdentities = sources.keys.filter { $0.owner.layerID != nil }
                .sorted { lhs, rhs in
                if let left = lhs.owner.layerID, let right = rhs.owner.layerID,
                   left != right {
                    return left < right
                }
                return lhs.deviceRegistryID < rhs.deviceRegistryID
            }
        }
        return (orderedSourceIdentities ?? []).reduce(
            into: [Int: SceneScriptVideoPlaybackSnapshot]()
        ) { result, identity in
            guard let source = sources[identity] else { return }
            guard let snapshot = source.playbackSnapshot(sceneTime: sceneTime) else { return }
            if result[snapshot.layerID] == nil {
                result[snapshot.layerID] = snapshot
            }
        }
    }

    func apply(
        _ commands: [SceneScriptMediaPlaybackCommand],
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
        _ commands: [SceneScriptMediaPlaybackCommand],
        timing: SceneFrameTiming
    ) -> Result<Void, SceneVideoCommandApplicationFailure> {
        switch validatedSources(for: commands, timing: timing) {
        case .success: .success(())
        case let .failure(failure): .failure(failure)
        }
    }

    private func validatedSources(
        for commands: [SceneScriptMediaPlaybackCommand],
        timing: SceneFrameTiming
    ) -> Result<[Int: [SceneVideoTextureSource]], SceneVideoCommandApplicationFailure> {
        guard commands.count <= 64 else {
            return .failure(.commandBudgetExceeded)
        }
        var sourcesByLayer: [Int: [SceneVideoTextureSource]] = [:]
        for source in sources.values {
            if let layerID = source.owner.layerID {
                sourcesByLayer[layerID, default: []].append(source)
            }
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

    /// Resolve one shared decode publication after all display consumers have
    /// sampled this simulation frame. GPU submission belongs to each consumer.
    func commitPreparedFrame() {
        sources.values.forEach { $0.commitPreparedFrame() }
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
