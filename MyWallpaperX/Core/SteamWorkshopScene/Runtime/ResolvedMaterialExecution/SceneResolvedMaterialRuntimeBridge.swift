import Foundation
import Metal
import simd

/// Surface-scoped facade for the resolved-material graph runtime. The
/// submission coordinator owns all mutable frame/GPU state; this type only
/// exposes the renderer and provider-facing contract.
final class SceneResolvedMaterialRuntimeBridge {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias State = SceneGraphExecutionState
    typealias LogSink = @Sendable (String) -> Void
    typealias ExactEffectSubject =
        SceneResolvedMaterialExecutionCapabilityCatalog.ExactEffectSubject

    struct ClaimedExecution {
        let layerID: Int
        let admittedGraphs: [Graph]
        let clearFunctionsByEffect: [Graph.EffectKey: SceneGraphClearFunctionRegistry]
        /// Stage-aligned target semantics. A non-nil entry is accepted only
        /// after the same dedicated typed program won capability ownership.
        let targetExecutionPlans: [SceneEffectStageExecutionPlan?]
        let pairPlan: SceneLayerFullFramePairPlan
        let fullFrameExtentPolicy: SceneFullFrameExtentPolicy
        let dependencyOwnership: SceneResolvedMaterialDependencyOwnership
        let sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute
        let sceneBackgroundRequirement:
            SceneResolvedMaterialExecutionCapabilityCatalog.SceneBackgroundRequirement?
        let requiresInvertibleEffectTextureProjection: Bool
        let token: SceneResolvedMaterialExecutionCapabilityCatalog.Token

        fileprivate init(
            layerID: Int,
            admittedGraphs: [Graph],
            clearFunctionsByEffect: [Graph.EffectKey: SceneGraphClearFunctionRegistry],
            targetExecutionPlans: [SceneEffectStageExecutionPlan?],
            pairPlan: SceneLayerFullFramePairPlan,
            fullFrameExtentPolicy: SceneFullFrameExtentPolicy,
            dependencyOwnership: SceneResolvedMaterialDependencyOwnership,
            sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute,
            sceneBackgroundRequirement:
                SceneResolvedMaterialExecutionCapabilityCatalog.SceneBackgroundRequirement? = nil,
            requiresInvertibleEffectTextureProjection: Bool,
            token: SceneResolvedMaterialExecutionCapabilityCatalog.Token
        ) {
            self.layerID = layerID
            self.admittedGraphs = admittedGraphs
            self.clearFunctionsByEffect = clearFunctionsByEffect
            self.targetExecutionPlans = targetExecutionPlans
            self.pairPlan = pairPlan
            self.fullFrameExtentPolicy = fullFrameExtentPolicy
            self.dependencyOwnership = dependencyOwnership
            self.sourceRoute = sourceRoute
            self.sceneBackgroundRequirement = sceneBackgroundRequirement
            self.requiresInvertibleEffectTextureProjection =
                requiresInvertibleEffectTextureProjection
            self.token = token
        }
    }

    enum Claim {
        case notMigrated
        case rejected(reasonCode: String)
        case claimed(ClaimedExecution)
    }

    struct ExecutionTicket: Hashable {
        struct EffectFailure: Hashable {
            let layerID: Int
            let effectIndex: Int
            let descriptorID: String
            let reasonCode: String
        }

        let identity, epoch: UInt64
        let finalTextureIdentity: ObjectIdentifier
        let consumesExternalPrimaryDependency: Bool
        let effectFailures: [EffectFailure]
    }

    enum ExecutionResult {
        case encoded(texture: MTLTexture, ticket: ExecutionTicket)
        case failed(reasonCode: String)
    }

    enum CompositeOutcome {
        case consumed
        case failed(reasonCode: String)
    }

    struct FramePreparationRequest {
        let claim: ClaimedExecution
        let targetPlan: SceneResolvedMaterialFrameTargetPlan
        let materialFunctionInvocations:
            [SceneGraphMaterialFunctionInvocationRequest]
        let sceneBackgroundResource: SceneFrameTextureResource?
        let sourceTexture: MTLTexture?
        let sourceUniforms: SceneLayerFragmentUniforms?
        let sourcePipeline: SceneImageLayerPipeline
        let dedicatedInputs: DedicatedFrameInputs

        init(
            claim: ClaimedExecution,
            targetPlan: SceneResolvedMaterialFrameTargetPlan,
            materialFunctionInvocations:
                [SceneGraphMaterialFunctionInvocationRequest] = [],
            sceneBackgroundResource: SceneFrameTextureResource? = nil,
            sourceTexture: MTLTexture?,
            sourceUniforms: SceneLayerFragmentUniforms?,
            sourcePipeline: SceneImageLayerPipeline,
            dedicatedInputs: DedicatedFrameInputs
        ) {
            self.claim = claim
            self.targetPlan = targetPlan
            self.materialFunctionInvocations = materialFunctionInvocations
            self.sceneBackgroundResource = sceneBackgroundResource
            self.sourceTexture = sourceTexture
            self.sourceUniforms = sourceUniforms
            self.sourcePipeline = sourcePipeline
            self.dedicatedInputs = dedicatedInputs
        }
    }

    struct DedicatedFrameInputs {
        let masks: SceneImageLayerMasks
        let dynamicValues: SceneDynamicSnapshot
        let pipelines: SceneAuthoredEffectPipelineSet
        let cursorUV: SIMD2<Float>
        let previousCursorUV: SIMD2<Float>
        let pointerIsInside: Bool
        let previousPointerIsInside: Bool
        let pointerMovement: Float
        let primaryButtonIsDown: Bool
        let layerModelMatrix: simd_float4x4
        let effectTextureProjectionMatrixInverse: simd_float4x4
        let frameTime: Float
        let time: Float
        let audioSpectrum: SceneAudioSpectrumSnapshot
        let dependencyEffect: SceneDependencyEffectInput?
    }

    enum FramePreparationResult {
        case ready
        case rejected(reasonCode: String)
    }

    private let catalog: SceneResolvedMaterialRuntimeCatalog
    private let capabilities: SceneResolvedMaterialExecutionCapabilityCatalog
    private let assets: SceneMaterialAssetTextureCatalog
    private let submissions: SceneResolvedMaterialSubmissionCoordinator
    private let executionEvidenceLock = NSLock()
    private var executionEvidenceByKey: [Graph.EffectKey: String] = [:]
    private var executionEvidenceIssues: [String: Int] = [:]

    enum ExecutionEvidenceOutcome {
        case encodedOutput
        case failed(reasonCode: String)
    }

    init(
        catalog: SceneResolvedMaterialRuntimeCatalog,
        capabilities: SceneResolvedMaterialExecutionCapabilityCatalog,
        assets: SceneMaterialAssetTextureCatalog,
        device: MTLDevice,
        logSink: @escaping LogSink = { NSLog("%@", $0) }
    ) {
        self.catalog = catalog
        self.capabilities = capabilities
        self.assets = assets
        submissions = .init(
            device: device,
            capabilities: capabilities,
            logSink: logSink
        )
    }

    var assetStates: [SceneAssetTextureIdentity: SceneTextureProviderState] {
        assets.states
    }

    var userPropertyDemands: Set<SceneUserPropertyTextureIdentity> {
        catalog.userPropertyDemands
    }

    var shouldDeferFrame: Bool { submissions.shouldDeferFrame }

    var runtimeDispositionSubjects: [ExactEffectSubject] {
        capabilities.runtimeDispositionOwnerships.flatMap(\.subjects)
    }

    var executionLayerIDs: Set<Int> {
        capabilities.executionLayerIDs
    }

    var sceneBackgroundLayerIDs: Set<Int> {
        capabilities.sceneBackgroundLayerIDs
    }

    func userPropertyDemands(
        including declaredPropertyKeys: [String]
    ) -> Set<SceneUserPropertyTextureIdentity> {
        catalog.userPropertyDemands.union(declaredPropertyKeys.compactMap {
            SceneUserPropertyTextureIdentity(
                propertyKey: $0,
                purpose: .premultipliedColor
            )
        })
    }

    func systemProviderBlocks(
        for snapshot: SceneMediaThumbnailTextureStore.Snapshot
    ) -> [String: SceneFrameTextureRegistry.ProviderStatus] {
        let grouped = Dictionary(grouping: catalog.systemProviderDemands, by: \.name)
        var blocks: [String: SceneFrameTextureRegistry.ProviderStatus] = [:]
        for name in grouped.keys.sorted() {
            guard let demands = grouped[name], demands.count == 1,
                  let demand = demands.first,
                  let publication = snapshot.publications[name],
                  let texture = snapshot.systemTextures[name],
                  publication.requestIdentity == .system(name),
                  publication.texture === texture,
                  publication.candidate.purpose == demand.purpose,
                  publication.isComplete else {
                blocks[name] = .unavailable
                continue
            }
        }
        return blocks
    }

    func beginFrame(
        textureSnapshot: SceneFrameTextureRegistrySnapshot,
        dynamicSnapshot: SceneDynamicSnapshot,
        frameInputs: SceneAuthoredShaderFrameInputs
    ) {
        submissions.beginFrame(
            textureSnapshot: textureSnapshot,
            dynamicSnapshot: dynamicSnapshot,
            frameInputs: frameInputs
        )
    }

    func claim(
        layerID: Int
    ) -> Claim {
        submissions.claim(layerID: layerID)
    }

    func preflightClaim(
        layerID: Int
    ) -> Claim {
        submissions.preflightClaim(layerID: layerID)
    }

    func recordClaimedFailure(reasonCode: String) {
        submissions.recordClaimedFailure(reasonCode: reasonCode)
    }

    func installFrameLocalFallbacks(_ fallbacks: [Int: String]) -> Bool {
        submissions.installFrameLocalFallbacks(fallbacks)
    }

    func deferPreparedFrame() -> Bool {
        submissions.deferPreparedFrame()
    }

    /// Installs the static disposition projection after effect resources have
    /// been loaded.  It is used only to label successful runtime evidence; it
    /// never changes capability admission or claim state.
    func installExecutionEvidence(_ subjects: [ExactEffectSubject]) {
        executionEvidenceLock.lock()
        defer { executionEvidenceLock.unlock() }
        var installed: [Graph.EffectKey: String] = [:]
        for (key, values) in Dictionary(grouping: subjects, by: \.key) {
            guard values.count == 1, let subject = values.first else {
                executionEvidenceIssues["duplicate-key", default: 0] += 1
                continue
            }
            guard !subject.family.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty else {
                executionEvidenceIssues["empty-family", default: 0] += 1
                continue
            }
            installed[key] = subject.family
        }
        executionEvidenceByKey = installed
    }

    func executionEvidenceFamily(for key: Graph.EffectKey) -> String? {
        executionEvidenceLock.lock()
        defer { executionEvidenceLock.unlock() }
        return executionEvidenceByKey[key]
    }

    func executionEvidenceSubjects(
        for claim: ClaimedExecution
    ) -> [ExactEffectSubject] {
        guard let runtimeClaim = capabilities.resolve(claim.token) else { return [] }
        return runtimeClaim.stages.compactMap(\.subject)
    }

    func executionEvidenceOutcome(
        for subject: ExactEffectSubject,
        claim: ClaimedExecution,
        ticket: ExecutionTicket
    ) -> ExecutionEvidenceOutcome {
        guard let runtimeClaim = capabilities.resolve(claim.token),
              let stage = runtimeClaim.stages.first(where: {
                  $0.subject?.key == subject.key
              }) else { return .encodedOutput }
        let dynamicReason = ticket.effectFailures.first {
            $0.layerID == subject.key.layerID
                && $0.effectIndex == subject.key.effectIndex
                && $0.descriptorID == subject.key.descriptorID
        }?.reasonCode
        guard let reason = dynamicReason ?? stage.visualFailureReasonCode else {
            return .encodedOutput
        }
        return .failed(
            reasonCode: "effect-local-passthrough-\(reason)"
        )
    }

    /// Returns dedicated leaf plans owned by the unified capability for a
    /// layer. This projection keeps resource loading on the same owner as
    /// runtime admission.
    func dedicatedEffectStages(
        for layerID: Int
    ) -> [SceneEffectStageExecutionPlan] {
        guard let claimed = capabilities.claim(layerID: layerID),
              let runtimeClaim = capabilities.resolve(claimed.token) else {
            return []
        }
        return runtimeClaim.stages.compactMap(\.dedicatedExecutionPlan)
    }

    var executionEvidenceReportLines: [String] {
        executionEvidenceLock.lock()
        defer { executionEvidenceLock.unlock() }
        var lines = [
            "resolved material execution evidence: schema=effect-graph-disposition-v1"
                + " subjects=\(executionEvidenceByKey.count)"
        ]
        lines += executionEvidenceIssues.keys.sorted().map {
            "resolved material execution evidence issue: \($0)"
                + " count=\(executionEvidenceIssues[$0] ?? 0)"
        }
        return lines
    }

    func executeClaimed(
        claim: ClaimedExecution,
        dependencyEffect: SceneDependencyEffectInput?,
        sceneBackgroundTexture: MTLTexture? = nil,
        commandBuffer: MTLCommandBuffer
    ) -> ExecutionResult {
        submissions.executeClaimed(
            claim: claim,
            dependencyEffect: dependencyEffect,
            sceneBackgroundTexture: sceneBackgroundTexture,
            commandBuffer: commandBuffer
        )
    }

    func prepareFrame(
        _ requests: [FramePreparationRequest],
        pool: SceneOffscreenTexturePool?,
        commandBuffer: MTLCommandBuffer
    ) -> FramePreparationResult {
        submissions.prepareFrame(
            requests,
            pool: pool,
            commandBuffer: commandBuffer
        )
    }

    func markComposite(
        _ ticket: ExecutionTicket,
        texture: MTLTexture,
        consumed: Bool
    ) -> CompositeOutcome {
        submissions.markComposite(
            ticket,
            texture: texture,
            consumed: consumed
        )
    }

    @discardableResult
    func sealFrame(on commandBuffer: MTLCommandBuffer) -> Bool {
        submissions.sealFrame(on: commandBuffer)
    }

    @discardableResult
    func endFrame() -> [String] {
        submissions.endFrame()
    }

    func invalidate(reason: SceneGraphExecutionResetReason) {
        submissions.invalidate(reason: reason)
    }
}

extension SceneResolvedMaterialSubmissionCoordinator {
    func claim(layerID: Int) -> Bridge.Claim {
        resolvedClaim(
            layerID: layerID,
            recordsClaim: true
        )
    }

    func preflightClaim(layerID: Int) -> Bridge.Claim {
        resolvedClaim(
            layerID: layerID,
            recordsClaim: false
        )
    }

    private func resolvedClaim(
        layerID: Int,
        recordsClaim: Bool
    ) -> Bridge.Claim {
        guard let claim = capabilities.claim(layerID: layerID) else {
            return .notMigrated
        }
        guard let capability = capabilities.resolve(claim.token),
              capability.layerID == layerID,
              capability.pairPlan.layerID == layerID,
              capability.effectSubjectsAreConserved else {
            return .rejected(reasonCode: "execution-capability-token-invalid")
        }
        let execution = Bridge.ClaimedExecution(
            layerID: layerID,
            admittedGraphs: capability.admittedProducts.map(\.graph),
            clearFunctionsByEffect: Dictionary(uniqueKeysWithValues: capability.admittedProducts.compactMap {
                guard let effect = $0.graph.effects.first?.key else { return nil }
                return (effect, $0.clearFunctions)
            }),
            targetExecutionPlans: capability.stages.map(\.dedicatedExecutionPlan),
            pairPlan: capability.pairPlan,
            fullFrameExtentPolicy: capability.fullFrameExtentPolicy,
            dependencyOwnership: capability.dependencyOwnership,
            sourceRoute: capability.sourceRoute,
            sceneBackgroundRequirement: capability.sceneBackgroundRequirement,
            requiresInvertibleEffectTextureProjection:
                capability.requiresInvertibleEffectTextureProjection,
            token: claim.token
        )
        guard recordsClaim else { return .claimed(execution) }

        lock.lock()
        if let reasonCode = frameLocalFallbacks[layerID] {
            lock.unlock()
            // The existing claim contract remains rejected until the compositor
            // explicitly recognizes this bounded local fallback reason.
            return .rejected(reasonCode: reasonCode)
        }
        guard frameIsActive, framePreparationComplete,
              !frameRequiresDrop, frameFailure == nil,
              let identity = preparedLedgerByLayerID[layerID],
              var ledger = activeByID[identity],
              ledger.layerID == layerID,
              ledger.capabilityToken == claim.token,
              ledger.phase == .allocationCommitted,
              !ledger.claimConsumed else {
            lock.unlock()
            return .rejected(reasonCode: "frame-candidate-not-prepared")
        }
        ledger.claimConsumed = true
        activeByID[identity] = ledger
        frameClaimed += 1
        lock.unlock()
        return .claimed(execution)
    }

    func recordClaimedFailure(reasonCode: String) {
        var emission = Emission()
        lock.lock()
        if frameIsActive {
            emission = claimedFailureLocked(
                reason: reasonCode.isEmpty
                    ? "claimed-execution-failed" : reasonCode
            )
        }
        lock.unlock()
        emit(emission)
    }
}
