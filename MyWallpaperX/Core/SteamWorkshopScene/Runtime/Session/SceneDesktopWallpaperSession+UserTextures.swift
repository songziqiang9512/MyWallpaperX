import Foundation
import Metal

extension SceneDesktopWallpaperSession {
    final class PendingUserTextureUpdate {
        let update: ScenePlaybackTextureUpdate
        let cancellation = SceneWallpaperLaunchCancellation()
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
        guard let context = launchContext, context.recordID == update.recordID else {
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
        let identities = Set(demands.filter { keys.contains($0.propertyKey) })
        // DispatchQueue executes synchronous nonisolated resource APIs. No
        // Task/MainActor hop can move decoding back onto the frame thread.
        userTexturePreparationQueue.async { [weak self] in
            let loaded = SceneUserPropertyTextureLoader().load(
                urlsByPropertyKey: resolvedURLs, requestedIdentities: identities,
                textureUploadCommandQueue: queue, textureDecodeCacheBudget: budget,
                device: device, contentGeneration: generation,
                isCancelled: {
                    do { try token.check(); return false }
                    catch { return true }
                }
            )
            DispatchQueue.main.async { [weak self] in
                guard let self else { pending.finish(.superseded); return }
                self.pendingUserTextureUpdates.removeValue(forKey: generation)
                guard let current = self.launchContext,
                      current.recordID == update.recordID,
                      current.propertyVectorScriptProgram.generation == scriptGeneration,
                      current.preparedDeviceResources.device.registryID == deviceID,
                      keys.allSatisfy({ self.latestUserTextureRevisions[$0] == update.revision }),
                      (try? token.check()) != nil else {
                    pending.finish(.superseded)
                    return
                }
                let selectedIdentities = Set(identities.filter { selectedKeys.contains($0.propertyKey) })
                    .union(selectedKeys.compactMap {
                        SceneUserPropertyTextureIdentity(propertyKey: $0, purpose: .premultipliedColor)
                    })
                guard loaded.hasCompletePublications(for: selectedIdentities) else {
                    pending.finish(.failed("texture-update-resource-unavailable"))
                    return
                }
                var liveState = current.liveState
                guard liveState.apply(
                    replacements: update.values, changedPropertyKeys: keys,
                    unavailableConsumerTargets: self.unavailableLiveConsumerTargets(in: current),
                    preparedTexturePropertyKeys: admittedKeys
                ) else {
                    pending.finish(.failed("texture-update-consumer-unavailable"))
                    return
                }
                // Main-thread callbacks are serialized with frame encoding.
                // Merge the current snapshot, preserving other keys that may
                // have committed while this worker prepared its resource.
                self.userPropertyTextureLoad = self.userPropertyTextureLoad
                    .replacing(propertyKeys: keys, with: loaded)
                var adoptedContext = current
                adoptedContext.liveState = liveState
                adoptedContext.userPropertyTextureLoad = self.userPropertyTextureLoad
                self.launchContext = adoptedContext
                for surface in self.surfaces.values {
                    surface.metalView.adoptUserPropertyTextures(self.userPropertyTextureLoad)
                    surface.didSubmitSimulationFrame = false
                }
                if self.sceneClock.isPaused { self.startFrameDriver() }
                pending.finish(.applied)
            }
        }
    }

    func cancelPendingUserTextureUpdates() {
        // Completion stays attached to the worker until it stops reading the
        // selected file, so daemon-owned security scope outlives the read.
        for pending in pendingUserTextureUpdates.values { pending.cancellation.cancel() }
        latestUserTextureRevisions.removeAll()
    }
}
