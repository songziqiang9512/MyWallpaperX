import Foundation
import Metal

/// Materializes one already-budgeted graph plan. The reservation and retained
/// history seed are validated before the first texture factory call.
struct ScenePersistentGraphTargetAllocator {
    typealias GraphPlan = SceneLayerGraphTargetPlan
    typealias Token = SceneGraphExecutionState.PhysicalToken
    typealias TextureFactory = (MTLTextureDescriptor, String) -> MTLTexture?

    let device: MTLDevice
    let cache: SceneOffscreenTextureAllocationCache
    let textureFactory: TextureFactory

    init(device: MTLDevice, cache: SceneOffscreenTextureAllocationCache) {
        self.device = device
        self.cache = cache
        textureFactory = { descriptor, label in
            let texture = device.makeSceneTexture(descriptor: descriptor)
            texture?.label = label
            return texture
        }
    }

    init(
        device: MTLDevice,
        cache: SceneOffscreenTextureAllocationCache,
        textureFactory: @escaping TextureFactory
    ) {
        self.device = device
        self.cache = cache
        self.textureFactory = textureFactory
    }

    func prepare(
        plan: GraphPlan,
        orderingContext: SceneGraphCommandQueueOrderingContext? = nil
    ) -> ScenePreparedPersistentGraphTargets? {
        prepare(plans: [plan], orderingContext: orderingContext)?.first
    }

    func prepare(
        plans: [GraphPlan],
        orderingContext: SceneGraphCommandQueueOrderingContext? = nil,
        recoveryBatch: SceneGraphAllocationRecoveryBatch? = nil
    ) -> [ScenePreparedPersistentGraphTargets]? {
        let recoveryBatch = recoveryBatch ?? makeRecoveryBatch(plans: plans)
        guard !plans.isEmpty,
              let reservations = cache.reserveGraphs(
                  plans: plans, orderingContext: orderingContext
              ) else { return nil }
        return prepare(plans: plans, reservations: reservations, recoveryBatch: recoveryBatch)
    }

    func prepare(
        plans: [GraphPlan],
        reservations: [SceneOffscreenTextureAllocationCache.GraphReservation],
        recoveryBatch: SceneGraphAllocationRecoveryBatch? = nil
    ) -> [ScenePreparedPersistentGraphTargets]? {
        guard !plans.isEmpty, plans.count == reservations.count else { return nil }
        if reservations.allSatisfy({ $0.cachedAllocation != nil }) {
            // No allocation or reclaim takes place. A prior GPU completion may
            // change cache revision without changing these exact resources.
            // Revalidate identities here and keep the original admission/commit
            // checks, rather than applying allocation-recovery's revision fence.
            guard cache.locked({ zip(plans, reservations).allSatisfy { plan, original in
                guard original.orderingContext?.isPending != false,
                      original.cachedAllocation?.plan == plan,
                      let refreshed = cache.reserveGraphLocked(plan: plan,
                        orderingContext: original.orderingContext, values: cache.residents)
                else { return false }
                return cache.reservationStillMatches(original, refreshed)
            } }) else { return nil }
            return reservations.map { reservation in
                let cached = reservation.cachedAllocation!
                return prepared(allocation: cached,
                    candidate: .init(key: .layerGraph(cached.plan.key),
                        allocation: .layerGraph(cached), byteCost: cached.plan.residentByteCost),
                    reservation: reservation, historyRehydrateCopiesByEffect: [:])
            }
        }
        let recoveryBatch = recoveryBatch ?? makeRecoveryBatch(plans: plans)
        guard recoveryBatch.protect(reservations) else { return nil }
        var result: [ScenePreparedPersistentGraphTargets] = []
        for (plan, reservation) in zip(plans, reservations) {
            guard valid(seed: reservation.historySeed, for: plan),
                  let prepared = prepare(plan: plan, reservation: reservation,
                    recoveryBatch: recoveryBatch)
            else { return nil }
            result.append(prepared)
        }
        // Reservations retain their original identities. The existing final
        // commit refresh must still prove reservationStillMatches after reclaim.
        return recoveryBatch.isCurrent ? result : nil
    }

    private func makeRecoveryBatch(plans: [GraphPlan]) -> SceneGraphAllocationRecoveryBatch {
        var keys = Set(plans.map { SceneOffscreenTextureAllocationCache.Key.layerGraph($0.key) })
        for plan in plans where plan.pairStorage == .shared {
            if let extent = plan.sharedPairDimensions {
                keys.insert(.sharedGraphPair(width: extent.width, height: extent.height))
            }
        }
        return .init(cache: cache, protectedKeys: keys)
    }

    private func prepare(
        plan: GraphPlan,
        reservation: SceneOffscreenTextureAllocationCache.GraphReservation,
        recoveryBatch: SceneGraphAllocationRecoveryBatch
    ) -> ScenePreparedPersistentGraphTargets? {
        if let cached = reservation.cachedAllocation {
            let candidate = SceneOffscreenTextureAllocationCache.Candidate(
                key: .layerGraph(plan.key),
                allocation: .layerGraph(cached),
                byteCost: plan.residentByteCost
            )
            return prepared(
                allocation: cached,
                candidate: candidate,
                reservation: reservation,
                historyRehydrateCopiesByEffect: [:]
            )
        }

        let pairSlots = Set([plan.fullFramePair.zeroSlot, plan.fullFramePair.oneSlot])
        let framebufferSlots = plan.pairStorage == .shared
            ? plan.slots.filter { !pairSlots.contains($0.id) }
            : plan.slots
        let sharedPair: SceneOffscreenTextureAllocationCache.SharedPair?
        if plan.pairStorage == .shared {
            guard let value = reservation.sharedPair else { return nil }
            sharedPair = value
        } else {
            sharedPair = nil
        }

        let texturesBySlot: [Int: MTLTexture]
        if let reusable = reservation.reusableAllocation {
            guard reusable.plan == plan,
                  validReusableTextures(reusable.texturesBySlot, for: plan) else {
                return nil
            }
            texturesBySlot = plan.pairStorage == .shared
                ? reusable.texturesBySlot.filter { slot, _ in
                    !pairSlots.contains(slot)
                }
                : reusable.texturesBySlot
        } else {
            var allocated: [Int: MTLTexture] = [:]
            for slot in framebufferSlots {
                let descriptor = textureDescriptor(for: slot.descriptor)
                let label = "SceneLayerGraphRT layer=\(plan.key.layerID) slot=\(slot.id)"
                guard let texture = recoveryBatch.makeTexture({
                    textureFactory(descriptor, label)
                }) else { return nil }
                allocated[slot.id] = texture
            }
            texturesBySlot = allocated
        }
        var allTexturesBySlot = texturesBySlot
        if let sharedPair {
            allTexturesBySlot[plan.fullFramePair.zeroSlot] = sharedPair.pair.first
            allTexturesBySlot[plan.fullFramePair.oneSlot] = sharedPair.pair.second
        }
        guard allTexturesBySlot.count == plan.slots.count else { return nil }
        let framebufferTextures = framebufferSlots.compactMap {
            texturesBySlot[$0.id]
        }
        guard framebufferTextures.count == framebufferSlots.count else {
            return nil
        }
        let identity = framebufferTextures.isEmpty
            ? nil
            : cache.issuePhysicalIdentity(textures: framebufferTextures)
        guard framebufferTextures.isEmpty || identity != nil else { return nil }

        var tokenBySlot: [Int: Token] = [:]
        if let identity {
            for slot in framebufferSlots {
                guard let texture = texturesBySlot[slot.id],
                      let token = identity.token(for: texture) else { return nil }
                tokenBySlot[slot.id] = token
            }
        }
        if let sharedPair {
            guard let zeroToken = sharedPair.identity.token(
                for: sharedPair.pair.first
            ), let oneToken = sharedPair.identity.token(
                for: sharedPair.pair.second
            ) else { return nil }
            tokenBySlot[plan.fullFramePair.zeroSlot] = zeroToken
            tokenBySlot[plan.fullFramePair.oneSlot] = oneToken
        } else if let identity {
            for slot in plan.slots where pairSlots.contains(slot.id) {
                guard let texture = allTexturesBySlot[slot.id],
                      let token = identity.token(for: texture) else { return nil }
                tokenBySlot[slot.id] = token
            }
        }

        guard let allocationGeneration = identity?.generation
            ?? cache.issueAllocationGeneration() else { return nil }
        var leases: [SceneGraphRenderTargetLease] = []
        for stage in plan.stages {
            let mapped = Dictionary(uniqueKeysWithValues: stage.slotByIdentity.compactMap {
                logical, slot in allTexturesBySlot[slot].map { (logical, $0) }
            })
            let pair = plan.fullFramePair
            guard mapped.count == stage.slotByIdentity.count,
                  let zero = allTexturesBySlot[pair.zeroSlot],
                  let one = allTexturesBySlot[pair.oneSlot],
                  case .success(let table) = SceneGraphRenderTargetTable.makeMapped(
                      plan: stage.plan,
                      device: device,
                      texturesByIdentity: mapped,
                      fullFramePair: .init(first: zero, second: one),
                      expectsInputOutputAlias: stage.pairStep.inputMember
                        == stage.pairStep.outputMember,
                      makeInputsDigest: stage.makeInputsDigest
                  ) else { return nil }
            let lease: SceneGraphRenderTargetLease
            if let sharedPair {
                guard case .success(let created) = SceneGraphRenderTargetLease.make(
                    table: table,
                    generation: allocationGeneration,
                    tokenForTexture: identity?.token(for:)
                        ?? sharedPair.identity.token(for:),
                    fullFramePairStorage: .shared,
                    fullFramePairGeneration: sharedPair.identity.generation,
                    tokenForPairTexture: sharedPair.identity.token(for:)
                ) else { return nil }
                lease = created
            } else {
                guard let identity,
                      case .success(let created) = SceneGraphRenderTargetLease.make(
                          table: table,
                          generation: identity.generation,
                          tokenForTexture: identity.token(for:),
                          fullFramePairStorage: .owned
                      ) else { return nil }
                lease = created
            }
            leases.append(lease)
        }
        guard let allocation = SceneLayerGraphTargetAllocation.make(
            plan: plan,
            leases: leases,
            texturesBySlot: allTexturesBySlot,
            generation: allocationGeneration,
            tokenBySlot: tokenBySlot,
            fullFramePairGeneration: sharedPair?.identity.generation
        ) else { return nil }
        let candidate = SceneOffscreenTextureAllocationCache.Candidate(
            key: .layerGraph(plan.key),
            allocation: .layerGraph(allocation),
            byteCost: plan.residentByteCost
        )
        guard let copies = Self.rehydrateCopies(
            seed: reservation.historySeed,
            allocation: allocation
        ) else { return nil }
        return prepared(
            allocation: allocation,
            candidate: candidate,
            reservation: reservation,
            historyRehydrateCopiesByEffect: copies
        )
    }

    private func prepared(
        allocation: SceneLayerGraphTargetAllocation,
        candidate: SceneOffscreenTextureAllocationCache.Candidate,
        reservation: SceneOffscreenTextureAllocationCache.GraphReservation,
        historyRehydrateCopiesByEffect: [
            SceneAuthoredEffectRenderPlan.EffectKey:
                [ScenePreparedPersistentGraphTargets.HistoryRehydrateCopy]
        ]
    ) -> ScenePreparedPersistentGraphTargets {
        .init(
            leases: allocation.leases,
            historyRehydrateCopiesByEffect: historyRehydrateCopiesByEffect,
            cache: cache,
            candidate: candidate,
            reservation: reservation
        )
    }

    static func rehydrateCopies(
        seed: SceneGraphHistorySeed?,
        allocation: SceneLayerGraphTargetAllocation
    ) -> [
        SceneAuthoredEffectRenderPlan.EffectKey:
            [ScenePreparedPersistentGraphTargets.HistoryRehydrateCopy]
    ]? {
        guard let seed else { return [:] }
        var result: [
            SceneAuthoredEffectRenderPlan.EffectKey:
                [ScenePreparedPersistentGraphTargets.HistoryRehydrateCopy]
        ] = [:]
        let slotBySourceToken = Dictionary(
            uniqueKeysWithValues: seed.tokensBySlot.map { ($0.value, $0.key) }
        )
        for (effect, sourceTokens) in seed.tokensByEffect {
            var copies: [ScenePreparedPersistentGraphTargets.HistoryRehydrateCopy] = []
            for sourceToken in sourceTokens {
                guard let slot = slotBySourceToken[sourceToken],
                      let sourceTexture = seed.texturesBySlot[slot],
                      let targetTexture = allocation.texturesBySlot[slot],
                      let targetToken = allocation.tokenBySlot[slot],
                      sourceTexture !== targetTexture,
                      sourceToken != targetToken else { return nil }
                copies.append(.init(
                    sourceToken: sourceToken,
                    sourceTexture: sourceTexture,
                    targetToken: targetToken,
                    targetTexture: targetTexture
                ))
            }
            result[effect] = copies
        }
        return result
    }

    private func valid(
        seed: SceneGraphHistorySeed?,
        for plan: GraphPlan
    ) -> Bool {
        guard let seed else { return true }
        guard seed.generation > 0,
              seed.texturesBySlot.count == seed.tokensBySlot.count,
              Set(seed.texturesBySlot.keys) == Set(seed.tokensBySlot.keys),
              Set(seed.tokensBySlot.values).count == seed.tokensBySlot.count,
              Set(seed.tokensByEffect.keys) == plan.historyEffects,
              seed.tokensByEffect.allSatisfy({ effect, tokens in
                  tokens.count == plan.stages.first(where: {
                      $0.plan.output.effect == effect
                  })?.historyClosureIdentities.count
              }) else {
            return false
        }
        for (slotID, texture) in seed.texturesBySlot {
            guard let slot = plan.slots.first(where: { $0.id == slotID }),
                  let token = seed.tokensBySlot[slotID],
                  let effect = seed.tokensByEffect.first(where: {
                      $0.value.contains(token)
                  })?.key,
                  slot.historyEffect == effect,
                  texture.device.registryID == device.registryID,
                  texture.storageMode == .private,
                  SceneGraphRenderTargetLease.textureMatches(
                      texture,
                      descriptor: .init(
                          extent: slot.descriptor.extent,
                          format: slot.descriptor.format,
                          addressMode: slot.descriptor.addressMode,
                          isUnique: slot.isEffectUnique,
                          initialClear: nil
                      )
                  ) else { return false }
        }
        return true
    }

    private func validReusableTextures(
        _ texturesBySlot: [Int: MTLTexture],
        for plan: GraphPlan
    ) -> Bool {
        guard texturesBySlot.count == plan.slots.count,
              Set(texturesBySlot.keys) == Set(plan.slots.map(\.id)),
              Set(texturesBySlot.values.map(ObjectIdentifier.init)).count
                == texturesBySlot.count else { return false }
        let pairSlots = Set([plan.fullFramePair.zeroSlot, plan.fullFramePair.oneSlot])
        let framebufferSlots = plan.pairStorage == .shared
            ? plan.slots.filter { !pairSlots.contains($0.id) }
            : plan.slots
        guard texturesBySlot.count >= framebufferSlots.count else { return false }
        return framebufferSlots.allSatisfy { slot in
            guard let texture = texturesBySlot[slot.id] else { return false }
            return texture.device.registryID == device.registryID
                && texture.storageMode == .private
                && SceneGraphRenderTargetLease.textureMatches(
                    texture,
                    descriptor: .init(
                        extent: slot.descriptor.extent,
                        format: slot.descriptor.format,
                        addressMode: slot.descriptor.addressMode,
                        isUnique: slot.isEffectUnique,
                        initialClear: nil
                    )
                )
        }
    }

    private func textureDescriptor(
        for value: GraphPlan.Descriptor
    ) -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: value.format.metalPixelFormat,
            width: value.extent.width,
            height: value.extent.height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        return descriptor
    }
}
