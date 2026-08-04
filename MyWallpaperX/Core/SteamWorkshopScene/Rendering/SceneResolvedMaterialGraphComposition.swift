import Metal

struct SceneResolvedMaterialFrameTargetPlan {
    let token: SceneResolvedMaterialExecutionCapabilityCatalog.Token
    let allocation: ScenePersistentGraphTargetFramePlan
}

/// The compositor-facing claim handshake. Only a static `notMigrated` result may
/// reach the legacy authored renderer; every capability-owned failure stays closed.
enum SceneResolvedMaterialGraphComposition {
    struct FrameTargetRequest {
        let claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution
        let fullFrameExtentPolicy: SceneFullFrameExtentPolicy
        let requestedWidth: Int
        let requestedHeight: Int
    }

    enum FramePreflightResult {
        case ready([Int: SceneResolvedMaterialFrameTargetPlan])
        case deferred
        case rejected(reasonCode: String)
    }

    enum Result {
        case encoded(
            texture: MTLTexture,
            ticket: SceneResolvedMaterialRuntimeBridge.ExecutionTicket
        )
        case failed
    }

    static func executeClaimed(
        runtime: SceneResolvedMaterialRuntimeBridge,
        claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution,
        request: SceneImageLayerDrawRequest,
        mainPass: SceneMainPassEncoder,
        executionTrace: SceneEffectExecutionFrameTrace?,
        executionOrigin: SceneEffectExecutionOrigin
    ) -> Result {
        guard let framePlan = request.resolvedMaterialFrameTargetPlan,
              framePlan.token == claim.token,
              framePlan.allocation.chainPlan.key.layerID == claim.layerID else {
            runtime.recordClaimedFailure(
                reasonCode: "frame-target-plan-consumption-failed"
            )
            executionTrace?.recordRouteOperation(
                layerID: request.layer.id,
                origin: executionOrigin,
                operation: "r4-graph-target-allocation",
                outcome: .failed(reasonCode: "frame-plan-unavailable")
            )
            return .failed
        }
        let result = mainPass.encodeOffscreen { commandBuffer in
            runtime.executeClaimed(
                claim: claim,
                commandBuffer: commandBuffer
            )
        }
        switch result {
        case let .encoded(texture, ticket):
            for subject in runtime.executionEvidenceSubjects(for: claim) {
                executionTrace?.recordExact(
                    identity: .init(
                        layerID: subject.key.layerID,
                        effectIndex: subject.key.effectIndex,
                        descriptorID: subject.key.descriptorID
                    ),
                    origin: executionOrigin,
                    family: runtime.executionEvidenceFamily(for: subject.key)
                        ?? subject.family,
                    backend: "resolved-material-graph",
                    outcome: .encodedOutput
                )
            }
            return .encoded(texture: texture, ticket: ticket)
        case let .failed(reasonCode):
            executionTrace?.recordRouteOperation(
                layerID: request.layer.id,
                origin: executionOrigin,
                operation: "r4-unified-graph-executor",
                outcome: .failed(reasonCode: reasonCode)
            )
            return .failed
        }
    }

    static func preflight(
        requests: [FrameTargetRequest],
        pool: SceneOffscreenTexturePool,
        commandBuffer: MTLCommandBuffer? = nil
    ) -> FramePreflightResult {
        guard Set(requests.map(\.claim.layerID)).count == requests.count else {
            return .rejected(reasonCode: "frame-target-layer-ambiguous")
        }
        var byLayerID: [Int: SceneResolvedMaterialFrameTargetPlan] = [:]
        var allocationPlans: [ScenePersistentGraphTargetFramePlan] = []
        let orderingContext = commandBuffer.map {
            SceneGraphCommandQueueOrderingContext(commandBuffer: $0)
        }
        for request in requests {
            guard request.requestedWidth > 0, request.requestedHeight > 0,
                  request.fullFrameExtentPolicy
                    == request.claim.fullFrameExtentPolicy,
                  let allocation = pool.framePlanForPersistentGraphTargets(
                      admittedGraphs: request.claim.admittedGraphs,
                      pairPlan: request.claim.pairPlan,
                      extentPolicy: request.fullFrameExtentPolicy,
                      requestedWidth: request.requestedWidth,
                      requestedHeight: request.requestedHeight,
                      orderingContext: orderingContext
                  ), allocation.chainPlan.key.layerID == request.claim.layerID,
                  byLayerID.updateValue(.init(
                      token: request.claim.token,
                      allocation: allocation
                  ), forKey: request.claim.layerID) == nil else {
                return .rejected(reasonCode: "frame-target-plan-rejected")
            }
            allocationPlans.append(allocation)
        }
        switch pool.preflightPersistentGraphTargets(allocationPlans) {
        case .ready:
            return .ready(byLayerID)
        case .temporarilyBlocked:
            return .deferred
        case .rejected(let reasonCode):
            return .rejected(reasonCode: reasonCode)
        }
    }
}

enum SceneResolvedMaterialClaimRoute {
    case legacy
    case rejected(reasonCode: String)
    case claimed(SceneResolvedMaterialRuntimeBridge.ClaimedExecution)

    var execution: SceneResolvedMaterialRuntimeBridge.ClaimedExecution? {
        guard case let .claimed(value) = self else { return nil }
        return value
    }

    var isRejected: Bool {
        guard case .rejected = self else { return false }
        return true
    }
}

extension SceneImageLayerCompositor {
    func prepareResolvedMaterialFrame(
        _ requests: [SceneResolvedMaterialRuntimeBridge.FramePreparationRequest],
        pool: SceneOffscreenTexturePool?,
        commandBuffer: MTLCommandBuffer
    ) -> SceneResolvedMaterialRuntimeBridge.FramePreparationResult {
        guard let resolvedMaterialRuntime else {
            return requests.isEmpty
                ? .ready : .rejected(reasonCode: "resolved-runtime-unavailable")
        }
        return resolvedMaterialRuntime.prepareFrame(
            requests,
            pool: pool,
            commandBuffer: commandBuffer
        )
    }

    func preflightResolvedMaterialClaim(
        layerID: Int
    ) -> SceneResolvedMaterialClaimRoute {
        guard let resolvedMaterialRuntime else { return .legacy }
        switch resolvedMaterialRuntime.preflightClaim(layerID: layerID) {
        case .notMigrated:
            return .legacy
        case let .rejected(reasonCode):
            return .rejected(reasonCode: reasonCode)
        case let .claimed(claim):
            return .claimed(claim)
        }
    }

    func resolvedMaterialClaim(
        for request: SceneImageLayerDrawRequest
    ) -> SceneResolvedMaterialClaimRoute {
        guard let resolvedMaterialRuntime else { return .legacy }
        switch resolvedMaterialRuntime.claim(layerID: request.layer.id) {
        case .notMigrated:
            return .legacy
        case let .rejected(reasonCode):
            resolvedMaterialRuntime.recordClaimedFailure(reasonCode: reasonCode)
            return .rejected(reasonCode: reasonCode)
        case let .claimed(claim):
            return .claimed(claim)
        }
    }

    func rejectResolvedMaterialClaim(
        _ claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution?,
        reasonCode: String
    ) -> Bool {
        if claim != nil {
            resolvedMaterialRuntime?.recordClaimedFailure(reasonCode: reasonCode)
        }
        return false
    }

    func consumeResolvedMaterialComposite(
        _ ticket: SceneResolvedMaterialRuntimeBridge.ExecutionTicket,
        texture: MTLTexture,
        consumed: Bool,
        layerID: Int,
        executionTrace: SceneEffectExecutionFrameTrace?,
        executionOrigin: SceneEffectExecutionOrigin
    ) -> Bool {
        guard let resolvedMaterialRuntime else { return false }
        switch resolvedMaterialRuntime.markComposite(
            ticket,
            texture: texture,
            consumed: consumed
        ) {
        case .consumed:
            return true
        case let .failed(reasonCode):
            executionTrace?.recordRouteOperation(
                layerID: layerID,
                origin: executionOrigin,
                operation: "r4-final-composite",
                outcome: .failed(reasonCode: reasonCode)
            )
            return false
        }
    }

    func recordResolvedMaterialFramePreflightFailure(_ reasonCode: String) {
        resolvedMaterialRuntime?.recordClaimedFailure(reasonCode: reasonCode)
    }

    var resolvedMaterialAssetStates: [
        SceneAssetTextureIdentity: SceneTextureProviderState
    ] {
        resolvedMaterialRuntime?.assetStates ?? [:]
    }

    func resolvedMaterialSystemProviderBlocks(
        _ snapshot: SceneMediaThumbnailTextureStore.Snapshot
    ) -> [String: SceneFrameTextureRegistry.ProviderStatus] {
        resolvedMaterialRuntime?.systemProviderBlocks(for: snapshot) ?? [:]
    }

    func beginResolvedMaterialFrame(
        textureSnapshot: SceneFrameTextureRegistrySnapshot,
        dynamicSnapshot: SceneDynamicSnapshot,
        frameInputs: SceneAuthoredShaderFrameInputs
    ) {
        resolvedMaterialRuntime?.beginFrame(
            textureSnapshot: textureSnapshot,
            dynamicSnapshot: dynamicSnapshot,
            frameInputs: frameInputs
        )
    }

    func endResolvedMaterialFrame(on commandBuffer: MTLCommandBuffer) -> Bool {
        defer { resolvedMaterialRuntime?.endFrame() }
        return resolvedMaterialRuntime?.sealFrame(on: commandBuffer) ?? true
    }
}
