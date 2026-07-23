import Foundation

nonisolated struct SceneGraphRenderTargetPlan: Equatable {
    typealias Graph = SceneAuthoredEffectRenderPlan

    enum TextureFormat: String {
        case rgbaBackbuffer
    }

    struct PixelExtent: Equatable {
        let width: Int
        let height: Int
    }

    struct Lifetime: Equatable {
        let firstWriteNodeIndex: Int
        let lastWriteNodeIndex: Int
        let firstReadNodeIndex: Int?
        let lastReadNodeIndex: Int?
    }

    struct LogicalTarget: Equatable {
        let identity: Graph.TextureIdentity
        let extent: PixelExtent
        let format: TextureFormat
        let lifetime: Lifetime
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
    let inputExtent: PixelExtent
    let logicalTargets: [LogicalTarget]

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
              validInput(effect.input, layerID: graph.layerID),
              validOutput(effect.output, effect: effect.key, layerID: graph.layerID) else {
            return .failure(.incompleteIdentity)
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
        var outputWriteCount = 0
        var previousNodeIndex: Int?

        for node in graph.nodes {
            guard node.effect == effect.key,
                  node.kind == .material,
                  node.compose == nil,
                  node.conditions == nil,
                  node.commandSource == nil,
                  node.commandTarget == nil,
                  let target = node.target else {
                return .failure(.executionMismatch)
            }
            if let previousNodeIndex, node.nodeIndex <= previousNodeIndex {
                return .failure(.invalidNodeOrder)
            }
            previousNodeIndex = node.nodeIndex

            for binding in node.bindings {
                guard binding.conditions == nil else { return .failure(.executionMismatch) }
                switch binding.texture.kind {
                case .framebuffer:
                    guard declarations[binding.texture] != nil else {
                        return .failure(.invalidAccess)
                    }
                    guard firstWrites[binding.texture] != nil else {
                        return .failure(.historyRequired)
                    }
                    firstReads[binding.texture] = firstReads[binding.texture] ?? node.nodeIndex
                    lastReads[binding.texture] = node.nodeIndex
                case .layerSource:
                    guard binding.texture == effect.input else {
                        return .failure(.invalidAccess)
                    }
                case .effectOutput, .unresolved:
                    return .failure(.invalidAccess)
                }
            }

            switch target.kind {
            case .framebuffer:
                guard declarations[target] != nil else { return .failure(.invalidAccess) }
                firstWrites[target] = firstWrites[target] ?? node.nodeIndex
                lastWrites[target] = node.nodeIndex
            case .effectOutput:
                guard target == effect.output else { return .failure(.invalidAccess) }
                outputWriteCount += 1
            case .layerSource, .unresolved:
                return .failure(.invalidAccess)
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
            guard let extent = pixelExtent(
                target.extent,
                inputWidth: inputWidth,
                inputHeight: inputHeight
            ), target.format?.lowercased() == "rgba_backbuffer",
            !target.declaredUnique,
            target.clear == nil,
            target.uvs == nil,
            target.conditions == nil else {
                return .failure(.unsupportedTargetDescriptor)
            }
            targets.append(LogicalTarget(
                identity: target.texture,
                extent: extent,
                format: .rgbaBackbuffer,
                lifetime: Lifetime(
                    firstWriteNodeIndex: firstWrite,
                    lastWriteNodeIndex: lastWrite,
                    firstReadNodeIndex: firstReads[target.texture],
                    lastReadNodeIndex: lastReads[target.texture]
                )
            ))
        }

        return .success(Self(
            layerID: graph.layerID,
            input: effect.input,
            output: effect.output,
            inputExtent: PixelExtent(width: inputWidth, height: inputHeight),
            logicalTargets: targets
        ))
    }

    private static func pixelExtent(
        _ authored: Graph.TargetExtent,
        inputWidth: Int,
        inputHeight: Int
    ) -> PixelExtent? {
        switch authored.kind {
        case .input:
            guard authored.first == nil, authored.second == nil else { return nil }
            return PixelExtent(width: inputWidth, height: inputHeight)
        case .scale:
            guard let scale = authored.first,
                  scale.isFinite,
                  scale >= 1,
                  authored.second == nil else {
                return nil
            }
            return PixelExtent(
                width: max(1, Int((Double(inputWidth) / scale).rounded(.down))),
                height: max(1, Int((Double(inputHeight) / scale).rounded(.down)))
            )
        case .fit, .absolute, .unsupported:
            return nil
        }
    }

    private static func validEffectKey(_ key: Graph.EffectKey, layerID: Int) -> Bool {
        key.layerID == layerID && key.effectIndex >= 0 && !key.descriptorID.isEmpty
    }

    private static func validInput(_ identity: Graph.TextureIdentity, layerID: Int) -> Bool {
        identity.kind == .layerSource
            && identity.layerID == layerID
            && identity.effect == nil
            && identity.name == nil
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
