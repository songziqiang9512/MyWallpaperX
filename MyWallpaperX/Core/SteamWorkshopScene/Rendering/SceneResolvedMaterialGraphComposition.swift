import Metal
import simd

struct SceneResolvedMaterialFrameTargetPlan {
    let token: SceneResolvedMaterialExecutionCapabilityCatalog.Token
    let allocation: ScenePersistentGraphTargetFramePlan
}

/// The compositor-facing claim handshake. Only a static `notMigrated` result may
/// remain unclaimed; every capability-owned failure stays closed.
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
        executeClaimed(
            runtime: runtime,
            claim: claim,
            framePlan: request.resolvedMaterialFrameTargetPlan,
            layerID: request.layer.id,
            dependencyEffect: request.dependencyEffect,
            mainPass: mainPass,
            executionTrace: executionTrace,
            executionOrigin: executionOrigin
        )
    }

    static func executeClaimed(
        runtime: SceneResolvedMaterialRuntimeBridge,
        claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution,
        framePlan: SceneResolvedMaterialFrameTargetPlan?,
        layerID: Int,
        dependencyEffect: SceneDependencyEffectInput?,
        mainPass: SceneMainPassEncoder,
        executionTrace: SceneEffectExecutionFrameTrace?,
        executionOrigin: SceneEffectExecutionOrigin
    ) -> Result {
        guard let framePlan,
              framePlan.token == claim.token,
              framePlan.allocation.graphPlan.key.layerID == claim.layerID else {
            runtime.recordClaimedFailure(
                reasonCode: "frame-target-plan-consumption-failed"
            )
            executionTrace?.recordRouteOperation(
                layerID: layerID,
                origin: executionOrigin,
                operation: "layer-graph-target-allocation",
                outcome: .failed(reasonCode: "frame-plan-unavailable")
            )
            return .failed
        }
        let result = mainPass.encodeOffscreen { commandBuffer in
            runtime.executeClaimed(
                claim: claim,
                dependencyEffect: dependencyEffect,
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
                layerID: layerID,
                origin: executionOrigin,
                operation: "unified-graph-executor",
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
                      targetExecutionPlans: request.claim.targetExecutionPlans,
                      pairPlan: request.claim.pairPlan,
                      extentPolicy: request.fullFrameExtentPolicy,
                      requestedWidth: request.requestedWidth,
                      requestedHeight: request.requestedHeight,
                      sharesFullFramePairWhenHistoryFree: true,
                      orderingContext: orderingContext
                  ), allocation.graphPlan.key.layerID == request.claim.layerID,
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
    case unclaimed
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
    func drawResolvedDirectDrawQuad(
        layer: SceneRenderDescriptor.Layer,
        modelViewProjection: simd_float4x4,
        alpha: Float,
        framePlan: SceneResolvedMaterialFrameTargetPlan,
        pipeline: SceneImageLayerPipeline,
        mainPass: SceneMainPassEncoder,
        executionTrace: SceneEffectExecutionFrameTrace?
    ) -> Bool {
        guard layer.contentKind == "quad",
              (layer.colorBlendMode ?? 0) == 0,
              let resolvedMaterialRuntime else {
            return false
        }
        let claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution
        switch resolvedMaterialRuntime.claim(layerID: layer.id) {
        case .notMigrated:
            return false
        case let .rejected(reasonCode):
            resolvedMaterialRuntime.recordClaimedFailure(reasonCode: reasonCode)
            return false
        case let .claimed(value):
            claim = value
        }
        guard claim.sourceRoute == .transparentDirectDraw,
              framePlan.token == claim.token else {
            resolvedMaterialRuntime.recordClaimedFailure(
                reasonCode: "direct-draw-claim-route-invalid"
            )
            return false
        }
        let executed = executeResolvedMaterialClaim(
            runtime: resolvedMaterialRuntime,
            claim: claim,
            framePlan: framePlan,
            layerID: layer.id,
            dependencyEffect: nil,
            mainPass: mainPass,
            executionTrace: executionTrace,
            executionOrigin: .quad
        )
        let texture: MTLTexture
        let ticket: SceneResolvedMaterialRuntimeBridge.ExecutionTicket
        switch executed {
        case let .encoded(value, executionTicket):
            texture = value
            ticket = executionTicket
        case .failed:
            return false
        }
        let uniforms = makeFragmentUniforms(
            values: .init(time: 0, alpha: alpha, cursorUV: .zero),
            textureFrame: .identity,
            tint: SIMD3<Float>(repeating: 1),
            dependencyBlendMode: nil
        )
        let composited = SceneImageLayerMainPassRenderer.draw(
            texture: texture,
            mvp: modelViewProjection,
            uniforms: uniforms,
            dependencyTexture: nil,
            layer: layer,
            pipeline: pipeline,
            colorBlendPipeline: nil,
            mainPass: mainPass
        )
        return consumeResolvedMaterialComposite(
            ticket,
            texture: texture,
            consumed: composited,
            layerID: layer.id,
            executionTrace: executionTrace,
            executionOrigin: .quad
        ) && composited
    }

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
        guard let resolvedMaterialRuntime else { return .unclaimed }
        switch resolvedMaterialRuntime.preflightClaim(layerID: layerID) {
        case .notMigrated:
            return .unclaimed
        case let .rejected(reasonCode):
            return .rejected(reasonCode: reasonCode)
        case let .claimed(claim):
            return .claimed(claim)
        }
    }

    func resolvedMaterialClaim(
        for request: SceneImageLayerDrawRequest
    ) -> SceneResolvedMaterialClaimRoute {
        guard let resolvedMaterialRuntime else { return .unclaimed }
        switch resolvedMaterialRuntime.claim(layerID: request.layer.id) {
        case .notMigrated:
            return .unclaimed
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
                operation: "final-composite",
                outcome: .failed(reasonCode: reasonCode)
            )
            return false
        }
    }

    func recordResolvedMaterialFramePreflightFailure(_ reasonCode: String) {
        resolvedMaterialRuntime?.recordClaimedFailure(reasonCode: reasonCode)
    }

    func deferResolvedMaterialFrame() -> Bool {
        resolvedMaterialRuntime?.deferPreparedFrame() ?? true
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
