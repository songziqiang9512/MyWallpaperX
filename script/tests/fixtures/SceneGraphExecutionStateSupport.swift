import Foundation

struct SceneEffectStageExecutionPlan {
    let layerID: Int
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole
    var supportsUnifiedFullFrameComposeStage: Bool { false }
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Plan = SceneGraphRenderTargetPlan
    typealias Pair = SceneLayerFullFramePairPlan
    typealias State = SceneGraphExecutionState

    static let layerID = 10
    static let key = Graph.EffectKey(
        layerID: layerID, effectIndex: 0, descriptorID: "effect-0"
    )
    static let input = identity(.layerSource)
    static let output = identity(.effectOutput, effect: key)
    static let fixedExtent = Graph.TargetExtent(
        width: 100, height: 50, fit: nil, scale: nil
    )
    static let dynamicExtent = Graph.TargetExtent(
        width: nil, height: nil, fit: nil, scale: nil
    )

    static func identity(
        _ kind: Graph.TextureKind,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }

    static func rawTarget(
        _ identity: Graph.TextureIdentity,
        unique: Bool = false,
        extent: Graph.TargetExtent = fixedExtent,
        clear: SceneJSONValue? = nil,
        uvs: SceneJSONValue? = nil
    ) -> Graph.RenderTarget {
        .init(
            texture: identity,
            extent: extent,
            format: "rgba_backbuffer",
            declaredUnique: unique,
            clear: clear,
            uvs: uvs,
            conditions: nil
        )
    }

    static func binding(
        _ identity: Graph.TextureIdentity,
        slot: Int
    ) -> Graph.Binding {
        .init(
            slot: slot,
            authoredName: identity.name ?? "previous",
            texture: identity,
            conditions: nil
        )
    }

    static func material(
        _ nodeIndex: Int,
        ordinal: Int,
        target: Graph.TextureIdentity,
        reads: [Graph.TextureIdentity],
        compose: SceneJSONValue? = nil
    ) -> Graph.Node {
        .init(
            nodeIndex: nodeIndex,
            effect: key,
            definitionPassIndex: nodeIndex,
            materialOrdinal: ordinal,
            instancePassIndex: ordinal,
            kind: .material,
            materialPath: "materials/test.json",
            materialPassID: "test#\(ordinal)",
            target: target,
            bindings: reads.enumerated().map { binding($0.element, slot: $0.offset) },
            commandSource: nil,
            commandTarget: nil,
            compose: compose,
            conditions: nil
        )
    }

    static func command(
        _ nodeIndex: Int,
        kind: Graph.NodeKind,
        source: Graph.TextureIdentity,
        target: Graph.TextureIdentity
    ) -> Graph.Node {
        .init(
            nodeIndex: nodeIndex,
            effect: key,
            definitionPassIndex: nodeIndex,
            materialOrdinal: nil,
            instancePassIndex: nil,
            kind: kind,
            materialPath: nil,
            materialPassID: nil,
            target: nil,
            bindings: [],
            commandSource: source,
            commandTarget: target,
            compose: nil,
            conditions: nil
        )
    }

    static func graph(
        targets: [Graph.RenderTarget],
        nodes: [Graph.Node],
        blockers: [Graph.Blocker] = []
    ) -> Graph {
        let effect = Graph.Effect(
            key: key,
            definitionPath: "effects/test/effect.json",
            input: input,
            output: output,
            nodeIndices: nodes.map(\.nodeIndex)
        )
        return .init(
            layerID: layerID,
            effects: [effect],
            renderTargets: targets,
            nodes: nodes,
            finalOutput: output,
            blockers: blockers
        )
    }

    static func requirePlan(
        _ graph: Graph,
        width: Int = 100,
        height: Int = 50,
        materialFunctionTargets: Set<Graph.TextureIdentity> = [],
        line: UInt = #line
    ) -> Plan {
        let result = Plan.make(
            graph: graph,
            inputRole: .layerSource,
            inputWidth: width,
            inputHeight: height,
            materialFunctionTargets: materialFunctionTargets
        )
        guard case let .success(plan) = result else {
            if case let .failure(reason) = result {
                fatalError("expected target plan at \(line): \(reason)")
            }
            fatalError("expected target plan at \(line)")
        }
        return plan
    }

    static func requirePair(_ graph: Graph) -> Pair.EffectStep {
        guard case .success(let plan) = Pair.make(conditionPrunedGraphs: [graph]),
              let step = plan.effects.first else {
            fatalError("expected pair step")
        }
        return step
    }

    static func allocation(
        plan: Plan,
        generation: UInt64,
        prefix: String,
        tokenOverrides: [Graph.TextureIdentity: String] = [:]
    ) -> State.Allocation {
        let resources = Dictionary(uniqueKeysWithValues: plan.logicalTargets.map {
            logical in
            let token = tokenOverrides[logical.identity]
                ?? "\(prefix)-\(logical.identity.name ?? "fbo")"
            return (logical.identity, State.Resource(
                token: .init(rawValue: token),
                descriptor: .init(
                    extent: logical.extent,
                    format: logical.format,
                    addressMode: logical.addressMode,
                    isUnique: logical.isUnique,
                    initialClear: logical.initialClear
                )
            ))
        })
        return .init(generation: generation, resources: resources)
    }

    static func prepared(_ graph: Graph, _ plan: Plan, _ pair: Pair.EffectStep,
                         targets: Set<Graph.TextureIdentity> = []) -> State.PreparedExecution {
        guard case let .success(value) = State.prepareExecution(
            graph: graph, plan: plan, pairStep: pair, materialFunctionTargets: targets
        ) else { fatalError("expected static execution") }
        return value
    }

    static func failureCode<T>(_ result: Result<T, State.Failure>) -> String {
        if case let .failure(failure) = result { return failure.rawValue }
        return "accepted"
    }

    static func require(
        _ result: Result<State.Transition, State.Failure>,
        line: UInt = #line
    ) -> State.Transition {
        guard case .success(let value) = result else {
            let failure: String
            if case .failure(let reason) = result {
                failure = reason.rawValue
            } else {
                failure = "unknown"
            }
            fatalError("expected transition at \(line): \(failure)")
        }
        return value
    }

    static func failure(
        graph: Graph,
        plan: Plan,
        pair: Pair.EffectStep,
        allocation: State.Allocation,
        effectGeneration: UInt64 = 1,
        resetGeneration: UInt64 = 1,
        previous: State = .empty,
        historyRehydration: [State.PhysicalToken: State.PhysicalToken] = [:],
        materialFunctionInvocations: [State.MaterialFunctionInvocation] = []
    ) -> String {
        switch State.reduce(
            graph: graph,
            targetPlan: plan,
            pairStep: pair,
            allocation: allocation,
            effectGeneration: effectGeneration,
            resetGeneration: resetGeneration,
            previous: previous,
            historyRehydration: historyRehydration,
            materialFunctionInvocations: materialFunctionInvocations
        ) {
        case .success: return "success"
        case .failure(let reason): return reason.rawValue
        }
    }

    static func kinds(_ intents: [State.Intent]) -> [String] {
        intents.map {
            switch $0 {
            case .initialize: return "initialize"
            case .material: return "material"
            case .copy: return "copy"
            case .swap: return "swap"
            }
        }
    }

    static func token(
        _ mapping: [Graph.TextureIdentity: State.VersionedResource],
        _ identity: Graph.TextureIdentity
    ) -> String {
        mapping[identity]?.token.rawValue ?? "missing"
    }

    static func generation(
        _ mapping: [Graph.TextureIdentity: State.VersionedResource],
        _ identity: Graph.TextureIdentity
    ) -> UInt64 {
        mapping[identity]?.contentGeneration ?? 0
    }

    static func initializationTokens(_ intents: [State.Intent]) -> [String] {
        intents.compactMap {
            guard case .initialize(_, let resource, _) = $0 else { return nil }
            return resource.token.rawValue
        }
    }

    static func functionClearReasons(_ intents: [State.Intent]) -> [String] {
        intents.compactMap {
            guard case let .initialize(_, _, reason) = $0,
                  case let .materialFunctionClear(
                      name, invocationOrdinal, targetOrdinal
                  ) = reason else { return nil }
            return "\(name):\(invocationOrdinal):\(targetOrdinal)"
        }
    }

    static func materialShapes(_ intents: [State.Intent]) -> [[String]] {
        intents.compactMap {
            guard case .material(_, _, let bindings, let target) = $0 else {
                return nil
            }
            return [
                bindings.map { $0.identity.name ?? "pair" }.joined(separator: ","),
                target?.identity.name ?? "pair",
            ]
        }
    }

    static func materialOrdinals(_ intents: [State.Intent]) -> [Int] {
        intents.compactMap {
            guard case .material(_, let ordinal, _, _) = $0 else { return nil }
            return ordinal
        }
    }

}
