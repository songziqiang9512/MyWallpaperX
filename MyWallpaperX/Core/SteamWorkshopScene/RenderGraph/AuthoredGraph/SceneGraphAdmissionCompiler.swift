import CryptoKit
import Foundation

nonisolated struct SceneGraphClearFunctionRegistry: Equatable {
    typealias Graph = SceneAuthoredEffectRenderPlan

    struct ClearFunction: Equatable {
        let name: String
        /// Authored order is significant and duplicate targets remain visible.
        let targets: [Graph.TextureIdentity]
    }

    let functions: [ClearFunction]

    func function(named name: String) -> ClearFunction? {
        functions.first { $0.name == name }
    }
}

/// One explicit, frame-scoped request from the future SceneScript host bridge.
/// The request is inert until it is carried by a graph frame preparation.
nonisolated struct SceneGraphMaterialFunctionInvocationRequest: Hashable {
    typealias Graph = SceneAuthoredEffectRenderPlan

    let effect: Graph.EffectKey
    let functionName: String
    let frameEpoch: UInt64
}

nonisolated struct SceneGraphComposeTransitions: Equatable, Sendable {
    let nodeIndices: [Int]
    let digest: String

    var count: Int { nodeIndices.count }
}

/// Immutable handoff from raw authored graph parsing into target planning.
/// Functions are registered for explicit invocation only; compilation never
/// turns a named function into an automatic clear operation.
nonisolated struct SceneGraphAdmissionProduct {
    let graph: SceneAuthoredEffectRenderPlan
    let clearFunctions: SceneGraphClearFunctionRegistry
    let conditionSnapshot: SceneGraphConditionComboSnapshot
    let composeTransitions: SceneGraphComposeTransitions
}

nonisolated enum SceneGraphAdmissionCompiler {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Failure = SceneGraphAdmissionFailure
    typealias Product = SceneGraphAdmissionProduct

    private struct NodeDecision {
        let node: Graph.Node
        let admitted: Bool
        let bindingAdmission: [Bool]
        let composeTransition: Bool
    }

    private struct ComposeDigestPayload: Encodable {
        let schemaVersion: Int
        let effect: Graph.EffectKey
        let nodeIndices: [Int]
    }

    /// Conservative entry point when no shader-schema proof is available.
    static func compile(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        functions: SceneJSONValue?
    ) -> Result<Product, Failure> {
        compile(
            graph: graph,
            descriptor: descriptor,
            functions: functions,
            schemaEvidence: .unavailable
        )
    }

    static func compile(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        functions: SceneJSONValue?,
        schemaEvidence: SceneGraphConditionSchemaEvidence
    ) -> Result<Product, Failure> {
        do {
            return .success(try admitted(
                graph: graph,
                descriptor: descriptor,
                functions: functions,
                schemaEvidence: schemaEvidence
            ))
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(.init(code: .invalidGraph, path: "unexpected"))
        }
    }

    private static func admitted(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        functions: SceneJSONValue?,
        schemaEvidence: SceneGraphConditionSchemaEvidence
    ) throws -> Product {
        let effect = try validateRawGraph(graph, functions: functions)
        let providers = try SceneGraphConditionProviderSet(
            graph: graph,
            descriptor: descriptor
        )
        var evaluator = SceneGraphConditionEvaluator(
            providers: providers,
            evidence: schemaEvidence
        )

        var targetAdmission: [Bool] = []
        for (index, target) in graph.renderTargets.enumerated() {
            targetAdmission.append(try evaluator.evaluate(
                target.conditions,
                path: "fbos[\(index)].conditions"
            ))
        }
        var nodeDecisions: [NodeDecision] = []
        for node in graph.nodes {
            let compose = try composeTransition(node)
            let admitted = try evaluator.evaluate(
                node.conditions,
                path: "passes[\(node.definitionPassIndex)].conditions"
            )
            var bindings: [Bool] = []
            for (index, binding) in node.bindings.enumerated() {
                bindings.append(try evaluator.evaluate(
                    binding.conditions,
                    path: "passes[\(node.definitionPassIndex)].bind[\(index)].conditions"
                ))
            }
            nodeDecisions.append(.init(
                node: node,
                admitted: admitted,
                bindingAdmission: bindings,
                composeTransition: compose
            ))
        }

        let targets = zip(graph.renderTargets, targetAdmission).compactMap { target, keep in
            keep ? Graph.RenderTarget(
                texture: target.texture,
                extent: target.extent,
                format: target.format,
                declaredUnique: target.declaredUnique,
                clear: target.clear,
                uvs: target.uvs,
                conditions: nil
            ) : nil
        }
        let nodes = nodeDecisions.compactMap { decision -> Graph.Node? in
            guard decision.admitted else { return nil }
            let bindings = zip(decision.node.bindings, decision.bindingAdmission)
                .compactMap { binding, keep in
                    keep ? Graph.Binding(
                        slot: binding.slot,
                        authoredName: binding.authoredName,
                        texture: binding.texture,
                        conditions: nil
                    ) : nil
                }
            return Graph.Node(
                nodeIndex: decision.node.nodeIndex,
                effect: decision.node.effect,
                definitionPassIndex: decision.node.definitionPassIndex,
                materialOrdinal: decision.node.materialOrdinal,
                instancePassIndex: decision.node.instancePassIndex,
                kind: decision.node.kind,
                materialPath: decision.node.materialPath,
                materialPassID: decision.node.materialPassID,
                target: decision.node.target,
                bindings: bindings,
                commandSource: decision.node.commandSource,
                commandTarget: decision.node.commandTarget,
                compose: decision.composeTransition ? .bool(true) : nil,
                conditions: nil
            )
        }
        try validateAdmittedResources(nodes: nodes, targets: targets, effect: effect)
        try validateOutputSchedule(nodes: nodes, effect: effect)

        let admittedEffect = Graph.Effect(
            key: effect.key,
            definitionPath: effect.definitionPath,
            input: effect.input,
            output: effect.output,
            nodeIndices: nodes.map(\.nodeIndex)
        )
        let admittedGraph = Graph(
            layerID: graph.layerID,
            effects: [admittedEffect],
            renderTargets: targets,
            nodes: nodes,
            finalOutput: graph.finalOutput,
            blockers: []
        )
        let registry = try clearFunctionRegistry(
            functions,
            admittedTargets: targets
        )
        let composeIndices = nodes.compactMap {
            $0.compose == .bool(true) ? $0.nodeIndex : nil
        }
        let compose = try composeSummary(effect: effect.key, nodeIndices: composeIndices)
        return .init(
            graph: admittedGraph,
            clearFunctions: registry,
            conditionSnapshot: evaluator.snapshot(),
            composeTransitions: compose
        )
    }

    private static func validateRawGraph(
        _ graph: Graph,
        functions: SceneJSONValue?
    ) throws -> Graph.Effect {
        guard graph.effects.count == 1, let effect = graph.effects.first,
              graph.layerID == effect.key.layerID,
              graph.finalOutput == effect.output,
              effect.nodeIndices == graph.nodes.map(\.nodeIndex),
              Set(effect.nodeIndices).count == effect.nodeIndices.count,
              Set(graph.renderTargets.map(\.texture)).count == graph.renderTargets.count,
              graph.nodes.allSatisfy({ $0.effect == effect.key }) else {
            throw failure(.invalidGraph, "graph")
        }
        let handled: [Graph.BlockerReason] = [
            .unsupportedCondition,
            .unsupportedFunctions,
            .unsupportedCompose,
            .multipleEffectOutputs,
        ]
        guard graph.blockers.allSatisfy({ blocker in
            blocker.effect == effect.key && handled.contains(blocker.reason)
        }) else { throw failure(.graphBlocked, "blockers") }
        if graph.blockers.contains(where: { $0.reason == .unsupportedFunctions }),
           functions == nil {
            throw failure(.invalidFunctionRegistry, "functions")
        }
        guard graph.nodes.allSatisfy({ $0.kind != .unknownCommand }) else {
            throw failure(.invalidGraph, "nodes.kind")
        }
        return effect
    }

    private static func composeTransition(_ node: Graph.Node) throws -> Bool {
        guard let raw = node.compose else { return false }
        guard case .bool(let value) = raw else {
            throw failure(.invalidCompose, "passes[\(node.definitionPassIndex)].compose")
        }
        guard !value || node.kind == .material else {
            throw failure(.invalidCompose, "passes[\(node.definitionPassIndex)].compose")
        }
        return value
    }

    private static func validateAdmittedResources(
        nodes: [Graph.Node],
        targets: [Graph.RenderTarget],
        effect: Graph.Effect
    ) throws {
        let admitted = Set(targets.map(\.texture))
        func valid(_ identity: Graph.TextureIdentity?) -> Bool {
            guard let identity else { return true }
            switch identity.kind {
            case .framebuffer: return admitted.contains(identity)
            case .layerSource, .effectOutput:
                return identity == effect.input || identity == effect.output
            case .unresolved: return false
            }
        }
        for node in nodes {
            guard valid(node.target), valid(node.commandSource), valid(node.commandTarget),
                  node.bindings.allSatisfy({ valid($0.texture) }) else {
                throw failure(
                    .prunedResourceReferenced,
                    "passes[\(node.definitionPassIndex)]"
                )
            }
        }
    }

    private static func validateOutputSchedule(
        nodes: [Graph.Node],
        effect: Graph.Effect
    ) throws {
        let writers = nodes.enumerated().filter {
            $0.element.kind == .material && $0.element.target == effect.output
        }
        guard !writers.isEmpty else { throw failure(.missingEffectOutput, "effect.output") }
        guard let final = writers.last,
              final.element.compose == nil,
              writers.dropLast().allSatisfy({
                  $0.element.compose == .bool(true) && $0.offset < final.offset
              }) else {
            throw failure(.graphBlocked, "multipleEffectOutputs")
        }
    }

    private static func clearFunctionRegistry(
        _ raw: SceneJSONValue?,
        admittedTargets: [Graph.RenderTarget]
    ) throws -> SceneGraphClearFunctionRegistry {
        guard let raw else { return .init(functions: []) }
        guard case .object(let functions) = raw else {
            throw failure(.invalidFunctionRegistry, "functions")
        }
        let byName = Dictionary(grouping: admittedTargets, by: { $0.texture.name ?? "" })
        var compiled: [SceneGraphClearFunctionRegistry.ClearFunction] = []
        for name in functions.keys.sorted() {
            guard !name.isEmpty, name == name.trimmingCharacters(in: .whitespacesAndNewlines),
                  case .object(let descriptor) = functions[name],
                  Set(descriptor.keys) == Set(["action", "fbos"]),
                  descriptor["action"] == .string("clear"),
                  case .array(let rawTargets)? = descriptor["fbos"],
                  !rawTargets.isEmpty else {
                throw failure(.invalidFunctionRegistry, "functions.\(name)")
            }
            var targets: [Graph.TextureIdentity] = []
            for (index, rawTarget) in rawTargets.enumerated() {
                guard case .string(let targetName) = rawTarget,
                      !targetName.isEmpty,
                      let group = byName[targetName], group.count == 1 else {
                    throw failure(
                        .unknownFunctionTarget,
                        "functions.\(name).fbos[\(index)]"
                    )
                }
                targets.append(group[0].texture)
            }
            compiled.append(.init(name: name, targets: targets))
        }
        return .init(functions: compiled)
    }

    private static func composeSummary(
        effect: Graph.EffectKey,
        nodeIndices: [Int]
    ) throws -> SceneGraphComposeTransitions {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(ComposeDigestPayload(
            schemaVersion: 1,
            effect: effect,
            nodeIndices: nodeIndices
        )) else { throw failure(.digestFailure, "compose") }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return .init(nodeIndices: nodeIndices, digest: digest)
    }

    private static func failure(
        _ code: Failure.Code,
        _ path: String
    ) -> Failure {
        .init(code: code, path: path)
    }
}
