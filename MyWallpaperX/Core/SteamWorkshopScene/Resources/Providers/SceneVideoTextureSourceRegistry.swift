import Foundation
import Metal

nonisolated enum SceneVideoCommandApplicationFailure: Error, Equatable {
    case unavailableLayer(Int)
    case invalidCommand(Int)
}

final class SceneVideoTextureSourceRegistry {
    fileprivate struct SourceIdentity: Hashable {
        let owner: SceneVideoTexturePlaybackOwner
        let source: SceneTextureLoader.SourceKey
        let deviceRegistryID: UInt64
    }
    private struct RegisteredSource {
        let source: SceneVideoTextureSource
        let observationIndex: Int?
        var retainedForPreparedCatalog = false
        var consumerCount = 0
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
    private var sources: [SourceIdentity: RegisteredSource] = [:]
    /// Source rows are stable while live. Noncatalog rows are reclaimed only
    /// at preparation boundaries; native incarnations prevent handle ABA.
    private var ordinarySources: [SceneVideoTextureSource?] = []
    private var preparedSourceIdentitiesByModel: [String: [SourceIdentity]] = [:]
    private var pendingUserPropertyCandidates: [SceneUserPropertyTextureIdentity: PendingCandidate] = [:]
    private var nextUserPropertyEpoch: UInt64
    private var isStopped = false
    /// One layer index serves command lookup and the first-device script
    /// observation. Membership and device order change only with sources.
    private var sourceIdentitiesByLayer: [Int: [SourceIdentity]] = [:]
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
        let retired = replaced.compactMap { removeSource($0) }
        sources[candidate.sourceIdentity] = .init(source: candidate.source, observationIndex: nil)
        rebuildingSourceIdentities?.subtract(replaced)
        rebuildingSourceIdentities?.insert(candidate.sourceIdentity)
        pendingUserPropertyCandidates.removeValue(forKey: candidate.identity)
        candidate.transferred = true
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
            guard let source = sources[identity]?.source, source.owner == identity.owner else { continue }
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
        for identity in retired { removeSource(identity)?.stop() }
        rebuildingSourceIdentities?.subtract(retired)
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
                return try source(sourceKey: sourceKey, owner: .ordinary, layerID: layerID,
                    permitsCompletedWebM: true, cacheDirectory: cacheDirectory, device: device,
                    makeDeclaration: { try loader.videoSourceDeclaration(from: url) },
                    onSourceCreationFailure: onSourceCreationFailure)
            }
        }
        guard let declaration = try loader.videoSourceDeclaration(from: url) else { return nil }
        // Loader selected and read this request's snapshot. Only independently
        // supplied declarations need the separate entry's current-source check.
        return try source(sourceKey: declaration.source, owner: .ordinary, layerID: layerID,
            permitsCompletedWebM: declaration.isWebM, cacheDirectory: cacheDirectory, device: device,
            makeDeclaration: { declaration }, onSourceCreationFailure: onSourceCreationFailure)
    }

    func source(
        declaration: SceneTextureLoader.VideoSourceDeclaration,
        owner: SceneVideoTexturePlaybackOwner,
        layerID: Int? = nil,
        cacheDirectory: URL,
        device: MTLDevice,
        loader: SceneTextureLoader,
        onSourceCreationFailure: (() -> Void)? = nil
    ) throws -> SceneVideoTextureSource? {
        guard !isStopped else { return nil }
        guard try declaration.input.currentIdentity(checkCancellation: { try Task.checkCancellation() })
                == declaration.source else { throw SceneResourceView.ReadError.sourceChanged }
        return try source(sourceKey: declaration.source, owner: owner, layerID: layerID,
            permitsCompletedWebM: declaration.isWebM, cacheDirectory: cacheDirectory, device: device,
            makeDeclaration: { declaration }, onSourceCreationFailure: onSourceCreationFailure)
    }

    func source(
        sourceKey: SceneTextureLoader.SourceKey,
        preparedFile: SceneVideoOwnedFile,
        owner: SceneVideoTexturePlaybackOwner,
        layerID: Int? = nil,
        device: MTLDevice,
        onSourceCreationFailure: (() -> Void)? = nil
    ) throws -> SceneVideoTextureSource? {
        try source(sourceKey: sourceKey, owner: owner, layerID: layerID, device: device) {
            let source = SceneVideoTextureSource(owner: owner, preparedFile: preparedFile,
                device: device, capturesLifecycleObservations: capturesLifecycleObservations)
            if source == nil { onSourceCreationFailure?() }
            return source
        }
    }

    private func source(
        sourceKey: SceneTextureLoader.SourceKey,
        owner: SceneVideoTexturePlaybackOwner,
        layerID: Int? = nil,
        permitsCompletedWebM: Bool,
        cacheDirectory: URL,
        device: MTLDevice,
        makeDeclaration: () throws -> SceneTextureLoader.VideoSourceDeclaration?,
        onSourceCreationFailure: (() -> Void)?
    ) throws -> SceneVideoTextureSource? {
        try source(sourceKey: sourceKey, owner: owner, layerID: layerID, device: device) {
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
            let source: SceneVideoTextureSource?
            if let completedFile {
                source = SceneVideoTextureSource(owner: owner, preparedFile: completedFile,
                    device: device, capturesLifecycleObservations: capturesLifecycleObservations)
            } else {
                let declaration = try makeDeclaration()
                try Task.checkCancellation()
                guard let declaration else { return nil }
                guard declaration.source == sourceKey else { throw SceneResourceView.ReadError.sourceChanged }
                source = SceneVideoTextureSource(
                    owner: owner, mp4PayloadData: declaration.payload, isWebM: declaration.isWebM,
                    cacheDirectory: cacheDirectory, device: device,
                    capturesLifecycleObservations: capturesLifecycleObservations,
                    onWebMPrepared: onWebMPrepared
                )
            }
            if source == nil { onSourceCreationFailure?() }
            return source
        }
    }

    /// Every input shares the owner/device cache, lifecycle epoch and rebuild
    /// admission. Materialize a payload or file lease only on a true miss.
    private func source(
        sourceKey: SceneTextureLoader.SourceKey,
        owner: SceneVideoTexturePlaybackOwner,
        layerID: Int? = nil,
        device: MTLDevice,
        makeSource: () throws -> SceneVideoTextureSource?
    ) throws -> SceneVideoTextureSource? {
        guard !isStopped else { return nil }
        try Task.checkCancellation()
        let identity = SourceIdentity(
            owner: owner,
            source: sourceKey,
            deviceRegistryID: device.registryID
        )
        if let entry = sources[identity] {
            try Task.checkCancellation()
            rebuildingSourceIdentities?.insert(identity)
            if owner == .ordinary, let layerID { bind(identity, to: layerID) }
            return entry.source
        }
        guard let source = try makeSource() else { return nil }
        try Task.checkCancellation()
        rebuildingSourceIdentities?.insert(identity)
        source.adoptLifecycleEpoch(epoch)
        let index = owner == .ordinary ? ordinarySources.firstIndex(where: { $0 == nil }) ?? ordinarySources.count : nil
        if let index {
            if index == ordinarySources.count { ordinarySources.append(source) }
            else { ordinarySources[index] = source }
        }
        sources[identity] = .init(source: source, observationIndex: index)
        if owner == .ordinary, let layerID { bind(identity, to: layerID) }
        return source
    }

    private func bind(_ identity: SourceIdentity, to layerID: Int) {
        var bound = sourceIdentitiesByLayer[layerID] ?? []
        bound.removeAll { $0.deviceRegistryID == identity.deviceRegistryID }
        bound.append(identity)
        bound.sort { $0.deviceRegistryID < $1.deviceRegistryID }
        replaceBindings(bound, for: layerID)
    }

    private func replaceBindings(_ identities: [SourceIdentity], for layerID: Int) {
        let previous = sourceIdentitiesByLayer[layerID] ?? []
        for identity in previous where !identities.contains(identity) {
            sources[identity]?.consumerCount -= 1
        }
        for identity in identities where !previous.contains(identity) {
            sources[identity]?.consumerCount += 1
        }
        if identities.isEmpty { sourceIdentitiesByLayer.removeValue(forKey: layerID) }
        else { sourceIdentitiesByLayer[layerID] = identities }
    }

    private func removeSource(_ identity: SourceIdentity) -> SceneVideoTextureSource? {
        guard let entry = sources.removeValue(forKey: identity) else { return nil }
        if let index = entry.observationIndex { ordinarySources[index] = nil }
        return entry.source
    }

    private func currentUserFileMatches(_ declaration: SceneUserPropertyVideoDeclaration) -> Bool {
        do { return try SceneResourceView.FileInput.externalFile(declaration.file.url).currentIdentity() == declaration.source }
        catch { return false }
    }

    /// Preparation boundary only. The qualified catalog supplies eligibility;
    /// model aliases share this launch's existing file lease and Source.
    func prepareDynamicVideoSources(
        resources: [String: ScenePreparedDynamicImageResource],
        modelPaths: Set<String>, device: MTLDevice
    ) throws {
        for path in modelPaths.sorted() {
            guard case let .video(key, file, _)? = resources[path]?.product,
                  try source(sourceKey: key, preparedFile: file, owner: .ordinary, device: device) != nil else { continue }
            let identity = SourceIdentity(owner: .ordinary, source: key, deviceRegistryID: device.registryID)
            sources[identity]?.retainedForPreparedCatalog = true
            var identities = preparedSourceIdentitiesByModel[path] ?? []
            identities.removeAll { $0.deviceRegistryID == device.registryID }
            identities.append(identity)
            identities.sort { $0.deviceRegistryID < $1.deviceRegistryID }
            preparedSourceIdentitiesByModel[path] = identities
        }
    }

    var preparedVideoSourceReferences: [String: Int] {
        preparedSourceIdentitiesByModel.compactMapValues {
            $0.first.flatMap { sources[$0]?.observationIndex }
        }
    }

    func bindPreparedVideoConsumers(_ consumers: [Int: String]) {
        for (layerID, path) in consumers {
            if let identities = preparedSourceIdentitiesByModel[path.lowercased()] {
                replaceBindings(identities, for: layerID)
            }
        }
    }

    func retire(layerIDs: Set<Int>) {
        var affected: Set<SourceIdentity> = []
        for layerID in layerIDs {
            affected.formUnion(sourceIdentitiesByLayer[layerID] ?? [])
            replaceBindings([], for: layerID)
        }
        // Births and ordered actions have settled. Same-Source replacement
        // retains demand, so per-frame destroy/create never pauses a decoder.
        for identity in affected where sources[identity]?.consumerCount == 0 {
            sources[identity]?.source.suspendUnusedBackend()
        }
    }

    func layerSources(deviceRegistryID: UInt64) -> [Int: SceneVideoTextureSource] {
        sourceIdentitiesByLayer.compactMapValues { identities in
            identities.first { $0.deviceRegistryID == deviceRegistryID }.flatMap { sources[$0]?.source }
        }
    }

    func sourceIncarnations(for layerIDs: Set<Int>, deviceRegistryID: UInt64) -> Set<UUID> {
        var incarnations: Set<UUID> = []
        for layerID in layerIDs {
            guard let identity = sourceIdentitiesByLayer[layerID]?.first(where: {
                $0.deviceRegistryID == deviceRegistryID
            }), let source = sources[identity]?.source else { continue }
            incarnations.insert(source.sourceIncarnation)
        }
        return incarnations
    }

    func pause(sceneTime: TimeInterval, hostTime: TimeInterval) {
        sources.values.forEach {
            $0.source.pause(sceneTime: sceneTime, hostTime: hostTime)
        }
    }

    func sceneScriptSnapshots(
        sceneTime: TimeInterval
    ) -> SceneScriptVideoFrameSnapshot {
        .init(sources: ordinarySources.map { $0?.playbackSnapshot(sceneTime: sceneTime) },
            layerBindings: sourceIdentitiesByLayer.compactMapValues {
                $0.first.flatMap { sources[$0]?.observationIndex }
            })
    }

    /// The fixed-point owner barrier already admitted the binding and payload.
    func applyAdmitted(_ command: SceneScriptMediaPlaybackCommand, timing: SceneFrameTiming) {
        for identity in sourceIdentitiesByLayer[command.layerID] ?? [] {
            sources[identity]?.source.apply(command.action, timing: timing)
        }
    }

    func validate(
        _ commands: [SceneScriptMediaPlaybackCommand],
        createdConsumers: [Int: String] = [:],
        timing: SceneFrameTiming
    ) -> Result<Void, SceneVideoCommandApplicationFailure> {
        var sourcesByLayer: [Int: [SceneVideoTextureSource]] = [:]
        for (index, command) in commands.enumerated() {
            if sourcesByLayer[command.layerID] == nil {
                let identities = sourceIdentitiesByLayer[command.layerID]
                    ?? createdConsumers[command.layerID].flatMap { preparedSourceIdentitiesByModel[$0.lowercased()] }
                sourcesByLayer[command.layerID] = identities?.compactMap { sources[$0]?.source }
            }
            guard let targets = sourcesByLayer[command.layerID],
                  let first = targets.first,
                  command.videoSourceIncarnation == first.sourceIncarnation else {
                return .failure(.unavailableLayer(command.layerID))
            }
            guard targets.allSatisfy({ $0.canApply(command.action) }) else {
                return .failure(.invalidCommand(index))
            }
        }
        return .success(())
    }

    func resume(sceneTime: TimeInterval, hostTime: TimeInterval) {
        sources.values.forEach {
            $0.source.resume(sceneTime: sceneTime, hostTime: hostTime)
        }
    }

    func beginSurfaceRebuild(
        sceneTime: TimeInterval,
        hostTime: TimeInterval
    ) {
        rebuildingSourceIdentities = []
        for identity in sources.keys { sources[identity]?.consumerCount = 0 }
        sourceIdentitiesByLayer.removeAll()
        preparedSourceIdentitiesByModel.removeAll()
        sources.values.forEach {
            $0.source.rebuild(sceneTime: sceneTime, hostTime: hostTime)
        }
    }

    func completeSurfaceRebuild() {
        guard let rebuildingSourceIdentities else { return }
        let obsoleteIdentities = sources.compactMap { identity, entry -> SourceIdentity? in
            if !entry.retainedForPreparedCatalog && !rebuildingSourceIdentities.contains(identity) { return identity }
            if identity.owner == .ordinary && entry.consumerCount == 0 { entry.source.suspendUnusedBackend() }
            return nil
        }
        for identity in obsoleteIdentities {
            removeSource(identity)?.stop()
        }
        self.rebuildingSourceIdentities = nil
    }

    /// Resolve one shared decode publication after all display consumers have
    /// sampled this simulation frame. GPU submission belongs to each consumer.
    func commitPreparedFrame() {
        sources.values.forEach { $0.source.commitPreparedFrame() }
    }

    func discardPreparedFrame() {
        sources.values.forEach { $0.source.discardPreparedFrame() }
    }

    func stop() {
        isStopped = true
        pendingUserPropertyCandidates.values.forEach { $0.value?.cancel() }
        pendingUserPropertyCandidates.removeAll()
        sources.values.forEach { $0.source.stop() }
        sources.removeAll()
        ordinarySources.removeAll()
        preparedSourceIdentitiesByModel.removeAll()
        sourceIdentitiesByLayer.removeAll()
        rebuildingSourceIdentities = nil
    }

    deinit {
        stop()
    }
}
