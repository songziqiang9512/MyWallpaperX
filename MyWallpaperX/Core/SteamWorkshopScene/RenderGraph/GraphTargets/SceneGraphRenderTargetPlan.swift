import Foundation

nonisolated struct SceneGraphRenderTargetPlan: Equatable {
    typealias Graph = SceneAuthoredEffectRenderPlan

    enum TextureFormat: String {
        case r8
        case rg88
        case r16f
        case rg1616f
        case rgbaBackbuffer
        case rgba8888
    }

    enum UVAddressMode: String, Equatable {
        case clampToEdge
        case repeatWrap
    }

    struct PixelExtent: Equatable {
        let width: Int
        let height: Int
    }

    struct ClearColor: Equatable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    struct Lifetime: Equatable {
        let firstWriteNodeIndex: Int
        let lastWriteNodeIndex: Int
        let firstReadNodeIndex: Int?
        let lastReadNodeIndex: Int?
        var requiresHistorySeed = false
    }

    struct LogicalTarget: Equatable {
        let identity: Graph.TextureIdentity
        let extent: PixelExtent
        let format: TextureFormat
        let addressMode: UVAddressMode
        let isUnique: Bool
        let lifetime: Lifetime
        let initialClear: ClearColor?
    }

    struct FeedbackHistoryProfile: Equatable {
        let seedTargets: Set<Graph.TextureIdentity>
        let stateTargets: Set<Graph.TextureIdentity>
    }

    enum CommandKind: String, Equatable {
        case copy
        case swap
    }

    struct Command: Equatable {
        let nodeIndex: Int
        let kind: CommandKind
        let source: Graph.TextureIdentity
        let target: Graph.TextureIdentity
    }

    enum Failure: String, Error {
        case invalidInputExtent
        case executionMismatch
        case incompleteIdentity
        case duplicateTarget
        case invalidNodeOrder
        case invalidAccess
        case historyRequired
        case unsupportedTargetDescriptor
        case unwrittenTarget
        case missingOutput
    }

    let layerID: Int
    let input: Graph.TextureIdentity
    let output: Graph.TextureIdentity
    let inputRole: SceneAuthoredEffectInputRole
    let inputExtent: PixelExtent
    let logicalTargets: [LogicalTarget]
    let commands: [Command]

    private init(
        layerID: Int,
        input: Graph.TextureIdentity,
        output: Graph.TextureIdentity,
        inputRole: SceneAuthoredEffectInputRole = .layerSource,
        inputExtent: PixelExtent,
        logicalTargets: [LogicalTarget],
        commands: [Command] = []
    ) {
        self.layerID = layerID
        self.input = input
        self.output = output
        self.inputRole = inputRole
        self.inputExtent = inputExtent
        self.logicalTargets = logicalTargets
        self.commands = commands
    }

#if SCENE_GRAPH_TESTING
    static func testingPlan(
        layerID: Int,
        input: Graph.TextureIdentity,
        output: Graph.TextureIdentity,
        inputRole: SceneAuthoredEffectInputRole = .layerSource,
        inputExtent: PixelExtent,
        logicalTargets: [LogicalTarget],
        commands: [Command] = []
    ) -> Self {
        Self(
            layerID: layerID,
            input: input,
            output: output,
            inputRole: inputRole,
            inputExtent: inputExtent,
            logicalTargets: logicalTargets,
            commands: commands
        )
    }
#endif

    /// R4 entry point for one immutable condition-pruned authored graph.
    /// Dedicated backends are not consulted for target or history semantics.
    static func make(
        graph: Graph,
        inputRole: SceneAuthoredEffectInputRole,
        inputWidth: Int,
        inputHeight: Int,
        materialFunctionTargets: Set<Graph.TextureIdentity> = []
    ) -> Result<Self, Failure> {
        makeValidated(
            graph: graph,
            inputRole: inputRole,
            inputWidth: inputWidth,
            inputHeight: inputHeight,
            materialFunctionTargets: materialFunctionTargets
        )
    }

    private static func makeValidated(
        graph: Graph,
        inputRole: SceneAuthoredEffectInputRole,
        inputWidth: Int,
        inputHeight: Int,
        materialFunctionTargets: Set<Graph.TextureIdentity>
    ) -> Result<Self, Failure> {
        guard inputWidth > 0, inputHeight > 0 else {
            return .failure(.invalidInputExtent)
        }
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              let effect = graph.effects.first,
              effect.nodeIndices == graph.nodes.map(\.nodeIndex),
              graph.finalOutput == effect.output else {
            return .failure(.executionMismatch)
        }
        guard validEffectKey(effect.key, layerID: graph.layerID),
              let resolvedInputRole = SceneAuthoredEffectInputValidator.role(
                for: effect.input,
                layerID: graph.layerID
              ),
              validOutput(effect.output, effect: effect.key, layerID: graph.layerID) else {
            return .failure(.incompleteIdentity)
        }
        guard resolvedInputRole == inputRole else {
            return .failure(.executionMismatch)
        }

        var declarations: [Graph.TextureIdentity: Graph.RenderTarget] = [:]
        for target in graph.renderTargets {
            guard validTargetIdentity(
                target.texture,
                effect: effect.key,
                layerID: graph.layerID
            ) else {
                return .failure(.incompleteIdentity)
            }
            guard declarations.updateValue(target, forKey: target.texture) == nil else {
                return .failure(.duplicateTarget)
            }
        }

        var descriptors: [Graph.TextureIdentity: TargetDescriptor] = [:]
        descriptors.reserveCapacity(graph.renderTargets.count)
        for target in graph.renderTargets {
            guard let descriptor = targetDescriptor(
                target,
                inputWidth: inputWidth,
                inputHeight: inputHeight
            ) else {
                return .failure(.unsupportedTargetDescriptor)
            }
            descriptors[target.texture] = descriptor
        }
        guard authoredSwapDescriptorsAreCompatible(in: graph) else {
            return .failure(.unsupportedTargetDescriptor)
        }
        let feedbackHistory = boundedFeedbackHistoryProfile(
            graph: graph,
            descriptors: descriptors
        )

        var firstReads: [Graph.TextureIdentity: Int] = [:]
        var lastReads: [Graph.TextureIdentity: Int] = [:]
        var firstWrites: [Graph.TextureIdentity: Int] = [:]
        var lastWrites: [Graph.TextureIdentity: Int] = [:]
        var historySeedTargets = Set<Graph.TextureIdentity>()
        var outputWriteCount = 0
        var outputComposeFlags: [Bool] = []
        var previousNodeIndex: Int?
        var commands: [Command] = []

        let functionTargets = materialFunctionTargets.filter {
            declarations[$0] != nil
        }
        guard functionTargets == materialFunctionTargets else {
            return .failure(.invalidAccess)
        }
        if let firstNodeIndex = graph.nodes.first?.nodeIndex {
            for identity in functionTargets {
                firstWrites[identity] = firstNodeIndex
                lastWrites[identity] = firstNodeIndex
            }
        }

        func permitsFirstRead(_ identity: Graph.TextureIdentity) -> Bool {
            guard let descriptor = descriptors[identity] else { return false }
            return descriptor.initialClear != nil || permitsHistorySeed(
                identity,
                feedbackHistory: feedbackHistory,
                declarations: declarations
            )
        }

        for node in graph.nodes {
            guard node.effect == effect.key,
                  node.conditions == nil else {
                return .failure(.executionMismatch)
            }
            let composes: Bool
            switch node.compose {
            case nil, .some(.bool(false)): composes = false
            case .some(.bool(true)): composes = true
            default: return .failure(.executionMismatch)
            }
            if let previousNodeIndex, node.nodeIndex <= previousNodeIndex {
                return .failure(.invalidNodeOrder)
            }
            previousNodeIndex = node.nodeIndex

            switch node.kind {
            case .material:
                guard node.commandSource == nil,
                      node.commandTarget == nil,
                      let target = node.target else {
                    return .failure(.executionMismatch)
                }
                for binding in node.bindings {
                    guard binding.conditions == nil else {
                        return .failure(.executionMismatch)
                    }
                    switch binding.texture.kind {
                    case .framebuffer:
                        guard declarations[binding.texture] != nil else {
                            return .failure(.invalidAccess)
                        }
                        if firstWrites[binding.texture] == nil {
                            guard permitsFirstRead(binding.texture) else {
                                return .failure(.historyRequired)
                            }
                            historySeedTargets.insert(binding.texture)
                        }
                        firstReads[binding.texture] =
                            firstReads[binding.texture] ?? node.nodeIndex
                        lastReads[binding.texture] = node.nodeIndex
                    case .layerSource, .effectOutput:
                        guard binding.texture == effect.input else {
                            return .failure(.invalidAccess)
                        }
                    case .unresolved:
                        return .failure(.invalidAccess)
                    }
                }

                switch target.kind {
                case .framebuffer:
                    guard !composes, declarations[target] != nil else {
                        return .failure(.invalidAccess)
                    }
                    firstWrites[target] = firstWrites[target] ?? node.nodeIndex
                    lastWrites[target] = node.nodeIndex
                case .effectOutput:
                    guard target == effect.output else {
                        return .failure(.invalidAccess)
                    }
                    outputWriteCount += 1
                    outputComposeFlags.append(composes)
                case .layerSource, .unresolved:
                    return .failure(.invalidAccess)
                }
            case .copy, .swap:
                guard !composes,
                      node.target == nil,
                      node.bindings.isEmpty,
                      node.materialOrdinal == nil,
                      node.instancePassIndex == nil,
                      node.materialPath == nil,
                      node.materialPassID == nil,
                      let source = node.commandSource,
                      let target = node.commandTarget,
                      source != target,
                      declarations[source] != nil,
                      declarations[target] != nil else {
                    return .failure(.invalidAccess)
                }
                guard let sourceDescriptor = descriptors[source],
                      let targetDescriptor = descriptors[target],
                      sourceDescriptor.storageCompatible(with: targetDescriptor),
                      node.kind != .swap || sourceDescriptor == targetDescriptor else {
                    return .failure(.unsupportedTargetDescriptor)
                }
                if firstWrites[source] == nil {
                    guard permitsFirstRead(source) else {
                        return .failure(.historyRequired)
                    }
                    historySeedTargets.insert(source)
                }
                firstReads[source] = firstReads[source] ?? node.nodeIndex
                lastReads[source] = node.nodeIndex

                let commandKind: CommandKind
                if node.kind == .swap {
                    if firstWrites[target] == nil {
                        guard permitsFirstRead(target) else {
                            return .failure(.historyRequired)
                        }
                        historySeedTargets.insert(target)
                    }
                    firstReads[target] = firstReads[target] ?? node.nodeIndex
                    lastReads[target] = node.nodeIndex
                    firstWrites[source] = firstWrites[source] ?? node.nodeIndex
                    lastWrites[source] = node.nodeIndex
                    commandKind = .swap
                } else {
                    commandKind = .copy
                }
                firstWrites[target] = firstWrites[target] ?? node.nodeIndex
                lastWrites[target] = node.nodeIndex
                commands.append(.init(
                    nodeIndex: node.nodeIndex,
                    kind: commandKind,
                    source: source,
                    target: target
                ))
            case .unknownCommand:
                return .failure(.executionMismatch)
            }
        }

        guard outputWriteCount == outputComposeFlags.count,
              outputComposeFlags.last == false,
              outputComposeFlags.dropLast().allSatisfy({ $0 }) else {
            return .failure(.missingOutput)
        }
        var targets: [LogicalTarget] = []
        targets.reserveCapacity(graph.renderTargets.count)
        for target in graph.renderTargets {
            guard let firstWrite = firstWrites[target.texture],
                  let lastWrite = lastWrites[target.texture] else {
                return .failure(.unwrittenTarget)
            }
            guard let descriptor = descriptors[target.texture] else {
                return .failure(.unsupportedTargetDescriptor)
            }
            var lifetime = Lifetime(
                firstWriteNodeIndex: firstWrite,
                lastWriteNodeIndex: lastWrite,
                firstReadNodeIndex: firstReads[target.texture],
                lastReadNodeIndex: lastReads[target.texture]
            )
            lifetime.requiresHistorySeed = historySeedTargets.contains(target.texture)
            targets.append(.init(
                identity: target.texture,
                extent: descriptor.extent,
                format: descriptor.format,
                addressMode: descriptor.addressMode,
                isUnique: descriptor.isUnique,
                lifetime: lifetime,
                initialClear: descriptor.initialClear
            ))
        }

        return .success(Self(
            layerID: graph.layerID,
            input: effect.input,
            output: effect.output,
            inputRole: inputRole,
            inputExtent: PixelExtent(width: inputWidth, height: inputHeight),
            logicalTargets: targets,
            commands: commands
        ))
    }

    /// Shared two-target feedback primitive: one history-seeded target feeds
    /// a first state update, the second update writes back to the seed target,
    /// and one terminal material combines that state with the effect input.
    /// Names, paths and effect identities never participate in admission.
    static func boundedFeedbackHistoryProfile(
        in graph: Graph
    ) -> FeedbackHistoryProfile? {
        guard authoredTargetDescriptorsAreEquivalent(graph.renderTargets) else {
            return nil
        }
        var descriptors: [Graph.TextureIdentity: TargetDescriptor] = [:]
        for target in graph.renderTargets {
            guard let descriptor = targetDescriptor(
                target,
                inputWidth: 1,
                inputHeight: 1
            ), descriptors.updateValue(
                descriptor,
                forKey: target.texture
            ) == nil else { return nil }
        }
        return boundedFeedbackHistoryProfile(
            graph: graph,
            descriptors: descriptors
        )
    }

    private static func boundedFeedbackHistoryProfile(
        graph: Graph,
        descriptors: [Graph.TextureIdentity: TargetDescriptor]
    ) -> FeedbackHistoryProfile? {
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              graph.renderTargets.count == 2,
              graph.nodes.count == 3,
              let effect = graph.effects.first else { return nil }
        let targets = Set(graph.renderTargets.map(\.texture))
        guard let firstDescriptor = descriptors.values.first else { return nil }
        guard targets.count == 2,
              descriptors.count == 2,
              targets.allSatisfy({
                  $0.kind == .framebuffer
                      && $0.layerID == effect.key.layerID
                      && $0.effect == effect.key
              }),
              descriptors.values.allSatisfy({
                  $0.format == .rgba8888
                      && !$0.isUnique
                      && $0.initialClear == nil
                      && $0 == firstDescriptor
              }) else { return nil }
        let nodes = graph.nodes.sorted { $0.nodeIndex < $1.nodeIndex }
        guard nodes.allSatisfy({
            $0.kind == .material
                && $0.effect == effect.key
                && $0.conditions == nil
                && $0.commandSource == nil
                && $0.commandTarget == nil
                && ($0.compose == nil || $0.compose == .bool(false))
                && $0.bindings.allSatisfy({ $0.conditions == nil })
        }), let firstTarget = nodes[0].target,
          nodes[0].bindings.count == 1,
          let seedTarget = nodes[0].bindings.first?.texture,
          targets.contains(seedTarget),
          firstTarget != seedTarget,
          targets == Set([firstTarget, seedTarget]),
          nodes[1].target == seedTarget,
          nodes[1].bindings.count == 1,
          nodes[1].bindings.first?.texture == firstTarget,
          nodes[2].target == effect.output,
          nodes[2].bindings.count == 2,
          Set(nodes[2].bindings.map(\.texture))
              == Set([seedTarget, effect.input]) else { return nil }
        return .init(seedTargets: [seedTarget], stateTargets: targets)
    }

}
