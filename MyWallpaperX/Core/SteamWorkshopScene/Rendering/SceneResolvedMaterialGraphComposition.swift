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
        let materialFunctionInvocations: [SceneGraphMaterialFunctionInvocationRequest]

        init(
            claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution,
            fullFrameExtentPolicy: SceneFullFrameExtentPolicy,
            requestedWidth: Int,
            requestedHeight: Int,
            materialFunctionInvocations:
                [SceneGraphMaterialFunctionInvocationRequest] = []
        ) {
            self.claim = claim
            self.fullFrameExtentPolicy = fullFrameExtentPolicy
            self.requestedWidth = requestedWidth
            self.requestedHeight = requestedHeight
            self.materialFunctionInvocations = materialFunctionInvocations
        }
    }

    enum FramePreflightResult {
        case ready(
            plans: [Int: SceneResolvedMaterialFrameTargetPlan],
            localFallbacks: [Int: String]
        )
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
        let execute: (
            MTLTexture?, MTLCommandBuffer
        ) -> SceneResolvedMaterialRuntimeBridge.ExecutionResult = {
            sceneBackgroundTexture, commandBuffer in
            runtime.executeClaimed(
                claim: claim,
                dependencyEffect: dependencyEffect,
                sceneBackgroundTexture: sceneBackgroundTexture,
                commandBuffer: commandBuffer
            )
        }
        let result: SceneResolvedMaterialRuntimeBridge.ExecutionResult
        if claim.sceneBackgroundRequirement != nil {
            guard let backgroundResult = mainPass.withReadableTarget({
                mainTarget, commandBuffer in
                execute(mainTarget, commandBuffer)
            }) else {
                runtime.recordClaimedFailure(
                    reasonCode: "scene-background-main-target-unavailable"
                )
                return .failed
            }
            result = backgroundResult
        } else {
            result = mainPass.encodeOffscreen { commandBuffer in
                execute(nil, commandBuffer)
            }
        }
        switch result {
        case let .encoded(texture, ticket):
            for subject in runtime.executionEvidenceSubjects(for: claim) {
                let outcome: SceneEffectCPUInvocationOutcome
                switch runtime.executionEvidenceOutcome(
                    for: subject,
                    claim: claim,
                    ticket: ticket
                ) {
                case .encodedOutput:
                    outcome = .encodedOutput
                case let .failed(reasonCode):
                    outcome = .failed(reasonCode: reasonCode)
                }
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
                    outcome: outcome
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
        var localFallbacks: [Int: String] = [:]
        var allocationPlans: [ScenePersistentGraphTargetFramePlan] = []
        let orderingContext = commandBuffer.map {
            SceneGraphCommandQueueOrderingContext(commandBuffer: $0)
        }
        for request in requests {
            var invocationFailure: String?
            var materialFunctionTargetsByEffect: [
                SceneAuthoredEffectRenderPlan.EffectKey:
                    Set<SceneAuthoredEffectRenderPlan.TextureIdentity>
            ] = [:]
            for invocation in request.materialFunctionInvocations {
                guard request.claim.admittedGraphs.contains(where: {
                    $0.effects.first?.key == invocation.effect
                }) else {
                    invocationFailure = "function-invocation-unknown-effect"
                    break
                }
                guard let function = request.claim.clearFunctionsByEffect[invocation.effect]
                    .flatMap({ $0.function(named: invocation.functionName) }) else {
                    invocationFailure = "function-invocation-unknown-function"
                    break
                }
                materialFunctionTargetsByEffect[invocation.effect, default: []]
                    .formUnion(function.targets)
            }
            if let invocationFailure {
                localFallbacks[request.claim.layerID] = invocationFailure
                continue
            }
            guard request.requestedWidth > 0, request.requestedHeight > 0,
                  request.fullFrameExtentPolicy
                    == request.claim.fullFrameExtentPolicy else {
                localFallbacks[request.claim.layerID] =
                    "frame-target-plan-rejected"
                continue
            }
            let allocation: ScenePersistentGraphTargetFramePlan
            switch pool.framePlanResultForPersistentGraphTargets(
                admittedGraphs: request.claim.admittedGraphs,
                targetExecutionPlans: request.claim.targetExecutionPlans,
                materialFunctionTargetsByEffect: materialFunctionTargetsByEffect,
                pairPlan: request.claim.pairPlan,
                extentPolicy: request.fullFrameExtentPolicy,
                requestedWidth: request.requestedWidth,
                requestedHeight: request.requestedHeight,
                sharesFullFramePairWhenHistoryFree: true,
                orderingContext: orderingContext
            ) {
            case let .success(value): allocation = value
            case let .failure(failure):
                localFallbacks[request.claim.layerID] =
                    failure.localFallbackReasonCode
                continue
            }
            guard allocation.graphPlan.key.layerID == request.claim.layerID,
                  byLayerID.updateValue(.init(
                      token: request.claim.token,
                      allocation: allocation
                  ), forKey: request.claim.layerID) == nil else {
                localFallbacks[request.claim.layerID] =
                    "frame-target-plan-rejected"
                continue
            }
            allocationPlans.append(allocation)
        }
        switch pool.preflightPersistentGraphTargets(allocationPlans) {
        case .ready:
            return .ready(
                plans: byLayerID,
                localFallbacks: localFallbacks
            )
        case .temporarilyBlocked:
            return .deferred
        case .rejected(let reasonCode):
            return .rejected(reasonCode: reasonCode)
        }
    }
}

enum SceneResolvedMaterialClaimRoute {
    case unclaimed
    case localFallback(reasonCode: String)
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

    var allowsLayerSourcePassthrough: Bool {
        switch self {
        case .unclaimed, .localFallback:
            return true
        case .rejected, .claimed:
            return false
        }
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
            if reasonCode == "function-invocation-unknown-effect"
                || reasonCode == "function-invocation-unknown-function"
                || ScenePersistentGraphTargetPlanningFailure
                    .isLocalFallbackReasonCode(reasonCode) {
                return .localFallback(reasonCode: reasonCode)
            }
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

    func installResolvedMaterialFrameLocalFallbacks(
        _ fallbacks: [Int: String]
    ) -> Bool {
        resolvedMaterialRuntime?.installFrameLocalFallbacks(fallbacks)
            ?? fallbacks.isEmpty
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
