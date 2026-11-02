extension Harness {
    static func programProviderResults() -> [String: Any] {
        let shadowedProvider = layer(420, kind: .composition, visible: false)
        let shadowedConsumer = SceneRenderDescriptor.Layer(
            id: 421,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [shadowedProvider.id],
            childLayerIDs: [],
            visible: true,
            effects: [
                effect(id: 421, provider: shadowedProvider.id),
                shadowedEffect(id: 422, provider: shadowedProvider.id),
                shadowedEffect(
                    id: 423,
                    provider: shadowedProvider.id,
                    userTextureKind: .system
                ),
                shadowedEffect(
                    id: 424,
                    provider: shadowedProvider.id,
                    userTextureKind: .path
                ),
                shadowedEffect(
                    id: 425,
                    provider: shadowedProvider.id,
                    userTextureKind: .unknown
                ),
            ]
        )
        let shadowedPlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: [shadowedProvider, shadowedConsumer],
                renderOrderLayerIDs: [shadowedProvider.id, shadowedConsumer.id]
            ),
            visibleLayerIDs: [shadowedProvider.id, shadowedConsumer.id]
        )
        let mixedProvider = layer(1321, visible: false)
        let mixedConsumer = SceneRenderDescriptor.Layer(
            id: 1509,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [mixedProvider.id],
            childLayerIDs: [],
            visible: true,
            effects: [
                shadowedEffect(
                    id: 961,
                    provider: mixedProvider.id,
                    userTextureKind: .system
                ),
                shadowedEffect(
                    id: 962,
                    provider: mixedProvider.id,
                    userTextureKind: .system
                ),
                .init(
                    id: "suffix",
                    file: "effects/waterwaves/effect.json",
                    visible: true,
                    passes: [.init(
                        passIndex: 0,
                        texturePaths: [],
                        textureSlots: [],
                        combos: [:],
                        constantShaderValues: [:]
                    )]
                ),
            ]
        )
        let mixedProviderDescriptor = SceneRenderDescriptor(
            layers: [mixedConsumer, mixedProvider],
            renderOrderLayerIDs: [mixedConsumer.id, mixedProvider.id]
        )
        let allMixedPotentialReferences = Set(
            SceneDependencyGraphAnalysis
                .potentialNamedReferences(
                    in: mixedProviderDescriptor.layers
                )
        )
        let mixedPotentialReferences = Set(
            allMixedPotentialReferences.filter {
                $0.slot.effectID == "effect-961"
            }
        )
        let mixedProviderUnadmittedPlan = SceneDependencyRenderPlan(
            descriptor: mixedProviderDescriptor,
            visibleLayerIDs: [mixedConsumer.id]
        )
        let mixedProviderPlan = SceneDependencyRenderPlan(
            descriptor: mixedProviderDescriptor,
            visibleLayerIDs: [mixedConsumer.id],
            admittedResolvedMaterialReferences: mixedPotentialReferences
        )
        let vectorProvider = layer(1325, visible: false)
        let vectorConsumer = SceneRenderDescriptor.Layer(
            id: 1515,
            contentKind: "solid",
            utilityLayer: nil,
            dependencyLayerIDs: [vectorProvider.id],
            childLayerIDs: [],
            visible: true,
            effects: [
                effect(
                    id: 964,
                    provider: vectorProvider.id,
                    path: "effects/workshop/direct/effect.json"
                ),
                shadowedEffect(
                    id: 965,
                    provider: vectorProvider.id,
                    userTextureKind: .system
                ),
                shadowedEffect(
                    id: 966,
                    provider: vectorProvider.id,
                    userTextureKind: .property
                ),
            ]
        )
        let vectorDescriptor = SceneRenderDescriptor(
            layers: [vectorConsumer, vectorProvider],
            renderOrderLayerIDs: [vectorConsumer.id, vectorProvider.id]
        )
        let vectorDirectReferences = Set(
            SceneDependencyGraphAnalysis.references(
                in: vectorDescriptor.layers
            )
        )
        let vectorPotentialReferences = Set(
            SceneDependencyGraphAnalysis
                .potentialNamedReferences(
                    in: vectorDescriptor.layers
                )
        )
        let vectorDirectPlan = SceneDependencyRenderPlan(
            descriptor: vectorDescriptor,
            visibleLayerIDs: [vectorConsumer.id],
            admittedResolvedMaterialReferences: vectorDirectReferences
        )
        let vectorPlan = SceneDependencyRenderPlan(
            descriptor: vectorDescriptor,
            visibleLayerIDs: [vectorConsumer.id],
            admittedResolvedMaterialReferences:
                vectorDirectReferences.union(vectorPotentialReferences)
        )
        let vectorPotentialBindings = SceneDependencyRenderPlan
            .potentialNamedBindings(
                descriptor: vectorDescriptor,
                visibleLayerIDs: [vectorConsumer.id]
            )[vectorConsumer.id] ?? []
        let vectorDirectSlots = vectorDirectPlan.bindingsByConsumerLayerID[
            vectorConsumer.id
        ]?.referenceSlots.map { slot in
            slot.effectID + ":" + String(slot.passIndex)
                + ":" + String(slot.slotIndex)
        } ?? []
        let vectorExpandedSlots = vectorPlan.bindingsByConsumerLayerID[
            vectorConsumer.id
        ]?.referenceSlots.map { slot in
            slot.effectID + ":" + String(slot.passIndex)
                + ":" + String(slot.slotIndex)
        } ?? []
        let propertyProvider = layer(1331, visible: false)
        let propertyConsumer = SceneRenderDescriptor.Layer(
            id: 1511,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [propertyProvider.id],
            childLayerIDs: [],
            visible: true,
            effects: [shadowedEffect(
                id: 963,
                provider: propertyProvider.id,
                userTextureKind: .property
            )]
        )
        let propertyDescriptor = SceneRenderDescriptor(
            layers: [propertyConsumer, propertyProvider],
            renderOrderLayerIDs: [propertyConsumer.id, propertyProvider.id]
        )
        let propertyPotentialReferences = Set(
            SceneDependencyGraphAnalysis
                .potentialNamedReferences(
                    in: propertyDescriptor.layers
                )
        )
        let propertyUnadmittedPlan = SceneDependencyRenderPlan(
            descriptor: propertyDescriptor,
            visibleLayerIDs: [propertyConsumer.id]
        )
        let propertyAdmittedPlan = SceneDependencyRenderPlan(
            descriptor: propertyDescriptor,
            visibleLayerIDs: [propertyConsumer.id],
            admittedResolvedMaterialReferences: propertyPotentialReferences
        )
        let isolatedConsumer = layer(
            1510,
            dependencies: [1331, 1332]
        )
        let isolatedProvider = layer(1331, visible: false)
        let cyclicPotentialProvider = layer(
            1332,
            dependencies: [isolatedConsumer.id],
            visible: false
        )
        let isolatedReference = SceneDependencyRenderPlan.Reference(
            consumerLayerID: isolatedConsumer.id,
            providerLayerID: isolatedProvider.id,
            slot: .init(effectID: "isolated", passIndex: 0, slotIndex: 1),
            variant: .primary
        )
        let unadmittedCycleReference = SceneDependencyRenderPlan.Reference(
            consumerLayerID: isolatedConsumer.id,
            providerLayerID: cyclicPotentialProvider.id,
            slot: .init(effectID: "cycle-out", passIndex: 0, slotIndex: 2),
            variant: .primary
        )
        let unadmittedCycleReturn = SceneDependencyRenderPlan.Reference(
            consumerLayerID: cyclicPotentialProvider.id,
            providerLayerID: isolatedConsumer.id,
            slot: .init(effectID: "cycle-back", passIndex: 0, slotIndex: 1),
            variant: .primary
        )
        let isolationLayers = [
            isolatedConsumer, isolatedProvider, cyclicPotentialProvider,
        ]
        let isolationPotentials: Set<SceneDependencyRenderPlan.Reference> = [
            isolatedReference,
            unadmittedCycleReference,
            unadmittedCycleReturn,
        ]
        let isolatedEdges = SceneDependencyRenderPlan.productDependencyEdges(
            layers: isolationLayers,
            references: [isolatedReference],
            productReferences: [],
            potentialReferences: isolationPotentials,
            admittedPotentialReferences: [isolatedReference]
        )
        let broadPotentialEdges = SceneDependencyGraphAnalysis.dependencyEdges(
            layers: isolationLayers,
            references: Array(isolationPotentials)
        )
        let selectedMultiReferenceConsumer = SceneRenderDescriptor.Layer(
            id: 431,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [shadowedProvider.id],
            childLayerIDs: [],
            visible: true,
            effects: [
                effect(id: 431, provider: shadowedProvider.id),
                effect(id: 432, provider: shadowedProvider.id),
            ]
        )
        let selectedMultiReferencePlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: [shadowedProvider, selectedMultiReferenceConsumer],
                renderOrderLayerIDs: [
                    shadowedProvider.id, selectedMultiReferenceConsumer.id,
                ]
            ),
            visibleLayerIDs: [
                shadowedProvider.id, selectedMultiReferenceConsumer.id,
            ]
        )
        return [
            "shadowedNamedReferences": [
                "referenceCount": shadowedPlan.references.count,
                "binding": shadowedPlan.bindingsByConsumerLayerID[
                    shadowedConsumer.id
                ]?.kind == .resolvedMaterial,
                "provider": shadowedPlan.bindingsByConsumerLayerID[
                    shadowedConsumer.id
                ]?.providerLayerID ?? -1,
                "issues": shadowedPlan.issues.map {
                    "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
                },
            ],
            "mixedSystemNamedProvider": [
                "potentialCount": allMixedPotentialReferences.count,
                "references": mixedProviderPlan.references.count,
                "bindingKind": mixedProviderPlan.bindingsByConsumerLayerID[
                    mixedConsumer.id
                ].map { String(describing: $0.kind) } ?? "none",
                "requiresForwardCapture": mixedProviderPlan
                    .bindingsByConsumerLayerID[mixedConsumer.id]?
                    .requiresForwardCapture == true,
                "requiresProgram": mixedProviderPlan.bindingsByConsumerLayerID[
                    mixedConsumer.id
                ]?.requiresResolvedMaterialProgram == true,
                "provider": mixedProviderPlan.bindingsByConsumerLayerID[
                    mixedConsumer.id
                ]?.providerLayerID ?? -1,
                "issues": mixedProviderPlan.issues.map {
                    "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
                },
            ],
            "singleProviderProgramVector": [
                "directReferences": vectorDirectPlan.references.count,
                "directSlots": vectorDirectSlots,
                "potentialBindings": vectorPotentialBindings.count,
                "potentialSingletons": vectorPotentialBindings.allSatisfy {
                    $0.referenceSlots == [$0.slot]
                },
                "expandedReferences": vectorPlan.references.count,
                "expandedSlots": vectorExpandedSlots,
                "provider": vectorPlan.bindingsByConsumerLayerID[
                    vectorConsumer.id
                ]?.providerLayerID ?? -1,
                "kind": vectorPlan.bindingsByConsumerLayerID[
                    vectorConsumer.id
                ].map { String(describing: $0.kind) } ?? "none",
                "forward": vectorPlan.bindingsByConsumerLayerID[
                    vectorConsumer.id
                ]?.requiresForwardCapture == true,
                "requiresProgram": vectorPlan.bindingsByConsumerLayerID[
                    vectorConsumer.id
                ]?.requiresResolvedMaterialProgram == true,
                "issues": vectorPlan.issues.map {
                    "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
                },
            ],
            "mixedSystemNamedUnadmitted": [
                "references": mixedProviderUnadmittedPlan.references.count,
                "binding": mixedProviderUnadmittedPlan
                    .bindingsByConsumerLayerID[mixedConsumer.id] != nil,
                "requiresEffect": mixedProviderUnadmittedPlan
                    .requiredEffectConsumerLayerIDs.contains(mixedConsumer.id),
                "consumerBlocked": mixedProviderUnadmittedPlan
                    .blocksStaticLayerSourcePassthrough(for: mixedConsumer.id),
                "providerBlocked": mixedProviderUnadmittedPlan
                    .blocksStaticLayerSourcePassthrough(for: mixedProvider.id),
            ],
            "mixedPropertyNamedProvider": [
                "potentialCount": propertyPotentialReferences.count,
                "unadmittedReferences": propertyUnadmittedPlan.references.count,
                "unadmittedBinding": propertyUnadmittedPlan
                    .bindingsByConsumerLayerID[propertyConsumer.id] != nil,
                "unadmittedConsumerBlocked": propertyUnadmittedPlan
                    .blocksStaticLayerSourcePassthrough(for: propertyConsumer.id),
                "unadmittedProviderBlocked": propertyUnadmittedPlan
                    .blocksStaticLayerSourcePassthrough(for: propertyProvider.id),
                "admittedReferences": propertyAdmittedPlan.references.count,
                "admittedBinding": propertyAdmittedPlan
                    .bindingsByConsumerLayerID[propertyConsumer.id]?
                    .requiresResolvedMaterialProgram == true,
                "admittedProvider": propertyAdmittedPlan
                    .bindingsByConsumerLayerID[propertyConsumer.id]?
                    .providerLayerID ?? -1,
            ],
            "potentialCycleIsolation": [
                "broadCycles": SceneDependencyGraphAnalysis.cyclicLayerIDs(
                    edges: broadPotentialEdges
                ).sorted(),
                "isolatedCycles": SceneDependencyGraphAnalysis.cyclicLayerIDs(
                    edges: isolatedEdges
                ).sorted(),
                "isolatedConsumerEdges": Array(
                    isolatedEdges[isolatedConsumer.id] ?? []
                ).sorted(),
                "unadmittedProviderEdges": Array(
                    isolatedEdges[cyclicPotentialProvider.id] ?? []
                ).sorted(),
            ],
            "selectedMultiReferenceAccepted":
                selectedMultiReferencePlan.bindingsByConsumerLayerID[
                    selectedMultiReferenceConsumer.id
                ]?.kind == .resolvedMaterial
                && selectedMultiReferencePlan.references.filter {
                    $0.consumerLayerID == selectedMultiReferenceConsumer.id
                }.count == 2
                && selectedMultiReferencePlan.requiredProviderLayerIDs == [
                    shadowedProvider.id
                ],
        ]
    }
}
