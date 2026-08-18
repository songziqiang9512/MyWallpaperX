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
        capability: SceneResolvedMaterialExecutionCapabilityCatalog.LayerCapability,
        lease: SceneGraphRenderTargetLease,
        frame: SceneResolvedMaterialFrameSnapshot,
        sourcePipeline: SceneImageLayerPipeline,
        time: Float,
        originalSourceTexture: MTLTexture?,
        dedicatedInputs: SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs,
        pair: inout PairAtom,
        publications: inout [Graph.TextureIdentity: SceneFrameTextureResource],
        commands: inout [Command],
        programKeys: inout [String],
        effectLocalFailureReasonCode: inout String?
    ) -> Failure? {
        let visualFailureSnapshot = VisualFailureSnapshot(
            pair: pair,
            publications: publications,
            commandCount: commands.count,
            programKeyCount: programKeys.count
        )
        if case let .visualFailurePassthrough(_, reasonCode) = stageCapability {
            return prepareVisualFailurePassthrough(
                reasonCode: reasonCode,
                transition: transition,
                graph: graph,
                pairStep: pairStep,
                lease: lease,
                snapshot: visualFailureSnapshot,
                pair: &pair,
                publications: &publications,
                commands: &commands,
                programKeys: &programKeys,
                effectLocalFailureReasonCode: &effectLocalFailureReasonCode
            )
        }
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
        let dependencyFrame: SceneResolvedMaterialFrameSnapshot
        if let dependency = dedicatedInputs.dependencyEffect {
            guard dependency.frameEpoch > 0,
                  let resource = dependency.reservedMaterialResource,
                  let replacement = frameTextureSnapshot(
                    frame,
                    overlaying: dependency.namedReference,
                    resource: resource,
                    frameEpoch: dependency.frameEpoch
                  ) else { return .graphPublicationRejected }
            dependencyFrame = replacement
        } else {
            dependencyFrame = frame
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
                          content: resource.descriptor.format == .r8
                              ? .scalarRedUnorm
                              : .color(.resolved(initialization.representation))
                      ) else { return .resourceCommandRejected }
                if case let .materialFunctionClear(
                    _, invocationOrdinal, targetOrdinal
                ) = reason {
                    commands.append(.functionClear(
                        prepared,
                        invocationOrdinal: invocationOrdinal,
                        targetOrdinal: targetOrdinal
                    ))
                } else {
                    commands.append(.resource(prepared))
                }
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
                guard let overlaid = dependencyFrame.overlayingGraphResources(
                    publications
                ) else {
                    return .graphPublicationRejected
                }
                let finalized = SceneResolvedMaterialProgramFinalizer.finalize(
                    overlaid.finalizationInput(
                        template: material.template,
                        renderSize: CGSize(width: target.width, height: target.height),
                        modelViewProjection: Self.fullTargetMVP(target),
                        layerModelMatrix: dedicatedInputs.layerModelMatrix,
                        effectTextureProjectionMatrixInverse:
                            dedicatedInputs.effectTextureProjectionMatrixInverse,
                        implicitFramebufferIdentity: pairStep.inputIdentity
                    ),
                    variantCache: material.variants,
                    outputStorage: material.attachmentStorage == .color
                        ? .color : .scalarRedUnorm
                )
                let program: SceneResolvedMaterialProgram
                switch finalized {
                case let .success(value):
                    program = value
                case let .failure(failure):
                    let rejection = Failure.materialFinalizerRejected(
                        stageIndex: stageIndex,
                        effect: node.effect,
                        nodeIndex: nodeIndex,
                        materialOrdinal: ordinal,
                        failure: failure
                    )
                    guard failure.phase == .uniform else {
                        return rejection
                    }
                    let reasonCode: String
                    switch failure.code {
                    case .dynamicUniformBindingInvalid:
                        reasonCode = "material-finalizer-dynamic-uniform-binding"
                    case .staticUniformBindingInvalid:
                        reasonCode = "material-finalizer-static-uniform-binding"
                    case .hostUniformDeclarationConflict:
                        reasonCode = "material-finalizer-host-uniform-declaration-conflict"
                    case .uniformDeclarationConflict:
                        reasonCode = "material-finalizer-uniform-declaration-conflict"
                    default:
                        return rejection
                    }
                    return prepareVisualFailurePassthrough(
                        reasonCode: reasonCode,
                        transition: transition,
                        graph: graph,
                        pairStep: pairStep,
                        lease: lease,
                        snapshot: visualFailureSnapshot,
                        pair: &pair,
                        publications: &publications,
                        commands: &commands,
                        programKeys: &programKeys,
                        effectLocalFailureReasonCode:
                            &effectLocalFailureReasonCode,
                        boundedDetail: failure.boundedDetails.first,
                        rejection: rejection
                    )
                }
                guard let passPreparation = prepareMaterialPass(
                    program: program,
                    material: material,
                    target: target,
                    descriptor: fboTarget?.resource.descriptor
                ) else { return .graphStructureRejected }
                guard case let .success(prepared) = passPreparation else {
                    guard case let .failure(failure) = passPreparation else {
                        return .materialPassEncoderRejected
                    }
                    let rejection = Failure.materialPassPreparationRejected(
                        stageIndex: stageIndex,
                        nodeIndex: nodeIndex,
                        materialOrdinal: ordinal,
                        programKey: program.preparedShader.cacheKey,
                        failure: failure
                    )
                    guard let reasonCode = failure.effectLocalPreEncodeReasonCode else {
                        return rejection
                    }
                    return prepareVisualFailurePassthrough(
                        reasonCode: reasonCode,
                        transition: transition,
                        graph: graph,
                        pairStep: pairStep,
                        lease: lease,
                        snapshot: visualFailureSnapshot,
                        pair: &pair,
                        publications: &publications,
                        commands: &commands,
                        programKeys: &programKeys,
                        effectLocalFailureReasonCode:
                            &effectLocalFailureReasonCode,
                        rejection: rejection
                    )
                }
                commands.append(.material(prepared))
                programKeys.append(program.preparedShader.cacheKey)
                SceneResolvedMaterialGenericShaderArtifactCache.recordExecution(
                    backend: program.frontendProgram.backend,
                    colorTransfer: program.frontendProgram.colorTransfer,
                    hasExternalProviderTexture:
                        SceneResolvedMaterialVariantCache
                            .hasExternalProviderTexture(in: material.template),
                    producesScalarRedOutput:
                        program.outputContract == .scalarRedUnorm,
                    graphTextureSlots: Set(program.textureSlots.compactMap { slot in
                        guard let slot,
                              case let .graph(identity) =
                                  slot.resource.publication.requestIdentity,
                              identity.kind == .framebuffer
                        else { return nil }
                        return slot.index
                    }),
                    graphInputTextureSlots: Set(
                        program.textureSlots.compactMap { slot in
                            guard let slot,
                                  case .graph =
                                      slot.resource.publication.requestIdentity
                            else { return nil }
                            return slot.index
                        }
                    ),
                    r8TextureSlots: Set(program.textureSlots.compactMap { slot in
                        guard let slot else { return nil }
                        let candidate = slot.resource.publication.candidate
                        guard candidate.content == .scalarRedUnorm
                                || candidate.authoredFormat == .r8 else { return nil }
                        return slot.index
                    }),
                    hasStageScopedUniformBindings: {
                        let stages = Set(program.frontendProgram.uniformLayout.fields
                            .compactMap(\.stage))
                        return stages.contains(.vertex)
                            && stages.contains(.fragment)
                    }(),
                    layerID: node.effect.layerID,
                    effectIndex: node.effect.effectIndex,
                    descriptorID: node.effect.descriptorID,
                    nodeIndex: nodeIndex,
                    preparedKey: program.preparedShader.cacheKey
                )

                if let fboTarget {
                    guard node.target == fboTarget.identity,
                          pairNode.fullFrameWriteMember == nil else {
                        return .graphStructureRejected
                    }
                    guard let publication = framebufferResource(
                        lease: lease,
                        identity: fboTarget.identity,
                        resource: fboTarget.resource,
                        content: prepared.storedContent
                    ) else { return .graphPublicationRejected }
                    publications[fboTarget.identity] = publication
                } else {
                    guard let identity = node.target,
                          identity == pairStep.outputIdentity,
                          let member = pairNode.fullFrameWriteMember,
                          let fragmentOutput = prepared.fragmentOutput else {
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
                        representation: fragmentOutput
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
                            representation: fragmentOutput
                        ) else { return .graphPublicationRejected }
                        publications[pairStep.inputIdentity] = input
                        pair = .init(
                            member: member,
                            resource: input,
                            representation: fragmentOutput
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
        framebufferResource(
            lease: lease,
            identity: identity,
            resource: resource,
            content: .color(.resolved(representation))
        )
    }

    func framebufferResource(
        lease: SceneGraphRenderTargetLease,
        identity: Graph.TextureIdentity,
        resource: State.VersionedResource,
        content: SceneTextureContent
    ) -> SceneFrameTextureResource? {
        guard case let .success(publication) = lease.graphResource(
            for: identity,
            versionedResource: resource,
            storedContent: content
        ) else { return nil }
        return publication
    }

    private func publication(
        _ publication: SceneFrameTextureResource?,
        matches resource: State.VersionedResource,
        identity: Graph.TextureIdentity
    ) -> Bool {
        guard let publication,
              SceneGraphRenderTargetLease.graphSamplingMatches(
                  publication,
                  descriptor: resource.descriptor
              ),
              publication.publication.requestIdentity == .graph(identity),
              publication.resourceGeneration == resource.contentGeneration,
              case let .provider(.graph(_, token)) =
                publication.publication.candidate.identity else { return false }
        return token == resource.token.rawValue
    }

    private func frameTextureSnapshot(
        _ frame: SceneResolvedMaterialFrameSnapshot,
        overlaying reference: SceneNamedTextureReference,
        resource: SceneFrameTextureResource,
        frameEpoch: UInt64
    ) -> SceneResolvedMaterialFrameSnapshot? {
        let snapshot = frame.textureRegistrySnapshot
        guard snapshot.frameEpoch == frameEpoch,
              let replacement = snapshot.overlayingNamedLayerTarget(
                reference,
                resource: resource
              ) else { return nil }
        return frame.replacingTextureSnapshot(replacement)
    }
}
