import CoreGraphics
import Metal

extension SceneResolvedMaterialGraphExecutor {
    func prepare(
        stageIndex: Int,
        transition: State.Transition,
        graph: Graph,
        pairStep: Pair.EffectStep,
        stageCapability:
            SceneResolvedMaterialExecutionCapabilityCatalog.StageCapability,
        capability: SceneResolvedMaterialExecutionCapabilityCatalog.ChainCapability,
        lease: SceneGraphRenderTargetLease,
        frame: SceneResolvedMaterialFrameSnapshot,
        sourcePipeline: SceneImageLayerPipeline,
        time: Float,
        originalSourceTexture: MTLTexture?,
        dedicatedInputs: SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs,
        pair: inout PairAtom,
        publications: inout [Graph.TextureIdentity: SceneFrameTextureResource],
        commands: inout [Command],
        programKeys: inout [String]
    ) -> Failure? {
        if case let .dedicated(_, program, _) = stageCapability {
            let failure = prepareDedicated(
                program: program,
                transition: transition,
                graph: graph,
                pairStep: pairStep,
                lease: lease,
                sourcePipeline: sourcePipeline,
                time: time,
                originalSourceTexture: originalSourceTexture,
                inputs: dedicatedInputs,
                pair: &pair,
                publications: &publications,
                commands: &commands
            )
            if failure == nil {
                programKeys.append(
                    "dedicated:\(SceneShaderStableDigest.hash(program.stageGraph))"
                )
            }
            return failure
        }
        let nodes = Dictionary(uniqueKeysWithValues: graph.nodes.map {
            ($0.nodeIndex, $0)
        })
        let pairNodes = Dictionary(uniqueKeysWithValues: pairStep.nodes.map {
            ($0.nodeIndex, $0)
        })
        var visited = Set<Int>()

        for intent in transition.transaction.intents {
            switch intent {
            case let .initialize(identity, resource, reason):
                guard let target = lease.texturesByToken[resource.token],
                      let initialization = initialization(reason),
                      let prepared = resourceEncoder?.prepareInitialization(
                          target: target,
                          clear: initialization.clear
                      ), let publication = framebufferResource(
                          lease: lease,
                          identity: identity,
                          resource: resource,
                          representation: initialization.representation
                      ) else { return .resourceCommandRejected }
                commands.append(.resource(prepared))
                publications[identity] = publication

            case let .material(nodeIndex, ordinal, bindings, fboTarget):
                guard let node = nodes[nodeIndex],
                      let pairNode = pairNodes[nodeIndex],
                      visited.insert(nodeIndex).inserted,
                      node.kind == .material,
                      node.materialOrdinal == ordinal,
                      pairNode.kind == .material,
                      pairNode.currentMemberBeforeNode == pair.member,
                      validate(
                          bindings: bindings,
                          node: node,
                          pair: pair,
                          publications: publications
                      ), let target = materialTarget(
                          node: node,
                          pairNode: pairNode,
                          fboTarget: fboTarget,
                          pair: pair,
                          lease: lease
                      ), let material = capability.material(for: node) else {
                    return .graphStructureRejected
                }
                guard let overlaid = frame.overlayingGraphResources(publications) else {
                    return .graphPublicationRejected
                }
                let finalized = SceneResolvedMaterialProgramFinalizer.finalize(
                    overlaid.finalizationInput(
                        template: material.template,
                        renderSize: CGSize(width: target.width, height: target.height),
                        modelViewProjection: Self.fullTargetMVP(target),
                        effectTextureProjectionMatrixInverse:
                            dedicatedInputs.effectTextureProjectionMatrixInverse,
                        implicitFramebufferIdentity: pairStep.inputIdentity
                    ),
                    variantCache: material.variants
                )
                let program: SceneResolvedMaterialProgram
                switch finalized {
                case let .success(value):
                    program = value
                case let .failure(failure):
                    return .materialFinalizerRejected(
                        nodeIndex: nodeIndex,
                        materialOrdinal: ordinal,
                        failure: failure
                    )
                }
                let passPreparation = materialEncoder.prepareResult(
                    program: program,
                    target: target
                )
                guard case let .success(prepared) = passPreparation else {
                    guard case let .failure(failure) = passPreparation else {
                        return .materialPassEncoderRejected
                    }
                    return .materialPassPreparationRejected(
                        stageIndex: stageIndex,
                        nodeIndex: nodeIndex,
                        materialOrdinal: ordinal,
                        programKey: program.preparedShader.cacheKey,
                        failure: failure
                    )
                }
                commands.append(.material(prepared))
                programKeys.append(program.preparedShader.cacheKey)

                if let fboTarget {
                    guard node.target == fboTarget.identity,
                          pairNode.fullFrameWriteMember == nil else {
                        return .graphStructureRejected
                    }
                    guard let publication = framebufferResource(
                        lease: lease,
                        identity: fboTarget.identity,
                        resource: fboTarget.resource,
                        representation: prepared.fragmentOutput
                    ) else { return .graphPublicationRejected }
                    publications[fboTarget.identity] = publication
                } else {
                    guard let identity = node.target,
                          identity == pairStep.outputIdentity,
                          let member = pairNode.fullFrameWriteMember else {
                        return .graphStructureRejected
                    }
                    guard let generation = nextPairGeneration() else {
                        return .contentGenerationOverflow
                    }
                    guard let publication = pairResource(
                        lease: lease,
                        identity: identity,
                        member: member,
                        generation: generation,
                        representation: prepared.fragmentOutput
                    ) else { return .graphPublicationRejected }
                    publications[identity] = publication
                    if pairNode.rotatesAfterNode {
                        guard member == pairNode.currentMemberAfterNode else {
                            return .graphStructureRejected
                        }
                        guard let input = pairResource(
                            lease: lease,
                            identity: pairStep.inputIdentity,
                            member: member,
                            generation: generation,
                            representation: prepared.fragmentOutput
                        ) else { return .graphPublicationRejected }
                        publications[pairStep.inputIdentity] = input
                        pair = .init(
                            member: member,
                            resource: input,
                            representation: prepared.fragmentOutput
                        )
                    }
                }

            case let .copy(
                nodeIndex, ordinal, source, sourceResource, target, targetResource
            ):
                guard validateCommand(
                    nodeIndex: nodeIndex,
                    ordinal: ordinal,
                    kind: .copy,
                    source: source,
                    sourceResource: sourceResource,
                    target: target,
                    targetResource: targetResource,
                    nodes: nodes,
                    pairNodes: pairNodes,
                    visited: &visited,
                    publications: publications
                ), let sourcePublication = publications[source],
                      let representation = representation(sourcePublication),
                      let sourceTexture = lease.texturesByToken[sourceResource.token],
                      let targetTexture = lease.texturesByToken[targetResource.token],
                      let prepared = resourceEncoder?.prepareCopy(
                          source: sourceTexture,
                          target: targetTexture
                      ), let publication = framebufferResource(
                          lease: lease,
                          identity: target,
                          resource: targetResource,
                          representation: representation
                      ) else { return .resourceCommandRejected }
                commands.append(.resource(prepared))
                publications[target] = publication

            case let .swap(
                nodeIndex, ordinal, source, sourceResource, target, targetResource
            ):
                guard validateCommand(
                    nodeIndex: nodeIndex,
                    ordinal: ordinal,
                    kind: .swap,
                    source: source,
                    sourceResource: sourceResource,
                    target: target,
                    targetResource: targetResource,
                    nodes: nodes,
                    pairNodes: pairNodes,
                    visited: &visited,
                    publications: publications
                ), let sourcePublication = publications[source],
                      let targetPublication = publications[target],
                      let newSource = targetPublication.rewrappedForGraphIdentity(source),
                      let newTarget = sourcePublication.rewrappedForGraphIdentity(target)
                else { return .resourceCommandRejected }
                publications[source] = newSource
                publications[target] = newTarget
            }
        }

        guard visited == Set(graph.nodes.map(\.nodeIndex)),
              programKeys.count == graph.nodes.filter({ $0.kind == .material }).count
        else { return .graphStructureRejected }
        guard let final = publications[pairStep.outputIdentity],
              let representation = representation(final),
              final.publication.texture === pairTexture(
                  lease: lease,
                  member: pairStep.outputMember
              ) else { return .graphPublicationRejected }
        pair = .init(
            member: pairStep.outputMember,
            resource: final,
            representation: representation
        )
        return nil
    }

    private func validate(
        bindings: [State.MaterialBinding],
        node: Graph.Node,
        pair: PairAtom,
        publications: [Graph.TextureIdentity: SceneFrameTextureResource]
    ) -> Bool {
        let expected = node.bindings.filter { $0.texture.kind == .framebuffer }
            .sorted { ($0.slot ?? Int.max) < ($1.slot ?? Int.max) }
        guard expected.count == bindings.count else { return false }
        for (authored, reduced) in zip(expected, bindings) {
            guard authored.slot == reduced.slot,
                  authored.texture == reduced.identity,
                  publication(
                      publications[reduced.identity],
                      matches: reduced.resource,
                      identity: reduced.identity
                  ) else { return false }
        }
        return node.bindings.allSatisfy { binding in
            switch binding.texture.kind {
            case .framebuffer:
                return true
            case .layerSource, .effectOutput:
                guard let resource = publications[binding.texture] else { return false }
                return resource.resourceGeneration == pair.resource.resourceGeneration
                    && resource.publication.texture
                        === pair.resource.publication.texture
            case .unresolved:
                return false
            }
        }
    }

    private func materialTarget(
        node: Graph.Node,
        pairNode: Pair.NodeStep,
        fboTarget: State.MaterialTarget?,
        pair: PairAtom,
        lease: SceneGraphRenderTargetLease
    ) -> MTLTexture? {
        if let fboTarget {
            guard node.target == fboTarget.identity,
                  pairNode.fullFrameWriteMember == nil else { return nil }
            return lease.texturesByToken[fboTarget.resource.token]
        }
        guard node.target?.kind == .effectOutput,
              let member = pairNode.fullFrameWriteMember,
              member == pair.member.opposite else { return nil }
        return pairTexture(lease: lease, member: member)
    }

    private func validateCommand(
        nodeIndex: Int,
        ordinal: Int,
        kind: Graph.NodeKind,
        source: Graph.TextureIdentity,
        sourceResource: State.VersionedResource,
        target: Graph.TextureIdentity,
        targetResource: State.VersionedResource,
        nodes: [Int: Graph.Node],
        pairNodes: [Int: Pair.NodeStep],
        visited: inout Set<Int>,
        publications: [Graph.TextureIdentity: SceneFrameTextureResource]
    ) -> Bool {
        guard let node = nodes[nodeIndex], let pairNode = pairNodes[nodeIndex],
              visited.insert(nodeIndex).inserted,
              node.kind == kind,
              node.commandSource == source,
              node.commandTarget == target,
              pairNode.kind == (kind == .copy ? .copy : .swap),
              !pairNode.rotatesAfterNode,
              pairNode.fullFrameReadMember == nil,
              pairNode.fullFrameWriteMember == nil,
              publication(
                  publications[source], matches: sourceResource, identity: source
              ) else { return false }
        if kind == .swap {
            guard publication(
                publications[target], matches: targetResource, identity: target
            ) else { return false }
        } else {
            guard targetResource.contentGeneration > 0 else { return false }
        }
        let commandsBefore = nodes.values.filter {
            $0.nodeIndex < nodeIndex && ($0.kind == .copy || $0.kind == .swap)
        }.count
        return ordinal == commandsBefore
    }

    func framebufferResource(
        lease: SceneGraphRenderTargetLease,
        identity: Graph.TextureIdentity,
        resource: State.VersionedResource,
        representation: SceneShaderColorRepresentation
    ) -> SceneFrameTextureResource? {
        guard case let .success(publication) = lease.graphResource(
            for: identity,
            versionedResource: resource,
            fragmentColorRepresentation: .resolved(representation)
        ) else { return nil }
        return publication
    }

    private func publication(
        _ publication: SceneFrameTextureResource?,
        matches resource: State.VersionedResource,
        identity: Graph.TextureIdentity
    ) -> Bool {
        guard let publication,
              publication.publication.requestIdentity == .graph(identity),
              publication.resourceGeneration == resource.contentGeneration,
              case let .provider(.graph(_, token)) =
                publication.publication.candidate.identity else { return false }
        return token == resource.token.rawValue
    }
}
