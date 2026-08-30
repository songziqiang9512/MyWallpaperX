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
        let frameInputs: FrameInputs

        init(
            claim: ClaimedExecution,
            targetPlan: SceneResolvedMaterialFrameTargetPlan,
            materialFunctionInvocations:
                [SceneGraphMaterialFunctionInvocationRequest] = [],
            sceneBackgroundResource: SceneFrameTextureResource? = nil,
            sourceTexture: MTLTexture?,
            sourceUniforms: SceneLayerFragmentUniforms?,
            sourcePipeline: SceneImageLayerPipeline,
            frameInputs: FrameInputs
        ) {
            self.claim = claim
            self.targetPlan = targetPlan
            self.materialFunctionInvocations = materialFunctionInvocations
            self.sceneBackgroundResource = sceneBackgroundResource
            self.sourceTexture = sourceTexture
            self.sourceUniforms = sourceUniforms
            self.sourcePipeline = sourcePipeline
            self.frameInputs = frameInputs
        }
    }

    struct FrameInputs {
        let dynamicValues: SceneDynamicSnapshot
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

        func withDependencyEffect(
            _ dependencyEffect: SceneDependencyEffectInput?
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
                effectTextureProjectionMatrixInverse:
                    effectTextureProjectionMatrixInverse,
                frameTime: frameTime,
                time: time,
                audioSpectrum: audioSpectrum,
                dependencyEffect: dependencyEffect
            )
        }
    }

    enum FramePreparationResult {
        case ready
        case rejected(reasonCode: String)
    }

    private let catalog: SceneResolvedMaterialRuntimeCatalog
    private let capabilities: SceneResolvedMaterialExecutionCapabilityCatalog
    private let assetProvider: SceneMaterialAssetTextureCatalog.FrameProvider
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
        assetProvider = assets.makeFrameProvider()
        submissions = .init(
            device: device,
            capabilities: capabilities,
            logSink: logSink
        )
    }

    func resolvedAssetStates(
        sceneTime: TimeInterval
    ) -> [SceneAssetTextureIdentity: SceneTextureProviderState] {
        assetProvider.states(sceneTime: sceneTime)
    }

    var userPropertyDemands: Set<SceneUserPropertyTextureIdentity> {
        catalog.userPropertyDemands
    }

    var systemProviderDemands: Set<SceneSystemProviderTextureIdentity> {
        catalog.systemProviderDemands
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
    ) -> [
        SceneSystemProviderTextureIdentity: SceneFrameTextureRegistry.ProviderStatus
    ] {
        var blocks: [
            SceneSystemProviderTextureIdentity: SceneFrameTextureRegistry.ProviderStatus
        ] = [:]
        for identity in catalog.systemProviderDemands.sorted(by: {
            $0.reportToken < $1.reportToken
        }) {
            // Only an exactly missing provider is a visual availability
            // state. Initial async preparation remains pending; a completed
            // generation without the demanded purpose is unavailable. Any
            // partial or malformed atom must enter the registry unchanged so
            // MaterialProgram can hard-reject request identity, generation,
            // lifecycle and publication integrity independently.
            // Per-consumer purpose checking also lets one compatible demand
            // continue when another demand for the same provider is invalid.
            if snapshot.publications[identity] == nil,
               snapshot.systemTextures[identity] == nil {
                blocks[identity] = snapshot.pendingGeneration != nil
                    && snapshot.pendingIdentities.contains(identity)
                    ? .pending
                    : .unavailable
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
        executionEvidenceLock.lock()
        defer { executionEvidenceLock.unlock() }
        return runtimeClaim.stages.compactMap { stage in
            guard let subject = stage.subject,
                  let family = executionEvidenceByKey[subject.key] else {
                return nil
            }
            return .init(key: subject.key, family: family)
        }
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

    func preparedOutputTexturesByLayerID() -> [Int: MTLTexture]? {
        submissions.preparedOutputTexturesByLayerID()
    }

    func rejectPreparedExternalDependencyLocally(
        layerID: Int,
        reasonCode: String
    ) -> Bool {
        submissions.rejectPreparedExternalDependencyLocally(
            layerID: layerID,
            reasonCode: reasonCode
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

    func markNamedPublication(
        _ ticket: ExecutionTicket,
        texture: MTLTexture,
        published: Bool
    ) -> CompositeOutcome {
        submissions.markNamedPublication(
            ticket,
            texture: texture,
            published: published
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
            if let reasonCode = capabilities.productAuthorityRejectionReason(
                layerID: layerID
            ) {
                return .rejected(reasonCode: reasonCode)
            }
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
