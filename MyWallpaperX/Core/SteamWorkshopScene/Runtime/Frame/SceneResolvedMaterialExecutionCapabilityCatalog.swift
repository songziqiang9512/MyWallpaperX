import Foundation

/// Launch-scoped prepared execution capabilities with one claim authority.
final class SceneResolvedMaterialExecutionCapabilityCatalog {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias MaterialKey = SceneResolvedMaterialKey
    typealias ExactEffectSubject = SceneEffectExactRuntimeSubject

    enum SourceRoute: Equatable {
        case capturedLayerTexture
        case capturedMainTargetTexture
        case transparentDirectDraw
    }

    struct Token: Hashable {
        fileprivate let ownerID: UUID
        let capabilityID: UUID
        fileprivate let layerID: Int
    }

    struct ClaimedLayer {
        let token: Token
        let layerID: Int
    }

    struct SceneBackgroundRequirement: Equatable {
        let layerID: Int
        let effect: Graph.EffectKey
        let nodeIndex: Int
        let slot: Int
        let bindingCount: Int
        let capturesTextSourcePrefixRGB: Bool

        init(layerID: Int, effect: Graph.EffectKey, nodeIndex: Int, slot: Int,
             bindingCount: Int, capturesTextSourcePrefixRGB: Bool = false) {
            self.layerID = layerID
            self.effect = effect
            self.nodeIndex = nodeIndex
            self.slot = slot
            self.bindingCount = bindingCount
            self.capturesTextSourcePrefixRGB = capturesTextSourcePrefixRGB
        }
    }

    struct RuntimeDispositionOwnership {
        let layerID: Int
        let subjects: [ExactEffectSubject]

        fileprivate init(layerID: Int, subjects: [ExactEffectSubject]) {
            self.layerID = layerID
            self.subjects = subjects
        }
    }

    struct StageCapability {
        enum Execution {
            case resolved(
                materials: [MaterialKey: MaterialCapability],
                activation: SceneResolvedMaterialStageActivationPolicy?
            )
            case visualFailurePassthrough(reasonCode: String)
            case initiallyInactivePassthrough(reasonCode: String)
        }

        enum PassthroughTopology: Hashable {
            case dependencyStage
            case framebuffer
            case preEncodeGraph
        }

        let product: SceneGraphAdmissionProduct
        let execution: Execution
        let passthroughTopologies: Set<PassthroughTopology>
        let preEncodeVisualFailureSlots: [SceneEffectPassSlot]?
    }

    typealias FrameInputContract = SceneResolvedMaterialFrameInputContract

    final class LayerCapability {
        let layerID: Int
        let admittedProducts: [SceneGraphAdmissionProduct]
        let stages: [StageCapability]
        let pairPlan: SceneLayerFullFramePairPlan
        let materials: [MaterialKey: MaterialCapability]
        let dependencyOwnership: SceneResolvedMaterialDependencyOwnership
        let sourceRoute: SourceRoute
        let sceneBackgroundRequirement: SceneBackgroundRequirement?
        let requiresSceneEnvironment: Bool
        let frameInputContract: FrameInputContract
        let graphFramebufferColorRepresentations: [
            Graph.TextureIdentity: SceneShaderColorRepresentation
        ]
        let isVisibleExecutionRoot: Bool
        let isGraphOutputProvider: Bool
        let requiresGraphOutputProvider: Bool
        let supportsSourceSizedSolidEffects: Bool
        let supportsTerminalMaterialReplay: Bool
        let supportsPlacementSpaceTerminalReplay: Bool
        let terminalReplayBlendMode: Int
        let effectSubjectsAreConserved: Bool

        fileprivate let capabilityID: UUID

        init(
            capabilityID: UUID,
            layerID: Int,
            admittedProducts: [SceneGraphAdmissionProduct],
            stages: [StageCapability],
            pairPlan: SceneLayerFullFramePairPlan,
            materials: [MaterialKey: MaterialCapability],
            dependencyOwnership: SceneResolvedMaterialDependencyOwnership,
            sourceRoute: SourceRoute,
            sceneBackgroundRequirement: SceneBackgroundRequirement?,
            requiresSceneEnvironment: Bool,
            frameInputContract: FrameInputContract,
            graphFramebufferColorRepresentations: [Graph.TextureIdentity: SceneShaderColorRepresentation],
            isVisibleExecutionRoot: Bool,
            isGraphOutputProvider: Bool,
            requiresGraphOutputProvider: Bool,
            supportsSourceSizedSolidEffects: Bool,
            supportsTerminalMaterialReplay: Bool,
            supportsPlacementSpaceTerminalReplay: Bool,
            terminalReplayBlendMode: Int,
            effectSubjectsAreConserved: Bool
        ) {
            self.capabilityID = capabilityID
            self.layerID = layerID
            self.admittedProducts = admittedProducts
            self.stages = stages
            self.pairPlan = pairPlan
            self.materials = materials
            self.dependencyOwnership = dependencyOwnership
            self.sourceRoute = sourceRoute
            self.sceneBackgroundRequirement = sceneBackgroundRequirement
            self.requiresSceneEnvironment = requiresSceneEnvironment
            self.frameInputContract = frameInputContract
            self.graphFramebufferColorRepresentations = graphFramebufferColorRepresentations
            self.isVisibleExecutionRoot = isVisibleExecutionRoot
            self.isGraphOutputProvider = isGraphOutputProvider
            self.requiresGraphOutputProvider = requiresGraphOutputProvider
            self.supportsSourceSizedSolidEffects = supportsSourceSizedSolidEffects
            self.supportsTerminalMaterialReplay = supportsTerminalMaterialReplay
            self.supportsPlacementSpaceTerminalReplay = supportsPlacementSpaceTerminalReplay
            self.terminalReplayBlendMode = terminalReplayBlendMode
            self.effectSubjectsAreConserved = effectSubjectsAreConserved
        }

        func material(for node: Graph.Node) -> MaterialCapability? {
            materials[.init(effect: node.effect, nodeIndex: node.nodeIndex)]
        }

        func material(effect: Graph.EffectKey, nodeIndex: Int) -> MaterialCapability? {
            materials[.init(effect: effect, nodeIndex: nodeIndex)]
        }
    }

    private let ownerID: UUID
    private let capabilitiesByLayerID: [Int: LayerCapability]
    let audioConsumerLayerIDs: Set<Int>
    let systemProviderConsumerLayerIDs: [SceneSystemProviderTextureIdentity: Set<Int>]
    private let productAuthorityRejectionReasonsByLayerID: [Int: String]
    private let dynamicVisibleRootLayerIDs: Set<Int>
    let reportLines: [String]

    var visibilityOwnedLayerIDs: Set<Int> { dynamicVisibleRootLayerIDs }

    init(
        ownerID: UUID,
        capabilitiesByLayerID: [Int: LayerCapability],
        audioConsumerLayerIDs: Set<Int>,
        systemProviderConsumerLayerIDs: [SceneSystemProviderTextureIdentity: Set<Int>],
        productAuthorityRejectionReasonsByLayerID: [Int: String],
        dynamicVisibleRootLayerIDs: Set<Int>,
        reportLines: [String]
    ) {
        self.ownerID = ownerID
        self.capabilitiesByLayerID = capabilitiesByLayerID
        self.audioConsumerLayerIDs = audioConsumerLayerIDs
        self.systemProviderConsumerLayerIDs = systemProviderConsumerLayerIDs
        self.productAuthorityRejectionReasonsByLayerID = productAuthorityRejectionReasonsByLayerID
        self.dynamicVisibleRootLayerIDs = dynamicVisibleRootLayerIDs
        self.reportLines = reportLines
    }

    func claim(layerID: Int) -> ClaimedLayer? {
        guard let capability = capabilitiesByLayerID[layerID] else { return nil }
        return .init(
            token: .init(
                ownerID: ownerID,
                capabilityID: capability.capabilityID,
                layerID: layerID
            ),
            layerID: layerID
        )
    }

    func productAuthorityRejectionReason(layerID: Int) -> String? {
        productAuthorityRejectionReasonsByLayerID[layerID]
    }

    func resolve(_ token: Token) -> LayerCapability? {
        guard token.ownerID == ownerID,
              let capability = capabilitiesByLayerID[token.layerID],
              token.capabilityID == capability.capabilityID else { return nil }
        return capability
    }

    func runtimeDispositionOwnership(
        token: Token,
        subjects: [ExactEffectSubject]
    ) -> RuntimeDispositionOwnership? {
        guard let capability = resolve(token),
              capability.effectSubjectsAreConserved else { return nil }
        let expected = capability.stages.compactMap(\.subject)
        let keys = subjects.map(\.key)
        guard !subjects.isEmpty,
              Set(keys).count == keys.count,
              Set(keys) == Set(expected.map(\.key)),
              Dictionary(uniqueKeysWithValues: subjects.map { ($0.key, $0.family) })
                == Dictionary(uniqueKeysWithValues: expected.map { ($0.key, $0.family) }),
              subjects.allSatisfy({ $0.key.layerID == capability.layerID }) else {
            return nil
        }
        return .init(
            layerID: capability.layerID,
            subjects: subjects.sorted {
                if $0.key.effectIndex != $1.key.effectIndex {
                    return $0.key.effectIndex < $1.key.effectIndex
                }
                return $0.key.descriptorID < $1.key.descriptorID
            }
        )
    }

    var runtimeDispositionOwnerships: [RuntimeDispositionOwnership] {
        capabilitiesByLayerID.keys.sorted().compactMap { layerID in
            guard let claim = claim(layerID: layerID),
                  let capability = resolve(claim.token) else { return nil }
            return runtimeDispositionOwnership(
                token: claim.token,
                subjects: capability.stages.compactMap(\.subject)
            )
        }
    }

    var executionLayerIDs: Set<Int> {
        Set(capabilitiesByLayerID.keys)
    }

    var admittedResolvedMaterialReferences: Set<SceneDependencyRenderPlan.Reference> {
        capabilitiesByLayerID.values.reduce(into: []) { result, capability in
            switch capability.dependencyOwnership {
            case let .externalPrimary(binding):
                for slot in binding.referenceSlots {
                    result.insert(.init(
                        consumerLayerID: binding.consumerLayerID,
                        providerLayerID: binding.providerLayerID,
                        slot: slot,
                        variant: .primary
                    ))
                }
            case let .externalAggregate(aggregate):
                // Preserve every authored slot in a multi-provider owner so a
                // subsequent generation can re-admit the exact aggregate
                // vector before any dependent MaterialProgram is compiled.
                for binding in aggregate.orderedBindings {
                    result.insert(.init(
                        consumerLayerID: binding.consumerLayerID,
                        providerLayerID: binding.providerLayerID,
                        slot: binding.slot,
                        variant: .primary
                    ))
                }
            case .none, .graphInternal:
                break
            }
        }
    }

    func requiresSceneEnvironment(layerID: Int) -> Bool {
        capabilitiesByLayerID[layerID]?.requiresSceneEnvironment == true
    }

    var sceneBackgroundLayerIDs: Set<Int> {
        Set(capabilitiesByLayerID.values.compactMap {
            $0.sceneBackgroundRequirement?.layerID
        })
    }

    var launchPipelineWarmupCapabilities: [LayerCapability] {
        capabilitiesByLayerID.keys.sorted().compactMap {
            capabilitiesByLayerID[$0]
        }
    }

    /// Dynamic uniforms owned by an admitted resolved graph remain live
    /// property consumers.
    var liveConsumerTargets: Set<SceneDynamicTarget> {
        capabilitiesByLayerID.values.reduce(into: Set<SceneDynamicTarget>()) {
            targets, capability in
            for stage in capability.stages {
                switch stage.execution {
                case .resolved(let materials, let activation):
                    targets.formUnion(activation?.liveConsumerTargets ?? [])
                    for material in materials.values {
                        for declaration in material.template.uniformDeclarations {
                            guard case let .dynamic(dynamic) = declaration.value,
                                  dynamic.valueContributors.count == 1,
                                  case .userProperty = dynamic.valueContributors[0]
                            else { continue }
                            targets.insert(dynamic.target)
                        }
                    }
                case .visualFailurePassthrough, .initiallyInactivePassthrough:
                    break
                }
            }
        }
    }

    /// SceneScript value producers remain live through the shared Program executor.
    var sceneScriptConsumerTargets: Set<SceneDynamicTarget> {
        capabilitiesByLayerID.values.reduce(into: Set<SceneDynamicTarget>()) {
            targets, capability in
            for stage in capability.stages {
                switch stage.execution {
                case .resolved(let materials, _):
                    for material in materials.values {
                        for declaration in material.template.uniformDeclarations {
                            guard case let .dynamic(dynamic) = declaration.value,
                                  dynamic.valueContributors == [.sceneScript] else {
                                continue
                            }
                            targets.insert(dynamic.target)
                        }
                    }
                case .visualFailurePassthrough, .initiallyInactivePassthrough:
                    break
                }
            }
        }
    }

}
