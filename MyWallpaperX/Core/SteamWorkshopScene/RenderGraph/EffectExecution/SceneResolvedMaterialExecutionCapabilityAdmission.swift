import Foundation

nonisolated struct SceneResolvedMaterialAdmittedLayer {
    typealias Graph = SceneAuthoredEffectRenderPlan

    enum SourceRoute: Equatable {
        case capturedLayerTexture
        case capturedMainTargetTexture
        case transparentDirectDraw
    }

    let layerID: Int
    let products: [SceneGraphAdmissionProduct]
    let pairPlan: SceneLayerFullFramePairPlan
    let dependencyOwnership: SceneResolvedMaterialDependencyOwnership
    let unavailableDependencyStageReasons: [Graph.EffectKey: String]
    let initiallyInactiveEffectKeys: Set<Graph.EffectKey>
    let sourceRoute: SourceRoute
    let isVisibleExecutionRoot: Bool
    let isGraphOutputProvider: Bool
    let requiresGraphOutputProvider: Bool

    init(
        layerID: Int,
        products: [SceneGraphAdmissionProduct],
        pairPlan: SceneLayerFullFramePairPlan,
        dependencyOwnership: SceneResolvedMaterialDependencyOwnership,
        unavailableDependencyStageReasons: [Graph.EffectKey: String] = [:],
        initiallyInactiveEffectKeys: Set<Graph.EffectKey> = [],
        sourceRoute: SourceRoute,
        isVisibleExecutionRoot: Bool,
        isGraphOutputProvider: Bool,
        requiresGraphOutputProvider: Bool
    ) {
        self.layerID = layerID
        self.products = products
        self.pairPlan = pairPlan
        self.dependencyOwnership = dependencyOwnership
        self.unavailableDependencyStageReasons = unavailableDependencyStageReasons
        self.initiallyInactiveEffectKeys = initiallyInactiveEffectKeys
        self.sourceRoute = sourceRoute
        self.isVisibleExecutionRoot = isVisibleExecutionRoot
        self.isGraphOutputProvider = isGraphOutputProvider
        self.requiresGraphOutputProvider = requiresGraphOutputProvider
    }
}

/// Narrows validated direct-bool bindings to ordinary, visible root layers.
/// Cross-layer providers/consumers and utility or hierarchy-owned output keep
/// their existing route; startup-inactive admission must not extend it.
nonisolated enum SceneInitiallyInactiveEffectRouteAdmission {
    static func targets(
        in descriptor: SceneRenderDescriptor,
        candidates: Set<SceneDynamicTarget>
    ) -> Set<SceneDynamicTarget> {
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let structuralUtilityConsumerLayerIDs =
            SceneResolvedMaterialDependencyOwnershipCompiler
                .structuralUtilityConsumerLayerIDs(in: descriptor)
        let dependencyPlan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: visibleLayerIDs,
            executableUtilityConsumerLayerIDs:
                structuralUtilityConsumerLayerIDs
        )
        return targets(
            in: descriptor,
            candidates: candidates,
            visibleLayerIDs: visibleLayerIDs,
            dependencyPlan: dependencyPlan
        )
    }

    static func targets(
        in descriptor: SceneRenderDescriptor,
        candidates: Set<SceneDynamicTarget>,
        visibleLayerIDs: Set<Int>,
        dependencyPlan: SceneDependencyRenderPlan
    ) -> Set<SceneDynamicTarget> {
        let layersByID = Dictionary(
            uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) }
        )
        let dependencyConsumerLayerIDs = Set(
            dependencyPlan.references.map(\.consumerLayerID)
        )
            .union(dependencyPlan.namedReferenceConsumerLayerIDs)
            .union(dependencyPlan.requiredEffectConsumerLayerIDs)
            .union(dependencyPlan.bindingsByConsumerLayerID.keys)
        let dependencyProviderLayerIDs = dependencyPlan.requiredProviderLayerIDs
            .union(dependencyPlan.requiredGraphOutputProviderLayerIDs)
        return Set(candidates.compactMap { target in
            guard case let .effectVisibility(layerID, effectIndex) = target,
                  let layer = layersByID[layerID],
                  layer.effects.indices.contains(effectIndex),
                  layer.effects[effectIndex].visible == false,
                  visibleLayerIDs.contains(layerID),
                  layer.parentID == nil,
                  layer.childLayerIDs.isEmpty,
                  layer.dependencyLayerIDs.isEmpty,
                  layer.authoredDependencies.isEmpty,
                  ["image", "solid", "text"].contains(layer.contentKind),
                  !dependencyConsumerLayerIDs.contains(layerID),
                  !dependencyProviderLayerIDs.contains(layerID),
                  !dependencyPlan.staticLayerSourcePassthroughBlockedLayerIDs
                    .contains(layerID) else { return nil }
            guard case nil = layer.utilityLayer else { return nil }
            return target
        })
    }
}

/// Raw-graph conservation and condition/function admission for one launch.
/// It never consumes a secondary renderer route or a recovery subset.
nonisolated enum SceneResolvedMaterialExecutionCapabilityAdmission {
    typealias Graph = SceneAuthoredEffectRenderPlan

    struct DynamicEffectVisibilityOwner: Hashable {
        let layerID: Int
        let effectIndex: Int
    }

    /// Bounds all layer-wide work before pair planning, target allocation, or
    /// per-frame executor preparation. Per-effect State limits still apply.
    static let maximumEffectsPerLayer = 512
    static let maximumNodesPerLayer = 65_536
    static let maximumRenderTargetsPerLayer = 65_536

    struct Failure: Error {
        let code: String
    }

    struct Candidate {
        let layerID: Int
        let result: Result<SceneResolvedMaterialAdmittedLayer, Failure>
        let dedicatedStagePrograms: [SceneEffectStageProgram]

        init(
            layerID: Int,
            result: Result<SceneResolvedMaterialAdmittedLayer, Failure>,
            dedicatedStagePrograms: [SceneEffectStageProgram] = []
        ) {
            self.layerID = layerID
            self.result = result
            self.dedicatedStagePrograms = dedicatedStagePrograms
        }
    }

    static func compile(
        descriptor: SceneRenderDescriptor,
        authoredPlans: [Graph],
        dedicatedStagePrograms: [SceneEffectStageProgram] = [],
        dynamicEffectVisibilityOwners: Set<DynamicEffectVisibilityOwner> = [],
        startupInactiveEffectVisibilityTargets: Set<SceneDynamicTarget> = [],
        conditionSchemaEvidence: [Graph.EffectKey: SceneGraphConditionSchemaEvidence] = [:]
    ) -> [Candidate] {
        let descriptorGroups = Dictionary(grouping: descriptor.layers, by: \.id)
        let rawGroups = Dictionary(grouping: authoredPlans, by: \.layerID)
        let dedicatedGroups = Dictionary(
            grouping: dedicatedStagePrograms,
            by: \.effectKey.layerID
        )
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let structuralUtilityDependencyConsumerLayerIDs =
            SceneResolvedMaterialDependencyOwnershipCompiler
                .structuralUtilityConsumerLayerIDs(in: descriptor)
        let dependencyPlan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: visibleLayerIDs,
            executableUtilityConsumerLayerIDs:
                structuralUtilityDependencyConsumerLayerIDs
        )
        let graphOutputProviderLayerIDs =
            dependencyPlan.requiredGraphOutputProviderLayerIDs
        let safeStartupInactiveTargets =
            SceneInitiallyInactiveEffectRouteAdmission.targets(
                in: descriptor,
                candidates: startupInactiveEffectVisibilityTargets,
                visibleLayerIDs: visibleLayerIDs,
                dependencyPlan: dependencyPlan
            )
        let activeLayerIDs = Set(descriptor.layers.compactMap { layer in
            layer.effects.contains(where: { $0.visible != false }) ? layer.id : nil
        })
        let dynamicLayerIDs = Set(dynamicEffectVisibilityOwners.map {
            $0.layerID
        })
        let candidateLayerIDs = activeLayerIDs.union(rawGroups.keys).union(dynamicLayerIDs)
        return candidateLayerIDs.sorted().map { layerID in
            let layers = descriptorGroups[layerID] ?? []
            guard layers.count == 1, let layer = layers.first else {
                return .init(
                    layerID: layerID,
                    result: .failure(failure("descriptor-layer-count"))
                )
            }
            let layerReferences = dependencyPlan.references.filter {
                $0.consumerLayerID == layerID
            }
            let binding = dependencyPlan.bindingsByConsumerLayerID[layerID]
            let compiledDependencyOwnership =
                SceneResolvedMaterialDependencyOwnershipCompiler
                .compile(
                    layer: layer,
                    graph: (rawGroups[layerID]?.count == 1)
                        ? rawGroups[layerID]?.first : nil,
                    references: layerReferences,
                    binding: binding
                )
            let unavailableDependencyStageReasons: [Graph.EffectKey: String]
            if compiledDependencyOwnership != nil {
                unavailableDependencyStageReasons = [:]
            } else if let keys =
                        SceneResolvedMaterialDependencyOwnershipCompiler
                            .forwardUnavailableEffectKeys(
                                layer: layer,
                                graph: (rawGroups[layerID]?.count == 1)
                                    ? rawGroups[layerID]?.first : nil,
                                descriptor: descriptor,
                                references: layerReferences,
                                binding: binding
                            ) {
                unavailableDependencyStageReasons = Dictionary(
                    uniqueKeysWithValues: keys.map {
                        ($0, "dependency-stage-reference-unavailable")
                    }
                )
            } else if let keys =
                        SceneResolvedMaterialDependencyOwnershipCompiler
                            .secondarySelfUnavailableEffectKeys(
                                layer: layer,
                                graph: (rawGroups[layerID]?.count == 1)
                                    ? rawGroups[layerID]?.first : nil,
                                references: layerReferences,
                                binding: binding
                            ) {
                unavailableDependencyStageReasons = Dictionary(
                    uniqueKeysWithValues: keys.map {
                        ($0, "dependency-stage-secondary-reference-unavailable")
                    }
                )
            } else {
                unavailableDependencyStageReasons = [:]
            }
            let dependencyOwnership = compiledDependencyOwnership
                ?? (unavailableDependencyStageReasons.isEmpty
                    ? nil : SceneResolvedMaterialDependencyOwnership.none)
            let sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute
            switch executionSourceRoute(
                layer,
                descriptor: descriptor,
                visibleLayerIDs: visibleLayerIDs,
                graphOutputProviderLayerIDs: graphOutputProviderLayerIDs,
                dependencyOwnership: dependencyOwnership
            ) {
            case let .success(route):
                sourceRoute = route
            case let .failure(reason):
                return .init(
                    layerID: layerID,
                    result: .failure(reason)
                )
            }
            guard !dynamicLayerIDs.contains(layerID) else {
                return .init(
                    layerID: layerID,
                    result: .failure(failure("dynamic-effect-visibility"))
                )
            }
            let graphs = rawGroups[layerID] ?? []
            guard graphs.count == 1, let graph = graphs.first,
                  let dependencyOwnership else {
                return .init(
                    layerID: layerID,
                    result: .failure(failure("raw-graph-count"))
                )
            }
            let graphKeys = Set(graph.effects.map(\.key))
            let plannedEffects = layer.effects.enumerated().filter {
                effectIndex, effect in
                if effect.visible != false { return true }
                return graphKeys.contains(.init(
                    layerID: layerID,
                    effectIndex: effectIndex,
                    descriptorID: effect.id
                ))
            }
            let initiallyInactiveEffectKeys: Set<Graph.EffectKey> = Set(
                plannedEffects.compactMap { effectIndex, effect -> Graph.EffectKey? in
                    guard effect.visible == false else { return nil }
                    let target = SceneDynamicTarget.effectVisibility(
                        layerID: layerID,
                        effectIndex: effectIndex
                    )
                    guard safeStartupInactiveTargets.contains(target)
                    else { return nil }
                    return Graph.EffectKey(
                        layerID: layerID,
                        effectIndex: effectIndex,
                        descriptorID: effect.id
                    )
                }
            )
            guard !plannedEffects.isEmpty,
                  plannedEffects.filter({ $0.element.visible == false }).count
                    == initiallyInactiveEffectKeys.count else {
                return .init(
                    layerID: layerID,
                    result: .failure(failure("active-effect-conservation"))
                )
            }
            return .init(
                layerID: layerID,
                result: compileLayer(
                    graph: graph,
                    layer: layer,
                    plannedEffects: plannedEffects,
                    descriptor: descriptor,
                    dependencyOwnership: dependencyOwnership,
                    unavailableDependencyStageReasons:
                        unavailableDependencyStageReasons,
                    initiallyInactiveEffectKeys:
                        initiallyInactiveEffectKeys,
                    sourceRoute: sourceRoute,
                    isVisibleExecutionRoot: visibleLayerIDs.contains(layerID),
                    isGraphOutputProvider:
                        graphOutputProviderLayerIDs.contains(layerID),
                    requiresGraphOutputProvider: {
                        guard case let .externalPrimary(binding) =
                                dependencyOwnership else { return false }
                        return graphOutputProviderLayerIDs.contains(
                            binding.providerLayerID
                        )
                    }(),
                    conditionSchemaEvidence: conditionSchemaEvidence
                ),
                dedicatedStagePrograms: dedicatedGroups[layerID] ?? []
            )
        }
    }

    private static func executionSourceRoute(
        _ layer: SceneRenderDescriptor.Layer,
        descriptor: SceneRenderDescriptor,
        visibleLayerIDs: Set<Int>,
        graphOutputProviderLayerIDs: Set<Int>,
        dependencyOwnership: SceneResolvedMaterialDependencyOwnership?
    ) -> Result<SceneResolvedMaterialAdmittedLayer.SourceRoute, Failure> {
        guard visibleLayerIDs.contains(layer.id)
                || graphOutputProviderLayerIDs.contains(layer.id) else {
            return .failure(failure("execution-route-layer-hidden"))
        }
        guard let dependencyOwnership else {
            return .failure(failure("execution-route-dependency-owner"))
        }
        if layer.utilityLayer != nil {
            let utilityRoute: SceneUtilityLayerSourceRoute.Resolution
            switch SceneUtilityLayerSourceRoute.resolve(
                layer: layer,
                descriptor: descriptor
            ) {
            case let .success(resolution):
                utilityRoute = resolution
            case let .failure(routeFailure):
                return .failure(failure("execution-route-\(routeFailure.rawValue)"))
            }
            switch dependencyOwnership {
            case .none:
                break
            case let .externalPrimary(binding):
                guard binding.consumerLayerID == layer.id,
                      binding.kind == .resolvedMaterial
                        || binding.kind == .solidLayer else {
                    return .failure(failure("execution-route-utility-shape"))
                }
            case .graphInternal:
                return .failure(failure("execution-route-utility-shape"))
            }
            if utilityRoute.capturesCompositionSubtree,
               dependencyOwnership != .none {
                return .failure(failure(
                    "execution-route-utility-composition-subtree-shape"
                ))
            }
            return .success(.capturedMainTargetTexture)
        }
        switch layer.contentKind {
        case "image", "solid", "text":
            return .success(.capturedLayerTexture)
        case "quad":
            return .success(.transparentDirectDraw)
        default:
            return .failure(failure("execution-route-content-kind"))
        }
    }

    private static func compileLayer(
        graph: Graph,
        layer: SceneRenderDescriptor.Layer,
        plannedEffects: [(offset: Int, element: SceneRenderDescriptor.EffectDescriptor)],
        descriptor: SceneRenderDescriptor,
        dependencyOwnership: SceneResolvedMaterialDependencyOwnership,
        unavailableDependencyStageReasons: [Graph.EffectKey: String],
        initiallyInactiveEffectKeys: Set<Graph.EffectKey>,
        sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute,
        isVisibleExecutionRoot: Bool,
        isGraphOutputProvider: Bool,
        requiresGraphOutputProvider: Bool,
        conditionSchemaEvidence: [Graph.EffectKey: SceneGraphConditionSchemaEvidence]
    ) -> Result<SceneResolvedMaterialAdmittedLayer, Failure> {
        do {
            guard graph.effects.count <= maximumEffectsPerLayer,
                  graph.nodes.count <= maximumNodesPerLayer,
                  graph.renderTargets.count <= maximumRenderTargetsPerLayer else {
                throw failure("layer-capacity")
            }
            try validateOuterGraph(
                graph,
                layer: layer,
                plannedEffects: plannedEffects
            )
            var products: [SceneGraphAdmissionProduct] = []
            for effect in graph.effects {
                let definitions = descriptor.effectDefinitions.filter {
                    normalized($0.relativePath) == normalized(effect.definitionPath)
                }
                guard definitions.count == 1, let definition = definitions.first else {
                    throw failure("effect-definition-count")
                }
                let stage = try extractStage(effect, from: graph)
                let result = SceneGraphAdmissionCompiler.compile(
                    graph: stage,
                    descriptor: descriptor,
                    functions: definition.functions,
                    schemaEvidence: conditionSchemaEvidence[effect.key] ?? .unavailable
                )
                switch result {
                case let .success(product):
                    try validateAdmittedStructure(product.graph)
                    products.append(product)
                case let .failure(rejection):
                    throw failure("graph-admission-\(rejection.code.rawValue)")
                }
            }
            guard products.count == graph.effects.count else {
                throw failure("active-effect-conservation")
            }
            let pairResult = SceneLayerFullFramePairPlan.make(
                conditionPrunedGraphs: products.map(\.graph)
            )
            let pair: SceneLayerFullFramePairPlan
            switch pairResult {
            case let .success(value): pair = value
            case let .failure(rejection):
                throw failure("pair-plan-\(rejection.rawValue)")
            }
            guard pair.effects.map(\.effect) == graph.effects.map(\.key),
                  pair.terminalOutputIdentity == graph.finalOutput else {
                throw failure("active-effect-conservation")
            }
            return .success(.init(
                layerID: graph.layerID,
                products: products,
                pairPlan: pair,
                dependencyOwnership: dependencyOwnership,
                unavailableDependencyStageReasons:
                    unavailableDependencyStageReasons,
                initiallyInactiveEffectKeys: initiallyInactiveEffectKeys,
                sourceRoute: sourceRoute,
                isVisibleExecutionRoot: isVisibleExecutionRoot,
                isGraphOutputProvider: isGraphOutputProvider,
                requiresGraphOutputProvider: requiresGraphOutputProvider
            ))
        } catch let rejection as Failure {
            return .failure(rejection)
        } catch {
            return .failure(failure("unexpected-admission-failure"))
        }
    }

    private static func validateOuterGraph(
        _ graph: Graph,
        layer: SceneRenderDescriptor.Layer,
        plannedEffects: [(offset: Int, element: SceneRenderDescriptor.EffectDescriptor)]
    ) throws {
        guard graph.layerID == layer.id,
              graph.effects.count == plannedEffects.count,
              !graph.effects.isEmpty else {
            throw failure("active-effect-conservation")
        }
        var expectedInput = SceneAuthoredEffectInputValidator.layerSource(
            layerID: layer.id
        )
        var seenKeys = Set<Graph.EffectKey>()
        var seenNodeIndices = Set<Int>()
        for (effect, active) in zip(graph.effects, plannedEffects) {
            let expectedKey = Graph.EffectKey(
                layerID: layer.id,
                effectIndex: active.offset,
                descriptorID: active.element.id
            )
            guard effect.key == expectedKey,
                  normalized(effect.definitionPath)
                    == normalized(active.element.file),
                  seenKeys.insert(effect.key).inserted else {
                throw failure("active-effect-identity")
            }
            guard effect.input == expectedInput else {
                throw failure("effect-input-continuity")
            }
            let expectedOutput = Graph.TextureIdentity(
                kind: .effectOutput,
                layerID: layer.id,
                effect: effect.key,
                name: nil
            )
            guard effect.output == expectedOutput, !effect.nodeIndices.isEmpty else {
                throw failure("active-effect-output")
            }
            for nodeIndex in effect.nodeIndices {
                guard seenNodeIndices.insert(nodeIndex).inserted else {
                    throw failure("outer-node-conservation")
                }
            }
            expectedInput = effect.output
        }
        let authoredNodeOrder = graph.effects.flatMap(\.nodeIndices)
        guard graph.finalOutput == expectedInput,
              authoredNodeOrder == graph.nodes.map(\.nodeIndex),
              seenNodeIndices.count == graph.nodes.count else {
            throw failure("outer-node-conservation")
        }
        let ownerByNode = Dictionary(uniqueKeysWithValues: graph.effects.flatMap { effect in
            effect.nodeIndices.map { ($0, effect.key) }
        })
        guard graph.nodes.allSatisfy({
                  ownerByNode[$0.nodeIndex] == $0.effect
              }), graph.renderTargets.allSatisfy({ target in
                  target.texture.effect.map(seenKeys.contains) == true
              }), graph.blockers.allSatisfy({ seenKeys.contains($0.effect) }) else {
            throw failure("outer-resource-conservation")
        }
    }

    private static func extractStage(
        _ effect: Graph.Effect,
        from graph: Graph
    ) throws -> Graph {
        let byIndex = Dictionary(grouping: graph.nodes, by: \.nodeIndex)
        var nodes: [Graph.Node] = []
        for index in effect.nodeIndices {
            let matches = byIndex[index] ?? []
            guard matches.count == 1, let node = matches.first,
                  node.effect == effect.key else {
                throw failure("stage-extraction")
            }
            nodes.append(node)
        }
        return Graph(
            layerID: graph.layerID,
            effects: [effect],
            renderTargets: graph.renderTargets.filter {
                $0.texture.effect == effect.key
            },
            nodes: nodes,
            finalOutput: effect.output,
            blockers: graph.blockers.filter { $0.effect == effect.key }
        )
    }

    private static func validateAdmittedStructure(_ graph: Graph) throws {
        guard graph.nodes.count <= SceneGraphExecutionState.maximumNodeCount,
              graph.renderTargets.count
                <= SceneGraphExecutionState.maximumLogicalBindingCount - 2,
              graph.nodes.contains(where: { node in
                  if case .material = node.kind { return true }
                  return false
              }), graph.renderTargets.allSatisfy({ target in
                  SceneGraphRenderTargetPlan.targetDescriptor(
                      target,
                      inputWidth: 1,
                      inputHeight: 1
                  ) != nil
              }), graph.nodes.allSatisfy({ node in
                  switch node.kind {
                  case .material, .copy, .swap: return true
                  case .unknownCommand: return false
                  }
              }) else {
            throw failure("admitted-graph-structure")
        }
        guard SceneGraphRenderTargetPlan.authoredSwapDescriptorsAreCompatible(in: graph) else {
            throw failure("swap-target-descriptor-incompatible")
        }
    }

    private static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private static func failure(_ code: String) -> Failure {
        .init(code: code)
    }
}
