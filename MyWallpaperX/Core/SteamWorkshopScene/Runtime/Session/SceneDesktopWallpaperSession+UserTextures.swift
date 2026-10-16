import Foundation
import Metal
import QuartzCore

extension SceneDesktopWallpaperSession {
    final class PendingUserTextureUpdate {
        let update: ScenePlaybackTextureUpdate
        let cancellation = SceneWallpaperLaunchCancellation()
        var resourceTask: Task<Void, Never>?
        var completion: (@MainActor (ScenePlaybackTextureUpdateOutcome) -> Void)?

        init(_ update: ScenePlaybackTextureUpdate,
             completion: @escaping @MainActor (ScenePlaybackTextureUpdateOutcome) -> Void) {
            self.update = update
            self.completion = completion
        }

        func finish(_ outcome: ScenePlaybackTextureUpdateOutcome) {
            let callback = completion
            completion = nil
            callback?(outcome)
        }
    }

    func applyUserTextureUpdate(
        _ update: ScenePlaybackTextureUpdate,
        resolvedURLs: [String: URL],
        completion: @escaping @MainActor (ScenePlaybackTextureUpdateOutcome) -> Void
    ) {
        guard let context = launchContext, context.recordID == update.recordID,
              let registry = videoTextureSourceRegistry else {
            completion(.unavailable)
            return
        }
        let selectedKeys = Set(update.references.keys)
        let keys = selectedKeys.union(update.resetKeys)
        // One selected/reset key is one failure and supersession atom. The
        // control plane sends a whole-panel reset as individual key requests.
        guard keys.count == 1, selectedKeys.isDisjoint(with: update.resetKeys),
              Set(update.values.keys) == keys, Set(resolvedURLs.keys) == selectedKeys,
              update.values.values.allSatisfy({ $0.stringValue != nil }) else {
            completion(.failed("texture-update-invalid-payload"))
            return
        }
        let demands = context.resolvedMaterialCatalog.userPropertyDemands
            .union(context.baseMaterialProviderBindings.userPropertyDemands)
            .union(context.runtimeInput.renderDescriptor.texturePropertyKeys.compactMap {
                SceneUserPropertyTextureIdentity(propertyKey: $0, purpose: .premultipliedColor)
            })
        let admittedKeys = Set(demands.map(\.propertyKey))
        var candidateState = context.liveState
        guard keys.isSubset(of: admittedKeys), candidateState.apply(
            replacements: update.values, changedPropertyKeys: keys,
            unavailableConsumerTargets: unavailableLiveConsumerTargets(in: context),
            retiredScriptCallbackTargets: retiredPropertyCallbackTargets(
                in: context, propertyKeys: keys),
            preparedTexturePropertyKeys: admittedKeys
        ) else {
            completion(.unavailable)
            return
        }
        guard keys.allSatisfy({ update.revision > latestUserTextureRevisions[$0, default: 0] }),
              nextUserTextureGeneration < UInt64.max else {
            completion(.superseded)
            return
        }
        for pending in pendingUserTextureUpdates.values
            where !Set(pending.update.values.keys).isDisjoint(with: keys) {
            pending.cancellation.cancel()
        }
        keys.forEach { latestUserTextureRevisions[$0] = update.revision }
        nextUserTextureGeneration += 1
        let generation = nextUserTextureGeneration
        let pending = PendingUserTextureUpdate(update, completion: completion)
        pendingUserTextureUpdates[generation] = pending
        let token = pending.cancellation
        let device = context.preparedDeviceResources.device
        let deviceID = device.registryID
        let scriptGeneration = context.propertyVectorScriptProgram.generation
        let queue = context.preparedDeviceResources.baseImages.textureLoader.uploadCommandQueue
        let budget = context.preparedDeviceResources.baseImages.textureLoader.decodeCacheBudget
        let cacheDirectory = context.cacheDirectory
        let identities = Set(demands.filter { keys.contains($0.propertyKey) })
        // DispatchQueue executes synchronous nonisolated resource APIs. No
        // Task/MainActor hop can move decoding back onto the frame thread.
        userTexturePreparationQueue.async { [weak self] in
            let loaded = SceneUserPropertyTextureLoader().load(
                urlsByPropertyKey: resolvedURLs, requestedIdentities: identities,
                textureUploadCommandQueue: queue, textureDecodeCacheBudget: budget,
                device: device, contentGeneration: generation,
                videoCacheDirectory: cacheDirectory,
                isCancelled: {
                    do { try token.check(); return false }
                    catch { return true }
                }
            )
            DispatchQueue.main.async { [weak self] in
                guard let self else { pending.finish(.superseded); return }
                pending.resourceTask = Task { @MainActor [weak self] in
                    guard let self else { pending.finish(.superseded); return }
                    defer { self.pendingUserTextureUpdates.removeValue(forKey: generation) }
                    @MainActor func isCurrent() -> Bool {
                        guard let current = self.launchContext else { return false }
                        return current.recordID == update.recordID
                            && current.propertyVectorScriptProgram.generation == scriptGeneration
                            && current.preparedDeviceResources.device.registryID == deviceID
                            && self.videoTextureSourceRegistry === registry
                            && !self.surfaces.isEmpty
                            && keys.allSatisfy { self.latestUserTextureRevisions[$0] == update.revision }
                            && (try? token.check()) != nil && !Task.isCancelled
                    }
                    guard isCurrent() else { pending.finish(.superseded); return }
                    let selectedIdentities = Set(identities.filter { selectedKeys.contains($0.propertyKey) })
                        .union(selectedKeys.compactMap {
                            SceneUserPropertyTextureIdentity(propertyKey: $0, purpose: .premultipliedColor)
                        })
                    guard loaded.hasPreparedResources(for: selectedIdentities) else {
                        pending.finish(.failed("texture-update-resource-unavailable")); return
                    }
                    var candidates: [SceneVideoTextureSourceRegistry.UserPropertyCandidate] = []
                    for declaration in loaded.videoDeclarations.values {
                        guard let candidate = registry.makeUserPropertyCandidate(declaration: declaration, device: device),
                              await candidate.source.primeInitialFrame(isCancelled: {
                                  (try? token.check()) == nil || Task.isCancelled
                              }) else {
                            pending.finish(isCurrent() ? .failed("texture-update-video-unavailable") : .superseded)
                            return
                        }
                        candidates.append(candidate)
                    }
                    guard isCurrent(), let current = self.launchContext else {
                        pending.finish(.superseded); return
                    }
                    var liveState = current.liveState
                    guard liveState.apply(
                        replacements: update.values, changedPropertyKeys: keys,
                        unavailableConsumerTargets: self.unavailableLiveConsumerTargets(in: current),
                        retiredScriptCallbackTargets: self.retiredPropertyCallbackTargets(
                            in: current, propertyKeys: keys),
                        preparedTexturePropertyKeys: admittedKeys
                    ), candidates.allSatisfy(registry.canAdoptUserPropertyCandidate) else {
                        pending.finish(.failed("texture-update-consumer-unavailable")); return
                    }
                    // One key, one candidate, no suspension point from admission
                    // through every surface's immutable binding replacement.
                    let hostTime = CACurrentMediaTime()
                    let sceneTime = self.sceneClock.currentSceneTime(hostTime: hostTime)
                    for candidate in candidates {
                        guard registry.adoptUserPropertyCandidate(candidate, sceneTime: sceneTime,
                            hostTime: hostTime, isPaused: self.sceneClock.isPaused) else {
                            pending.finish(.failed("texture-update-video-adoption-failed")); return
                        }
                    }
                    if candidates.isEmpty { registry.retireUserPropertySources(propertyKeys: keys) }
                    self.userPropertyTextureLoad = self.userPropertyTextureLoad
                        .replacing(propertyKeys: keys, with: loaded)
                    var adoptedContext = current
                    adoptedContext.liveState = liveState
                    adoptedContext.userPropertyTextureLoad = self.userPropertyTextureLoad
                    self.launchContext = adoptedContext
                    self.publishUserPropertyTextureBindings(registry: registry, device: device)
                    if self.sceneClock.isPaused { self.startFrameDriver() }
                    pending.finish(.applied)
                }
            }
        }
    }

    func cancelPendingUserTextureUpdates() {
        // Completion stays attached to the worker until it stops reading the
        // selected file, so daemon-owned security scope outlives the read.
        for pending in pendingUserTextureUpdates.values {
            pending.cancellation.cancel()
            pending.resourceTask?.cancel()
        }
        latestUserTextureRevisions.removeAll()
    }

    func publishUserPropertyTextureBindings(registry: SceneVideoTextureSourceRegistry, device: MTLDevice) {
        let sources = registry.userPropertySources(
            declarations: userPropertyTextureLoad.videoDeclarations, device: device
        )
        for surface in surfaces.values {
            surface.metalView.adoptUserPropertyTextures(userPropertyTextureLoad, videoSources: sources)
            surface.didSubmitSimulationFrame = false
        }
    }

    func prepareInitialUserPropertyVideos() {
        guard let context = launchContext, let registry = videoTextureSourceRegistry,
              !userPropertyTextureLoad.videoDeclarations.isEmpty else { return }
        let declarations = userPropertyTextureLoad.videoDeclarations
        let device = context.preparedDeviceResources.device
        initialUserVideoPreparation = Task { @MainActor [weak self] in
            var candidates: [SceneVideoTextureSourceRegistry.UserPropertyCandidate] = []
            for declaration in declarations.values {
                guard !Task.isCancelled,
                      let candidate = registry.makeUserPropertyCandidate(declaration: declaration, device: device),
                      await candidate.source.primeInitialFrame(isCancelled: { Task.isCancelled }) else {
                    if !Task.isCancelled, let self, let screen = self.surfaces.keys.first {
                        self.onFirstFrameCompletion?(screen, false)
                    }
                    return
                }
                candidates.append(candidate)
            }
            guard !Task.isCancelled, let self, self.videoTextureSourceRegistry === registry,
                  self.launchContext?.recordID == context.recordID,
                  candidates.allSatisfy(registry.canAdoptUserPropertyCandidate) else { return }
            let hostTime = CACurrentMediaTime()
            let sceneTime = self.sceneClock.currentSceneTime(hostTime: hostTime)
            for candidate in candidates {
                guard registry.adoptUserPropertyCandidate(candidate, sceneTime: sceneTime,
                    hostTime: hostTime, isPaused: self.sceneClock.isPaused) else {
                    if let screen = self.surfaces.keys.first { self.onFirstFrameCompletion?(screen, false) }
                    return
                }
            }
            self.initialUserVideoPreparation = nil
            self.publishUserPropertyTextureBindings(registry: registry, device: device)
            self.startFrameDriver()
        }
    }
}
