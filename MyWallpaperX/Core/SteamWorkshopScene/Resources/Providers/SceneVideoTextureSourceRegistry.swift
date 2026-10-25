import Foundation
import Metal

nonisolated enum SceneVideoCommandApplicationFailure: Error, Equatable {
    case commandBudgetExceeded
    case unavailableLayer(Int)
    case invalidCommand(Int)
}

final class SceneVideoTextureSourceRegistry {
    fileprivate struct SourceIdentity: Hashable {
        let owner: SceneVideoTexturePlaybackOwner
        let source: SceneTextureLoader.SourceKey
        let deviceRegistryID: UInt64
    }

    /// Pending preparation never enters `sources`. The request owns this
    /// candidate until the synchronous Session adoption transfers its source.
    final class UserPropertyCandidate {
        let source: SceneVideoTextureSource
        let identity: SceneUserPropertyTextureIdentity
        fileprivate weak var registry: SceneVideoTextureSourceRegistry?
        fileprivate let declaration: SceneUserPropertyVideoDeclaration
        fileprivate let sourceIdentity: SourceIdentity
        fileprivate let epoch: UInt64
        fileprivate var transferred = false
        fileprivate var cancelled = false

        fileprivate init(
            source: SceneVideoTextureSource,
            declaration: SceneUserPropertyVideoDeclaration,
            registry: SceneVideoTextureSourceRegistry,
            deviceRegistryID: UInt64,
            epoch: UInt64
        ) {
            self.source = source
            identity = declaration.identity
            self.declaration = declaration
            self.registry = registry
            sourceIdentity = .init(owner: .userProperty(declaration.identity),
                source: declaration.source, deviceRegistryID: deviceRegistryID)
            self.epoch = epoch
        }

        func cancel() {
            guard !transferred, !cancelled else { return }
            cancelled = true
            source.stop()
        }

        deinit {
            if !transferred && !cancelled { source.stop() }
        }
    }

    private final class PendingCandidate {
        weak var value: UserPropertyCandidate?
        init(_ value: UserPropertyCandidate) { self.value = value }
    }

    private let epoch: UInt64
    private let capturesLifecycleObservations: Bool
    private var sources: [SourceIdentity: SceneVideoTextureSource] = [:]
    private var pendingUserPropertyCandidates: [SceneUserPropertyTextureIdentity: PendingCandidate] = [:]
    private var nextUserPropertyEpoch: UInt64
    private var isStopped = false
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
        nextUserPropertyEpoch = epoch
        self.capturesLifecycleObservations = capturesLifecycleObservations
    }

    func makeUserPropertyCandidate(
        declaration: SceneUserPropertyVideoDeclaration,
        device: MTLDevice
    ) -> UserPropertyCandidate? {
        guard !isStopped, nextUserPropertyEpoch < UInt64.max else { return nil }
        // Consume an epoch even when this attempt fails. A later source must
        // never reuse a lifecycle identity that may have reached preparation.
        nextUserPropertyEpoch += 1
        let candidateEpoch = nextUserPropertyEpoch
        pendingUserPropertyCandidates.removeValue(forKey: declaration.identity)?.value?.cancel()
        guard declaration.identity.purpose == .premultipliedColor,
              currentUserFileMatches(declaration),
              let source = SceneVideoTextureSource(
                owner: .userProperty(declaration.identity), preparedFile: declaration.file,
                device: device, capturesLifecycleObservations: capturesLifecycleObservations
              ) else { return nil }
        guard currentUserFileMatches(declaration) else {
            source.stop()
            return nil
        }
        source.adoptLifecycleEpoch(candidateEpoch)
        let candidate = UserPropertyCandidate(source: source, declaration: declaration,
            registry: self, deviceRegistryID: device.registryID, epoch: candidateEpoch)
        pendingUserPropertyCandidates[declaration.identity] = PendingCandidate(candidate)
        return candidate
    }

    /// Boundary-only validation; ordinary frame lookup never stats a file.
    func canAdoptUserPropertyCandidate(_ candidate: UserPropertyCandidate) -> Bool {
        !isStopped && candidate.registry === self
            && !candidate.transferred && !candidate.cancelled
            && pendingUserPropertyCandidates[candidate.identity]?.value === candidate
            && candidate.identity.purpose == .premultipliedColor
            && candidate.epoch > epoch && candidate.epoch <= nextUserPropertyEpoch
            && candidate.source.owner == .userProperty(candidate.identity)
            && candidate.sourceIdentity.owner == candidate.source.owner
            && candidate.sourceIdentity.source == candidate.declaration.source
            && currentUserFileMatches(candidate.declaration)
            && candidate.source.hasCompletePrimedPublication(for: candidate.identity)
    }

    func adoptUserPropertyCandidate(
        _ candidate: UserPropertyCandidate,
        sceneTime: TimeInterval, hostTime: TimeInterval, isPaused: Bool
    ) -> Bool {
        guard sceneTime.isFinite, hostTime.isFinite,
              canAdoptUserPropertyCandidate(candidate),
              candidate.source.activatePrimed(
                sceneTime: sceneTime, hostTime: hostTime, isPaused: isPaused
              ) else {
            if candidate.registry === self { candidate.cancel() }
            return false
        }
        let replaced = sources.keys.filter {
            if case let .userProperty(property) = $0.owner {
                return property.propertyKey == candidate.identity.propertyKey
            }
            return false
        }
        // All fallible work ended above. Transfer ownership before retiring
        // the former decoder; no failed replacement may stop the live source.
        let retired = replaced.compactMap { sources.removeValue(forKey: $0) }
        sources[candidate.sourceIdentity] = candidate.source
        rebuildingSourceIdentities?.subtract(replaced)
        rebuildingSourceIdentities?.insert(candidate.sourceIdentity)
        pendingUserPropertyCandidates.removeValue(forKey: candidate.identity)
        candidate.transferred = true
        orderedSourceIdentities = nil
        retired.forEach { $0.stop() }
        return true
    }

    /// Immutable declarations select already-adopted sources. This is also
    /// the rebuild reachability declaration; there is no frame-time file I/O.
    func userPropertySources(
        declarations: [String: SceneUserPropertyVideoDeclaration], device: MTLDevice
    ) -> [SceneUserPropertyTextureIdentity: SceneVideoTextureSource] {
        guard !isStopped else { return [:] }
        var result: [SceneUserPropertyTextureIdentity: SceneVideoTextureSource] = [:]
        for (key, declaration) in declarations {
            guard declaration.identity.propertyKey == key,
                  declaration.identity.purpose == .premultipliedColor else { continue }
            let identity = SourceIdentity(owner: .userProperty(declaration.identity),
                source: declaration.source, deviceRegistryID: device.registryID)
            guard let source = sources[identity], source.owner == identity.owner else { continue }
            rebuildingSourceIdentities?.insert(identity)
            result[declaration.identity] = source
        }
        return result
    }

    func retireUserPropertySources(propertyKeys: Set<String>) {
        let pending = pendingUserPropertyCandidates.keys.filter { propertyKeys.contains($0.propertyKey) }
        for identity in pending {
            pendingUserPropertyCandidates.removeValue(forKey: identity)?.value?.cancel()
        }
        let retired = sources.keys.filter {
            if case let .userProperty(property) = $0.owner {
                return propertyKeys.contains(property.propertyKey)
            }
            return false
        }
        for identity in retired { sources.removeValue(forKey: identity)?.stop() }
        rebuildingSourceIdentities?.subtract(retired)
        orderedSourceIdentities = nil
    }

    func source(
        from url: SceneResourceView.FileInput,
        layerID: Int,
        cacheDirectory: URL,
        device: MTLDevice,
        loader: SceneTextureLoader,
        onSourceCreationFailure: (() -> Void)? = nil
    ) throws -> SceneVideoTextureSource? {
        guard !isStopped else { return nil }
        if case let .resource(handle) = url, handle.wasSelectedEntry,
           handle.owner.packageBacking != nil, url.pathExtension.lowercased() == "tex" {
            let sourceKey = try url.currentIdentity(checkCancellation: { try Task.checkCancellation() })
            if case .package = sourceKey {
                return try source(sourceKey: sourceKey, owner: .layer(layerID),
                    permitsCompletedWebM: true, cacheDirectory: cacheDirectory, device: device,
                    makeDeclaration: { try loader.videoSourceDeclaration(from: url) },
                    onSourceCreationFailure: onSourceCreationFailure)
            }
        }
        guard let declaration = try loader.videoSourceDeclaration(from: url) else { return nil }
        // Loader selected and read this request's snapshot. Only independently
        // supplied declarations need the separate entry's current-source check.
        return try source(sourceKey: declaration.source, owner: .layer(layerID),
            permitsCompletedWebM: declaration.isWebM, cacheDirectory: cacheDirectory, device: device,
            makeDeclaration: { declaration }, onSourceCreationFailure: onSourceCreationFailure)
    }

    func source(
        declaration: SceneTextureLoader.VideoSourceDeclaration,
        owner: SceneVideoTexturePlaybackOwner,
        cacheDirectory: URL,
        device: MTLDevice,
        loader: SceneTextureLoader,
        onSourceCreationFailure: (() -> Void)? = nil
    ) throws -> SceneVideoTextureSource? {
        guard !isStopped else { return nil }
        guard try declaration.input.currentIdentity(checkCancellation: { try Task.checkCancellation() })
                == declaration.source else { throw SceneResourceView.ReadError.sourceChanged }
        return try source(sourceKey: declaration.source, owner: owner,
            permitsCompletedWebM: declaration.isWebM, cacheDirectory: cacheDirectory, device: device,
            makeDeclaration: { declaration }, onSourceCreationFailure: onSourceCreationFailure)
    }

    /// Both request entries select the current identity before reaching here.
    /// Reuse and fresh creation consume that identity and captured payload;
    /// the synchronous declaration producer runs only on a true miss.
    private func source(
        sourceKey: SceneTextureLoader.SourceKey,
        owner: SceneVideoTexturePlaybackOwner,
        permitsCompletedWebM: Bool,
        cacheDirectory: URL,
        device: MTLDevice,
        makeDeclaration: () throws -> SceneTextureLoader.VideoSourceDeclaration?,
        onSourceCreationFailure: (() -> Void)?
    ) throws -> SceneVideoTextureSource? {
        guard !isStopped else { return nil }
        try Task.checkCancellation()
        let identity = SourceIdentity(
            owner: owner,
            source: sourceKey,
            deviceRegistryID: device.registryID
        )
        if let source = sources[identity] {
            try Task.checkCancellation()
            rebuildingSourceIdentities?.insert(identity)
            return source
        }
        var completedFile: SceneVideoOwnedFile?
        var onWebMPrepared: (@Sendable (SceneVideoOwnedFile.Writer) throws -> Void)? = nil
        if permitsCompletedWebM, case let .package(packageIdentity) = sourceKey {
            completedFile = try SceneVideoOwnedFile.borrowCompletedWebM(
                identity: packageIdentity, cacheDirectory: cacheDirectory,
                checkCancellation: { try Task.checkCancellation() }
            )
            onWebMPrepared = { writer in
                try SceneVideoOwnedFile.publishCompletedWebM(
                    writer, identity: packageIdentity,
                    cacheDirectory: cacheDirectory, checkCancellation: { try Task.checkCancellation() }
                )
            }
        }
        let preparedSource: SceneVideoTextureSource?
        if let completedFile {
            preparedSource = SceneVideoTextureSource(owner: owner, preparedFile: completedFile,
                device: device, capturesLifecycleObservations: capturesLifecycleObservations)
        } else {
            let declaration = try makeDeclaration()
            try Task.checkCancellation()
            guard let declaration else { return nil }
            guard declaration.source == sourceKey else { throw SceneResourceView.ReadError.sourceChanged }
            preparedSource = SceneVideoTextureSource(
                owner: owner, mp4PayloadData: declaration.payload, isWebM: declaration.isWebM,
                cacheDirectory: cacheDirectory, device: device,
                capturesLifecycleObservations: capturesLifecycleObservations,
                onWebMPrepared: onWebMPrepared
            )
        }
        guard let source = preparedSource else {
            onSourceCreationFailure?()
            return nil
        }
        try Task.checkCancellation()
        rebuildingSourceIdentities?.insert(identity)
        source.adoptLifecycleEpoch(epoch)
        sources[identity] = source
        orderedSourceIdentities = nil
        return source
    }

    private func currentUserFileMatches(_ declaration: SceneUserPropertyVideoDeclaration) -> Bool {
        do { return try SceneResourceView.FileInput.externalFile(declaration.file.url).currentIdentity() == declaration.source }
        catch { return false }
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

    func discardPreparedFrame() {
        sources.values.forEach { $0.discardPreparedFrame() }
    }

    func stop() {
        isStopped = true
        pendingUserPropertyCandidates.values.forEach { $0.value?.cancel() }
        pendingUserPropertyCandidates.removeAll()
        sources.values.forEach { $0.stop() }
        sources.removeAll()
        orderedSourceIdentities = nil
        rebuildingSourceIdentities = nil
    }

    deinit {
        stop()
    }
}
