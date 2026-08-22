import Foundation

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    struct PreservedChannelGraphRejection {
        let target: Graph.TextureIdentity
        let reasonCode: String
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
                return rejection(for: target)
            }
            if admittedPairMembers.contains(target.identity) {
                continue
            }
            let commands = graph.nodes.filter {
                $0.commandSource == target.identity
                    || $0.commandTarget == target.identity
            }
            if commands.isEmpty {
                guard ordinaryTargetIsExecutable(
                    target,
                    graph: graph,
                    materials: materials
                ) else { return rejection(for: target) }
                continue
            }
            guard let command = commands.only,
                  command.kind == .swap,
                  let otherIdentity = command.commandSource == target.identity
                    ? command.commandTarget : command.commandSource,
                  let other = byIdentity[otherIdentity]?.only,
                  feedbackPairIsExecutable(
                      target,
                      other,
                      swap: command,
                      graph: graph,
                      materials: materials
                  ) else { return rejection(for: target) }
            admittedPairMembers.insert(target.identity)
            admittedPairMembers.insert(other.identity)
        }
        return nil
    }

    private static func ordinaryTargetIsExecutable(
        _ target: PreservedChannelTarget,
        graph: Graph,
        materials: [MaterialKey: MaterialCapability]
    ) -> Bool {
        let writers = materialWriters(of: target.identity, in: graph)
        let readers = materialReaders(of: target.identity, in: graph)
        guard let writer = writers.only,
              writerStores(target, node: writer, materials: materials),
              !readers.isEmpty,
              (!target.descriptor.isUnique || readers.contains {
                  $0.nodeIndex < writer.nodeIndex
              }),
              readers.allSatisfy({ reader in
                  reader.nodeIndex != writer.nodeIndex
                      && (reader.nodeIndex > writer.nodeIndex
                      || target.descriptor.initialClear != nil
                      || target.descriptor.isUnique)
                      && readerUsesExactChannels(
                          reader,
                          target: target,
                          materials: materials
                      )
              }),
              graph.nodes.allSatisfy({
                  $0.commandSource != target.identity
                      && $0.commandTarget != target.identity
              }) else { return false }
        return true
    }

    private static func feedbackPairIsExecutable(
        _ first: PreservedChannelTarget,
        _ second: PreservedChannelTarget,
        swap: Graph.Node,
        graph: Graph,
        materials: [MaterialKey: MaterialCapability]
    ) -> Bool {
        let identities: Set<Graph.TextureIdentity> = [
            first.identity, second.identity,
        ]
        let pairCommands = graph.nodes.filter { node in
            node.commandSource.map(identities.contains) == true
                || node.commandTarget.map(identities.contains) == true
        }
        guard first.identity != second.identity,
              first.descriptor.isUnique,
              second.descriptor.isUnique,
              first.descriptor.initialClear != nil,
              second.descriptor.initialClear != nil,
              SceneGraphRenderTargetPlan.authoredTargetDescriptorsAreEquivalent([
                  first.declaration, second.declaration,
              ]),
              pairCommands.only?.nodeIndex == swap.nodeIndex,
              swap.commandSource.map(identities.contains) == true,
              swap.commandTarget.map(identities.contains) == true else {
            return false
        }

        var hasReadBeforeFirstWrite = false
        for target in [first, second] {
            let writers = materialWriters(of: target.identity, in: graph)
            let readers = materialReaders(of: target.identity, in: graph)
            guard let firstWriter = writers.first,
                  !writers.isEmpty,
                  !readers.isEmpty,
                  writers.allSatisfy({
                      $0.nodeIndex < swap.nodeIndex
                          && writerStores(target, node: $0, materials: materials)
                  }),
                  readers.allSatisfy({ reader in
                      reader.nodeIndex < swap.nodeIndex
                          && !writers.contains {
                              $0.nodeIndex == reader.nodeIndex
                          }
                          && readerUsesExactChannels(
                              reader,
                              target: target,
                              materials: materials
                          )
                  }) else { return false }
            hasReadBeforeFirstWrite = hasReadBeforeFirstWrite || readers.contains {
                $0.nodeIndex < firstWriter.nodeIndex
            }
        }
        return hasReadBeforeFirstWrite
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
                return material.variants.provesRedGreenOnlyConsumer(slot: slot)
            case .rgbaBackbuffer, .rgba8888:
                return false
            }
        }
    }

    private static func rejection(
        for target: PreservedChannelTarget
    ) -> PreservedChannelGraphRejection {
        .init(target: target.identity, reasonCode: target.reasonCode)
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
