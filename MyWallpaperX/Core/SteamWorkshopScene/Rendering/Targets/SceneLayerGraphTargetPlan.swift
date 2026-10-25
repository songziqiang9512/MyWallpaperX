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
        let addressMode: TargetPlan.UVAddressMode
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
        /// Original input digest for raw table validation. Production carries
        /// the captured static execution with this target plan.
        let makeInputsDigest: Int
        let preparedExecution: SceneGraphExecutionState.PreparedExecution?
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
    let capabilityID: UUID?

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
        pairStorage: FullFramePairStorage = .owned,
        makeInputsDigests: [Int],
        admittedGraphs: [Graph]? = nil,
        materialFunctionTargetsByEffect: [Graph.EffectKey: Set<Graph.TextureIdentity>] = [:],
        capabilityID: UUID? = nil
    ) -> Result<Self, Failure> {
        guard byteBudget >= 0 else { return .failure(.invalidBudget) }
        guard let first = plans.first,
              plans.count == pairPlan.effects.count,
              admittedGraphs == nil || admittedGraphs?.count == plans.count,
              first.layerID == pairPlan.layerID else {
            return .failure(.invalidGraph)
        }
        let effects = plans.compactMap(\.output.effect)
        guard effects == pairPlan.effects.map(\.effect),
              Set(effects).count == effects.count,
              plans.allSatisfy({
                  $0.layerID == first.layerID && $0.inputExtent == first.inputExtent
                    && $0.backbufferFormat == first.backbufferFormat
              }) else { return .failure(.invalidGraph) }

        let pairDescriptor = Descriptor(
            extent: first.inputExtent,
            format: first.backbufferFormat,
            addressMode: .clampToEdge
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
            let preparedExecution: SceneGraphExecutionState.PreparedExecution?
            if let admittedGraphs {
                switch SceneGraphExecutionState.prepareExecution(
                    graph: admittedGraphs[index], plan: plan, pairStep: pairStep,
                    materialFunctionTargets: materialFunctionTargetsByEffect[pairStep.effect] ?? []
                ) {
                case let .success(value): preparedExecution = value
                case .failure: return .failure(.invalidPlan)
                }
            } else {
                preparedExecution = nil
            }
            let identities = [plan.input]
                + plan.logicalTargets.map(\.identity) + [plan.output]
            guard Set(identities).count == identities.count,
                  plan.input == pairStep.inputIdentity,
                  plan.output == pairStep.outputIdentity,
                  let historyClosure = preparedExecution?.historyClosureIdentities
                    ?? SceneGraphExecutionState.historyClosure(in: plan) else {
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
                            format: target.format,
                            addressMode: target.addressMode
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
                historyClosureIdentities: historyClosure,
                makeInputsDigest: index < makeInputsDigests.count
                    ? makeInputsDigests[index] : 0,
                preparedExecution: preparedExecution
            ))
            priorOrdinaryFramebufferSlots = framebufferSlots.filter {
                slots[$0].historyEffect == nil && !slots[$0].isEffectUnique
            }
        }
        guard stages.last?.pairStep.outputMember == pairPlan.terminalMember,
              pairPlan.terminalMember == PairPlan.fixedTerminalMember else {
            return .failure(.invalidPlan)
        }

        let pairSlots = Set([pair.zeroSlot, pair.oneSlot])
        var resident = 0
        var history = 0
        // Shared pair textures are charged by the pool that owns them.
        for slot in slots where pairStorage == .owned || !pairSlots.contains(slot.id) {
            let (pixels, pixelOverflow) = slot.descriptor.extent.width
                .multipliedReportingOverflow(by: slot.descriptor.extent.height)
            guard !pixelOverflow else { return .failure(.byteCostOverflow) }
            let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(
                by: slot.descriptor.format.logicalBytesPerPixel
            )
            let (nextResident, totalOverflow) = resident.addingReportingOverflow(bytes)
            guard !byteOverflow, !totalOverflow else {
                return .failure(.byteCostOverflow)
            }
            resident = nextResident
            if slot.historyEffect != nil {
                let (nextHistory, overflow) = history.addingReportingOverflow(bytes)
                guard !overflow else { return .failure(.byteCostOverflow) }
                history = nextHistory
            }
        }
        // History is retained only from authored framebuffer slots. The
        // full-frame pair is a submission-scoped working surface, so sharing
        // it cannot move either pair member into the history closure.
        let historySlots = Set(slots.compactMap {
            $0.historyEffect == nil ? nil : $0.id
        })
        guard historySlots.isDisjoint(with: pairSlots) else {
            return .failure(.invalidPlan)
        }
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
            historyByteCost: history,
            capabilityID: capabilityID
        ))
    }
}
