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
        let vectorExpandedBindings = vectorPlan.multiProviderAggregatesByConsumerLayerID[
            vectorConsumer.id
        ]?.bindings ?? vectorPlan.bindingsByConsumerLayerID[
            vectorConsumer.id
        ].map { [$0] } ?? []
        let vectorExpandedSlots = vectorExpandedBindings.map {
            "\($0.slot.effectID):\($0.slot.passIndex):\($0.slot.slotIndex)"
        }
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
        let selectedMultiBindings = selectedMultiReferencePlan
            .multiProviderAggregatesByConsumerLayerID[selectedMultiReferenceConsumer.id]?
            .bindings ?? selectedMultiReferencePlan.bindingsByConsumerLayerID[
                selectedMultiReferenceConsumer.id
            ].map { [$0] } ?? []
        let shadowedNamedReferences: [String: Any] = [
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
        ]
        let mixedSystemNamedProvider: [String: Any] = [
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
        ]
        let singleProviderProgramVector: [String: Any] = [
            "directReferences": vectorDirectPlan.references.count,
            "directSlots": vectorDirectSlots,
            "potentialBindings": vectorPotentialBindings.count,
            "potentialSingletons": vectorPotentialBindings.allSatisfy {
                $0.referenceSlots == [$0.slot]
            },
            "expandedReferences": vectorPlan.references.count,
            "expandedSlots": vectorExpandedSlots,
            "providers": vectorExpandedBindings.map(\.providerLayerID),
            "requiredProviders": vectorPlan.requiredProviderLayerIDs.sorted(),
            "kinds": vectorExpandedBindings.map { String(describing: $0.kind) },
            "forward": vectorExpandedBindings.map(\.requiresForwardCapture),
            "requiresProgram": vectorExpandedBindings.map(\.requiresResolvedMaterialProgram),
            "issues": vectorPlan.issues.map {
                "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
            },
        ]
        let mixedSystemNamedUnadmitted: [String: Any] = [
            "references": mixedProviderUnadmittedPlan.references.count,
            "binding": mixedProviderUnadmittedPlan
                .bindingsByConsumerLayerID[mixedConsumer.id] != nil,
            "requiresEffect": mixedProviderUnadmittedPlan
                .requiredEffectConsumerLayerIDs.contains(mixedConsumer.id),
            "consumerBlocked": mixedProviderUnadmittedPlan
                .blocksStaticLayerSourcePassthrough(for: mixedConsumer.id),
            "providerBlocked": mixedProviderUnadmittedPlan
                .blocksStaticLayerSourcePassthrough(for: mixedProvider.id),
        ]
        let mixedPropertyNamedProvider: [String: Any] = [
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
        ]
        let potentialCycleIsolation: [String: Any] = [
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
        ]
        let selectedMultiReferences: [String: Any] = [
            "slots": selectedMultiBindings.map {
                "\($0.slot.effectID):\($0.slot.passIndex):\($0.slot.slotIndex)"
            },
            "providers": selectedMultiBindings.map(\.providerLayerID),
            "requiredProviders": selectedMultiReferencePlan.requiredProviderLayerIDs.sorted(),
            "kinds": selectedMultiBindings.map { String(describing: $0.kind) },
            "requiresProgram": selectedMultiBindings.map(\.requiresResolvedMaterialProgram),
            "references": selectedMultiReferencePlan.references.filter {
                $0.consumerLayerID == selectedMultiReferenceConsumer.id
            }.count,
        ]
        let cycleConsumer = consumer(100, provider: 110,
            effectPath: "effects/review/front/effect.json")
        let cyclicA = consumer(110, provider: 120, visible: false,
            effectPath: "effects/review/hidden-a/effect.json")
        let cyclicB = consumer(120, provider: 110, visible: false,
            effectPath: "effects/review/hidden-b/effect.json")
        let healthyConsumer = consumer(200, provider: 210,
            effectPath: "effects/review/peer/effect.json")
        let healthyProvider = layer(210, visible: false)
        let forwardLayers = [cycleConsumer, healthyConsumer, cyclicA, cyclicB, healthyProvider]
        let forwardLayerIDs = forwardLayers.map(\.id)
        let forwardDescriptor = SceneRenderDescriptor(
            layers: forwardLayers, renderOrderLayerIDs: forwardLayerIDs)
        let preparedForwardBindings = SceneDependencyRenderPlan.potentialNamedBindings(
            descriptor: forwardDescriptor, visibleLayerIDs: [100, 200])
        let preparedForwardPlan = SceneDependencyRenderPlan(
            descriptor: forwardDescriptor, visibleLayerIDs: [100, 200],
            preparedNamedInputBindingsByConsumerLayerID: preparedForwardBindings)
        let candidateBindings = [100, 110, 120, 200].flatMap {
            preparedForwardBindings[$0] ?? []
        }
        let preparedForwardCycle: [String: Any] = [
            "candidateProviders": candidateBindings.map(\.providerLayerID),
            "candidateForward": candidateBindings.map(\.requiresForwardCapture),
            "cycles": preparedForwardPlan.cyclicLayerIDs.sorted(),
            "requiredProviders": preparedForwardPlan.requiredProviderLayerIDs.sorted(),
            "graphProviders": preparedForwardPlan.requiredGraphOutputProviderLayerIDs.sorted(),
            "consumerBindingRetained": preparedForwardPlan.bindingsByConsumerLayerID[100]?
                .providerLayerID == 110,
            "activeExecution": preparedForwardPlan.sourcePreparationPlan(
                authoredLayerIDs: forwardLayerIDs, availableExecutionLayerIDs: [100, 110, 120, 200],
                visibleRootLayerIDs: [100, 200], activeStaticModelConsumerLayerIDs: [],
                sourceAfterLayerIDByLayerID: [:])?.preparationSchedule().preparationLayerIDs.sorted() ?? [-1],
            "cycleOnlyForward": preparedForwardPlan.sourcePreparationPlan(
                authoredLayerIDs: forwardLayerIDs, availableExecutionLayerIDs: [100],
                visibleRootLayerIDs: [100], activeStaticModelConsumerLayerIDs: [],
                sourceAfterLayerIDByLayerID: [:])?.preparationSchedule().prepassProviderLayerIDs ?? [-1],
            "withHealthyForward": preparedForwardPlan.sourcePreparationPlan(
                authoredLayerIDs: forwardLayerIDs, availableExecutionLayerIDs: [100, 200],
                visibleRootLayerIDs: [100, 200], activeStaticModelConsumerLayerIDs: [],
                sourceAfterLayerIDByLayerID: [:])?.preparationSchedule().prepassProviderLayerIDs ?? [-1],
        ]
        return [
            "shadowedNamedReferences": shadowedNamedReferences,
            "mixedSystemNamedProvider": mixedSystemNamedProvider,
            "singleProviderProgramVector": singleProviderProgramVector,
            "mixedSystemNamedUnadmitted": mixedSystemNamedUnadmitted,
            "mixedPropertyNamedProvider": mixedPropertyNamedProvider,
            "potentialCycleIsolation": potentialCycleIsolation,
            "selectedMultiReferences": selectedMultiReferences,
            "preparedForwardCycle": preparedForwardCycle,
            "definitionMaterialProviders": definitionMaterialProviderResults(),
            "forwardRepeatedProvider": forwardRepeatedProviderResults(),
            "sourceTiming": sourceTimingResults(),
        ]
    }

    static func forwardRepeatedProviderResults() -> [String: Any] {
        var rows: [String: Any] = [:]
        for mode in ["same", "renamed", "twoProviders", "secondary", "self", "background", "visible"] {
            let renamed = mode == "renamed"
            let upstreamID = renamed ? 2901 : 1901
            let otherID = upstreamID + 1, middleID = upstreamID + 2, consumerID = upstreamID + 3
            let effectID = renamed ? "omega" : "vector"
            let passIndex = renamed ? 2 : 0
            let indices = renamed ? [1, 6] : [2, 5]
            let providers = mode == "self" ? [middleID, middleID]
                : mode == "twoProviders" ? [upstreamID, otherID] : [upstreamID, upstreamID]
            var textures = Array<String?>(repeating: nil, count: indices[1] + 1)
            for index in indices.indices {
                let suffix = mode == "secondary" && index == 1 ? "b" : "a"
                textures[indices[index]] = "_rt_imageLayerComposite_\(providers[index])_\(suffix)"
            }
            var paths = textures.compactMap { $0 }
            if mode == "background" { paths.append("_rt_FullFrameBuffer") }
            let middle = SceneRenderDescriptor.Layer(id: middleID, contentKind: "image", utilityLayer: nil,
                dependencyLayerIDs: Array(Set(providers)).sorted(), childLayerIDs: [],
                visible: mode == "visible", effects: [.init(id: effectID,
                    file: renamed ? "effects/retitled/other/effect.json" : "effects/owned/vector/effect.json",
                    visible: true, passes: [.init(passIndex: passIndex, texturePaths: paths,
                        textureSlots: textures, combos: [:], constantShaderValues: [:])])])
            let front = consumer(consumerID, provider: middleID,
                                 effectPath: "effects/owned/front/effect.json")
            let layers = [front, middle, layer(upstreamID, visible: false), layer(otherID, visible: false)]
            let order = layers.map(\.id)
            let descriptor = SceneRenderDescriptor(layers: layers, renderOrderLayerIDs: order)
            let visible: Set<Int> = mode == "visible" ? [consumerID, middleID] : [consumerID]
            let candidates = SceneDependencyRenderPlan.potentialNamedBindings(
                descriptor: descriptor, visibleLayerIDs: visible)
            let plan = SceneDependencyRenderPlan(descriptor: descriptor, visibleLayerIDs: visible,
                preparedNamedInputBindingsByConsumerLayerID: candidates)
            let bindings = plan.multiProviderAggregatesByConsumerLayerID[middleID]?.bindings ?? []
            rows[mode] = [
                "candidateCount": candidates[consumerID]?.count ?? 0,
                "consumerProvider": plan.bindingsByConsumerLayerID[consumerID]?.providerLayerID ?? -1,
                "middleBindings": bindings.map { "\($0.slot.effectID):\($0.slot.passIndex):\($0.slot.slotIndex)=\($0.providerLayerID)" },
                "middleProviders": bindings.map(\.providerLayerID),
                "requiredProviders": plan.requiredProviderLayerIDs.sorted(),
                "forwardOrder": plan.sourcePreparationPlan(authoredLayerIDs: order,
                    availableExecutionLayerIDs: plan.requiredGraphOutputProviderLayerIDs.union([consumerID]),
                    visibleRootLayerIDs: visible, activeStaticModelConsumerLayerIDs: [],
                    sourceAfterLayerIDByLayerID: [:])?.preparationSchedule().prepassProviderLayerIDs ?? [-1],
            ]
        }
        let foreign = SceneDependencyRenderPlan.Reference(consumerLayerID: 77, providerLayerID: 1901,
            slot: .init(effectID: "foreign", passIndex: 0, slotIndex: 2), variant: .primary)
        rows["foreignConsumerAccepted"] = SceneDependencyRenderPlan.providerGraphIsAuthoredOrderIndependent(
            layer(1903, dependencies: [1901], visible: false), references: [foreign], texturePaths: [])
        return rows
    }

    static func sourceTimingResults() -> [String: Any] {
        var rows: [String: Any] = [:]
        for renamed in [false, true] {
            let base = renamed ? 2300 : 1300
            let o = base, u = base + 1, c = base + 2, p = base + 3, d = base + 4
            for mode in ["prefix", "earlyLate", "visibleDeadline", "independent", "inactive", "sameProviderActiveSlot"] {
                let early = ["earlyLate", "inactive", "sameProviderActiveSlot"].contains(mode)
                let order = early ? [c, u, p, d]
                    : mode == "visibleDeadline" ? [p, u, d] : [o, u, c, p]
                let visible: Set<Int> = early ? [c, d]
                    : mode == "visibleDeadline" ? [p, d] : [o, c]
                let available = Set(order).subtracting([u])
                let ordinary = SceneRenderDescriptor.Layer(id: o, contentKind: "image", utilityLayer: nil,
                    dependencyLayerIDs: [], childLayerIDs: [], visible: true,
                    effects: localEffects(layerID: o, count: 1, suffix: "prefix"))
                var utility = SceneUtilityLayer(kind: .composition)
                utility.copyBackground = mode != "independent"
                let source = SceneRenderDescriptor.Layer(id: u, contentKind: "composition",
                    utilityLayer: utility, dependencyLayerIDs: [], childLayerIDs: [],
                    visible: false, effects: [])
                let resource = renamed ? "effects/retitled/chain.json" : "effects/owned/read.json"
                let named = "_rt_imageLayerComposite_\(u)_a"
                let middle = mode == "sameProviderActiveSlot"
                    ? SceneRenderDescriptor.Layer(id: p, contentKind: "image", utilityLayer: nil,
                        dependencyLayerIDs: [u], childLayerIDs: [], visible: false,
                        effects: [.init(id: "effect-\(p)", file: resource, visible: true,
                            passes: [.init(passIndex: 0, texturePaths: [named, named],
                                textureSlots: [nil, named, nil, named], combos: [:], constantShaderValues: [:])])])
                    : consumer(p, provider: u, visible: mode == "visibleDeadline", effectPath: resource)
                let all = [ordinary, source, consumer(c, provider: p, effectPath: resource),
                    middle, consumer(d, provider: p, effectPath: resource)]
                let descriptor = SceneRenderDescriptor(layers: all.filter { order.contains($0.id) },
                    renderOrderLayerIDs: order)
                var bindings = SceneDependencyRenderPlan.potentialNamedBindings(
                    descriptor: descriptor, visibleLayerIDs: visible)
                if mode == "visibleDeadline" {
                    // This seam supplies the selected Program input; source
                    // admission and actual publication are separate owners.
                    bindings[p] = [.init(consumerLayerID: p, providerLayerID: u,
                        slot: .init(effectID: "effect-\(p)", passIndex: 0, slotIndex: 1),
                        blendMode: 0, kind: .resolvedMaterial, requiresForwardCapture: true,
                        requiresResolvedMaterialProgram: true)]
                    bindings[d] = [.init(consumerLayerID: d, providerLayerID: p,
                        slot: .init(effectID: "effect-\(d)", passIndex: 0, slotIndex: 1),
                        blendMode: 0, kind: .visibleImageGraphOutput,
                        requiresResolvedMaterialProgram: true)]
                }
                let plan = SceneDependencyRenderPlan(descriptor: descriptor, visibleLayerIDs: visible,
                    preparedNamedInputBindingsByConsumerLayerID: bindings)
                guard let sourcePlan = plan.sourcePreparationPlan(authoredLayerIDs: order,
                    availableExecutionLayerIDs: available, visibleRootLayerIDs: visible,
                    activeStaticModelConsumerLayerIDs: [],
                    sourceAfterLayerIDByLayerID: mode == "independent" ? [:] : [u: u]) else {
                    fatalError("source timing schedule unavailable")
                }
                let excluded: [Int: Set<SceneEffectPassSlot>] = mode == "inactive" || mode == "sameProviderActiveSlot"
                    ? [p: [.init(effectID: "effect-\(p)", passIndex: 0, slotIndex: 1)]] : [:]
                let schedule = sourcePlan.preparationSchedule(excludingSlotsByConsumerLayerID: excluded)
                rows["\(mode)\(renamed ? "Renamed" : "")"] = [
                    "preparation": schedule.preparationLayerIDs,
                    "prepass": schedule.prepassProviderLayerIDs,
                    "before": Dictionary(uniqueKeysWithValues:
                        schedule.providersBeforeLayerID.map { (String($0.key), $0.value) }),
                    "scheduled": schedule.scheduledGraphProviderLayerIDs.sorted(),
                    "providers": plan.requiredProviderLayerIDs.sorted(),
                ]
            }
        }
        return rows
    }

    static func definitionMaterialProviderResults() -> [String: Any] {
        let sourceA = layer(1601, visible: false), sourceB = layer(1602, visible: false)
        let lower = "_rt_imageLayerComposite_1601_a", upper = "_rt_imageLayerComposite_1602_a"
        var rows: [[String: Any]] = []
        for overridden in [false, true] {
            let identifier = overridden ? 1604 : 1603
            let effectID = overridden ? "instance-override" : "definition-shared"
            let passes: [SceneRenderDescriptor.EffectDescriptor.PassDescriptor] = overridden
                ? [0, 1].map { .init(passIndex: $0, textureSlots: [nil, nil, upper],
                    combos: [:], constantShaderValues: [:]) } : []
            let consumer = SceneRenderDescriptor.Layer(id: identifier, contentKind: "image",
                utilityLayer: nil, dependencyLayerIDs: [1601, 1602], childLayerIDs: [], visible: true,
                effects: [.init(id: effectID, file: "effects/reused-definition.json", visible: true, passes: passes)])
            let effect = SceneAuthoredEffectRenderPlan.EffectKey(layerID: identifier,
                effectIndex: 0, descriptorID: effectID)
            let graph = SceneAuthoredEffectRenderPlan(layerID: identifier, nodes: [
                .init(effect: effect, definitionPassIndex: 0, instancePassIndex: overridden ? 0 : nil,
                    materialPassID: "reused-material#0"),
                .init(effect: effect, definitionPassIndex: 2, instancePassIndex: overridden ? 1 : nil,
                    materialPassID: "reused-material#0"),
            ])
            var descriptor = SceneRenderDescriptor(layers: [sourceA, sourceB, consumer],
                renderOrderLayerIDs: [1601, 1602, identifier])
            descriptor.materialPasses = [.init(id: "reused-material#0", materialPath: "materials/reused.json",
                passIndex: 0, texturePaths: [lower], textureSlots: [nil, nil, lower], userTextureInputs: [])]
            let candidates = SceneDependencyRenderPlan.potentialNamedBindings(
                descriptor: descriptor, authoredPlans: [graph], visibleLayerIDs: [identifier])[identifier] ?? []
            rows.append(["overridden": overridden,
                "passes": candidates.map { $0.slot.passIndex }, "slots": candidates.map { $0.slot.slotIndex },
                "providers": candidates.map(\.providerLayerID),
                "effects": candidates.map { $0.slot.effectID },
                "requiresProgram": candidates.map(\.requiresResolvedMaterialProgram)])
        }
        var forward: [[String: Any]] = []
        for (readsBackground, declaresDependency) in [(false, true), (false, false), (true, true), (true, false)] {
            let front = consumer(1700, provider: 1710)
            let hidden = SceneRenderDescriptor.Layer(id: 1710, contentKind: "image", utilityLayer: nil,
                dependencyLayerIDs: declaresDependency ? [1720] : [], childLayerIDs: [], visible: false,
                effects: [.init(id: "hidden-definition", file: "effects/hidden-definition.json", visible: true, passes: [])])
            let terminal = layer(1720, visible: false)
            let graph = SceneAuthoredEffectRenderPlan(layerID: 1710, nodes: [.init(
                effect: .init(layerID: 1710, effectIndex: 0, descriptorID: "hidden-definition"),
                definitionPassIndex: 0, materialPassID: "hidden-material#0")])
            let input = "_rt_imageLayerComposite_1720_a"
            var descriptor = SceneRenderDescriptor(layers: [front, hidden, terminal], renderOrderLayerIDs: [1700, 1710, 1720])
            descriptor.materialPasses = [.init(id: "hidden-material#0", materialPath: "materials/hidden.json",
                passIndex: 0, texturePaths: readsBackground ? ["_rt_FullFrameBuffer", input] : [input],
                textureSlots: [readsBackground ? "_rt_FullFrameBuffer" : nil, nil, input], userTextureInputs: [])]
            let candidates = SceneDependencyRenderPlan.potentialNamedBindings(
                descriptor: descriptor, authoredPlans: [graph], visibleLayerIDs: [1700])
            forward.append(["readsBackground": readsBackground, "declaresDependency": declaresDependency,
                "frontProviders": (candidates[1700] ?? []).map(\.providerLayerID),
                "frontForward": (candidates[1700] ?? []).map(\.requiresForwardCapture),
                "frontKinds": (candidates[1700] ?? []).map { String(describing: $0.kind) },
                "hiddenProviders": (candidates[1710] ?? []).map(\.providerLayerID),
                "hiddenKinds": (candidates[1710] ?? []).map { String(describing: $0.kind) }])
        }
        return ["passes": rows, "forward": forward]
    }
}
