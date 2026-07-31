import Foundation

nonisolated struct SceneGraphRenderTargetPlan: Equatable {
    typealias Graph = SceneAuthoredEffectRenderPlan

    enum TextureFormat: String {
        case rgbaBackbuffer
        case rgba8888
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
        let lifetime: Lifetime
        let initialClear: ClearColor?
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

    init(
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

    static func make(
        executionPlan: SceneAuthoredEffectExecutionPlan,
        graph: Graph,
        inputWidth: Int,
        inputHeight: Int
    ) -> Result<Self, Failure> {
        guard inputWidth > 0, inputHeight > 0 else {
            return .failure(.invalidInputExtent)
        }
        let materialNodeCount = graph.nodes.filter { $0.kind == .material }.count
        guard executionPlan.layerID == graph.layerID,
              graph.blockers.isEmpty,
              graph.effects.count == 1,
              executionPlan.materialNodeCount == materialNodeCount,
              executionPlan.logicalRenderTargetCount == graph.renderTargets.count,
              let effect = graph.effects.first,
              effect.nodeIndices == graph.nodes.map(\.nodeIndex),
              graph.finalOutput == effect.output else {
            return .failure(.executionMismatch)
        }
        guard validEffectKey(effect.key, layerID: graph.layerID),
              let inputRole = SceneAuthoredEffectInputValidator.role(
                for: effect.input,
                layerID: graph.layerID
              ),
              validOutput(effect.output, effect: effect.key, layerID: graph.layerID) else {
            return .failure(.incompleteIdentity)
        }
        guard inputRole == executionPlan.inputRole else {
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

        var firstReads: [Graph.TextureIdentity: Int] = [:]
        var lastReads: [Graph.TextureIdentity: Int] = [:]
        var firstWrites: [Graph.TextureIdentity: Int] = [:]
        var lastWrites: [Graph.TextureIdentity: Int] = [:]
        var historySeedTargets = Set<Graph.TextureIdentity>()
        var outputWriteCount = 0
        var previousNodeIndex: Int?
        var commands: [Command] = []

        for node in graph.nodes {
            guard node.effect == effect.key,
                  node.compose == nil,
                  node.conditions == nil else {
                return .failure(.executionMismatch)
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
                            guard permitsHistorySeed(
                                binding.texture,
                                executionPlan: executionPlan,
                                declarations: declarations
                            ) else {
                                return .failure(.historyRequired)
                            }
                            historySeedTargets.insert(binding.texture)
                        }
                        guard permitsHistorySeed(
                            binding.texture,
                            executionPlan: executionPlan,
                            declarations: declarations
                        ) || firstWrites[binding.texture] != nil else {
                            return .failure(.historyRequired)
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
                    guard declarations[target] != nil else {
                        return .failure(.invalidAccess)
                    }
                    firstWrites[target] = firstWrites[target] ?? node.nodeIndex
                    lastWrites[target] = node.nodeIndex
                case .effectOutput:
                    guard target == effect.output else {
                        return .failure(.invalidAccess)
                    }
                    outputWriteCount += 1
                case .layerSource, .unresolved:
                    return .failure(.invalidAccess)
                }
            case .copy, .swap:
                guard node.target == nil,
                      node.bindings.isEmpty,
                      node.materialOrdinal == nil,
                      node.instancePassIndex == nil,
                      node.materialPath == nil,
                      node.materialPassID == nil,
                      let source = node.commandSource,
                      let target = node.commandTarget,
                      source != target,
                      let sourceDeclaration = declarations[source],
                      let targetDeclaration = declarations[target] else {
                    return .failure(.invalidAccess)
                }
                guard let sourceDescriptor = targetDescriptor(
                    sourceDeclaration,
                    inputWidth: inputWidth,
                    inputHeight: inputHeight
                ), let targetDescriptor = targetDescriptor(
                    targetDeclaration,
                    inputWidth: inputWidth,
                    inputHeight: inputHeight
                ), sourceDescriptor == targetDescriptor else {
                    return .failure(.unsupportedTargetDescriptor)
                }
                if firstWrites[source] == nil {
                    guard declarations[source]?.declaredUnique == true else {
                        return .failure(.historyRequired)
                    }
                    historySeedTargets.insert(source)
                }
                guard declarations[source]?.declaredUnique == true
                    || firstWrites[source] != nil else {
                    return .failure(.historyRequired)
                }
                firstReads[source] = firstReads[source] ?? node.nodeIndex
                lastReads[source] = node.nodeIndex

                let commandKind: CommandKind
                if node.kind == .swap {
                    if firstWrites[target] == nil {
                        guard declarations[target]?.declaredUnique == true else {
                            return .failure(.historyRequired)
                        }
                        historySeedTargets.insert(target)
                    }
                    guard declarations[target]?.declaredUnique == true
                        || firstWrites[target] != nil else {
                        return .failure(.historyRequired)
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

        guard outputWriteCount == 1 else { return .failure(.missingOutput) }
        var targets: [LogicalTarget] = []
        targets.reserveCapacity(graph.renderTargets.count)
        for target in graph.renderTargets {
            guard let firstWrite = firstWrites[target.texture],
                  let lastWrite = lastWrites[target.texture] else {
                return .failure(.unwrittenTarget)
            }
            guard let descriptor = targetDescriptor(
                target,
                inputWidth: inputWidth,
                inputHeight: inputHeight
            ) else {
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

    private struct TargetDescriptor: Equatable {
        let extent: PixelExtent
        let format: TextureFormat
        let initialClear: ClearColor?
    }

    private static func targetDescriptor(
        _ target: Graph.RenderTarget,
        inputWidth: Int,
        inputHeight: Int
    ) -> TargetDescriptor? {
        guard let extent = pixelExtent(
            target.extent,
            inputWidth: inputWidth,
            inputHeight: inputHeight
        ), let format = textureFormat(target.format),
              target.uvs == nil,
              target.conditions == nil else {
            return nil
        }
        let initialClear: ClearColor?
        if let authoredClear = target.clear {
            guard let zeroClear = zeroClear(authoredClear) else { return nil }
            initialClear = zeroClear
        } else {
            initialClear = nil
        }
        return TargetDescriptor(
            extent: extent,
            format: format,
            initialClear: initialClear
        )
    }

    private static func textureFormat(_ authored: String?) -> TextureFormat? {
        switch authored?.lowercased() {
        case "rgba_backbuffer":
            return .rgbaBackbuffer
        case "rgba8888":
            return .rgba8888
        default:
            return nil
        }
    }

    private static func validEffectKey(_ key: Graph.EffectKey, layerID: Int) -> Bool {
        key.layerID == layerID && key.effectIndex >= 0 && !key.descriptorID.isEmpty
    }

    private static func validOutput(
        _ identity: Graph.TextureIdentity,
        effect: Graph.EffectKey,
        layerID: Int
    ) -> Bool {
        identity.kind == .effectOutput
            && identity.layerID == layerID
            && identity.effect == effect
            && identity.name == nil
    }

    private static func validTargetIdentity(
        _ identity: Graph.TextureIdentity,
        effect: Graph.EffectKey,
        layerID: Int
    ) -> Bool {
        identity.kind == .framebuffer
            && identity.layerID == layerID
            && identity.effect == effect
            && identity.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}
