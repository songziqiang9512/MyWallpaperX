import Foundation

/// Physical layout for one admitted layer graph. Pair rotation is owned only
/// by `SceneLayerFullFramePairPlan`; this type assigns its two members and the
/// authored FBOs to non-overlapping resident slots.
nonisolated struct SceneLayerGraphTargetPlan: Equatable {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias PairPlan = SceneLayerFullFramePairPlan
    typealias TargetPlan = SceneGraphRenderTargetPlan

    enum FullFramePairStorage: Equatable, Hashable {
        case owned
        case shared
    }

    struct Key: Hashable {
        let layerID: Int
        let effects: [Graph.EffectKey]
        let pairStorage: FullFramePairStorage
    }

    struct Descriptor: Equatable {
        let extent: TargetPlan.PixelExtent
        let format: TargetPlan.TextureFormat
    }

    /// Owner-scoped projection of the verified client cache-key shape. The
    /// cache scope remains this layer graph until cross-owner aliasing is
    /// dynamically proven; `unique` adds effect identity inside that scope.
    struct FramebufferCacheIdentity: Equatable {
        let authoredName: String
        let descriptor: Descriptor
        let uniqueEffect: Graph.EffectKey?
    }

    struct Slot: Equatable {
        enum Kind: Equatable {
            case fullFrame(PairPlan.Member)
            case framebuffer(
                cacheIdentity: FramebufferCacheIdentity,
                historyEffect: Graph.EffectKey?
            )
        }

        let id: Int
        let descriptor: Descriptor
        let kind: Kind

        var historyEffect: Graph.EffectKey? {
            guard case .framebuffer(_, let effect) = kind else { return nil }
            return effect
        }

        var isEffectUnique: Bool {
            framebufferCacheIdentity?.uniqueEffect != nil
        }

        var framebufferCacheIdentity: FramebufferCacheIdentity? {
            guard case .framebuffer(let identity, _) = kind else { return nil }
            return identity
        }
    }

    struct FullFramePair: Equatable {
        let descriptor: Descriptor
        let zeroSlot: Int
        let oneSlot: Int

        func slot(for member: PairPlan.Member) -> Int {
            member == .zero ? zeroSlot : oneSlot
        }
    }

    struct Stage: Equatable {
        let plan: TargetPlan
        let pairStep: PairPlan.EffectStep
        let slotByIdentity: [Graph.TextureIdentity: Int]
        /// Full permutation closure of history-seeded identities through every
        /// authored swap. This must match State.historyClosureIdentities.
        let historyClosureIdentities: Set<Graph.TextureIdentity>
    }

    enum Failure: String, Error {
        case invalidBudget
        case invalidGraph
        case invalidPlan
        case byteCostOverflow
        case byteBudgetExceeded
    }

    let key: Key
    let pairPlan: PairPlan
    let fullFramePair: FullFramePair
    let pairStorage: FullFramePairStorage
    let stages: [Stage]
    let slots: [Slot]
    let residentByteCost: Int
    let historyByteCost: Int

    var ephemeralByteCost: Int { residentByteCost - historyByteCost }
    var fullFramePairByteCost: Int {
        guard pairStorage == .shared else { return 0 }
        let descriptor = fullFramePair.descriptor
        let (pixels, pixelOverflow) = descriptor.extent.width
            .multipliedReportingOverflow(by: descriptor.extent.height)
        guard !pixelOverflow else { return Int.max }
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 8)
        return byteOverflow ? Int.max : bytes
    }

    var sharedPairDimensions: (width: Int, height: Int)? {
        guard pairStorage == .shared else { return nil }
        return (
            fullFramePair.descriptor.extent.width,
            fullFramePair.descriptor.extent.height
        )
    }
    var historyEffects: Set<Graph.EffectKey> {
        Set(slots.compactMap(\.historyEffect))
    }

    static func make(
        plans: [TargetPlan],
        pairPlan: PairPlan,
        byteBudget: Int,
        pairStorage: FullFramePairStorage = .owned
    ) -> Result<Self, Failure> {
        guard byteBudget >= 0 else { return .failure(.invalidBudget) }
        guard let first = plans.first,
              plans.count == pairPlan.effects.count,
              first.layerID == pairPlan.layerID else {
            return .failure(.invalidGraph)
        }
        let effects = plans.compactMap(\.output.effect)
        guard effects == pairPlan.effects.map(\.effect),
              Set(effects).count == effects.count,
              plans.allSatisfy({
                  $0.layerID == first.layerID && $0.inputExtent == first.inputExtent
              }) else { return .failure(.invalidGraph) }

        let pairDescriptor = Descriptor(
            extent: first.inputExtent,
            format: .rgbaBackbuffer
        )
        var slots = [
            Slot(id: 0, descriptor: pairDescriptor, kind: .fullFrame(.zero)),
            Slot(id: 1, descriptor: pairDescriptor, kind: .fullFrame(.one)),
        ]
        let pair = FullFramePair(
            descriptor: pairDescriptor,
            zeroSlot: 0,
            oneSlot: 1
        )
        var stages: [Stage] = []
        var freeFramebufferSlots: [Int] = []
        var priorOrdinaryFramebufferSlots: [Int] = []

        func historyClosureIdentities(
            in plan: TargetPlan
        ) -> Set<Graph.TextureIdentity>? {
            let identities = plan.logicalTargets.map(\.identity)
            guard Set(identities).count == identities.count else { return nil }
            var permutation = Dictionary(
                uniqueKeysWithValues: identities.map { ($0, $0) }
            )
            for command in plan.commands where command.kind == .swap {
                guard let source = permutation[command.source],
                      let target = permutation[command.target] else { return nil }
                permutation[command.source] = target
                permutation[command.target] = source
            }
            var eligible = Set<Graph.TextureIdentity>()
            for target in plan.logicalTargets where target.lifetime.requiresHistorySeed {
                var identity = target.identity
                while eligible.insert(identity).inserted {
                    guard let next = permutation[identity] else { return nil }
                    identity = next
                }
            }
            return eligible
        }

        func takeFramebufferSlot(
            cacheIdentity: FramebufferCacheIdentity,
            historyEffect: Graph.EffectKey?
        ) -> Int {
            if historyEffect == nil, cacheIdentity.uniqueEffect == nil,
               let index = freeFramebufferSlots.firstIndex(where: {
                   slots[$0].framebufferCacheIdentity == cacheIdentity
               }) {
                return freeFramebufferSlots.remove(at: index)
            }
            let id = slots.count
            slots.append(.init(
                id: id,
                descriptor: cacheIdentity.descriptor,
                kind: .framebuffer(
                    cacheIdentity: cacheIdentity,
                    historyEffect: historyEffect
                )
            ))
            return id
        }

        for (index, values) in zip(plans, pairPlan.effects).enumerated() {
            let (plan, pairStep) = values
            let identities = [plan.input]
                + plan.logicalTargets.map(\.identity) + [plan.output]
            guard Set(identities).count == identities.count,
                  plan.input == pairStep.inputIdentity,
                  plan.output == pairStep.outputIdentity,
                  let historyClosure = historyClosureIdentities(in: plan) else {
                return .failure(.invalidPlan)
            }
            if index == 0 {
                guard plan.inputRole == .layerSource,
                      plan.input == pairPlan.baseCaptureIdentity else {
                    return .failure(.invalidGraph)
                }
            } else {
                guard plan.inputRole == .priorEffectOutput,
                      plan.input == plans[index - 1].output else {
                    return .failure(.invalidGraph)
                }
            }

            freeFramebufferSlots.append(contentsOf: priorOrdinaryFramebufferSlots)
            freeFramebufferSlots = Array(Set(freeFramebufferSlots)).sorted()
            var mapping: [Graph.TextureIdentity: Int] = [
                plan.input: pair.slot(for: pairStep.inputMember),
                plan.output: pair.slot(for: pairStep.outputMember),
            ]
            for target in plan.logicalTargets {
                guard let authoredName = target.identity.name, !authoredName.isEmpty else {
                    return .failure(.invalidPlan)
                }
                mapping[target.identity] = takeFramebufferSlot(
                    cacheIdentity: .init(
                        authoredName: authoredName,
                        descriptor: .init(
                            extent: target.extent,
                            format: target.format
                        ),
                        uniqueEffect: target.isUnique ? pairStep.effect : nil
                    ),
                    historyEffect: historyClosure.contains(target.identity)
                        ? pairStep.effect : nil,
                )
            }

            let framebufferSlots = plan.logicalTargets.compactMap {
                mapping[$0.identity]
            }
            let pairSlots = Set([pair.zeroSlot, pair.oneSlot])
            guard mapping.count == identities.count,
                  framebufferSlots.count == plan.logicalTargets.count,
                  Set(framebufferSlots).count == framebufferSlots.count,
                  Set(framebufferSlots).isDisjoint(with: pairSlots),
                  (mapping[plan.input] == mapping[plan.output])
                    == (pairStep.inputMember == pairStep.outputMember) else {
                return .failure(.invalidPlan)
            }
            stages.append(.init(
                plan: plan,
                pairStep: pairStep,
                slotByIdentity: mapping,
                historyClosureIdentities: historyClosure
            ))
            priorOrdinaryFramebufferSlots = framebufferSlots.filter {
                slots[$0].historyEffect == nil && !slots[$0].isEffectUnique
            }
        }
        guard stages.last?.pairStep.outputMember == pairPlan.terminalMember,
              pairPlan.terminalMember == PairPlan.fixedTerminalMember else {
            return .failure(.invalidPlan)
        }

        var total = 0
        var history = 0
        for slot in slots {
            let (pixels, pixelOverflow) = slot.descriptor.extent.width
                .multipliedReportingOverflow(by: slot.descriptor.extent.height)
            guard !pixelOverflow else { return .failure(.byteCostOverflow) }
            let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
            let (nextTotal, totalOverflow) = total.addingReportingOverflow(bytes)
            guard !byteOverflow, !totalOverflow else {
                return .failure(.byteCostOverflow)
            }
            total = nextTotal
            if slot.historyEffect != nil {
                let (nextHistory, overflow) = history.addingReportingOverflow(bytes)
                guard !overflow else { return .failure(.byteCostOverflow) }
                history = nextHistory
            }
        }
        guard pairStorage == .owned || history == 0 else {
            return .failure(.invalidPlan)
        }
        let pairBytes: Int
        let (pairPixels, pairPixelOverflow) = pairDescriptor.extent.width
            .multipliedReportingOverflow(by: pairDescriptor.extent.height)
        guard !pairPixelOverflow else { return .failure(.byteCostOverflow) }
        let (pairCost, pairByteOverflow) = pairPixels.multipliedReportingOverflow(by: 8)
        guard !pairByteOverflow else { return .failure(.byteCostOverflow) }
        pairBytes = pairCost
        let resident = pairStorage == .shared ? total - pairBytes : total
        guard resident >= 0, resident <= byteBudget else {
            return .failure(.byteBudgetExceeded)
        }
        return .success(.init(
            key: .init(
                layerID: first.layerID,
                effects: effects,
                pairStorage: pairStorage
            ),
            pairPlan: pairPlan,
            fullFramePair: pair,
            pairStorage: pairStorage,
            stages: stages,
            slots: slots,
            residentByteCost: resident,
            historyByteCost: history
        ))
    }
}
