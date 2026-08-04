import Foundation

nonisolated struct SceneResolvedMaterialAdmittedLayer {
    typealias Graph = SceneAuthoredEffectRenderPlan

    let layerID: Int
    let products: [SceneGraphAdmissionProduct]
    let pairPlan: SceneLayerFullFramePairPlan
}

/// Raw-graph conservation and condition/function admission for one launch.
/// It never consumes strict renderer chains or recovery subsets.
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
    }

    static func compile(
        descriptor: SceneRenderDescriptor,
        authoredPlans: [Graph],
        dynamicEffectVisibilityOwners: Set<DynamicEffectVisibilityOwner> = [],
        specializedLayerIDs: Set<Int> = []
    ) -> [Candidate] {
        let descriptorGroups = Dictionary(grouping: descriptor.layers, by: \.id)
        let rawGroups = Dictionary(grouping: authoredPlans, by: \.layerID)
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let dependencyPlan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: visibleLayerIDs
        )
        let activeLayerIDs = Set(descriptor.layers.compactMap { layer in
            layer.effects.contains(where: { $0.visible != false }) ? layer.id : nil
        })
        let dynamicLayerIDs = Set(dynamicEffectVisibilityOwners.map(\.layerID))
        let candidateLayerIDs = activeLayerIDs.union(rawGroups.keys).union(dynamicLayerIDs)
        return candidateLayerIDs.sorted().map { layerID in
            let layers = descriptorGroups[layerID] ?? []
            guard layers.count == 1, let layer = layers.first else {
                return .init(
                    layerID: layerID,
                    result: .failure(failure("descriptor-layer-count"))
                )
            }
            if let reason = executionRouteRejection(
                layer,
                visibleLayerIDs: visibleLayerIDs,
                namedReferenceConsumerLayerIDs:
                    dependencyPlan.namedReferenceConsumerLayerIDs,
                specializedLayerIDs: specializedLayerIDs
            ) {
                return .init(
                    layerID: layerID,
                    result: .failure(failure(reason))
                )
            }
            guard !dynamicLayerIDs.contains(layerID) else {
                return .init(
                    layerID: layerID,
                    result: .failure(failure("dynamic-effect-visibility"))
                )
            }
            let activeEffects = layer.effects.enumerated().filter {
                $0.element.visible != false
            }
            guard !activeEffects.isEmpty else {
                return .init(
                    layerID: layerID,
                    result: .failure(failure("active-effect-conservation"))
                )
            }
            let graphs = rawGroups[layerID] ?? []
            guard graphs.count == 1, let graph = graphs.first else {
                return .init(
                    layerID: layerID,
                    result: .failure(failure("raw-graph-count"))
                )
            }
            return .init(
                layerID: layerID,
                result: compileLayer(
                    graph: graph,
                    layer: layer,
                    activeEffects: activeEffects,
                    descriptor: descriptor
                )
            )
        }
    }

    private static func executionRouteRejection(
        _ layer: SceneRenderDescriptor.Layer,
        visibleLayerIDs: Set<Int>,
        namedReferenceConsumerLayerIDs: Set<Int>,
        specializedLayerIDs: Set<Int>
    ) -> String? {
        guard visibleLayerIDs.contains(layer.id) else {
            return "execution-route-layer-hidden"
        }
        guard ["image", "solid", "text"].contains(layer.contentKind) else {
            return "execution-route-content-kind"
        }
        guard case .none = layer.utilityLayer else {
            return "execution-route-utility-owner"
        }
        guard layer.dependencyLayerIDs.isEmpty,
              layer.authoredDependencies.isEmpty,
              !namedReferenceConsumerLayerIDs.contains(layer.id) else {
            return "execution-route-dependency-owner"
        }
        guard !specializedLayerIDs.contains(layer.id) else {
            return "execution-route-specialized-owner"
        }
        return nil
    }

    private static func compileLayer(
        graph: Graph,
        layer: SceneRenderDescriptor.Layer,
        activeEffects: [(offset: Int, element: SceneRenderDescriptor.EffectDescriptor)],
        descriptor: SceneRenderDescriptor
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
                activeEffects: activeEffects
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
                    schemaEvidence: .unavailable
                )
                switch result {
                case let .success(product):
                    guard product.clearFunctions.functions.isEmpty else {
                        throw failure("function-invocation-unavailable")
                    }
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
                pairPlan: pair
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
        activeEffects: [(offset: Int, element: SceneRenderDescriptor.EffectDescriptor)]
    ) throws {
        guard graph.layerID == layer.id,
              graph.effects.count == activeEffects.count,
              !graph.effects.isEmpty else {
            throw failure("active-effect-conservation")
        }
        var expectedInput = SceneAuthoredEffectInputValidator.layerSource(
            layerID: layer.id
        )
        var seenKeys = Set<Graph.EffectKey>()
        var seenNodeIndices = Set<Int>()
        for (effect, active) in zip(graph.effects, activeEffects) {
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
    }

    private static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private static func failure(_ code: String) -> Failure {
        .init(code: code)
    }
}
