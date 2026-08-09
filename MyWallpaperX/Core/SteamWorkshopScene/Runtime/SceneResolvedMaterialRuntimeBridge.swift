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
        let pairPlan: SceneLayerFullFramePairPlan
        let fullFrameExtentPolicy: SceneFullFrameExtentPolicy
        let sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute
        let token: SceneResolvedMaterialExecutionCapabilityCatalog.Token

        fileprivate init(
            layerID: Int,
            admittedGraphs: [Graph],
            pairPlan: SceneLayerFullFramePairPlan,
            fullFrameExtentPolicy: SceneFullFrameExtentPolicy,
            sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute,
            token: SceneResolvedMaterialExecutionCapabilityCatalog.Token
        ) {
            self.layerID = layerID
            self.admittedGraphs = admittedGraphs
            self.pairPlan = pairPlan
            self.fullFrameExtentPolicy = fullFrameExtentPolicy
            self.sourceRoute = sourceRoute
            self.token = token
        }
    }

    enum Claim {
        case notMigrated
        case rejected(reasonCode: String)
        case claimed(ClaimedExecution)
    }

    struct ExecutionTicket: Hashable {
        let identity, epoch: UInt64
        let finalTextureIdentity: ObjectIdentifier
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
        let sourceTexture: MTLTexture?
        let sourceUniforms: SceneLayerFragmentUniforms?
        let sourcePipeline: SceneImageLayerPipeline
        let dedicatedInputs: DedicatedFrameInputs
    }

    struct DedicatedFrameInputs {
        let masks: SceneImageLayerMasks
        let dynamicValues: SceneDynamicSnapshot
        let pipelines: SceneAuthoredEffectPipelineSet
        let cursorUV: SIMD2<Float>
        let previousCursorUV: SIMD2<Float>
        let pointerIsInside: Bool
        let previousPointerIsInside: Bool
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

    /// Returns dedicated leaf plans owned by the unified capability for a
    /// layer. This projection keeps resource loading on the same owner as
    /// runtime admission and never consults the legacy authored catalog.
    func dedicatedEffectStages(
        for layerID: Int
    ) -> [SceneAuthoredEffectExecutionPlan] {
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
            "resolved material execution evidence: schema=r4-static-disposition-v1"
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
        commandBuffer: MTLCommandBuffer
    ) -> ExecutionResult {
        submissions.executeClaimed(
            claim: claim,
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
            pairPlan: capability.pairPlan,
            fullFrameExtentPolicy: capability.fullFrameExtentPolicy,
            sourceRoute: capability.sourceRoute,
            token: claim.token
        )
        guard recordsClaim else { return .claimed(execution) }

        lock.lock()
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
