import Foundation
import Metal

struct SceneGraphMaterialFunctionInvocationRequest {}
struct SceneGraphClearFunctionRegistry {
    init() {}
}

struct SceneAuthoredEffectRenderPlan {
    struct EffectKey: Hashable {
        let layerID: Int
        let effectIndex: Int
        let descriptorID: String
    }
    enum TextureKind: Hashable { case framebuffer, effectOutput, layerSource }
    struct TextureIdentity: Hashable {
        let kind: TextureKind
        let layerID: Int
        let effect: EffectKey?
        let name: String?
    }
    enum NodeKind: Equatable { case material, copy, swap }
    struct Node {
        let nodeIndex: Int
        let kind: NodeKind
        let materialOrdinal: Int?
        let commandSource: TextureIdentity?
        let commandTarget: TextureIdentity?

        init(
            nodeIndex: Int,
            kind: NodeKind,
            materialOrdinal: Int? = nil,
            commandSource: TextureIdentity? = nil,
            commandTarget: TextureIdentity? = nil
        ) {
            self.nodeIndex = nodeIndex
            self.kind = kind
            self.materialOrdinal = materialOrdinal
            self.commandSource = commandSource
            self.commandTarget = commandTarget
        }
    }
    struct Effect { let key: EffectKey }
    let layerID: Int
    let effects: [Effect]
    let nodes: [Node]
    let renderTargets: [TextureIdentity]

    init(
        layerID: Int,
        effects: [Effect],
        nodes: [Node],
        renderTargets: [TextureIdentity] = []
    ) {
        self.layerID = layerID
        self.effects = effects
        self.nodes = nodes
        self.renderTargets = renderTargets
    }
}

struct SceneLayerFullFramePairPlan {
    enum Member { case zero, one }
    struct NodeStep {
        let nodeIndex: Int
        let kind: SceneAuthoredEffectRenderPlan.NodeKind
        let rotatesAfterNode: Bool
    }
    struct EffectStep {
        let effect: SceneAuthoredEffectRenderPlan.EffectKey
        let inputIdentity: SceneAuthoredEffectRenderPlan.TextureIdentity
        let outputIdentity: SceneAuthoredEffectRenderPlan.TextureIdentity
        let inputMember: Member
        let outputMember: Member
        let nodes: [NodeStep]
    }
    let layerID: Int
}

struct SceneGraphExecutionState {
    typealias Identity = SceneAuthoredEffectRenderPlan.TextureIdentity
    static let maximumNodeCount = 512
    static let maximumLogicalBindingCount = 512
    struct PhysicalToken: Hashable { let rawValue: String }
    struct ResourceDescriptor: Equatable {
        let extent: SceneGraphRenderTargetPlan.PixelExtent
        let format: SceneGraphRenderTargetPlan.TextureFormat
        let addressMode: SceneGraphRenderTargetPlan.UVAddressMode

        init(
            extent: SceneGraphRenderTargetPlan.PixelExtent = .init(
                width: 2,
                height: 2
            ),
            format: SceneGraphRenderTargetPlan.TextureFormat = .rgbaBackbuffer,
            addressMode: SceneGraphRenderTargetPlan.UVAddressMode
        ) {
            self.extent = extent
            self.format = format
            self.addressMode = addressMode
        }
    }
    struct VersionedResource {
        let token: PhysicalToken
        let descriptor: ResourceDescriptor
        let contentGeneration: UInt64

        init(
            token: PhysicalToken,
            descriptor: ResourceDescriptor = .init(addressMode: .clampToEdge),
            contentGeneration: UInt64
        ) {
            self.token = token
            self.descriptor = descriptor
            self.contentGeneration = contentGeneration
        }
    }
    enum InitializationReason { case authoredClear }
    struct MaterialBinding {}
    struct MaterialTarget {}
    enum Intent {
        case initialize(
            identity: Identity,
            resource: VersionedResource,
            reason: InitializationReason
        )
        case material(
            nodeIndex: Int,
            materialOrdinal: Int,
            bindings: [MaterialBinding],
            target: MaterialTarget?
        )
        case copy(
            nodeIndex: Int,
            commandOrdinal: Int,
            source: Identity,
            sourceResource: VersionedResource,
            target: Identity,
            targetResource: VersionedResource
        )
        case swap(
            nodeIndex: Int,
            commandOrdinal: Int,
            source: Identity,
            sourceResource: VersionedResource,
            target: Identity,
            targetResource: VersionedResource
        )
    }
    struct Transaction {
        let intents: [Intent]
        let mappingBefore: [Identity: VersionedResource]
        let mappingAfter: [Identity: VersionedResource]
        let allocationGeneration: UInt64
        let effectGeneration: UInt64
        let resetGeneration: UInt64
    }
    struct Transition {
        let nextState: SceneGraphExecutionState
        let transaction: Transaction
    }
    let effectGeneration: UInt64?
    let resetGeneration: UInt64?
    let allocationGeneration: UInt64?
    let logicalMapping: [Identity: VersionedResource]
    let historyLogicalIdentities: Set<Identity>
    let historyClosureIdentities: Set<Identity>

    func hasSameCompletePlan(as other: Self) -> Bool {
        let lhs = logicalMapping.mapValues(\.descriptor)
        let rhs = other.logicalMapping.mapValues(\.descriptor)
        return lhs == rhs
    }
}

enum SceneTextureLoadPurpose: Hashable {
    case noise
    case premultipliedColor
    case preservedChannels
}
enum SceneTextureProviderIdentity: Hashable {
    case graph(allocationGeneration: UInt64, physicalToken: String)
    case sceneBackground(consumerLayerID: Int, frameEpoch: UInt64)
    var reportToken: String {
        switch self {
        case let .graph(generation, token): return "graph:\(generation):\(token)"
        case let .sceneBackground(layerID, epoch): return "background:\(layerID):\(epoch)"
        }
    }
}
enum SceneTextureCandidateIdentity: Hashable {
    case provider(SceneTextureProviderIdentity)
    case file(String)
    case builtIn(String)
}
struct SceneSystemProviderTextureIdentity: Hashable {
    let name: String
    let purpose: SceneTextureLoadPurpose

    var reportToken: String {
        "system:\(name.utf8.count)#\(name):\(purpose)"
    }
}
struct SceneCompletedColorSourceIdentity: Hashable, Sendable {
    let frameIndex: UInt64
    let frameEpoch: UInt64
    let executionEpoch: UInt64
    let commandBufferObservationID: UUID
    let allocationGeneration: UInt64
    let resetEpoch: UUID
}

enum SceneFrameTextureIdentity: Hashable {
    case graph(SceneAuthoredEffectRenderPlan.TextureIdentity)
    case system(SceneSystemProviderTextureIdentity)
    case sceneBackground(Int)

    var reportToken: String {
        switch self {
        case let .graph(identity):
            let effect = identity.effect.map {
                "\($0.layerID):\($0.effectIndex):\($0.descriptorID)"
            } ?? "none"
            return "graph:\(identity.kind):\(identity.layerID):\(effect):\(identity.name ?? "none")"
        case let .system(identity): return identity.reportToken
        case let .sceneBackground(layerID): return "scene-background:\(layerID)"
        }
    }
}

enum SceneShaderStableDigest {
    static func hash(_ data: Data) -> String { "data-\(data.count)" }
    static func hash(_ graph: SceneAuthoredEffectRenderPlan) -> String {
        "graph-\(graph.layerID)-\(graph.nodes.count)"
    }
}
enum StubAlpha: Hashable { case premultipliedAlpha }
enum StubColor: Hashable { case resolved(StubAlpha) }
enum SceneTextureContent: Hashable {
    case data
    case color(StubColor)
}
enum SceneTextureSampling { case linearClamp, linearRepeat }
struct SceneTextureCandidate {
    let texture: MTLTexture
    let identity: SceneTextureCandidateIdentity
    let purpose: SceneTextureLoadPurpose
    let sampling: SceneTextureSampling
    let content: SceneTextureContent = .color(.resolved(.premultipliedAlpha))

    init(
        texture: MTLTexture,
        identity: SceneTextureCandidateIdentity,
        purpose: SceneTextureLoadPurpose,
        sampling: SceneTextureSampling = .linearClamp
    ) {
        self.texture = texture
        self.identity = identity
        self.purpose = purpose
        self.sampling = sampling
    }
}
struct SceneTextureProviderPublication {
    let requestIdentity: SceneFrameTextureIdentity
    let candidate: SceneTextureCandidate
    let contentGeneration: UInt64
    var texture: MTLTexture { candidate.texture }
    var isComplete: Bool { contentGeneration > 0 }
    func isSameAtom(as other: Self) -> Bool {
        requestIdentity == other.requestIdentity
            && candidate.identity == other.candidate.identity
            && candidate.sampling == other.candidate.sampling
            && contentGeneration == other.contentGeneration
            && texture === other.texture
    }
}
struct SceneFrameTextureResource {
    let publication: SceneTextureProviderPublication
    let resourceGeneration: UInt64
    var isCompleteGraphResource: Bool {
        resourceGeneration > 0
            && publication.contentGeneration == resourceGeneration
    }
    func isCompleteSceneBackground(consumerLayerID: Int, frameEpoch: UInt64) -> Bool {
        resourceGeneration == frameEpoch
            && publication.contentGeneration == frameEpoch
            && publication.requestIdentity == .sceneBackground(consumerLayerID)
            && publication.texture.usage.contains(.renderTarget)
            && publication.texture.usage.contains(.shaderRead)
    }
}

enum SceneResolvedMaterialInFlightCapacity {
    static let maximumSubmissions = 2
}

struct SceneGraphRenderTargetPlan: Equatable {
    enum UVAddressMode { case clampToEdge, repeatWrap }
    enum TextureFormat: String { case rgbaBackbuffer }
    struct PixelExtent: Equatable {
        let width: Int
        let height: Int
    }
    let identity: Int
}
struct SceneGraphRenderTargetTable { let plan: SceneGraphRenderTargetPlan }
struct SceneGraphRenderTargetLease {
    struct FullFramePair {
        let first: SceneGraphExecutionState.PhysicalToken
        let second: SceneGraphExecutionState.PhysicalToken
    }
    let table: SceneGraphRenderTargetTable
    let generation: UInt64
    let texturesByToken: [SceneGraphExecutionState.PhysicalToken: MTLTexture]
    let fullFramePair: FullFramePair

    static func graphSamplingMatches(
        _ resource: SceneFrameTextureResource,
        descriptor: SceneGraphExecutionState.ResourceDescriptor
    ) -> Bool {
        graphSamplingMatches(
            resource,
            expectedSampling: descriptor.addressMode == .repeatWrap
                ? .linearRepeat
                : .linearClamp
        )
    }

    static func graphSamplingMatches(
        _ resource: SceneFrameTextureResource,
        expectedSampling: SceneTextureSampling
    ) -> Bool {
        resource.isCompleteGraphResource
            && resource.publication.candidate.sampling == expectedSampling
    }
}

final class SceneGraphRenderTargetResidencyPin: @unchecked Sendable {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey
    typealias Token = SceneGraphExecutionState.PhysicalToken
    enum Purpose: Hashable { case submission, sceneColor, history(EffectKey, Set<Token>) }
    let purpose: Purpose
    let generation: UInt64
    private(set) var active = true
    private(set) var releaseCount = 0
    init(purpose: Purpose, generation: UInt64) {
        self.purpose = purpose
        self.generation = generation
    }
    func release() {
        guard active else { return }
        active = false
        releaseCount += 1
    }
}

final class ScenePreparedPersistentGraphTargets {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey
    typealias Token = SceneGraphExecutionState.PhysicalToken
    struct HistoryRehydrateCopy {}
    struct Commit {
        let leases: [SceneGraphRenderTargetLease]
        let submissionPin: SceneGraphRenderTargetResidencyPin
        let historyPinsByEffect: [EffectKey: SceneGraphRenderTargetResidencyPin]
        func releaseAll() {
            submissionPin.release()
            historyPinsByEffect.values.forEach { $0.release() }
        }
    }
    let leases: [SceneGraphRenderTargetLease]
    let historyRehydrateCopiesByEffect: [EffectKey: [HistoryRehydrateCopy]]
    private var action: ((
        [EffectKey: Set<Token>],
        Set<EffectKey>,
        MTLCommandBuffer?
    ) -> Commit?)?
    init(
        leases: [SceneGraphRenderTargetLease] = [],
        historyRehydrateCopiesByEffect: [EffectKey: [HistoryRehydrateCopy]] = [:],
        action: ((
            [EffectKey: Set<Token>],
            Set<EffectKey>,
            MTLCommandBuffer?
        ) -> Commit?)? = nil
    ) {
        self.leases = leases
        self.historyRehydrateCopiesByEffect = historyRehydrateCopiesByEffect
        self.action = action
    }
    func commitAndPin(
        historyTokensByEffect: [EffectKey: Set<Token>],
        discardedHistoryEffects: Set<EffectKey> = [],
        commandBuffer: MTLCommandBuffer? = nil
    ) -> Commit? {
        let current = action
        action = nil
        return current?(
            historyTokensByEffect,
            discardedHistoryEffects,
            commandBuffer
        )
    }
}

enum SceneResolvedMaterialExecutionCapabilityAdmission {
    static let maximumEffectsPerLayer = 512
    static let maximumNodesPerLayer = 65_536
}
struct SceneResolvedMaterialAdmittedLayer {
    enum SourceRoute {
        case capturedLayerTexture
        case capturedMainTargetTexture
        case transparentDirectDraw
    }
}
struct SceneEffectPassSlot: Hashable {
    let effectID: String
    let passIndex: Int
    let slotIndex: Int
}
enum SceneNamedTextureReference {
    enum Variant: Hashable {
        case primary
        case secondary
    }
}
struct SceneDependencyRenderPlan {
    struct Reference: Hashable {
        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let variant: SceneNamedTextureReference.Variant
    }
    struct MultiProviderAggregate: Hashable {
        let consumerLayerID: Int
        let bindings: [Binding]
        let authoredSlotOrder: [SceneEffectPassSlot]

        var orderedBindings: [Binding] {
            guard authoredSlotOrder.count == bindings.count else { return [] }
            var bindingsBySlot: [SceneEffectPassSlot: Binding] = [:]
            for binding in bindings {
                guard bindingsBySlot.updateValue(
                    binding, forKey: binding.slot
                ) == nil else { return [] }
            }
            guard bindingsBySlot.count == authoredSlotOrder.count else {
                return []
            }
            return authoredSlotOrder.compactMap { bindingsBySlot[$0] }
        }

        var referenceSlots: [SceneEffectPassSlot] {
            authoredSlotOrder
        }

        var providerLayerIDs: Set<Int> { Set(bindings.map(\.providerLayerID)) }
        var hasStrictBindingVector: Bool {
            guard bindings.count >= 2,
                  authoredSlotOrder.count == bindings.count,
                  Set(authoredSlotOrder).count == authoredSlotOrder.count,
                  Set(authoredSlotOrder) == Set(bindings.map(\.slot)),
                  bindings == orderedBindings,
                  Set(bindings.map(\.providerLayerID)).count > 1 else {
                return false
            }
            return bindings.allSatisfy { binding in
                binding.consumerLayerID == consumerLayerID
                    && binding.providerLayerID != consumerLayerID
                    && binding.referenceSlots == [binding.slot]
                    && binding.kind == .imageLayerBlend
                    && binding.blendMode == 0
                    && binding.requiresResolvedMaterialProgram
            }
        }

        func admits(_ references: [Reference]) -> Bool {
            guard hasStrictBindingVector else { return false }
            let expected = orderedBindings.map {
                Reference(
                    consumerLayerID: consumerLayerID,
                    providerLayerID: $0.providerLayerID,
                    slot: $0.slot,
                    variant: .primary
                )
            }
            return references == expected
        }
    }
}
enum SceneResolvedMaterialDependencyOwnership: Equatable {
    case none
    case graphInternal(referenceCount: Int)
    case externalPrimary(SceneDependencyRenderPlan.Binding)
    case externalAggregate(SceneDependencyRenderPlan.MultiProviderAggregate)

    var isAggregate: Bool {
        if case .externalAggregate = self { return true }
                return false
            }
        }
struct SceneEffectStageExecutionPlan {}
final class SceneResolvedMaterialExecutionCapabilityCatalog {
    struct FrameInputContract: Equatable {
        enum EffectTextureProjectionSource: Equatable {
            case emittedOutputGeometry
        }
        let effectTextureProjectionSource: EffectTextureProjectionSource
        let requiresInvertibleEffectTextureProjection: Bool
    }
    struct SceneBackgroundRequirement: Equatable {
        let layerID: Int
        let effect: SceneAuthoredEffectRenderPlan.EffectKey
        let nodeIndex: Int
        let slot: Int
    }
    struct Token: Hashable { let value: Int }
    struct Claim { let token: Token }
    struct AdmittedProduct {
        let graph: SceneAuthoredEffectRenderPlan
        let clearFunctions: SceneGraphClearFunctionRegistry

        init(
            graph: SceneAuthoredEffectRenderPlan,
            clearFunctions: SceneGraphClearFunctionRegistry = .init()
        ) {
            self.graph = graph
            self.clearFunctions = clearFunctions
        }
    }
    struct ExactEffectSubject: Hashable {
        let key: SceneAuthoredEffectRenderPlan.EffectKey
        let family: String
    }
    struct RuntimeDispositionOwnership {
        let layerID: Int
        let subjects: [ExactEffectSubject]
    }
    struct StageCapability {
        let subject: ExactEffectSubject?
        let dedicatedExecutionPlan: SceneEffectStageExecutionPlan?
        let visualFailureReasonCode: String?

        init(
            subject: ExactEffectSubject?,
            dedicatedExecutionPlan: SceneEffectStageExecutionPlan? = nil,
            visualFailureReasonCode: String? = nil
        ) {
            self.subject = subject
            self.dedicatedExecutionPlan = dedicatedExecutionPlan
            self.visualFailureReasonCode = visualFailureReasonCode
        }
    }
    struct ChainCapability {
        let layerID: Int
        let pairPlan: SceneLayerFullFramePairPlan
        let admittedProducts: [AdmittedProduct]
        let stages: [StageCapability]
        let dependencyOwnership: SceneResolvedMaterialDependencyOwnership
        let sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute
        let sceneBackgroundRequirement: SceneBackgroundRequirement? = nil
        let frameInputContract = FrameInputContract(
            effectTextureProjectionSource: .emittedOutputGeometry,
            requiresInvertibleEffectTextureProjection: false
        )
        var effectSubjectsAreConserved: Bool {
            let expected = admittedProducts.flatMap { $0.graph.effects.map(\.key) }
            return !expected.isEmpty && Set(expected).count == expected.count
        }
    }
    typealias LayerCapability = ChainCapability
    let capabilitiesByLayerID: [Int: ChainCapability]
    let resolvesClaims: Bool
    init(
        capability: ChainCapability? = nil,
        additionalCapabilities: [ChainCapability] = [],
        resolvesClaims: Bool = true
    ) {
        let values = ([capability].compactMap { $0 } + additionalCapabilities)
        self.capabilitiesByLayerID = Dictionary(
            uniqueKeysWithValues: values.map { ($0.layerID, $0) }
        )
        self.resolvesClaims = resolvesClaims
    }
    func claim(layerID: Int) -> Claim? {
        capabilitiesByLayerID[layerID] == nil
            ? nil : .init(token: .init(value: layerID))
    }
    func productAuthorityRejectionReason(layerID: Int) -> String? { nil }
    func resolve(_ token: Token) -> ChainCapability? {
        resolvesClaims ? capabilitiesByLayerID[token.value] : nil
    }
    var runtimeDispositionOwnerships: [RuntimeDispositionOwnership] {
        capabilitiesByLayerID.keys.sorted().compactMap { layerID in
            guard let capability = capabilitiesByLayerID[layerID] else { return nil }
            return .init(
                layerID: layerID,
                subjects: capability.stages.compactMap(\.subject)
            )
        }
    }
    var executionLayerIDs: Set<Int> { Set(capabilitiesByLayerID.keys) }
    // The legacy one-phase inputs contain no authored environment sampler.
    func requiresSceneEnvironment(layerID: Int) -> Bool { false }
    var visibilityOwnedLayerIDs: Set<Int> { [] }
    var admittedResolvedMaterialReferences:
        Set<SceneDependencyRenderPlan.Reference> { [] }
    var sceneBackgroundLayerIDs: Set<Int> {
        Set(capabilitiesByLayerID.values.compactMap {
            $0.sceneBackgroundRequirement?.layerID
        })
    }
}

struct SceneLayerGraphTargetPlan {
    struct Key { let layerID: Int }
    let key: Key
}
struct ScenePersistentGraphTargetFramePlan {
    let graphPlan: SceneLayerGraphTargetPlan
}
struct SceneResolvedMaterialFrameTargetPlan {
    let token: SceneResolvedMaterialExecutionCapabilityCatalog.Token
    let allocation: ScenePersistentGraphTargetFramePlan
}
enum SceneOffscreenTextureFramePreflight {
    enum Result {
        case ready
        case temporarilyBlocked
        case rejected(reasonCode: String)
    }
}
final class SceneFramePerformanceTelemetry: @unchecked Sendable {
    func beginStage(_ name: String) {}
    func endStage(_ name: String) {}
}

final class SceneOffscreenTexturePool {
    // Legacy graph tests never reserve terminal color. The dedicated RF07
    // fixture compiles the real pool and coordinator together instead.
    enum SceneColorIntent: Hashable { case persistence, snapshot }
    enum CacheKey: Hashable {
        case sceneColor(width: Int, height: Int, pixelFormat: MTLPixelFormat,
                        intent: SceneColorIntent)
    }
    let pixelFormat: MTLPixelFormat = .rgba16Float
    struct SceneColorTargets {
        struct Identity { let generation: UInt64 }
        let first: MTLTexture
        let second: MTLTexture
        let display: MTLTexture?
        let intent: SceneColorIntent
        let identity: Identity
        func raw(_ member: Int) -> MTLTexture { member == 0 ? first : second }
    }
    struct SceneColorLease {
        let targets: SceneColorTargets
        let key: CacheKey
        let resetEpoch: UUID
        let retention: SceneGraphRenderTargetResidencyPin
        let submission: SceneGraphRenderTargetResidencyPin
        func release() { retention.release(); submission.release() }
    }
    let sceneColorResetEpoch = UUID()
    func reserveDisplayScratch(width: Int, height: Int, commandBuffer: MTLCommandBuffer)
        -> (texture: MTLTexture, pin: SceneGraphRenderTargetResidencyPin)? { nil }
    func reserveSceneColor(width: Int, height: Int,
                           intent: SceneColorIntent = .persistence) -> SceneColorLease? { nil }
    typealias Factory = (
        ScenePersistentGraphTargetFramePlan
    ) -> ScenePreparedPersistentGraphTargets?
    let factory: Factory
    let preflightResult: SceneOffscreenTextureFramePreflight.Result
    private(set) var batchCommitCount = 0
    private(set) var discardedHistoryEffectsByCommit: [[
        Set<ScenePreparedPersistentGraphTargets.EffectKey>
    ]] = []
    init(
        prepared: ScenePreparedPersistentGraphTargets? = .init(),
        factory: Factory? = nil,
        preflightResult: SceneOffscreenTextureFramePreflight.Result = .ready
    ) {
        self.factory = factory ?? { _ in prepared }
        self.preflightResult = preflightResult
    }
    func preflightPersistentGraphTargets(
        _ plans: [ScenePersistentGraphTargetFramePlan]
    ) -> SceneOffscreenTextureFramePreflight.Result {
        preflightResult
    }
    func preparePersistentGraphTargets(
        framePlan: ScenePersistentGraphTargetFramePlan
    ) -> ScenePreparedPersistentGraphTargets? {
        factory(framePlan)
    }
    func preparePersistentGraphTargets(
        framePlans: [ScenePersistentGraphTargetFramePlan]
    ) -> [ScenePreparedPersistentGraphTargets]? {
        let values = framePlans.compactMap(factory)
        return values.count == framePlans.count ? values : nil
    }
    func preparePreflightedPersistentGraphTargets(
        framePlans: [ScenePersistentGraphTargetFramePlan]
    ) -> [ScenePreparedPersistentGraphTargets]? {
        preparePersistentGraphTargets(framePlans: framePlans)
    }
    func commitAndPinPersistentGraphTargets(
        _ targets: [ScenePreparedPersistentGraphTargets],
        historyTokensByTarget: [[ScenePreparedPersistentGraphTargets.EffectKey:
            Set<ScenePreparedPersistentGraphTargets.Token>]],
        discardedHistoryEffectsByTarget: [
            Set<ScenePreparedPersistentGraphTargets.EffectKey>
        ]? = nil,
        commandBuffer: MTLCommandBuffer
    ) -> [ScenePreparedPersistentGraphTargets.Commit]? {
        let discarded = discardedHistoryEffectsByTarget ?? Array(
            repeating: [],
            count: targets.count
        )
        guard targets.count == historyTokensByTarget.count,
              targets.count == discarded.count else { return nil }
        discardedHistoryEffectsByCommit.append(discarded)
        let commits = zip(
            zip(targets, historyTokensByTarget),
            discarded
        ).compactMap {
            $0.0.0.commitAndPin(
                historyTokensByEffect: $0.0.1,
                discardedHistoryEffects: $0.1,
                commandBuffer: commandBuffer
            )
        }
        guard commits.count == targets.count else {
            commits.forEach { $0.releaseAll() }
            return nil
        }
        batchCommitCount += 1
        return commits
    }
}

struct SceneBaseMaterialLitCapturePayload {}
struct SceneLayerFragmentUniforms {}
struct SceneImageLayerPipeline { static func bindQuad(encoder: MTLRenderCommandEncoder) {} }
struct SceneImageLayerMasks {}
struct SceneAuthoredEffectPipelineSet {}
struct SceneAudioSpectrumSnapshot {}
struct SceneDependencyEffectInput {
    let consumerLayerID: Int
    let providerLayerID: Int
    let variant: SceneNamedTextureReference.Variant
    let slot: SceneEffectPassSlot
    let blendMode: Int
    let frameEpoch: UInt64
    let texture: MTLTexture

    var content: SceneTextureContent = .color(.resolved(.premultipliedAlpha))
    var slotIndex: Int { slot.slotIndex }
    func withContent(_ content: SceneTextureContent) -> Self {
        var result = self
        result.content = content
        return result
    }
}
struct SceneResolvedMaterialFailure: Error {}
struct SceneFrameTextureRegistrySnapshot { let frameIndex: UInt64; let valid: Bool; var frameEpoch: UInt64 { frameIndex } }
struct SceneDynamicSnapshot {}
struct SceneAuthoredShaderFrameInputs {}
struct SceneResolvedMaterialFrameSnapshot {
    let frameIndex: UInt64
    var textureRegistrySnapshot: SceneFrameTextureRegistrySnapshot { .init(frameIndex: frameIndex, valid: true) }
    static func validated(
        textureSnapshot: SceneFrameTextureRegistrySnapshot,
        dynamicSnapshot: SceneDynamicSnapshot,
        frameInputs: SceneAuthoredShaderFrameInputs
    ) -> Result<Self, SceneResolvedMaterialFailure> {
        _ = dynamicSnapshot
        _ = frameInputs
        return textureSnapshot.valid
            ? .success(.init(frameIndex: textureSnapshot.frameIndex))
            : .failure(.init())
    }
}

struct SceneAssetTextureIdentity: Hashable { let value: String }
enum SceneTextureProviderState {
    case ready(SceneTextureProviderPublication)
    case absent
    case pending
    case unavailable
}
struct SceneUserPropertyTextureIdentity: Hashable {
    let propertyKey: String
    let purpose: SceneTextureLoadPurpose
    init?(propertyKey: String, purpose: SceneTextureLoadPurpose) {
        guard !propertyKey.isEmpty else { return nil }
        self.propertyKey = propertyKey
        self.purpose = purpose
    }
}
enum SceneFrameTextureRegistry {
    enum ProviderStatus { case absent, pending, unavailable }
}
enum SceneMediaThumbnailTextureStore {
    struct Snapshot {
        let providerStates: [
            SceneSystemProviderTextureIdentity: SceneTextureProviderState
        ]

        init(
            providerStates: [
                SceneSystemProviderTextureIdentity: SceneTextureProviderState
            ]
        ) {
            self.providerStates = providerStates
        }
    }
}
struct SceneResolvedMaterialRuntimeCatalog {
    let userPropertyDemands: Set<SceneUserPropertyTextureIdentity>
    let systemProviderDemands: Set<SceneSystemProviderTextureIdentity>
}
struct SceneMaterialAssetTextureCatalog {
    final class FrameProvider {
        let catalog: SceneMaterialAssetTextureCatalog

        init(catalog: SceneMaterialAssetTextureCatalog) {
            self.catalog = catalog
        }

        func states(
            sceneTime: TimeInterval
        ) -> [SceneAssetTextureIdentity: SceneTextureProviderState] {
            catalog.states
        }

        func commitFrame() {}
        func discardFrame() {}
    }

    let states: [SceneAssetTextureIdentity: SceneTextureProviderState]

    func makeFrameProvider() -> FrameProvider { .init(catalog: self) }
}

extension SceneResolvedMaterialRuntimeBridge.FrameInputs {
    static let fixture = Self(
        dynamicValues: .init(),
        cursorUV: .zero,
        previousCursorUV: .zero,
        pointerIsInside: false,
        previousPointerIsInside: false,
        pointerMovement: 0,
        primaryButtonIsDown: false,
        layerModelMatrix: .init(diagonal: .init(repeating: 1)),
        effectOutputModelViewProjection: .init(
            diagonal: .init(repeating: 1)
        ),
        effectTextureProjectionMatrixInverse: .init(
            diagonal: .init(repeating: 1)
        ),
        frameTime: 1 / 60,
        time: 0,
        audioSpectrum: .init(),
        dependencyEffects: []
    )

    func replacingDependencyEffects(
        _ dependencyEffects: [SceneDependencyEffectInput]
    ) -> Self {
        .init(
            dynamicValues: dynamicValues,
            cursorUV: cursorUV,
            previousCursorUV: previousCursorUV,
            pointerIsInside: pointerIsInside,
            previousPointerIsInside: previousPointerIsInside,
            pointerMovement: pointerMovement,
            primaryButtonIsDown: primaryButtonIsDown,
            layerModelMatrix: layerModelMatrix,
            effectOutputModelViewProjection:
                effectOutputModelViewProjection,
            effectTextureProjectionMatrixInverse:
                effectTextureProjectionMatrixInverse,
            frameTime: frameTime,
            time: time,
            audioSpectrum: audioSpectrum,
            dependencyEffects: dependencyEffects
        )
    }
}

final class SceneResolvedMaterialGraphExecutor {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias State = SceneGraphExecutionState
    enum Failure: String, Error {
        case unavailable = "fixture-preflight-unavailable"
        case graphStructureRejected = "graph-structure-rejected"
        var isColorContractVisualRejection: Bool { false }
    }
    struct PreparedStage {
        let effect: Graph.EffectKey
        let graph: Graph
        let pairStep: SceneLayerFullFramePairPlan.EffectStep
        let transition: State.Transition
        let inputWidth, inputHeight: Int
        let fullFramePairIsShared: Bool
        let fullFramePairGeneration: UInt64
        let historyRehydrateCopyCount: Int
        let historyContentDiscarded: Bool
        let frameResources: [Graph.TextureIdentity: SceneFrameTextureResource]
        let persistentResources: [Graph.TextureIdentity: SceneFrameTextureResource]
        let effectOutputResource: SceneFrameTextureResource
        let programCacheKeys: [String]
        let effectLocalFailureReasonCode: String?
        let effectLocalActivationBypassReasonCode: String?
        let discardedPersistentTargetState: Bool
    }
    struct PreparedGraph {
        let stages: [PreparedStage]
        let finalResource: SceneFrameTextureResource
        let finalTexture: MTLTexture
        let historyTokensByEffect: [Graph.EffectKey: Set<State.PhysicalToken>]
        let sceneBackgroundResource: SceneFrameTextureResource? = nil
    }
    static var prepareCallCount = 0
    static var prepareTokens: [Int] = []
    static var preparedByToken: [Int: PreparedGraph] = [:]
    static var preparedDependencyTextureByToken: [Int: ObjectIdentifier] = [:]
    static var encodeSucceeds = false
    init?(
        device: MTLDevice,
        capabilities: SceneResolvedMaterialExecutionCapabilityCatalog,
        capturesExecutionDiagnostics: Bool = true
    ) {
        _ = device
        _ = capabilities
        _ = capturesExecutionDiagnostics
    }
    func prepare(
        token: SceneResolvedMaterialExecutionCapabilityCatalog.Token,
        leases: [SceneGraphRenderTargetLease],
        historyRehydrateCopiesByEffect: [Graph.EffectKey: [ScenePreparedPersistentGraphTargets.HistoryRehydrateCopy]],
        frame: SceneResolvedMaterialFrameSnapshot,
        sceneBackgroundResource: SceneFrameTextureResource? = nil,
        sourceTexture: MTLTexture?,
        sourceUniforms: SceneLayerFragmentUniforms?,
        sourcePipeline: SceneImageLayerPipeline,
        sourceLighting: SceneBaseMaterialLitCapturePayload? = nil,
        frameInputs: SceneResolvedMaterialRuntimeBridge.FrameInputs,
        commandBuffer: MTLCommandBuffer,
        previousStates: [Graph.EffectKey: State],
        previousGraphResources: [Graph.EffectKey: [Graph.TextureIdentity: SceneFrameTextureResource]],
        materialFunctionInvocations:
            [SceneGraphMaterialFunctionInvocationRequest] = [],
        effectGeneration: UInt64,
        resetGeneration: UInt64
    ) -> Result<PreparedGraph, Failure> {
        _ = token; _ = leases; _ = historyRehydrateCopiesByEffect; _ = frame
        _ = materialFunctionInvocations; _ = sceneBackgroundResource
        _ = sourceTexture; _ = sourceUniforms; _ = sourcePipeline
        _ = sourceLighting
        _ = frameInputs; _ = commandBuffer
        _ = previousStates; _ = previousGraphResources
        _ = effectGeneration; _ = resetGeneration
        Self.prepareCallCount += 1
        Self.prepareTokens.append(token.value)
        if let texture = frameInputs.dependencyEffects.first?.texture {
            Self.preparedDependencyTextureByToken[token.value] =
                ObjectIdentifier(texture)
        }
        return Self.preparedByToken[token.value].map(Result.success)
            ?? .failure(.unavailable)
    }
    func encode(_ value: PreparedGraph, commandBuffer: MTLCommandBuffer) -> Bool {
        _ = value; _ = commandBuffer; return Self.encodeSucceeds
    }
    func encodeResult(
        _ value: PreparedGraph,
        commandBuffer: MTLCommandBuffer
    ) -> Result<Void, Failure> {
        _ = value; _ = commandBuffer
        return Self.encodeSucceeds ? .success(()) : .failure(.unavailable)
    }
    func reset() -> Bool { true }
}
