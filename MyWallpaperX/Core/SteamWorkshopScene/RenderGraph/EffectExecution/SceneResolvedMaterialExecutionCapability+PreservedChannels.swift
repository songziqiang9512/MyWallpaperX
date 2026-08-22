import Foundation

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    struct PreservedChannelGraphRejection {
        let target: Graph.TextureIdentity
        let reasonCode: String
        let detailCode: String

        var reportLine: String {
            "MWX preserved-channel graph rejection:"
                + " schema=preserved-channel-target-attribution-v1"
                + " layer=\(target.layerID)"
                + " effect=\(target.effect?.effectIndex ?? -1)"
                + " descriptor=\(token(target.effect?.descriptorID ?? "-"))"
                + " kind=\(target.kind.rawValue)"
                + " target=\(token(target.name ?? "-"))"
                + " reason=\(reasonCode) detail=\(detailCode)"
        }

        private func token(_ value: String) -> String {
            let allowed = CharacterSet.alphanumerics.union(
                CharacterSet(charactersIn: "-._~/")
            )
            return value.addingPercentEncoding(
                withAllowedCharacters: allowed
            ) ?? "<invalid>"
        }
    }

    /// Preserved-channel targets become product capability only as complete
    /// producer -> typed publication -> exact-channel consumer atoms. The
    /// ordinary atom keeps one writer. The feedback-pair atom additionally
    /// admits one same-descriptor terminal swap while graph state remains the
    /// sole owner of history, permutation, rehydration, reset and rollback.
    static func preservedChannelGraphRejection(
        _ graph: Graph,
        materials: [MaterialKey: MaterialCapability]
    ) -> PreservedChannelGraphRejection? {
        let targets = graph.renderTargets.compactMap {
            PreservedChannelTarget($0)
        }
        guard !targets.isEmpty else { return nil }

        let byIdentity = Dictionary(grouping: targets, by: \.identity)
        var admittedPairMembers = Set<Graph.TextureIdentity>()
        for target in targets {
            guard byIdentity[target.identity]?.count == 1 else {
                return rejection(
                    for: target,
                    detailCode: "duplicate-target-declaration"
                )
            }
            if admittedPairMembers.contains(target.identity) {
                continue
            }
            let commands = graph.nodes.filter {
                $0.commandSource == target.identity
                    || $0.commandTarget == target.identity
            }
            if commands.isEmpty {
                if let detailCode = ordinaryTargetRejection(
                    target,
                    graph: graph,
                    materials: materials
                ) {
                    return rejection(for: target, detailCode: detailCode)
                }
                continue
            }
            guard let command = commands.only else {
                return rejection(for: target, detailCode: "command-count")
            }
            guard command.kind == .swap else {
                return rejection(for: target, detailCode: "command-kind")
            }
            guard let otherIdentity = command.commandSource == target.identity
                    ? command.commandTarget : command.commandSource,
                  let other = byIdentity[otherIdentity]?.only else {
                return rejection(for: target, detailCode: "pair-member")
            }
            if let detailCode = feedbackPairRejection(
                target,
                other,
                swap: command,
                graph: graph,
                materials: materials
            ) {
                return rejection(for: target, detailCode: detailCode)
            }
            admittedPairMembers.insert(target.identity)
            admittedPairMembers.insert(other.identity)
        }
        return nil
    }

    private static func ordinaryTargetRejection(
        _ target: PreservedChannelTarget,
        graph: Graph,
        materials: [MaterialKey: MaterialCapability]
    ) -> String? {
        let writers = materialWriters(of: target.identity, in: graph)
        let readers = materialReaders(of: target.identity, in: graph)
        guard let writer = writers.only else { return "writer-count" }
        guard writerStores(target, node: writer, materials: materials) else {
            return "writer-storage"
        }
        guard !readers.isEmpty else { return "reader-count" }
        guard !target.descriptor.isUnique || readers.contains(where: {
            $0.nodeIndex < writer.nodeIndex
        }) else { return "unique-read-before-write" }
        for reader in readers {
            guard reader.nodeIndex != writer.nodeIndex else {
                return "same-node-read-write"
            }
            guard reader.nodeIndex > writer.nodeIndex
                    || target.descriptor.initialClear != nil
                    || target.descriptor.isUnique else {
                return "reader-order"
            }
            guard readerUsesExactChannels(
                reader,
                target: target,
                materials: materials
            ) else { return "reader-channel" }
        }
        guard graph.nodes.allSatisfy({
            $0.commandSource != target.identity
                && $0.commandTarget != target.identity
        }) else { return "command" }
        return nil
    }

    private static func feedbackPairRejection(
        _ first: PreservedChannelTarget,
        _ second: PreservedChannelTarget,
        swap: Graph.Node,
        graph: Graph,
        materials: [MaterialKey: MaterialCapability]
    ) -> String? {
        let identities: Set<Graph.TextureIdentity> = [
            first.identity, second.identity,
        ]
        let pairCommands = graph.nodes.filter { node in
            node.commandSource.map(identities.contains) == true
                || node.commandTarget.map(identities.contains) == true
        }
        guard first.identity != second.identity else { return "same-identity" }
        guard first.descriptor.isUnique, second.descriptor.isUnique else {
            return "pair-unique"
        }
        guard first.descriptor.initialClear != nil,
              second.descriptor.initialClear != nil else { return "pair-clear" }
        guard SceneGraphRenderTargetPlan.authoredTargetDescriptorsAreEquivalent([
            first.declaration, second.declaration,
        ]) else { return "pair-descriptor" }
        guard pairCommands.only?.nodeIndex == swap.nodeIndex else {
            return "pair-command-count"
        }
        guard swap.commandSource.map(identities.contains) == true,
              swap.commandTarget.map(identities.contains) == true else {
            return "pair-command-members"
        }

        var hasReadBeforeFirstWrite = false
        for target in [first, second] {
            let writers = materialWriters(of: target.identity, in: graph)
            let readers = materialReaders(of: target.identity, in: graph)
            guard let firstWriter = writers.first else { return "pair-writer-count" }
            guard !readers.isEmpty else { return "pair-reader-count" }
            for writer in writers {
                guard writer.nodeIndex < swap.nodeIndex else {
                    return "pair-writer-after-swap"
                }
                guard writerStores(target, node: writer, materials: materials) else {
                    return "pair-writer-storage"
                }
            }
            for reader in readers {
                guard reader.nodeIndex < swap.nodeIndex else {
                    return "pair-reader-after-swap"
                }
                guard !writers.contains(where: {
                    $0.nodeIndex == reader.nodeIndex
                }) else { return "pair-same-node-read-write" }
                guard readerUsesExactChannels(
                    reader,
                    target: target,
                    materials: materials
                ) else { return "pair-reader-channel" }
            }
            hasReadBeforeFirstWrite = hasReadBeforeFirstWrite || readers.contains {
                $0.nodeIndex < firstWriter.nodeIndex
            }
        }
        return hasReadBeforeFirstWrite ? nil : "pair-read-before-write"
    }

    private static func materialWriters(
        of identity: Graph.TextureIdentity,
        in graph: Graph
    ) -> [Graph.Node] {
        graph.nodes.filter {
            $0.kind == .material && $0.target == identity
        }
    }

    private static func materialReaders(
        of identity: Graph.TextureIdentity,
        in graph: Graph
    ) -> [Graph.Node] {
        graph.nodes.filter { node in
            node.kind == .material
                && node.bindings.contains { $0.texture == identity }
        }
    }

    private static func writerStores(
        _ target: PreservedChannelTarget,
        node: Graph.Node,
        materials: [MaterialKey: MaterialCapability]
    ) -> Bool {
        return materials[.init(
            effect: node.effect,
            nodeIndex: node.nodeIndex
        )]?.attachmentStorage == target.expectedStorage
    }

    private static func readerUsesExactChannels(
        _ reader: Graph.Node,
        target: PreservedChannelTarget,
        materials: [MaterialKey: MaterialCapability]
    ) -> Bool {
        let bindings = reader.bindings.filter {
            $0.texture == target.identity
        }
        guard !bindings.isEmpty,
              let material = materials[.init(
                  effect: reader.effect,
                  nodeIndex: reader.nodeIndex
              )] else { return false }
        return bindings.allSatisfy { binding in
            guard let slot = binding.slot else { return false }
            switch target.descriptor.format {
            case .r8, .r16f:
                return material.variants.provesRedOnlyConsumer(slot: slot)
            case .rg88, .rg1616f:
                return material.variants.provesRedGreenConsumer(slot: slot)
            case .rgbaBackbuffer, .rgba8888:
                return false
            }
        }
    }

    private static func rejection(
        for target: PreservedChannelTarget,
        detailCode: String
    ) -> PreservedChannelGraphRejection {
        .init(
            target: target.identity,
            reasonCode: target.reasonCode,
            detailCode: detailCode
        )
    }
}

private struct PreservedChannelTarget {
    typealias Graph = SceneAuthoredEffectRenderPlan

    let declaration: Graph.RenderTarget
    let descriptor: SceneGraphRenderTargetPlan.TargetDescriptor
    let expectedStorage: SceneResolvedMaterialAttachmentKind
    let reasonCode: String

    var identity: Graph.TextureIdentity { declaration.texture }

    init?(_ declaration: Graph.RenderTarget) {
        guard let descriptor = SceneGraphRenderTargetPlan.targetDescriptor(
            declaration,
            inputWidth: 1,
            inputHeight: 1
        ) else { return nil }
        let expectedStorage: SceneResolvedMaterialAttachmentKind
        let reasonCode: String
        switch descriptor.format {
        case .r8:
            expectedStorage = .scalarRedUnorm
            reasonCode = "r8-scalar-graph-unproven"
        case .rg88:
            expectedStorage = .redGreenUnorm
            reasonCode = "rg88-red-green-graph-unproven"
        case .r16f:
            expectedStorage = .scalarRedFloat16
            reasonCode = "r16f-scalar-graph-unproven"
        case .rg1616f:
            expectedStorage = .redGreenFloat16
            reasonCode = "rg1616f-red-green-graph-unproven"
        case .rgbaBackbuffer, .rgba8888:
            return nil
        }
        self.declaration = declaration
        self.descriptor = descriptor
        self.expectedStorage = expectedStorage
        self.reasonCode = reasonCode
    }
}

private extension Array {
    var only: Element? { count == 1 ? self[0] : nil }
}
