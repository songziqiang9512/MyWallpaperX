extension Harness {
    static func namedUtilityResults() -> [String: Any] {
        let provider = layer(1, kind: .composition, visible: false)
        let visibleConsumer = consumer(2, provider: 1, dependencies: [])
        let hiddenConsumer = consumer(3, provider: 1, visible: false)
        let cycleA = layer(4, kind: .composition, dependencies: [5])
        let cycleB = layer(5, kind: .composition, dependencies: [4])
        let forwardConsumer = consumer(6, provider: 7)
        let forwardProvider = layer(7, kind: .composition)
        let partialConsumer = consumer(8, provider: 1, extraEffect: true)
        let neutralOpacityConsumer = consumer(9, provider: 1, opacity: 1)
        let nonNeutralOpacityConsumer = consumer(10, provider: 1, opacity: 0.5)
        let userTextureOverrideConsumer = consumer(
            33,
            provider: 1,
            opacity: 0.5,
            userTextureOverride: true
        )
        let textMaskProvider = SceneRenderDescriptor.Layer(
            id: 34,
            contentKind: "text",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: true,
            effects: []
        )
        let textMaskConsumer = SceneRenderDescriptor.Layer(
            id: 35,
            contentKind: "text",
            utilityLayer: nil,
            dependencyLayerIDs: [34],
            childLayerIDs: [],
            visible: true,
            effects: [effect(id: 35, provider: 34, opacity: 1)]
        )
        let effectfulTextProvider = SceneRenderDescriptor.Layer(
            id: 36,
            contentKind: "text",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: true,
            effects: [.init(
                id: "effect-36",
                file: "effects/tint/effect.json",
                visible: true,
                passes: []
            )]
        )
        let effectfulTextMaskConsumer = SceneRenderDescriptor.Layer(
            id: 37,
            contentKind: "text",
            utilityLayer: nil,
            dependencyLayerIDs: [36],
            childLayerIDs: [],
            visible: true,
            effects: [effect(id: 37, provider: 36, opacity: 1)]
        )
        let alternateEffectConsumer = consumer(
            11,
            provider: 1,
            effectPath: "effects/blend/effect.json"
        )
        let alternatePathConsumer = consumer(
            16,
            provider: 1,
            effectPath: "effects/workshop/other/clipping_mask/effect.json"
        )
        let supportedGradientConsumer = gradientConsumer(12, provider: 1)
        let reversedGradientConsumer = gradientConsumer(13, provider: 1, reversed: true)
        let invalidGradientConsumer = gradientConsumer(14, provider: 1, axis: 2)
        let utilityConsumer = SceneRenderDescriptor.Layer(
            id: 15,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [1],
            childLayerIDs: [],
            visible: true,
            effects: [effect(id: 15, provider: 1)]
        )
        let projectUtilityConsumer = SceneRenderDescriptor.Layer(
            id: 17,
            contentKind: "project",
            utilityLayer: .init(kind: .project),
            dependencyLayerIDs: [1],
            childLayerIDs: [],
            visible: true,
            effects: [effect(id: 17, provider: 1)]
        )
        let childUtilityConsumer = SceneRenderDescriptor.Layer(
            id: 18,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [1],
            childLayerIDs: [99],
            visible: true,
            effects: [effect(id: 18, provider: 1)]
        )
        let extraDependencyUtilityConsumer = SceneRenderDescriptor.Layer(
            id: 19,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [1, 7],
            childLayerIDs: [],
            visible: true,
            effects: [effect(id: 19, provider: 1)]
        )
        let solidCarrierProvider = SceneRenderDescriptor.Layer(
            id: 30,
            contentKind: "solid",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: false,
            effects: []
        )
        let solidCarrierConsumer = SceneRenderDescriptor.Layer(
            id: 31,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [30],
            childLayerIDs: [],
            visible: true,
            effects: [slot3SolidCarrierEffect(id: 31, provider: 30)]
        )
        let missingProviderConsumer = consumer(32, provider: 999)
        let secondaryConsumer = consumer(33, provider: 1, variantSuffix: "b")
        let secondaryDescriptor = SceneRenderDescriptor(
            layers: [provider, secondaryConsumer],
            renderOrderLayerIDs: [1, 33]
        )
        let secondaryPlan = SceneDependencyRenderPlan(
            descriptor: secondaryDescriptor,
            visibleLayerIDs: [1, 33]
        )
        let routeProvider = layer(400, kind: .composition, visible: false)
        let routeConsumer = consumer(401, provider: 400)
        let routePlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: [routeProvider, routeConsumer],
                renderOrderLayerIDs: [routeProvider.id, routeConsumer.id]
            ),
            visibleLayerIDs: [routeProvider.id, routeConsumer.id]
        )
        let routeUtilityProvider = layer(410, kind: .composition, visible: false)
        let routeUtilityConsumer = SceneRenderDescriptor.Layer(
            id: 411,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [routeUtilityProvider.id],
            childLayerIDs: [],
            visible: true,
            effects: [effect(id: 411, provider: routeUtilityProvider.id)]
        )
        let routeUtilityPlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: [routeUtilityProvider, routeUtilityConsumer],
                renderOrderLayerIDs: [routeUtilityProvider.id, routeUtilityConsumer.id]
            ),
            visibleLayerIDs: [routeUtilityProvider.id, routeUtilityConsumer.id]
        )
        let descriptor = SceneRenderDescriptor(
            layers: [
                provider, visibleConsumer, hiddenConsumer,
                cycleA, cycleB, forwardConsumer, forwardProvider, partialConsumer,
                neutralOpacityConsumer, nonNeutralOpacityConsumer,
                userTextureOverrideConsumer, textMaskProvider, textMaskConsumer,
                effectfulTextProvider, effectfulTextMaskConsumer,
                alternateEffectConsumer,
                supportedGradientConsumer, reversedGradientConsumer, invalidGradientConsumer,
                utilityConsumer, alternatePathConsumer, projectUtilityConsumer,
                childUtilityConsumer, extraDependencyUtilityConsumer,
                solidCarrierProvider, solidCarrierConsumer, missingProviderConsumer,
            ],
            renderOrderLayerIDs: [
                1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
                30, 31, 32, 33, 34, 35, 36, 37,
            ]
        )
        let visibleLayerIDs: Set<Int> = [
            1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 31, 32,
            33, 34, 35, 36, 37,
        ]
        let plan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: visibleLayerIDs,
            executableUtilityConsumerLayerIDs: [15, 31],
            admittedResolvedMaterialReferences: Set(
                SceneDependencyGraphAnalysis.references(in: descriptor.layers)
            )
        )
        let defaultPlan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: visibleLayerIDs
        )
        let matrixProviders = (10...15).map { layer($0, kind: .composition) }
        let matrixProviderIDs = [10, 10, 10, 11, 12, 13, 14, 15]
        let matrixConsumers = matrixProviderIDs.enumerated().map { offset, providerID in
            consumer(20 + offset, provider: providerID, visible: offset != 2)
        }
        let matrixLayers = matrixProviders + matrixConsumers
        let matrixDescriptor = SceneRenderDescriptor(
            layers: matrixLayers,
            renderOrderLayerIDs: matrixLayers.map(\.id)
        )
        let matrixVisible = Set(matrixLayers.compactMap {
            $0.visible == false ? nil : $0.id
        })
        let matrixPlan = SceneDependencyRenderPlan(
            descriptor: matrixDescriptor,
            visibleLayerIDs: matrixVisible
        )
        let parsed = [
            SceneNamedTextureReference.parse("_rt_imageLayerComposite_42")?.variant.rawValue ?? "nil",
            SceneNamedTextureReference.parse("_rt_imageLayerComposite_42_a")?.variant.rawValue ?? "nil",
            SceneNamedTextureReference.parse("_rt_imageLayerComposite_42_b")?.variant.rawValue ?? "nil",
        ]
        let solidCarrier = plan.bindingsByConsumerLayerID[31]
        let materialProgramSolidCarrier = materialProgramSolidCarrierBinding()
        return [
            "utilitySelection": utilitySelection(),
            "preparedUtility": preparedUtilityResults(),
            "independentNamedSources": independentNamedSourceResults(),
            "parsedVariants": parsed,
            "invalidReference": SceneNamedTextureReference.parse("_rt_imageLayerComposite_bad_a") == nil,
            "referenceCount": plan.references.count,
            "namedConsumers": plan.namedReferenceConsumerLayerIDs.sorted(),
            "textMaskRoute": plan.bindingsByConsumerLayerID[35].map {
                [
                    "kind": "\($0.kind)",
                    "provider": $0.providerLayerID,
                    "slot": $0.slot.slotIndex,
                    "requiresProgram": $0.requiresResolvedMaterialProgram,
                ]
            },
            "effectfulTextMaskBinding": plan.bindingsByConsumerLayerID[37] != nil,
            "executableUtilityConsumers": plan.executableUtilityConsumerLayerIDs.sorted(),
            "requiredEffectConsumers": plan.requiredEffectConsumerLayerIDs.sorted(),
            "bindingConsumers": plan.bindingsByConsumerLayerID.keys.sorted(),
            "defaultUtilityBinding": defaultPlan.bindingsByConsumerLayerID[15] != nil,
            "requiredProviders": plan.requiredProviderLayerIDs.sorted(),
            "cycles": plan.cyclicLayerIDs.sorted(),
            "issues": plan.issues.map { "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)" },
            "secondaryBinding": secondaryPlan.bindingsByConsumerLayerID[33] != nil,
            "secondaryIssues": secondaryPlan.issues.map {
                "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
            },
            "resolvedMaterialRoute": [
                "binding": routePlan.bindingsByConsumerLayerID[routeConsumer.id] != nil,
                "resolvedMaterial": routePlan.bindingsByConsumerLayerID[routeConsumer.id]?.kind
                    == .resolvedMaterial,
                "requiredEffect": routePlan.requiredEffectConsumerLayerIDs
                    .contains(routeConsumer.id),
                "requiredProviders": routePlan.requiredProviderLayerIDs.sorted(),
                "issues": routePlan.issues.map {
                    "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
                },
            ],
            "resolvedMaterialUtilityRoute": [
                "binding": routeUtilityPlan.bindingsByConsumerLayerID[
                    routeUtilityConsumer.id
                ] != nil,
                "requiredEffect": routeUtilityPlan.requiredEffectConsumerLayerIDs
                    .contains(routeUtilityConsumer.id),
                "requiredProviders": routeUtilityPlan.requiredProviderLayerIDs.sorted(),
                "issues": routeUtilityPlan.issues.map {
                    "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
                },
            ],
            "matrixBindingCount": matrixPlan.bindingsByConsumerLayerID.count,
            "matrixRequiredProviders": matrixPlan.requiredProviderLayerIDs.sorted(),
            "solidCarrierBinding": [
                "consumer": solidCarrier?.consumerLayerID ?? -1,
                "provider": solidCarrier?.providerLayerID ?? -1,
                "effect": solidCarrier?.slot.effectID ?? "",
                "pass": solidCarrier?.slot.passIndex ?? -1,
                "slot": solidCarrier?.slot.slotIndex ?? -1,
                "blend": solidCarrier?.blendMode ?? -1,
                "solid": solidCarrier?.kind == .solidLayer,
            ],
            "solidCarrierRoute": [
                "binding": solidCarrier != nil,
                "solid": solidCarrier?.kind == .solidLayer,
                "requiredEffect": plan.requiredEffectConsumerLayerIDs.contains(31),
                "requiredProvider": plan.requiredProviderLayerIDs.contains(30),
                "issues": plan.issues.filter { $0.layerID == 31 }.map {
                    "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
                },
            ],
            "solidCarrierWithoutExecutableID": [
                "binding": defaultPlan.bindingsByConsumerLayerID[31] != nil,
                "requiredEffect": defaultPlan.requiredEffectConsumerLayerIDs.contains(31),
                "requiredProvider": defaultPlan.requiredProviderLayerIDs.contains(30),
                "issues": defaultPlan.issues.filter { $0.layerID == 31 }.map {
                    "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)"
                },
            ],
            "solidCarrierGeneralizesAuthoredShaderShape":
                solidCarrierBinding(
                    effectPath: "effects/workshop/unseen/volumetric_cloud/effect.json",
                    extraCombos: ["AB_TYPECOLOR": 27, "UNSEEN_COMBO": 9],
                    constantShaderValues: [
                        "Unseen Constant": .init(components: [0.125, 4]),
                    ]
                )?.kind == .solidLayer,
            "solidCarrierRejects": [
                "visibleProvider": solidCarrierBinding(providerVisible: true) == nil,
                "wrongProviderKind": solidCarrierBinding(providerContentKind: "image") == nil,
                "providerUtility": solidCarrierBinding(providerUtility: true) == nil,
                "effectfulProvider": solidCarrierBinding(providerEffectful: true) == nil,
                "secondary": solidCarrierBinding(variantSuffix: "b") == nil,
                "wrongPass": solidCarrierBinding(passIndex: 1) == nil,
                "wrongSlot": solidCarrierBinding(slotIndex: 2) == nil,
                "userTextureOverride": solidCarrierBinding(userTextureOverride: true) == nil,
                "extraPass": solidCarrierBinding(extraPass: true) == nil,
                "extraReference": solidCarrierBinding(extraReference: true) == nil,
                "forwardProvider": solidCarrierBinding(providerFirst: false) == nil,
                "cycle": solidCarrierBinding(providerDependencies: [91]) == nil,
            ],
            "materialProgramSolidCarrier": [
                "provider": materialProgramSolidCarrier?.providerLayerID ?? -1,
                "slot": materialProgramSolidCarrier?.slot.slotIndex ?? -1,
                "solid": materialProgramSolidCarrier?.kind == .solidLayer,
                "requiresProgram": materialProgramSolidCarrier?
                    .requiresResolvedMaterialProgram ?? false,
                "forward": materialProgramSolidCarrier?
                    .requiresForwardCapture ?? false,
            ],
            "materialProgramSolidCarrierRejects": [
                "unadmitted": materialProgramSolidCarrierBinding(
                    admitProgram: false
                ) == nil,
                "plainProvider": materialProgramSolidCarrierBinding(
                    providerEffectful: false
                ) == nil,
                "providerDependency": materialProgramSolidCarrierBinding(
                    providerDependencies: [92]
                ) == nil,
                "providerChild": materialProgramSolidCarrierBinding(
                    providerChildLayerIDs: [92]
                ) == nil,
                "secondary": materialProgramSolidCarrierBinding(
                    variantSuffix: "b"
                ) == nil,
                "wrongSlot": materialProgramSolidCarrierBinding(
                    slotIndex: 0
                ) == nil,
                "forwardProvider": materialProgramSolidCarrierBinding(
                    providerFirst: false
                ) == nil,
            ],
            "materialProgramSolidCarrierExtraAsset": materialProgramSolidCarrierBinding(
                extraTexture: true
            )?.requiresResolvedMaterialProgram == true,
        ]
    }

    static func independentNamedSourceResults() -> [String: Any] {
        func readEffect(_ id: String, provider: Int, pass: Int = 0, slot: Int = 2)
            -> SceneRenderDescriptor.EffectDescriptor {
            let path = "_rt_imageLayerComposite_\(provider)_a"
            var slots = [String?](repeating: nil, count: slot + 1)
            slots[slot] = path
            return .init(id: id, file: "effects/controlled/\(id)/effect.json", visible: true,
                passes: [.init(passIndex: pass, texturePaths: [path], textureSlots: slots,
                    combos: [:], constantShaderValues: [:])])
        }
        func observe(_ descriptor: SceneRenderDescriptor, consumer: Int, provider: Int)
            -> [String: Any] {
            let visible = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
            let candidates = SceneDependencyRenderPlan.potentialNamedBindings(
                descriptor: descriptor, visibleLayerIDs: visible)[consumer] ?? []
            // The CPU seam selects this authored read; Program/sampler execution
            // and transparent-source pixels remain the real rendering gate's job.
            let plan = SceneDependencyRenderPlan(descriptor: descriptor,
                visibleLayerIDs: visible,
                preparedNamedInputBindingsByConsumerLayerID: [consumer: candidates])
            let binding = plan.bindingsByConsumerLayerID[consumer]
            let inputs: [SceneDependencyRenderPlan.Binding] = binding.map { [$0] } ?? []
            let unused = SceneDependencyRenderPlan(descriptor: descriptor,
                visibleLayerIDs: visible,
                preparedNamedInputBindingsByConsumerLayerID: [consumer: []])
            let utilities = SceneUtilityLayerRuntimePlanner.plans(in: descriptor,
                dependencyPlan: plan, resolvedMaterialLayerIDs: [])
            let noDemand: [String: Any] = [
                "providers": unused.requiredProviderLayerIDs.sorted(),
                "prepass": unused.sourcePreparationPlan(
                    authoredLayerIDs: descriptor.renderOrderLayerIDs,
                    availableExecutionLayerIDs: [consumer], visibleRootLayerIDs: visible,
                    activeStaticModelConsumerLayerIDs: [], sourceAfterLayerIDByLayerID: [:])?.preparationSchedule()
                    .prepassProviderLayerIDs ?? [-1],
                "requiresEffect": unused.requiredEffectConsumerLayerIDs.contains(consumer),
                "references": unused.references.filter { $0.consumerLayerID == consumer }.count,
            ]
            var result: [String: Any] = [:]
            result["candidates"] = candidates.map {
                "\($0.slot.effectID):\($0.slot.passIndex):\($0.slot.slotIndex)=\($0.providerLayerID)"
            }
            result["bindings"] = inputs.map {
                "\($0.slot.effectID):\($0.slot.passIndex):\($0.slot.slotIndex)=\($0.providerLayerID)"
            }
            result["kinds"] = inputs.map { String(describing: $0.kind) }
            result["forward"] = inputs.map(\.requiresForwardCapture)
            result["providers"] = plan.requiredProviderLayerIDs.sorted()
            result["graphProviders"] = plan.requiredGraphOutputProviderLayerIDs.sorted()
            result["prepass"] = plan.sourcePreparationPlan(
                authoredLayerIDs: descriptor.renderOrderLayerIDs,
                availableExecutionLayerIDs: plan.requiredGraphOutputProviderLayerIDs.union([consumer]),
                visibleRootLayerIDs: visible, activeStaticModelConsumerLayerIDs: [],
                sourceAfterLayerIDByLayerID: [:])?.preparationSchedule().prepassProviderLayerIDs ?? [-1]
            result["utilityCaptures"] = utilities.values.filter(\.shouldCapture).map(\.layerID).sorted()
            result["providerDisposition"] = utilities[provider]?.disposition.rawValue ?? "none"
            result["noDemand"] = noDemand
            return result
        }
        var emptySource = SceneUtilityLayer(kind: .composition)
        emptySource.copyBackground = false
        let parent = SceneRenderDescriptor.Layer(id: 110, contentKind: "composition",
            utilityLayer: .init(kind: .composition), dependencyLayerIDs: [120],
            childLayerIDs: [120], visible: true,
            effects: [readEffect("member-read", provider: 120, slot: 1)])
        var child = SceneRenderDescriptor.Layer(id: 120, contentKind: "composition",
            utilityLayer: emptySource, dependencyLayerIDs: [], childLayerIDs: [],
            visible: true, effects: [])
        child.parentID = parent.id
        let member = observe(.init(layers: [parent, child], renderOrderLayerIDs: [110, 120]),
            consumer: 110, provider: 120)

        let solid = SceneRenderDescriptor.Layer(id: 210, contentKind: "solid", utilityLayer: nil,
            dependencyLayerIDs: [], childLayerIDs: [], visible: false, effects: [])
        let solidConsumer = SceneRenderDescriptor.Layer(id: 220, contentKind: "image", utilityLayer: nil,
            dependencyLayerIDs: [210], childLayerIDs: [], visible: true,
            effects: [readEffect("source-read", provider: 210)])
        let before = observe(.init(layers: [solid, solidConsumer], renderOrderLayerIDs: [210, 220]),
            consumer: 220, provider: 210)
        let after = observe(.init(layers: [solid, solidConsumer], renderOrderLayerIDs: [220, 210]),
            consumer: 220, provider: 210)
        let renamedSolid = SceneRenderDescriptor.Layer(id: 330, contentKind: "solid", utilityLayer: nil,
            dependencyLayerIDs: [], childLayerIDs: [], visible: false, effects: [])
        let renamedConsumer = SceneRenderDescriptor.Layer(id: 340, contentKind: "image", utilityLayer: nil,
            dependencyLayerIDs: [330], childLayerIDs: [], visible: true,
            effects: [readEffect("renamed-read", provider: 330, pass: 1, slot: 5)])
        let renamed = observe(.init(layers: [renamedConsumer, renamedSolid],
            renderOrderLayerIDs: [340, 330]), consumer: 340, provider: 330)

        let prefixConsumer = consumer(420, provider: 410)
        let prefix = layer(410, kind: .composition, visible: false)
        let backgroundGraph = SceneRenderDescriptor.Layer(id: 410, contentKind: "image",
            utilityLayer: nil, dependencyLayerIDs: [], childLayerIDs: [], visible: false,
            effects: [.init(id: "background-read", file: "effects/controlled/background/effect.json",
                visible: true, passes: [.init(passIndex: 0,
                    texturePaths: ["_rt_FullFrameBuffer"], textureSlots: ["_rt_FullFrameBuffer"],
                    combos: [:], constantShaderValues: [:])])])
        var negatives: [String: [String: [Int]]] = [:]
        for (name, provider) in [("copyBackgroundPrefix", prefix), ("effectfulMainBackground", backgroundGraph)] {
            let descriptor = SceneRenderDescriptor(layers: [prefixConsumer, provider],
                renderOrderLayerIDs: [420, 410])
            let forward = SceneDependencyRenderPlan.potentialNamedBindings(
                descriptor: descriptor, visibleLayerIDs: [420])[420]?.map(\.providerLayerID) ?? []
            let beforeDescriptor = SceneRenderDescriptor(layers: descriptor.layers,
                renderOrderLayerIDs: [410, 420])
            let before = SceneDependencyRenderPlan.potentialNamedBindings(
                descriptor: beforeDescriptor, visibleLayerIDs: [420])[420]?.map(\.providerLayerID) ?? []
            negatives[name] = ["before": before, "forward": forward]
        }
        return ["member": member, "solidBefore": before, "solidAfter": after,
            "renamed": renamed, "negativeCandidates": negatives]
    }

    static func preparedUtilityResults() -> [String: Any] {
        func descriptor(hidden: Bool = false, graphProvider: Bool = false) -> SceneRenderDescriptor {
            let consumer = SceneRenderDescriptor.Layer(
                id: 950, contentKind: "composition",
                utilityLayer: .init(kind: .composition), dependencyLayerIDs: [951, 952],
                childLayerIDs: [], visible: !hidden,
                effects: [951, 952].map { provider in
                    let path = "_rt_imageLayerComposite_\(provider)_a"
                    return .init(id: "prepared-\(provider)", file: "effects/unseen/program/effect.json",
                        visible: true, passes: [.init(passIndex: 0, texturePaths: [path],
                            textureSlots: [nil, path], combos: ["BLENDMODE": 0], constantShaderValues: [:])])
                }
            )
            let firstProvider = graphProvider ? SceneRenderDescriptor.Layer(
                id: 951, contentKind: "image", utilityLayer: nil, dependencyLayerIDs: [],
                childLayerIDs: [], visible: true,
                effects: [.init(id: "provider-effect", file: "effects/unseen/tint.json", visible: true, passes: [])]
            ) : layer(951, visible: false)
            return .init(layers: [firstProvider, layer(952, visible: false), consumer],
                renderOrderLayerIDs: [951, 952, 950])
        }
        let input = descriptor()
        let prepared = SceneDependencyRenderPlan(descriptor: input, visibleLayerIDs: [950],
            executableUtilityConsumerLayerIDs: [950])
        let emptyDescriptor = SceneRenderDescriptor(layers: [], renderOrderLayerIDs: [])
        let emptyPlan = SceneDependencyRenderPlan(descriptor: emptyDescriptor, visibleLayerIDs: [])
        func disposition(_ descriptor: SceneRenderDescriptor, _ plan: SceneDependencyRenderPlan,
                         resolved: Set<Int> = [950]) -> String {
            SceneUtilityLayerRuntimePlanner.plans(in: descriptor, dependencyPlan: plan,
                resolvedMaterialLayerIDs: resolved)[950]!.disposition.rawValue
        }
        let selected = SceneUtilityLayerRuntimePlanner.plans(in: input, dependencyPlan: prepared,
            resolvedMaterialLayerIDs: [950])
        let captures = Set(selected.values.filter(\.shouldCapture).map(\.layerID))
        func readable(_ descriptor: SceneRenderDescriptor = emptyDescriptor,
                      background: Set<Int> = [], capture: Set<Int> = [],
                      plan: SceneDependencyRenderPlan = emptyPlan) -> Bool {
            descriptor.requiresReadableFramebuffer(sceneBackgroundLayerIDs: background,
                utilityCaptureLayerIDs: capture, dependencyPlan: plan)
        }
        let expandedInput = descriptor(graphProvider: true)
        let restrictedPlan = SceneDependencyRenderPlan(descriptor: expandedInput,
            visibleLayerIDs: [950], executableUtilityConsumerLayerIDs: [950])
        let expandedPlan = SceneDependencyRenderPlan(descriptor: expandedInput,
            visibleLayerIDs: [950, 951], executableUtilityConsumerLayerIDs: [950])
        var blend = layer(953)
        blend.colorBlendMode = 5
        var refract = emptyDescriptor
        refract.materialPasses = [.init(combos: ["REFRACT": 1], materialPath: "self-owned", passIndex: 0,
            texturePaths: [], textureSlots: [], userTextureInputs: [])]
        return [
            "restrictedRoots": disposition(expandedInput, restrictedPlan),
            "expandedRoots": disposition(expandedInput, expandedPlan),
            "hiddenExpandedRoots": disposition(descriptor(hidden: true, graphProvider: true), expandedPlan),
            "restrictedFramebuffer": readable(expandedInput, plan: restrictedPlan),
            "expandedFramebuffer": readable(expandedInput, plan: expandedPlan),
            "capture": disposition(input, prepared),
            "missingBinding": disposition(input, emptyPlan),
            "unadmitted": disposition(input, prepared, resolved: []),
            // Retain the capture route; the frame's active closure gates encoding.
            "hidden": disposition(descriptor(hidden: true), prepared),
            "convenience": SceneUtilityLayerRuntimePlanner.plans(in: input,
                resolvedMaterialLayerIDs: [950])[950]!.disposition.rawValue,
            "captures": captures.sorted(),
            "framebufferEmpty": readable(),
            "framebufferPreparedProvider": readable(input, plan: prepared),
            "framebufferNoPreparedProvider": readable(input),
            "framebufferCapture": readable(capture: captures),
            "framebufferBackground": readable(background: [1]),
            "framebufferRefraction": readable(refract),
            "framebufferBlend": readable(.init(layers: [blend], renderOrderLayerIDs: [953])),
        ]
    }

    static func utilitySelection() -> [Int] {
        let provider = layer(900, visible: false)
        let layers: [SceneRenderDescriptor.Layer] = [provider] + (901...907).map { id in
            .init(
                id: id,
                contentKind: id == 906 ? "image" : "composition",
                utilityLayer: .init(kind: .composition),
                dependencyLayerIDs: id == 902 ? [900, 908] : [900],
                childLayerIDs: id == 905 ? [909] : [],
                visible: id == 903 ? false : true,
                effects: id == 907 ? [] : [effect(id: id, provider: 900)]
                    + (id == 902 ? [effect(id: 1902, provider: 908)] : [])
            )
        }
        let descriptor = SceneRenderDescriptor(
            layers: layers + [layer(908, visible: false)],
            renderOrderLayerIDs: layers.map(\.id) + [908]
        )
        return SceneUtilityLayerRuntimePlanner.executableUtilityConsumerLayerIDs(
            in: descriptor, resolvedMaterialLayerIDs: [901, 902, 903, 905, 906, 907]
        ).sorted()
    }

    static func slot3SolidCarrierEffect(
        id: Int,
        provider: Int,
        effectPath: String = "effects/workshop/2924967132/procedural_noise/effect.json",
        passIndex: Int = 0,
        slotIndex: Int = 3,
        variantSuffix: String = "a",
        extraCombos: [String: Int] = [:],
        constantShaderValues: [String: SceneDocument.ShaderValue] = [:],
        userTextureOverride: Bool = false,
        extraPass: Bool = false,
        extraReference: Bool = false
    ) -> SceneRenderDescriptor.EffectDescriptor {
        let path = "_rt_imageLayerComposite_\(provider)_\(variantSuffix)"
        var slots = Array<String?>(repeating: nil, count: 4)
        slots[slotIndex] = path
        if extraReference {
            slots[1] = "_rt_imageLayerComposite_\(provider)_a"
        }
        var combos = [
            "AB_TYPECOLOR": 3,
            "PERSPSWITCH": 1,
            "WRITEALPHA": 1,
        ]
        combos.merge(extraCombos) { _, new in new }
        let mainPass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: passIndex,
            texturePaths: extraReference
                ? [path, "_rt_imageLayerComposite_\(provider)_a"] : [path],
            textureSlots: slots,
            userTextureInputs: userTextureOverride ? [
                nil, nil, nil,
                .init(kind: .property, value: "userTexture"),
            ] : [],
            combos: combos,
            constantShaderValues: constantShaderValues
        )
        let passes: [SceneRenderDescriptor.EffectDescriptor.PassDescriptor]
        if extraPass {
            passes = [
                mainPass,
                .init(
                    passIndex: 1,
                    textureSlots: [],
                    combos: [:],
                    constantShaderValues: [:]
                ),
            ]
        } else {
            passes = [mainPass]
        }
        return .init(
            id: "\(id)#effect#slot3-solid",
            file: effectPath,
            visible: true,
            passes: passes
        )
    }

    static func solidCarrierBinding(
        providerVisible: Bool? = false,
        providerContentKind: String = "solid",
        providerUtility: Bool = false,
        providerEffectful: Bool = false,
        providerDependencies: [Int] = [],
        providerFirst: Bool = true,
        effectPath: String = "effects/workshop/2924967132/procedural_noise/effect.json",
        passIndex: Int = 0,
        slotIndex: Int = 3,
        variantSuffix: String = "a",
        extraCombos: [String: Int] = [:],
        constantShaderValues: [String: SceneDocument.ShaderValue] = [:],
        userTextureOverride: Bool = false,
        extraPass: Bool = false,
        extraReference: Bool = false
    ) -> SceneDependencyRenderPlan.Binding? {
        let providerID = 90
        let consumerID = 91
        let providerEffects: [SceneRenderDescriptor.EffectDescriptor] =
            providerEffectful ? [.init(
                id: "provider-effect",
                file: "effects/unseen/provider/effect.json",
                visible: true,
                passes: []
            )] : []
        let provider = SceneRenderDescriptor.Layer(
            id: providerID,
            contentKind: providerContentKind,
            utilityLayer: providerUtility ? .init(kind: .composition) : nil,
            dependencyLayerIDs: providerDependencies,
            childLayerIDs: [],
            visible: providerVisible,
            effects: providerEffects
        )
        let consumer = SceneRenderDescriptor.Layer(
            id: consumerID,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [providerID],
            childLayerIDs: [],
            visible: true,
            effects: [slot3SolidCarrierEffect(
                id: consumerID,
                provider: providerID,
                effectPath: effectPath,
                passIndex: passIndex,
                slotIndex: slotIndex,
                variantSuffix: variantSuffix,
                extraCombos: extraCombos,
                constantShaderValues: constantShaderValues,
                userTextureOverride: userTextureOverride,
                extraPass: extraPass,
                extraReference: extraReference
            )]
        )
        let descriptor = SceneRenderDescriptor(
            layers: [provider, consumer],
            renderOrderLayerIDs: providerFirst
                ? [providerID, consumerID] : [consumerID, providerID]
        )
        return SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: [consumerID],
            executableUtilityConsumerLayerIDs: [consumerID]
        ).bindingsByConsumerLayerID[consumerID]
    }

    static func materialProgramSolidCarrierBinding(
        providerVisible: Bool? = true,
        providerEffectful: Bool = true,
        providerDependencies: [Int] = [],
        providerChildLayerIDs: [Int] = [],
        variantSuffix: String = "a",
        slotIndex: Int = 1,
        extraTexture: Bool = false,
        admitProgram: Bool = true,
        providerFirst: Bool = true
    ) -> SceneDependencyRenderPlan.Binding? {
        let providerID = 94
        let consumerID = 95
        let providerEffects: [SceneRenderDescriptor.EffectDescriptor] =
            providerEffectful ? [.init(
                id: "provider-material",
                file: "effects/workshop/unseen/data_provider/effect.json",
                visible: true,
                passes: [.init(
                    passIndex: 0,
                    texturePaths: [],
                    textureSlots: [],
                    userTextureInputs: [],
                    combos: [:],
                    constantShaderValues: [:]
                )]
            )] : []
        let provider = SceneRenderDescriptor.Layer(
            id: providerID,
            contentKind: "solid",
            utilityLayer: nil,
            dependencyLayerIDs: providerDependencies,
            childLayerIDs: providerChildLayerIDs,
            visible: providerVisible,
            effects: providerEffects
        )
        let path = "_rt_imageLayerComposite_\(providerID)_\(variantSuffix)"
        let authoredSlotCount = max(2, slotIndex + 1)
        var textureSlots = Array<String?>(
            repeating: nil,
            count: authoredSlotCount
        )
        textureSlots[slotIndex] = path
        if extraTexture {
            textureSlots[0] = "assets/noise.tex"
        }
        let consumer = SceneRenderDescriptor.Layer(
            id: consumerID,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [providerID],
            childLayerIDs: [],
            visible: true,
            effects: [.init(
                id: "data-consumer",
                file: "effects/workshop/unseen/data_consumer/effect.json",
                visible: true,
                passes: [.init(
                    passIndex: 0,
                    texturePaths: textureSlots.compactMap { $0 },
                    textureSlots: textureSlots,
                    userTextureInputs: [],
                    combos: ["SOURCE": 0],
                    constantShaderValues: [
                        "Scale": .init(components: [0.125, 4]),
                    ]
                )]
            )]
        )
        let descriptor = SceneRenderDescriptor(
            layers: [provider, consumer],
            renderOrderLayerIDs: providerFirst
                ? [providerID, consumerID] : [consumerID, providerID]
        )
        let references = Set(SceneDependencyGraphAnalysis.references(
            in: descriptor.layers
        ))
        return SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: [providerID, consumerID],
            executableUtilityConsumerLayerIDs: [consumerID],
            admittedResolvedMaterialReferences: admitProgram ? references : []
        ).bindingsByConsumerLayerID[consumerID]
    }
}
