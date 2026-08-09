import CoreGraphics
import Foundation
import Metal

/// Prepares one complete R4 layer transaction before appending any Metal
/// command. The layer full-frame pair is captured once and shared by every
/// admitted effect; persistent state remains limited to authored FBOs.
final class SceneResolvedMaterialGraphExecutor {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias State = SceneGraphExecutionState
    typealias Pair = SceneLayerFullFramePairPlan

    enum Failure: Error, Equatable {
        case invalidClaim
        case invalidFrame
        case invalidLease
        case stateRejected
        case historyRejected
        case graphPublicationRejected
        case graphStructureRejected
        case materialFinalizerRejected(
            nodeIndex: Int,
            materialOrdinal: Int,
            failure: SceneResolvedMaterialFailure
        )
        case materialPassEncoderRejected
        case materialPassPreparationRejected(
            stageIndex: Int,
            nodeIndex: Int,
            materialOrdinal: Int,
            programKey: String,
            failure: SceneResolvedMaterialPassEncoder.PreparationFailure
        )
        case dedicatedLeafRejected(reason: String)
        case resourceCommandRejected
        case captureRejected
        case encodeRejected
        case contentGenerationOverflow
        case stalePreparation

        var rawValue: String {
            switch self {
            case .invalidClaim: "invalid-claim"
            case .invalidFrame: "invalid-frame"
            case .invalidLease: "invalid-lease"
            case .stateRejected: "state-rejected"
            case .historyRejected: "history-rejected"
            case .graphPublicationRejected: "graph-publication-rejected"
            case .graphStructureRejected: "graph-structure-rejected"
            case let .materialFinalizerRejected(nodeIndex, ordinal, failure):
                "node-\(nodeIndex)-material-\(ordinal)-finalizer-"
                    + "\(failure.phase.rawValue)-\(failure.code.rawValue)"
                    + Self.detailSuffix(failure.boundedDetails.first)
            case .materialPassEncoderRejected: "material-pass-encoder-rejected"
            case let .materialPassPreparationRejected(
                stageIndex, nodeIndex, ordinal, programKey, failure
            ):
                "stage-\(stageIndex)-node-\(nodeIndex)-material-\(ordinal)-"
                    + "program-\(programKey.prefix(12))-pass-\(failure.code)-rejected"
            case .dedicatedLeafRejected(let reason):
                "dedicated-leaf-rejected-\(reason)"
            case .resourceCommandRejected: "resource-command-rejected"
            case .captureRejected: "capture-rejected"
            case .encodeRejected: "encode-rejected"
            case .contentGenerationOverflow: "content-generation-overflow"
            case .stalePreparation: "stale-preparation"
            }
        }

        private static func detailSuffix(_ value: String?) -> String {
            guard let value, !value.isEmpty else { return "" }
            let characters = value.utf8.prefix(64).map { byte -> Character in
                switch byte {
                case 45, 46, 48 ... 57, 65 ... 90, 95, 97 ... 122:
                    Character(UnicodeScalar(byte))
                default:
                    "_"
                }
            }
            return "-detail-" + String(characters)
        }
    }

    struct PreparedTransition {
        let effect: Graph.EffectKey
        let graph: Graph
        let pairStep: Pair.EffectStep
        let transition: State.Transition
        let programCacheKeys: [String]
        /// Complete readable FBO publications for this frame's candidate.
        let frameResources: [Graph.TextureIdentity: SceneFrameTextureResource]
        /// History-only publications allowed to survive in a committed tail.
        let persistentResources: [Graph.TextureIdentity: SceneFrameTextureResource]
        let effectOutputResource: SceneFrameTextureResource
    }

    struct PreparedChain {
        let transitions: [PreparedTransition]
        let finalTexture: MTLTexture
        let finalResource: SceneFrameTextureResource
        let historyTokensByEffect: [Graph.EffectKey: Set<State.PhysicalToken>]

        fileprivate let ownerToken: UUID
        fileprivate let resetGeneration: UInt64
        fileprivate let queueIdentity: ObjectIdentifier
        fileprivate let commands: [Command]
    }

    struct PairAtom {
        let member: Pair.Member
        let resource: SceneFrameTextureResource
        let representation: SceneShaderColorRepresentation
    }

    struct HistoryContext {
        let rehydration: [State.PhysicalToken: State.PhysicalToken]
        let commands: [SceneGraphResourcePassEncoder.PreparedCommand]
        /// A descriptor-changing reprepare preserves the logical swap
        /// permutation but intentionally starts the new storage transparent.
        let discardsPreviousContent: Bool
    }

    enum Command {
        case resource(SceneGraphResourcePassEncoder.PreparedCommand)
        case material(SceneResolvedMaterialPassEncoder.PreparedPass)
        case dedicated(SceneAuthoredEffectChainRenderer.PreparedStage)
    }

    let device: MTLDevice
    let capabilities: SceneResolvedMaterialExecutionCapabilityCatalog
    let materialEncoder: SceneResolvedMaterialPassEncoder
    private let ownerToken = UUID()
    var resourceEncoder: SceneGraphResourcePassEncoder?
    private var queueIdentity: ObjectIdentifier?
    private var resetGeneration: UInt64 = 0
    private var pairContentGeneration: UInt64 = 0

    init?(
        device: MTLDevice,
        capabilities: SceneResolvedMaterialExecutionCapabilityCatalog
    ) {
        guard let materialEncoder = SceneResolvedMaterialPassEncoder(device: device) else {
            return nil
        }
        self.device = device
        self.capabilities = capabilities
        self.materialEncoder = materialEncoder
    }

    func prepare(
        token: SceneResolvedMaterialExecutionCapabilityCatalog.Token,
        leases: [SceneGraphRenderTargetLease],
        historyRehydrateCopiesByEffect: [
            Graph.EffectKey: [ScenePreparedPersistentGraphTargets.HistoryRehydrateCopy]
        ],
        frame: SceneResolvedMaterialFrameSnapshot,
        sourceTexture: MTLTexture?,
        sourceUniforms: SceneLayerFragmentUniforms?,
        sourcePipeline: SceneImageLayerPipeline,
        dedicatedInputs: SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs,
        commandBuffer: MTLCommandBuffer,
        previousStates: [Graph.EffectKey: State],
        previousGraphResources: [
            Graph.EffectKey: [Graph.TextureIdentity: SceneFrameTextureResource]
        ],
        effectGeneration: UInt64,
        resetGeneration: UInt64
    ) -> Result<PreparedChain, Failure> {
        guard let capability = capabilities.resolve(token),
              validate(capability: capability, leases: leases),
              commandBuffer.status == .notEnqueued,
              commandBuffer.commandQueue.device.registryID == device.registryID,
              ensureResourceEncoder(commandBuffer.commandQueue),
              let firstLease = leases.first else {
            return .failure(.invalidClaim)
        }
        let baseTarget = pairTexture(
            lease: firstLease,
            member: capability.pairPlan.baseCaptureMember
        )
        let baseCommand: SceneGraphResourcePassEncoder.PreparedCommand
        switch capability.sourceRoute {
        case .capturedLayerTexture, .capturedMainTargetTexture:
            guard let sourceTexture, let sourceUniforms,
                  let capture = resourceEncoder?.prepareSourceCapture(
                      source: sourceTexture,
                      target: baseTarget,
                      uniforms: sourceUniforms,
                      pipeline: sourcePipeline
                  ) else { return .failure(.captureRejected) }
            baseCommand = capture
        case .transparentDirectDraw:
            guard sourceTexture == nil, sourceUniforms == nil,
                  let initialization = resourceEncoder?.prepareInitialization(
                      target: baseTarget,
                      clear: .init(red: 0, green: 0, blue: 0, alpha: 0)
                  ) else { return .failure(.captureRejected) }
            baseCommand = initialization
        }
        guard let captureGeneration = nextPairGeneration(),
              let base = pairResource(
                  lease: firstLease,
                  identity: capability.pairPlan.baseCaptureIdentity,
                  member: capability.pairPlan.baseCaptureMember,
                  generation: captureGeneration,
                  representation: .premultipliedAlpha
              ) else { return .failure(.contentGenerationOverflow) }

        var commands: [Command] = [.resource(baseCommand)]
        var pair = PairAtom(
            member: capability.pairPlan.baseCaptureMember,
            resource: base,
            representation: .premultipliedAlpha
        )
        var publications = [
            capability.pairPlan.baseCaptureIdentity: base,
        ]
        var transitions: [PreparedTransition] = []

        for index in capability.stages.indices {
            let stageCapability = capability.stages[index]
            let product = stageCapability.product
            let graph = product.graph
            let pairStep = capability.pairPlan.effects[index]
            let lease = leases[index]
            guard let effect = graph.effects.first?.key,
                  effect == pairStep.effect,
                  pair.member == pairStep.inputMember,
                  let input = pairResource(
                      lease: lease,
                      identity: pairStep.inputIdentity,
                      member: pair.member,
                      generation: pair.resource.resourceGeneration,
                      representation: pair.representation
                  ) else { return .failure(.invalidLease) }
            publications[pairStep.inputIdentity] = input
            pair = .init(
                member: pair.member,
                resource: input,
                representation: pair.representation
            )

            let previous = previousStates[effect] ?? .empty
            let previousResources = previousGraphResources[effect] ?? [:]
            guard let history = prepareHistoryContext(
                historyRehydrateCopiesByEffect[effect] ?? [],
                previous: previous,
                previousResources: previousResources,
                lease: lease,
                effectGeneration: effectGeneration,
                resetGeneration: resetGeneration
            ) else { return .failure(.historyRejected) }
            let reduction = State.reduce(
                graph: graph,
                targetPlan: lease.table.plan,
                pairStep: pairStep,
                allocation: lease.framebufferAllocation,
                effectGeneration: effectGeneration,
                resetGeneration: resetGeneration,
                previous: previous,
                historyRehydration: history.rehydration
            )
            guard case let .success(transition) = reduction,
                  publishRehydratedHistory(
                      transition: transition,
                      previous: previous,
                      previousResources: previousResources,
                      history: history,
                      lease: lease,
                      publications: &publications
                  ) else { return .failure(.stateRejected) }
            commands.append(contentsOf: history.commands.map(Command.resource))

            var programKeys: [String] = []
            if let failure = prepare(
                stageIndex: index,
                transition: transition,
                graph: graph,
                pairStep: pairStep,
                stageCapability: stageCapability,
                capability: capability,
                lease: lease,
                frame: frame,
                sourcePipeline: sourcePipeline,
                time: dedicatedInputs.time,
                dedicatedInputs: dedicatedInputs,
                pair: &pair,
                publications: &publications,
                commands: &commands,
                programKeys: &programKeys
            ) {
                return .failure(failure)
            }
            guard pair.member == pairStep.outputMember,
                  let final = publications[pairStep.outputIdentity],
                  final.publication.texture === pair.resource.publication.texture,
                  final.resourceGeneration == pair.resource.resourceGeneration,
                  final.publication.isSameAtom(as: pair.resource.publication),
                  let frameResources = resources(
                      matching: transition.transaction.mappingAfter,
                      from: publications
                  ), let persistentResources = resources(
                      matching: transition.nextState.logicalMapping,
                      from: publications
                  ) else { return .failure(.graphPublicationRejected) }
            transitions.append(.init(
                effect: effect,
                graph: graph,
                pairStep: pairStep,
                transition: transition,
                programCacheKeys: programKeys,
                frameResources: frameResources,
                persistentResources: persistentResources,
                effectOutputResource: final
            ))
        }

        guard pair.member == capability.pairPlan.terminalMember,
              pair.member == Pair.fixedTerminalMember,
              pair.representation == .opaque
                || pair.representation == .premultipliedAlpha,
              let terminal = transitions.last?.effectOutputResource,
              terminal.publication.requestIdentity
                == .graph(capability.pairPlan.terminalOutputIdentity),
              terminal.publication.texture === pair.resource.publication.texture,
              let queueIdentity,
              let historyTokens = historyTokens(transitions) else {
            return .failure(.graphPublicationRejected)
        }
        return .success(.init(
            transitions: transitions,
            finalTexture: terminal.publication.texture,
            finalResource: terminal,
            historyTokensByEffect: historyTokens,
            ownerToken: ownerToken,
            resetGeneration: self.resetGeneration,
            queueIdentity: queueIdentity,
            commands: commands
        ))
    }

    /// `true` means every preflighted command was appended. Commit still waits
    /// for final compositor conservation and GPU completion.
    func encode(_ chain: PreparedChain, commandBuffer: MTLCommandBuffer) -> Bool {
        guard chain.ownerToken == ownerToken,
              chain.resetGeneration == resetGeneration,
              chain.queueIdentity == ObjectIdentifier(commandBuffer.commandQueue),
              commandBuffer.status == .notEnqueued else { return false }
        for command in chain.commands {
            let encoded: Bool
            switch command {
            case let .resource(value):
                encoded = resourceEncoder?.encode(value, commandBuffer: commandBuffer) == true
            case let .material(value):
                encoded = materialEncoder.encode(value, commandBuffer: commandBuffer)
            case let .dedicated(value):
                encoded = SceneAuthoredEffectChainRenderer.encodePreparedStage(
                    value,
                    commandBuffer: commandBuffer
                )
            }
            guard encoded else { return false }
        }
        return true
    }

    @discardableResult
    func reset() -> Bool {
        guard resetGeneration < UInt64.max else { return false }
        resetGeneration += 1
        materialEncoder.reset()
        resourceEncoder?.reset()
        return true
    }

    private func ensureResourceEncoder(_ queue: MTLCommandQueue) -> Bool {
        let identity = ObjectIdentifier(queue)
        if let queueIdentity { return queueIdentity == identity }
        queueIdentity = identity
        resourceEncoder = .init(commandQueue: queue)
        return true
    }

    func nextPairGeneration() -> UInt64? {
        guard pairContentGeneration < UInt64.max else { return nil }
        pairContentGeneration += 1
        return pairContentGeneration
    }
}
