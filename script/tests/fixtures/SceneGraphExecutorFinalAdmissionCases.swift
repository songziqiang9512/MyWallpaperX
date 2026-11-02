private func mismatchedOwnershipClaim(
    crossLayerGraph: Graph,
    crossLayerChain: AdmittedLayerGraph,
    namedReference: SceneNamedTextureReference,
    effectID: String,
    passIndex: Int,
    slotIndex: Int
) -> Bool {
    let binding = SceneDependencyRenderPlan.Binding(
        consumerLayerID: layerID,
        providerLayerID: namedReference.providerLayerID,
        slot: .init(
            effectID: effectID,
            passIndex: passIndex,
            slotIndex: slotIndex
        ),
        blendMode: 0,
        kind: .resolvedMaterial
    )
    return capabilities(
        crossLayerChain,
        catalog: catalog(
            for: crossLayerGraph,
            namedProvidersByNode: [0: namedReference]
        ),
        namedProvider: namedReference,
        dependencyBinding: binding
    ).claim(crossLayerChain) != nil
}

private func redGreenConsumerGraph(
    clear: SceneJSONValue? = nil,
    unique: Bool = false
) -> Graph {
    graph(
        targets: [rawTarget(
            first,
            format: "rg88",
            unique: unique,
            clear: clear
        )],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            material(1, ordinal: 1, target: output, read: first),
        ]
    )
}

private func redGreenRejection(
    _ candidateGraph: Graph,
    consumers: [Int: String]
) -> Bool {
    let chain = admittedGraph(candidateGraph)
    let candidateCapabilities = capabilities(
        chain,
        catalog: catalog(
            for: candidateGraph,
            scalarConsumerNodes: consumers
        )
    )
    return candidateCapabilities.claim(chain) == nil
        && candidateCapabilities.reportLines.contains {
            $0.contains(
                "rejection: rg88-red-green-graph-unproven count=1"
            )
        }
}

private func redGreenAdmission(
    _ candidateGraph: Graph,
    consumers: [Int: String]
) -> Bool {
    let chain = admittedGraph(candidateGraph)
    let candidateCapabilities = capabilities(
        chain,
        catalog: catalog(
            for: candidateGraph,
            scalarConsumerNodes: consumers
        )
    )
    return candidateCapabilities.claim(chain) != nil
}

private func scalarRejection(
    _ candidateGraph: Graph,
    consumers: [Int: String] = [:],
    unprovenProducer: Bool = false,
    expectedCode: String = "r8-scalar-graph-unproven"
) -> Bool {
    let chain = admittedGraph(candidateGraph)
    let candidateCapabilities = capabilities(
        chain,
        catalog: catalog(
            for: candidateGraph,
            scalarProducerUnprovenNodes: unprovenProducer ? [0] : [],
            scalarConsumerNodes: consumers
        )
    )
    return candidateCapabilities.claim(chain) == nil
        && candidateCapabilities.reportLines.contains {
            $0.contains("rejection: \(expectedCode) count=1")
        }
}

private func scalarAdmission(
    _ candidateGraph: Graph,
    consumers: [Int: String]
) -> Bool {
    let chain = admittedGraph(candidateGraph)
    let candidateCapabilities = capabilities(
        chain,
        catalog: catalog(
            for: candidateGraph,
            scalarConsumerNodes: consumers
        )
    )
    return candidateCapabilities.claim(chain) != nil
}

private func scalarConsumerGraph() -> Graph {
    graph(
        targets: [rawTarget(first, format: "r8")],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            material(1, ordinal: 1, target: output, read: first),
        ]
    )
}

private func finalAdmissionResults(
    crossLayerGraph: Graph,
    crossLayerChain: AdmittedLayerGraph,
    namedReference: SceneNamedTextureReference,
    secondaryCapabilities: Capabilities,
    pixelGraph: Graph,
    commandVisualFailureGraph: Graph,
    commandVisualFailureCapabilities: Capabilities,
    ordinaryChain: AdmittedLayerGraph,
    ordinaryCapabilities: Capabilities,
    uniformSchemaMultiNodeCapabilities: Capabilities,
    samplerSchemaMultiNodeCapabilities: Capabilities,
    ordinaryClaim: Capabilities.ClaimedLayer,
    scalarGraph: Graph,
    scalarChain: AdmittedLayerGraph,
    scalarCapabilities: Capabilities,
    redGreenGraph: Graph,
    redGreenChain: AdmittedLayerGraph,
    redGreenCapabilities: Capabilities,
    scalarClaim: Capabilities.ClaimedLayer,
    redGreenClaim: Capabilities.ClaimedLayer,
    redGreenRedConsumerGraph: Graph,
    redGreenWholeConsumerGraph: Graph,
    redGreenUniqueGraph: Graph,
    redGreenMultipleWriterGraph: Graph,
    scalarGreenGraph: Graph,
    scalarWholeGraph: Graph,
    scalarAliasGraph: Graph,
    scalarConditionalWriterGraph: Graph,
    scalarClearGraph: Graph,
    scalarUniqueGraph: Graph,
    scalarNoConsumerGraph: Graph,
    scalarMultipleWriterGraph: Graph,
    scalarCopyGraph: Graph,
    scalarSwapGraph: Graph,
    conditionGraph: Graph,
    composeGraph: Graph,
    inactiveComposeGraph: Graph,
    nonzeroClearGraph: Graph,
    uniqueVisualFailureGraph: Graph,
    readBeforeWriteVisualFailureGraph: Graph,
    unusedTargetVisualFailureGraph: Graph,
    passCapabilities: Capabilities,
    missingCapabilities: Capabilities,
    nonOverwriteCapabilities: Capabilities,
    nonzeroClearCapabilities: Capabilities,
    clearVisualFailureCapabilities: Capabilities,
    uniqueVisualFailureCapabilities: Capabilities,
    readBeforeWriteVisualFailureCapabilities: Capabilities,
    unusedTargetVisualFailureCapabilities: Capabilities,
    largeNodeGraph: Graph,
    largeLogicalGraph: Graph,
    lateCapabilities: Capabilities,
    failingCapabilities: Capabilities
) -> [String: Bool] {
    [
        "crossLayerWrongEffectOwnershipRejectedBeforeFrame":
            !mismatchedOwnershipClaim(
                crossLayerGraph: crossLayerGraph,
                crossLayerChain: crossLayerChain,
                namedReference: namedReference,
                effectID: effect.descriptorID + "-wrong",
                passIndex: 0,
                slotIndex: 1
            ),
        "crossLayerWrongPassOwnershipRejectedBeforeFrame":
            !mismatchedOwnershipClaim(
                crossLayerGraph: crossLayerGraph,
                crossLayerChain: crossLayerChain,
                namedReference: namedReference,
                effectID: effect.descriptorID,
                passIndex: 1,
                slotIndex: 1
            ),
        "crossLayerWrongSlotOwnershipRejectedBeforeFrame":
            !mismatchedOwnershipClaim(
                crossLayerGraph: crossLayerGraph,
                crossLayerChain: crossLayerChain,
                namedReference: namedReference,
                effectID: effect.descriptorID,
                passIndex: 0,
                slotIndex: 0
            ),
        "crossLayerSecondaryCannotClaim":
            secondaryCapabilities.claim(crossLayerChain) == nil,
        "ordinaryCanClaim": ordinaryCapabilities.claim(ordinaryChain) != nil,
        "foreignCatalogTokenRejected": lateCapabilities.resolve(
            ordinaryClaim.token
        ) == nil,
        "conditionRejected": capabilities(
            admittedGraph(conditionGraph), catalog: catalog(for: conditionGraph)
        ).claim(admittedGraph(conditionGraph)) == nil,
        "composeRejected": capabilities(
            admittedGraph(composeGraph), catalog: catalog(for: composeGraph)
        ).claim(admittedGraph(composeGraph)) == nil,
        "inactiveComposeAccepted": {
            let value = admittedGraph(inactiveComposeGraph)
            return capabilities(
                value,
                catalog: catalog(for: inactiveComposeGraph)
            ).claim(value) != nil
        }(),
        "activePassRejectedByLaunchEnvelope":
            passCapabilities.claim(ordinaryChain) == nil
                && passCapabilities.reportLines.contains {
                    $0.contains(
                        "rejection: material-variant-envelope-invariant count=1"
                    )
                },
        "missingTemplateRejected": missingCapabilities.claim(ordinaryChain) == nil,
        "nonOverwriteRejectedBeforeFrame": nonOverwriteCapabilities.claim(
            ordinaryChain
        ) == nil,
        "nonzeroClearAdmittedBeforeFrame": nonzeroClearCapabilities.claim(
            admittedGraph(nonzeroClearGraph)
        ) != nil,
        "authoredClearVisualFailureCanClaimWholeEffectPassthrough":
            clearVisualFailureCapabilities.claim(
                admittedGraph(nonzeroClearGraph)
            ) != nil,
        "uniqueTargetVisualFailureCanClaimWholeEffectPassthrough":
            uniqueVisualFailureCapabilities.claim(
                admittedGraph(uniqueVisualFailureGraph)
            ) != nil,
        "readBeforeWriteHistoryVisualFailureRemainsHardRejected":
            readBeforeWriteVisualFailureCapabilities.claim(
                admittedGraph(readBeforeWriteVisualFailureGraph)
            ) == nil,
        "writeOnlyTargetVisualFailureCanClaimWholeEffectPassthrough":
            unusedTargetVisualFailureCapabilities.claim(
                admittedGraph(unusedTargetVisualFailureGraph)
            ) != nil,
        "commandGraphLaunchVisualFailureCanClaimWholeEffectPassthrough":
            commandVisualFailureCapabilities.claim(
                admittedGraph(commandVisualFailureGraph)
            ) != nil,
        "largeNodeGraphCanClaim": capabilities(
            admittedGraph(largeNodeGraph), catalog: catalog(for: largeNodeGraph)
        ).claim(admittedGraph(largeNodeGraph)) != nil,
        "largeLogicalGraphCanClaim": capabilities(
            admittedGraph(largeLogicalGraph), catalog: catalog(for: largeLogicalGraph)
        ).claim(admittedGraph(largeLogicalGraph)) != nil,
        "scalarCapabilityCarriesExactAttachmentKinds": {
            guard let capability = scalarCapabilities.resolve(
                scalarClaim.token,
                for: scalarChain
            ) else { return false }
            return capability.material(for: scalarGraph.nodes[0])?
                    .attachmentStorage == .scalarRedUnorm
                && capability.material(for: scalarGraph.nodes[1])?
                    .attachmentStorage == .color
        }(),
        "redGreenCapabilityCarriesExactAttachmentKinds": {
            guard let capability = redGreenCapabilities.resolve(
                redGreenClaim.token,
                for: redGreenChain
            ) else { return false }
            return capability.material(for: redGreenGraph.nodes[0])?
                    .attachmentStorage == .redGreenUnorm
                && capability.material(for: redGreenGraph.nodes[1])?
                    .attachmentStorage == .color
        }(),
        "redGreenRedOnlyConsumerAdmittedBeforeFrame": redGreenAdmission(
            redGreenRedConsumerGraph,
            consumers: [1: "red"]
        ),
        "redGreenWholeConsumerAdmittedBeforeFrame": redGreenAdmission(
            redGreenWholeConsumerGraph,
            consumers: [1: "whole"]
        ),
        "redGreenFrameLocalUniqueAdmittedBeforeFrame": redGreenAdmission(
            redGreenUniqueGraph,
            consumers: [1: "rg"]
        ),
        "redGreenMultipleWriterRejectedBeforeFrame": redGreenRejection(
            redGreenMultipleWriterGraph,
            consumers: [2: "rg"]
        ),
        "scalarGreenConsumerRejectedBeforeFrame": scalarRejection(
            scalarGreenGraph,
            consumers: [1: "green"]
        ),
        "scalarWholeConsumerAdmittedBeforeFrame": scalarAdmission(
            scalarWholeGraph,
            consumers: [1: "whole"]
        ),
        "scalarAliasConsumerAdmittedBeforeFrame": scalarAdmission(
            scalarAliasGraph,
            consumers: [1: "alias"]
        ),
        "scalarConditionalWriterUsesWholeEffectPassthrough": {
            let chain = admittedGraph(scalarConditionalWriterGraph)
            let values = capabilities(
                chain,
                catalog: catalog(
                    for: scalarConditionalWriterGraph,
                    scalarProducerUnprovenNodes: [0],
                    scalarConsumerNodes: [1: "red"]
                )
            )
            guard let claim = values.claim(chain),
                  let capability = values.resolve(claim.token, for: chain)
            else { return false }
            return capability.stages.first?.execution.visualFailureReasonCode
                == "material-variant-envelope-color-contract"
        }(),
        "scalarClearSeedAdmittedBeforeFrame": {
            let chain = admittedGraph(scalarClearGraph)
            let values = capabilities(
                chain,
                catalog: catalog(
                    for: scalarClearGraph,
                    scalarConsumerNodes: [
                        0: "red", 1: "red", 2: "red",
                    ]
                )
            )
            return values.claim(chain) != nil
        }(),
        "scalarFrameLocalUniqueAdmittedBeforeFrame": scalarAdmission(
            scalarUniqueGraph,
            consumers: [1: "red"]
        ),
        "scalarNoConsumerRejectedBeforeFrame": scalarRejection(
            scalarNoConsumerGraph
        ),
        "scalarMultipleWriterRejectedBeforeFrame": scalarRejection(
            scalarMultipleWriterGraph,
            consumers: [2: "red"]
        ),
        "scalarCopyRejectedBeforeFrame": scalarRejection(
            scalarCopyGraph,
            consumers: [2: "red"]
        ),
        "scalarSwapRejectedBeforeFrame": scalarRejection(
            scalarSwapGraph,
            consumers: [2: "red"]
        ),
        "unsupportedBackwardReferenceFailsOnlyOwningEffect":
            unsupportedReferenceEffectKeys(
                graph: pixelGraph,
                referenceEffect: chainedSecondEffect,
                providerLayerID: layerID - 1
            ) == [chainedSecondEffect],
        // A reference whose slot is not represented by the owning node
        // keeps the whole layer fail-closed instead of guessing a slot.
        "unsupportedReferenceOutsideNodeBindingsStaysFailClosed":
            unsupportedReferenceEffectKeys(
                graph: pixelGraph,
                referenceEffect: chainedSecondEffect,
                providerLayerID: layerID - 1,
                slotIndex: 3
            ) == nil,
        // Command/multi-node effects cannot be replaced by previous-current.
        "unsupportedReferenceOnCommandEffectStaysFailClosed":
            unsupportedReferenceEffectKeys(
                graph: commandVisualFailureGraph,
                referenceEffect: commandVisualFailureGraph.effects[0].key,
                providerLayerID: layerID - 1
            ) == nil,
        "visualUniformSchemaMultiNodeUsesWholeEffectPassthrough": {
            guard let claim = uniformSchemaMultiNodeCapabilities.claim(
                      ordinaryChain
                  ), let capability = uniformSchemaMultiNodeCapabilities.resolve(
                      claim.token,
                      for: ordinaryChain
                  ) else { return false }
            return capability.stages.first?.execution.visualFailureReasonCode
                == "material-generic-owner-revoked"
        }(),
        "visualSamplerSchemaMultiNodeUsesWholeEffectPassthrough": {
            guard let claim = samplerSchemaMultiNodeCapabilities.claim(
                      ordinaryChain
                  ), let capability = samplerSchemaMultiNodeCapabilities.resolve(
                      claim.token,
                      for: ordinaryChain
                  ) else { return false }
            return capability.stages.first?.execution.visualFailureReasonCode
                == "material-variant-envelope-sampler-schema"
        }(),
        "frontendInvalidUsesWholeEffectPassthrough": {
            guard let claim = failingCapabilities.claim(ordinaryChain),
                  let capability = failingCapabilities.resolve(
                      claim.token,
                      for: ordinaryChain
                  ) else { return false }
            return capability.stages.first?.execution.visualFailureReasonCode
                == "material-generic-owner-revoked"
        }(),
    ]
}
