import Foundation
import Metal

final class ScenePreparedPersistentGraphTargets {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey
    typealias Token = SceneGraphExecutionState.PhysicalToken

    struct HistoryRehydrateCopy {
        let sourceToken: Token
        let sourceTexture: MTLTexture
        let targetToken: Token
        let targetTexture: MTLTexture
    }
    struct Commit {
        let leases: [SceneGraphRenderTargetLease]
        let submissionPin: SceneGraphRenderTargetResidencyPin
        let historyPinsByEffect: [EffectKey: SceneGraphRenderTargetResidencyPin]
        let sharedPairPin: SceneGraphRenderTargetResidencyPin?

        func releaseAll() {
            submissionPin.release()
            historyPinsByEffect.values.forEach { $0.release() }
            sharedPairPin?.release()
        }
    }
    struct CommitRequest {
        let cache: SceneOffscreenTextureAllocationCache
        let candidate: SceneOffscreenTextureAllocationCache.Candidate
        let reservation: SceneOffscreenTextureAllocationCache.GraphReservation
        let historyTokensByEffect: [EffectKey: Set<Token>]
        /// Effects whose launch-time visual fallback discarded every planned
        /// history target before encode. They retain no history pin.
        let discardedHistoryEffects: Set<EffectKey>
        let commandBuffer: MTLCommandBuffer?
    }

    let leases: [SceneGraphRenderTargetLease]
    let historyRehydrateCopiesByEffect: [EffectKey: [HistoryRehydrateCopy]]
    private let cache: SceneOffscreenTextureAllocationCache
    private let candidate: SceneOffscreenTextureAllocationCache.Candidate
    private let reservation: SceneOffscreenTextureAllocationCache.GraphReservation
    private let lock = NSLock()
    private var isAvailable = true

    init(
        leases: [SceneGraphRenderTargetLease],
        historyRehydrateCopiesByEffect: [EffectKey: [HistoryRehydrateCopy]],
        cache: SceneOffscreenTextureAllocationCache,
        candidate: SceneOffscreenTextureAllocationCache.Candidate,
        reservation: SceneOffscreenTextureAllocationCache.GraphReservation
    ) {
        self.leases = leases
        self.historyRehydrateCopiesByEffect = historyRehydrateCopiesByEffect
        self.cache = cache
        self.candidate = candidate
        self.reservation = reservation
    }

    func takeCommitRequest(
        historyTokensByEffect: [EffectKey: Set<Token>],
        discardedHistoryEffects: Set<EffectKey> = [],
        commandBuffer: MTLCommandBuffer?
    ) -> CommitRequest? {
        lock.lock()
        guard isAvailable else { lock.unlock(); return nil }
        isAvailable = false
        lock.unlock()
        return .init(
            cache: cache, candidate: candidate, reservation: reservation,
            historyTokensByEffect: historyTokensByEffect,
            discardedHistoryEffects: discardedHistoryEffects,
            commandBuffer: commandBuffer
        )
    }

    func commitAndPin(
        historyTokensByEffect: [EffectKey: Set<Token>],
        discardedHistoryEffects: Set<EffectKey> = [],
        commandBuffer: MTLCommandBuffer? = nil
    ) -> Commit? {
        guard let request = takeCommitRequest(
            historyTokensByEffect: historyTokensByEffect,
            discardedHistoryEffects: discardedHistoryEffects,
            commandBuffer: commandBuffer
        ) else { return nil }
        return cache.commitAndPin([request])?.first
    }
}

final class SceneGraphRenderTargetResidencyPin: @unchecked Sendable {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey
    typealias Token = SceneGraphExecutionState.PhysicalToken

    enum Purpose: Hashable {
        case submission
        case history(EffectKey, Set<Token>)
    }

    let purpose: Purpose
    let generation: UInt64
    var effect: EffectKey? {
        guard case .history(let effect, _) = purpose else { return nil }
        return effect
    }

    private let identity: UUID
    private let cache: SceneOffscreenTextureAllocationCache
    private let lock = NSLock()
    private var active = true

    init(
        identity: UUID,
        purpose: Purpose,
        generation: UInt64,
        cache: SceneOffscreenTextureAllocationCache
    ) {
        self.identity = identity
        self.purpose = purpose
        self.generation = generation
        self.cache = cache
    }

    func release() {
        lock.lock()
        guard active else { lock.unlock(); return }
        active = false
        lock.unlock()
        cache.releasePin(identity: identity)
    }

    deinit { release() }
}

struct SceneGraphHistoryResidency {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey
    typealias Token = SceneGraphExecutionState.PhysicalToken

    let plan: SceneLayerGraphTargetPlan
    let generation: UInt64
    let texturesByToken: [Token: MTLTexture]
    let byteCostsByToken: [Token: Int]
    let slotByToken: [Token: Int]
    let tokensByEffect: [EffectKey: Set<Token>]

    var textureCount: Int { texturesByToken.count }
    var byteCost: Int { byteCostsByToken.values.reduce(0, +) }

    var seed: SceneGraphHistorySeed {
        .init(
            generation: generation,
            texturesBySlot: Dictionary(uniqueKeysWithValues: slotByToken.compactMap {
                token, slot in texturesByToken[token].map { (slot, $0) }
            }),
            tokensBySlot: Dictionary(uniqueKeysWithValues: slotByToken.map { ($0.value, $0.key) }),
            tokensByEffect: tokensByEffect
        )
    }

    func retaining(tokens: Set<Token>) -> Self? {
        let textures = texturesByToken.filter { tokens.contains($0.key) }
        let costs = byteCostsByToken.filter { tokens.contains($0.key) }
        let slots = slotByToken.filter { tokens.contains($0.key) }
        let effects = tokensByEffect.compactMapValues { value -> Set<Token>? in
            let retained = value.intersection(tokens)
            return retained.isEmpty ? nil : retained
        }
        guard textures.count == tokens.count,
              costs.count == tokens.count,
              slots.count == tokens.count else { return nil }
        return .init(
            plan: plan,
            generation: generation,
            texturesByToken: textures,
            byteCostsByToken: costs,
            slotByToken: slots,
            tokensByEffect: effects
        )
    }

    /// Pair extent changes do not invalidate fixed-size authored history FBOs.
    /// Any changed history descriptor keeps the old pin resident but prevents
    /// that generation from becoming a rehydrate seed.
    func isCompatible(with candidate: SceneLayerGraphTargetPlan) -> Bool {
        guard plan.key == candidate.key,
              Set(tokensByEffect.keys) == candidate.historyEffects,
              historySemanticsMatch(candidate) else {
            return false
        }
        let expectedSlots = Set(candidate.slots.compactMap {
            $0.historyEffect == nil ? nil : $0.id
        })
        guard Set(slotByToken.values) == expectedSlots,
              Set(slotByToken.values).count == slotByToken.count else {
            return false
        }
        let newSlots = Dictionary(uniqueKeysWithValues: candidate.slots.map {
            ($0.id, $0)
        })
        let oldSlots = Dictionary(uniqueKeysWithValues: plan.slots.map {
            ($0.id, $0)
        })
        var effectByToken: [Token: EffectKey] = [:]
        for (effect, tokens) in tokensByEffect {
            for token in tokens {
                guard effectByToken.updateValue(effect, forKey: token) == nil else {
                    return false
                }
            }
        }
        guard effectByToken.count == slotByToken.count else { return false }
        for (token, slotID) in slotByToken {
            guard let effect = effectByToken[token],
                  let old = oldSlots[slotID],
                  let new = newSlots[slotID],
                  old.historyEffect == effect,
                  new.historyEffect == effect,
                  old.descriptor == new.descriptor else { return false }
        }
        return tokensByEffect.allSatisfy { effect, tokens in
            tokens.count == candidate.stages.first(where: {
                $0.plan.output.effect == effect
            })?.historyClosureIdentities.count
        }
    }

    private func historySemanticsMatch(
        _ candidate: SceneLayerGraphTargetPlan
    ) -> Bool {
        for effect in tokensByEffect.keys {
            let oldMatches = plan.stages.filter { $0.plan.output.effect == effect }
            let newMatches = candidate.stages.filter {
                $0.plan.output.effect == effect
            }
            guard oldMatches.count == 1, newMatches.count == 1,
                  let old = oldMatches.first, let new = newMatches.first,
                  old.pairStep == new.pairStep,
                  old.plan.input == new.plan.input,
                  old.plan.output == new.plan.output,
                  old.plan.inputRole == new.plan.inputRole,
                  old.plan.commands == new.plan.commands,
                  old.historyClosureIdentities == new.historyClosureIdentities
            else { return false }

            let oldTargets = Dictionary(uniqueKeysWithValues:
                old.plan.logicalTargets.map { ($0.identity, $0) }
            )
            let newTargets = Dictionary(uniqueKeysWithValues:
                new.plan.logicalTargets.map { ($0.identity, $0) }
            )
            for identity in old.historyClosureIdentities {
                guard oldTargets[identity] == newTargets[identity],
                      old.slotByIdentity[identity]
                        == new.slotByIdentity[identity] else {
                    return false
                }
            }
        }
        return true
    }
}

struct SceneGraphHistorySeed {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey
    typealias Token = SceneGraphExecutionState.PhysicalToken
    let generation: UInt64
    let texturesBySlot: [Int: MTLTexture]
    let tokensBySlot: [Int: Token]
    let tokensByEffect: [EffectKey: Set<Token>]
}

struct SceneLayerGraphTargetAllocation {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey
    typealias Token = SceneGraphExecutionState.PhysicalToken

    let plan: SceneLayerGraphTargetPlan
    let leases: [SceneGraphRenderTargetLease]
    let texturesBySlot: [Int: MTLTexture]
    let tokenBySlot: [Int: Token]
    let generation: UInt64
    let fullFramePairGeneration: UInt64
    let historyEligibleTokensByEffect: [EffectKey: Set<Token>]
    let requiredHistoryTokenCountByEffect: [EffectKey: Int]
    private let texturesByToken: [Token: MTLTexture]
    private let byteCostsByToken: [Token: Int]
    private let slotByToken: [Token: Int]

    var textureCount: Int {
        plan.pairStorage == .shared ? max(texturesBySlot.count - 2, 0)
            : texturesBySlot.count
    }

    static func make(
        plan: SceneLayerGraphTargetPlan,
        leases: [SceneGraphRenderTargetLease],
        texturesBySlot: [Int: MTLTexture],
        generation: UInt64,
        tokenBySlot: [Int: Token],
        fullFramePairGeneration: UInt64? = nil
    ) -> Self? {
        let pairGeneration = fullFramePairGeneration ?? generation
        guard generation > 0,
              pairGeneration > 0,
              leases.count == plan.stages.count,
              leases.allSatisfy({ $0.generation == generation }),
              leases.allSatisfy({
                  $0.fullFramePairGeneration == pairGeneration
              }),
              texturesBySlot.count == plan.slots.count,
              tokenBySlot.count == plan.slots.count,
              Set(tokenBySlot.values).count == tokenBySlot.count else { return nil }
        var textureTokens: [Token: MTLTexture] = [:]
        var costs: [Token: Int] = [:]
        var tokenSlots: [Token: Int] = [:]
        var eligible: [EffectKey: Set<Token>] = [:]
        for slot in plan.slots {
            guard let texture = texturesBySlot[slot.id],
                  let token = tokenBySlot[slot.id],
                  let bytes = byteCost(slot.descriptor) else { return nil }
            textureTokens[token] = texture
            costs[token] = bytes
            tokenSlots[token] = slot.id
            if let effect = slot.historyEffect {
                eligible[effect, default: []].insert(token)
            }
        }
        var required: [EffectKey: Int] = [:]
        for stage in plan.stages {
            guard let effect = stage.plan.output.effect else { return nil }
            if !stage.historyClosureIdentities.isEmpty {
                required[effect] = stage.historyClosureIdentities.count
            }
        }
        guard Set(required.keys) == plan.historyEffects,
              required.allSatisfy({ eligible[$0.key, default: []].count == $0.value }) else {
            return nil
        }
        return .init(
            plan: plan,
            leases: leases,
            texturesBySlot: texturesBySlot,
            tokenBySlot: tokenBySlot,
            generation: generation,
            fullFramePairGeneration: pairGeneration,
            historyEligibleTokensByEffect: eligible,
            requiredHistoryTokenCountByEffect: required,
            texturesByToken: textureTokens,
            byteCostsByToken: costs,
            slotByToken: tokenSlots
        )
    }

    func validatedHistoryTokens(
        _ requested: [EffectKey: Set<Token>],
        discarding discardedEffects: Set<EffectKey> = []
    ) -> Set<Token>? {
        let requiredEffects = Set(requiredHistoryTokenCountByEffect.keys)
        guard discardedEffects.isSubset(of: requiredEffects),
              Set(requested.keys) == requiredEffects.subtracting(discardedEffects)
        else { return nil }
        var union = Set<Token>()
        for (effect, count) in requiredHistoryTokenCountByEffect {
            if discardedEffects.contains(effect) { continue }
            guard let tokens = requested[effect], tokens.count == count,
                  tokens.isSubset(of: historyEligibleTokensByEffect[effect, default: []]),
                  union.isDisjoint(with: tokens) else { return nil }
            union.formUnion(tokens)
        }
        return union
    }

    func historyResidency(
        tokensByEffect: [EffectKey: Set<Token>]
    ) -> SceneGraphHistoryResidency? {
        let tokens = tokensByEffect.values.reduce(into: Set<Token>()) {
            $0.formUnion($1)
        }
        let textures = texturesByToken.filter { tokens.contains($0.key) }
        let costs = byteCostsByToken.filter { tokens.contains($0.key) }
        let slots = slotByToken.filter { tokens.contains($0.key) }
        guard textures.count == tokens.count,
              costs.count == tokens.count,
              slots.count == tokens.count else { return nil }
        return .init(
            plan: plan,
            generation: generation,
            texturesByToken: textures,
            byteCostsByToken: costs,
            slotByToken: slots,
            tokensByEffect: tokensByEffect
        )
    }

    private static func byteCost(
        _ descriptor: SceneLayerGraphTargetPlan.Descriptor
    ) -> Int? {
        let (pixels, pixelOverflow) = descriptor.extent.width
            .multipliedReportingOverflow(by: descriptor.extent.height)
        guard !pixelOverflow else { return nil }
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(
            by: descriptor.format.logicalBytesPerPixel
        )
        return byteOverflow ? nil : bytes
    }
}
