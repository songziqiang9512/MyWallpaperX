extension Harness {
    static func multiProviderResults() -> [String: Any] {
        let multiProviderPositivePlan = multiProviderCompositionPlan()
        let multiProviderAuthoredOrderPlan = multiProviderCompositionPlan(
            reverseEffectIDs: true
        )
        let multiProviderMismatchPlan = multiProviderCompositionPlan(
            dependencies: [601]
        )
        let multiProviderDuplicatePlan = multiProviderCompositionPlan(
            duplicateSlot: true
        )
        let multiProviderUnsafePlan = multiProviderCompositionPlan(
            providerChildLayerIDs: [699]
        )
        let multiProviderWrongPassPlan = multiProviderCompositionPlan(
            passIndex: 1
        )
        let multiProviderWrongSlotPlan = multiProviderCompositionPlan(
            slotIndex: 2
        )
        let multiProviderUserTexturePlan = multiProviderCompositionPlan(
            userTexture: true
        )
        let multiProviderExtraPassPlan = multiProviderCompositionPlan(
            extraPass: true
        )
        let multiProviderExtraSlotsPlan = multiProviderCompositionPlan(
            extraSlotCount: 2
        )
        let multiProviderUnknownComboPlan = multiProviderCompositionPlan(
            unknownCombo: true
        )
        let multiProviderMissingProviderOrderPlan =
            multiProviderCompositionPlan(omitRenderOrderID: 601)
        let multiProviderMissingConsumerOrderPlan =
            multiProviderCompositionPlan(omitRenderOrderID: 603)
        let multiProviderInactiveSupersetPlan =
            multiProviderInactiveSupersetCompositionPlan()
        let multiProviderVisibleProviderPlan = multiProviderCompositionPlan(
            providerVisible: true
        )
        let multiProviderVisibleEffectfulProviderPlan =
            multiProviderCompositionPlan(
                providerVisible: true,
                providerEffectful: true,
                providerTexturePaths: ["assets/provider-source.tex"]
            )
        let multiProviderForwardSafeProviderPlan = multiProviderCompositionPlan(
            providerEffectful: true,
            providerTexturePaths: ["assets/noise.tex"],
            providerFirst: false
        )
        let multiProviderForwardUnsafeProviderPlan = multiProviderCompositionPlan(
            providerEffectful: true,
            providerTexturePaths: ["_rt_FullFrameBuffer"],
            providerFirst: false
        )
        let multiProviderForwardVisibleEffectfulGeometryPlan =
            multiProviderCompositionPlan(
                providerVisible: true,
                providerEffectful: true,
                providerTexturePaths: ["assets/provider-source.tex"],
                providerFirst: false,
                geometryProviderID: 601
            )
        let multiProviderGeometryPlan = multiProviderCompositionPlan(
            geometryProviderID: 601
        )
        let nestedGeometryAggregatePlan = nestedGeometryProviderAggregatePlan()
        return [
            "multiProviderCandidate": [
                "candidate": multiProviderPositivePlan
                    .multiProviderCandidateLayerIDs.contains(603),
                "aggregate": multiProviderPositivePlan
                    .multiProviderAggregatesByConsumerLayerID[603]
                    .map { aggregate in
                        let reversed =
                            SceneDependencyRenderPlan.MultiProviderAggregate(
                                consumerLayerID: aggregate.consumerLayerID,
                                bindings: Array(aggregate.bindings.reversed()),
                                authoredSlotOrder: aggregate.authoredSlotOrder
                            )
                        let wrongBlend =
                            SceneDependencyRenderPlan.MultiProviderAggregate(
                                consumerLayerID: aggregate.consumerLayerID,
                                bindings: aggregate.bindings.enumerated().map {
                                    index, binding in
                                    guard index == 0 else { return binding }
                                    return .init(
                                        consumerLayerID: binding.consumerLayerID,
                                        providerLayerID: binding.providerLayerID,
                                        slot: binding.slot,
                                        referenceSlots: binding.referenceSlots,
                                        blendMode: 5,
                                        kind: binding.kind,
                                        requiresForwardCapture:
                                            binding.requiresForwardCapture,
                                        requiresResolvedMaterialProgram:
                                            binding.requiresResolvedMaterialProgram
                                    )
                                },
                                authoredSlotOrder: aggregate.authoredSlotOrder
                            )
                        return [
                            "providers": aggregate.providerLayerIDs.sorted(),
                            "slots": aggregate.referenceSlots.map {
                                "\($0.effectID):\($0.passIndex):\($0.slotIndex)"
                            },
                            "strict": aggregate.hasStrictBindingVector,
                            "reversedStrict": reversed.hasStrictBindingVector,
                            "wrongBlendStrict": wrongBlend.hasStrictBindingVector,
                        ]
                    },
                "authoredOrder": multiProviderAuthoredOrderPlan
                    .multiProviderAggregatesByConsumerLayerID[603]
                    .map { aggregate in
                        [
                            "slots": aggregate.authoredSlotOrder.map {
                                "\($0.effectID):\($0.passIndex):\($0.slotIndex)"
                            },
                            "bindingSlots": aggregate.bindings.map {
                                "\($0.slot.effectID):\($0.slot.passIndex):\($0.slot.slotIndex)"
                            },
                            "strict": aggregate.hasStrictBindingVector,
                            "admitted": aggregate.admits(
                                multiProviderAuthoredOrderPlan.references
                                    .filter { $0.consumerLayerID == 603 }
                            ),
                        ]
                    },
                "aggregateAdmission": multiProviderPositivePlan
                    .multiProviderAggregatesByConsumerLayerID[603]
                    .map { aggregate in
                        let references = multiProviderPositivePlan.references
                            .filter { $0.consumerLayerID == 603 }
                        let missing = Array(references.dropLast())
                        let duplicate = references + [references[0]]
                        let wrongProvider = references.enumerated().map {
                            offset, reference in
                            offset == 0 ? .init(
                                consumerLayerID: reference.consumerLayerID,
                                providerLayerID: 999,
                                slot: reference.slot,
                                variant: reference.variant
                            ) : reference
                        }
                        return [
                            "positive": aggregate.admits(references),
                            "reversed": aggregate.admits(
                                Array(references.reversed())
                            ),
                            "missing": aggregate.admits(missing),
                            "duplicate": aggregate.admits(duplicate),
                            "wrongProvider": aggregate.admits(wrongProvider),
                        ]
                    },
                "binding": multiProviderPositivePlan
                    .bindingsByConsumerLayerID[603] == nil,
                "requiredProviders": multiProviderPositivePlan
                    .requiredProviderLayerIDs.sorted(),
                "requiredEffect": multiProviderPositivePlan
                    .requiredEffectConsumerLayerIDs.contains(603),
            ],
            "multiProviderRejects": [
                "dependencyMismatch": multiProviderMismatchPlan
                    .multiProviderCandidateLayerIDs.contains(603)
                    && multiProviderMismatchPlan
                        .bindingsByConsumerLayerID[603] == nil,
                "duplicateSlot": multiProviderDuplicatePlan
                    .multiProviderCandidateLayerIDs.contains(603)
                    && multiProviderDuplicatePlan
                        .bindingsByConsumerLayerID[603] == nil,
                "unsafeProvider": multiProviderUnsafePlan
                    .multiProviderCandidateLayerIDs.contains(603)
                    && multiProviderUnsafePlan
                        .bindingsByConsumerLayerID[603] == nil,
                "unsafeAggregate": multiProviderUnsafePlan
                    .multiProviderAggregatesByConsumerLayerID[603] == nil,
                "wrongPass": multiProviderWrongPassPlan
                    .multiProviderAggregatesByConsumerLayerID[603] == nil,
                "wrongSlot": multiProviderWrongSlotPlan
                    .multiProviderAggregatesByConsumerLayerID[603] == nil,
                "userTexture": multiProviderUserTexturePlan
                    .multiProviderAggregatesByConsumerLayerID[603] == nil,
                "extraPass": multiProviderExtraPassPlan
                    .multiProviderAggregatesByConsumerLayerID[603] == nil,
                "extraSlots": multiProviderExtraSlotsPlan
                    .multiProviderAggregatesByConsumerLayerID[603] == nil,
                "unknownCombo": multiProviderUnknownComboPlan
                    .multiProviderAggregatesByConsumerLayerID[603] == nil,
                "missingProviderOrder": multiProviderMissingProviderOrderPlan
                    .multiProviderAggregatesByConsumerLayerID[603] == nil,
                "missingConsumerOrder": multiProviderMissingConsumerOrderPlan
                    .multiProviderAggregatesByConsumerLayerID[603] == nil,
                "visibleProvider": multiProviderVisibleProviderPlan
                    .multiProviderAggregatesByConsumerLayerID[603] == nil,
                "visibleEffectfulProvider":
                    multiProviderVisibleEffectfulProviderPlan
                        .multiProviderAggregatesByConsumerLayerID[603] != nil,
                "forwardSafeProvider": multiProviderForwardSafeProviderPlan
                    .multiProviderAggregatesByConsumerLayerID[603] != nil,
                "forwardUnsafeProvider": multiProviderForwardUnsafeProviderPlan
                    .multiProviderAggregatesByConsumerLayerID[603] == nil,
                "forwardVisibleEffectfulGeometryProvider":
                    multiProviderForwardVisibleEffectfulGeometryPlan
                        .multiProviderAggregatesByConsumerLayerID[603] == nil,
            ],
            "multiProviderGeometry": multiProviderGeometryPlan
                .multiProviderAggregatesByConsumerLayerID[603]
                .map { aggregate in
                    [
                        "providers": aggregate.bindings.map(\.providerLayerID),
                        "kinds": aggregate.bindings.map {
                            String(describing: $0.kind)
                        },
                        "slots": aggregate.bindings.map {
                            "\($0.slot.effectID):\($0.slot.passIndex):\($0.slot.slotIndex)"
                        },
                        "strict": aggregate.hasStrictBindingVector,
                        "admitted": aggregate.admits(
                            multiProviderGeometryPlan.references.filter {
                                $0.consumerLayerID == 603
                            }
                        ),
                    ]
                },
            "nestedGeometryAggregate": [
                "nestedBindingKind": nestedGeometryAggregatePlan
                    .bindingsByConsumerLayerID[701]
                    .map { String(describing: $0.kind) } ?? "none",
                "nestedRequiresProgram": nestedGeometryAggregatePlan
                    .bindingsByConsumerLayerID[701]?
                    .requiresResolvedMaterialProgram == true,
                "aggregateProviders": nestedGeometryAggregatePlan
                    .multiProviderAggregatesByConsumerLayerID[703]?
                    .bindings.map(\.providerLayerID) ?? [],
                "aggregateKinds": nestedGeometryAggregatePlan
                    .multiProviderAggregatesByConsumerLayerID[703]?
                    .bindings.map { String(describing: $0.kind) } ?? [],
                "requiredProviders": nestedGeometryAggregatePlan
                    .requiredProviderLayerIDs.sorted(),
                "graphProviders": nestedGeometryAggregatePlan
                    .requiredGraphOutputProviderLayerIDs.sorted(),
                "issues": nestedGeometryAggregatePlan.issues.map {
                    "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
                },
            ],
            "multiProviderInactiveSuperset": [
                "candidate": multiProviderInactiveSupersetPlan
                    .multiProviderCandidateLayerIDs.contains(603),
                "references": multiProviderInactiveSupersetPlan.references
                    .filter { $0.consumerLayerID == 603 }
                    .map { reference in
                        [
                            "provider": reference.providerLayerID,
                            "slot": "\(reference.slot.effectID):\(reference.slot.passIndex):\(reference.slot.slotIndex)",
                        ]
                    },
                "aggregate": multiProviderInactiveSupersetPlan
                    .multiProviderAggregatesByConsumerLayerID[603]
                    .map { aggregate in
                        [
                            "providers": aggregate.providerLayerIDs.sorted(),
                            "strict": aggregate.hasStrictBindingVector,
                            "admitted": aggregate.admits(
                                multiProviderInactiveSupersetPlan.references
                                    .filter { $0.consumerLayerID == 603 }
                            ),
                        ]
                    },
                "requiredProviders": multiProviderInactiveSupersetPlan
                    .requiredProviderLayerIDs.sorted(),
                "declaredProviders": [601, 602, 604],
            ],
        ]
    }

    static func multiProviderCompositionPlan(
        dependencies: [Int] = [601, 602],
        duplicateSlot: Bool = false,
        providerChildLayerIDs: [Int] = [],
        providerVisible: Bool? = false,
        providerEffectful: Bool = false,
        providerTexturePaths: [String] = [],
        providerFirst: Bool = true,
        passIndex: Int = 0,
        slotIndex: Int = 1,
        userTexture: Bool = false,
        extraPass: Bool = false,
        extraSlotCount: Int = 0,
        unknownCombo: Bool = false,
        omitRenderOrderID: Int? = nil,
        reverseEffectIDs: Bool = false,
        geometryProviderID: Int? = nil
    ) -> SceneDependencyRenderPlan {
        func providerEffects(_ id: Int) -> [SceneRenderDescriptor.EffectDescriptor] {
            guard providerEffectful else { return [] }
            return [.init(
                id: "provider-\(id)",
                file: "effects/workshop/unseen/provider/effect.json",
                visible: true,
                passes: providerTexturePaths.isEmpty ? [] : [.init(
                    passIndex: 0,
                    texturePaths: providerTexturePaths,
                    textureSlots: providerTexturePaths.map(Optional.some),
                    userTextureInputs: [],
                    combos: [:],
                    constantShaderValues: [:]
                )]
            )]
        }
        var providerA = SceneRenderDescriptor.Layer(
            id: 601,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: geometryProviderID == 601 ? true : providerVisible,
            effects: providerEffects(601)
        )
        providerA.puppetMeshPath = geometryProviderID == 601
            ? "models/unseen-a.mdl" : nil
        var providerB = SceneRenderDescriptor.Layer(
            id: 602,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: providerChildLayerIDs,
            visible: geometryProviderID == 602 ? true : providerVisible,
            effects: providerEffects(602)
        )
        providerB.puppetMeshPath = geometryProviderID == 602
            ? "models/unseen-b.mdl" : nil
        let pathA = "_rt_imageLayerComposite_601_a"
        let pathB = "_rt_imageLayerComposite_602_a"
        func namedEffect(
            id: String,
            path: String
        ) -> SceneRenderDescriptor.EffectDescriptor {
            let authoredSlotCount = max(2, slotIndex + 1)
            var authoredSlots = Array<String?>(
                repeating: nil,
                count: authoredSlotCount
            )
            authoredSlots[slotIndex] = path
            authoredSlots.append(contentsOf: Array(
                repeating: nil,
                count: max(0, extraSlotCount)
            ))
            var userTextureInputs: [SceneEffectTextureInput?] = []
            if userTexture {
                userTextureInputs = Array(
                    repeating: nil,
                    count: authoredSlots.count
                )
                userTextureInputs[0] = .init(kind: .path, value: "override")
            }
            var combos = ["BLENDMODE": 0]
            if unknownCombo {
                combos["UNSAFE_COMBO"] = 1
            }
            let primaryPass = SceneRenderDescriptor.EffectDescriptor
                .PassDescriptor(
                    passIndex: passIndex,
                    texturePaths: authoredSlots.compactMap { $0 },
                    textureSlots: authoredSlots,
                    userTextureInputs: userTextureInputs,
                    combos: combos,
                    constantShaderValues: [:]
                )
            var passes = [primaryPass]
            if extraPass {
                passes.append(.init(
                    passIndex: passIndex + 1,
                    texturePaths: [],
                    textureSlots: [],
                    userTextureInputs: [],
                    combos: [:],
                    constantShaderValues: [:]
                ))
            }
            return .init(
                id: id,
                file: "effects/workshop/unseen/multi/effect.json",
                visible: true,
                passes: passes
            )
        }
        let consumer = SceneRenderDescriptor.Layer(
            id: 603,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: dependencies,
            childLayerIDs: [],
            visible: true,
            effects: [
                namedEffect(
                    id: duplicateSlot
                        ? "same"
                        : (reverseEffectIDs ? "z-authored-first" : "first"),
                    path: pathA
                ),
                namedEffect(
                    id: duplicateSlot
                        ? "same"
                        : (reverseEffectIDs ? "a-authored-second" : "second"),
                    path: pathB
                ),
            ]
        )
        return SceneDependencyRenderPlan(
            descriptor: .init(
                layers: [providerA, providerB, consumer],
                renderOrderLayerIDs: (providerFirst
                    ? [601, 602, 603] : [603, 601, 602]).filter {
                    $0 != omitRenderOrderID
                }
            ),
            visibleLayerIDs: Set(
                (providerVisible == true ? [601, 602, 603] : [603])
                    + (geometryProviderID.map { [$0] } ?? [])
            ),
            executableUtilityConsumerLayerIDs: [603]
        )
    }

    /// Unseen topology regression for the real failure shape: a composition
    /// aggregate consumes a hidden Puppet graph provider, and that provider
    /// itself samples one visible Puppet publication. The flat image route
    /// remains rejected; both geometry edges must acquire typed ownership.

    static func nestedGeometryProviderAggregatePlan()
        -> SceneDependencyRenderPlan {
        func namedEffect(
            id: String,
            providerID: Int,
            trailingHole: Bool
        ) -> SceneRenderDescriptor.EffectDescriptor {
            let path = "_rt_imageLayerComposite_\(providerID)_a"
            return .init(
                id: id,
                file: "effects/workshop/unseen/nested/effect.json",
                visible: true,
                passes: [.init(
                    passIndex: 0,
                    texturePaths: [path],
                    textureSlots: trailingHole
                        ? [nil, path, nil] : [nil, path],
                    userTextureInputs: [],
                    combos: trailingHole ? [:] : ["BLENDMODE": 0],
                    constantShaderValues: [:]
                )]
            )
        }
        var rootGeometry = SceneRenderDescriptor.Layer(
            id: 700,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: true,
            effects: [.init(
                id: "root-geometry-effect",
                file: "effects/workshop/unseen/root/effect.json",
                visible: true,
                passes: []
            )]
        )
        rootGeometry.puppetMeshPath = "models/unseen-root.mdl"
        var nestedGeometry = SceneRenderDescriptor.Layer(
            id: 701,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [700],
            childLayerIDs: [],
            visible: false,
            effects: [namedEffect(
                id: "nested-geometry",
                providerID: 700,
                trailingHole: true
            )]
        )
        nestedGeometry.puppetMeshPath = "models/unseen-nested.mdl"
        let flatProvider = SceneRenderDescriptor.Layer(
            id: 702,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: false,
            effects: []
        )
        let aggregate = SceneRenderDescriptor.Layer(
            id: 703,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [702, 701],
            childLayerIDs: [],
            visible: true,
            effects: [
                namedEffect(
                    id: "flat-first",
                    providerID: 702,
                    trailingHole: false
                ),
                namedEffect(
                    id: "geometry-second",
                    providerID: 701,
                    trailingHole: true
                ),
            ]
        )
        let descriptor = SceneRenderDescriptor(
            layers: [rootGeometry, flatProvider, nestedGeometry, aggregate],
            renderOrderLayerIDs: [700, 702, 701, 703]
        )
        return SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: [700, 703],
            executableUtilityConsumerLayerIDs: [703],
            admittedResolvedMaterialReferences: Set(
                SceneDependencyGraphAnalysis.references(in: descriptor.layers)
            )
        )
    }

    /// Regression fixture for the authored declaration superset contract:
    /// provider 604 is named only by an inactive effect, while the active
    /// graph consumes providers 601 and 602. The aggregate must admit the
    /// active vector and still require the full declaration to be known.

    static func multiProviderInactiveSupersetCompositionPlan()
        -> SceneDependencyRenderPlan {
        func namedEffect(
            id: String,
            path: String,
            visible: Bool
        ) -> SceneRenderDescriptor.EffectDescriptor {
            .init(
                id: id,
                file: "effects/workshop/unseen/multi/effect.json",
                visible: visible,
                passes: [.init(
                    passIndex: 0,
                    texturePaths: [path],
                    textureSlots: [nil, path],
                    userTextureInputs: [],
                    combos: ["BLENDMODE": 0],
                    constantShaderValues: [:]
                )]
            )
        }
        let providers = [601, 602, 604].map { providerID in
            SceneRenderDescriptor.Layer(
                id: providerID,
                contentKind: "image",
                utilityLayer: nil,
                dependencyLayerIDs: [],
                childLayerIDs: [],
                visible: false,
                effects: []
            )
        }
        let consumer = SceneRenderDescriptor.Layer(
            id: 603,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [601, 602, 604],
            childLayerIDs: [],
            visible: true,
            effects: [
                namedEffect(
                    id: "first",
                    path: "_rt_imageLayerComposite_601_a",
                    visible: true
                ),
                namedEffect(
                    id: "second",
                    path: "_rt_imageLayerComposite_602_a",
                    visible: true
                ),
                namedEffect(
                    id: "inactive",
                    path: "_rt_imageLayerComposite_604_a",
                    visible: false
                ),
            ]
        )
        return SceneDependencyRenderPlan(
            descriptor: .init(
                layers: providers + [consumer],
                renderOrderLayerIDs: [601, 602, 604, 603]
            ),
            visibleLayerIDs: [603],
            executableUtilityConsumerLayerIDs: [603]
        )
    }
}
