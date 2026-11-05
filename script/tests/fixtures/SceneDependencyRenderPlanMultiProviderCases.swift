extension Harness {
    static func multiProviderResults() -> [String: Any] {
        let positive = multiProviderCompositionPlan()
        let authored = multiProviderCompositionPlan(reverseEffectIDs: true)
        let declaredSubset = multiProviderCompositionPlan(dependencies: [601])
        let duplicate = multiProviderCompositionPlan(duplicateSlot: true)
        let unsafe = multiProviderCompositionPlan(providerChildLayerIDs: [699])
        let visible = multiProviderCompositionPlan(providerVisible: true)
        let visibleGraph = multiProviderCompositionPlan(providerVisible: true,
            providerEffectful: true, providerTexturePaths: ["assets/provider-source.tex"])
        let forward = multiProviderCompositionPlan(providerEffectful: true,
            providerTexturePaths: ["assets/noise.tex"], providerFirst: false)
        let forwardUnsafe = multiProviderCompositionPlan(providerEffectful: true,
            providerTexturePaths: ["_rt_FullFrameBuffer"], providerFirst: false)
        let forwardGeometry = multiProviderCompositionPlan(providerVisible: true,
            providerEffectful: true, providerTexturePaths: ["assets/provider-source.tex"],
            providerFirst: false, geometryProviderID: 601)
        let geometry = multiProviderCompositionPlan(geometryProviderID: 601)
        let nested = nestedGeometryProviderAggregatePlan()
        let inactive = multiProviderInactiveSupersetCompositionPlan()
        func slots(_ plan: SceneDependencyRenderPlan) -> [String] {
            plan.multiProviderAggregatesByConsumerLayerID[603]?.bindings.map {
                "\($0.slot.effectID):\($0.slot.passIndex):\($0.slot.slotIndex)"
            } ?? []
        }
        var inactiveReferences: [[String: Any]] = []
        for reference in inactive.references where reference.consumerLayerID == 603 {
            let slot = "\(reference.slot.effectID):\(reference.slot.passIndex):\(reference.slot.slotIndex)"
            inactiveReferences.append(["provider": reference.providerLayerID, "slot": slot])
        }
        let positiveAggregate: [String: Any] = [
            "providers": positive.requiredProviderLayerIDs.sorted(), "slots": slots(positive),
        ]
        let candidate: [String: Any] = [
            "candidate": positive.multiProviderCandidateLayerIDs.contains(603),
            "aggregate": positiveAggregate,
            "authoredSlots": slots(authored),
            "requiredProviders": positive.requiredProviderLayerIDs.sorted(),
            "requiredEffect": positive.requiredEffectConsumerLayerIDs.contains(603),
        ]
        let rejects: [String: Bool] = [
            "duplicateSlot": duplicate.multiProviderAggregatesByConsumerLayerID[603] == nil,
            "unsafeProvider": unsafe.multiProviderAggregatesByConsumerLayerID[603] == nil,
            "missingProviderOrder": multiProviderCompositionPlan(omitRenderOrderID: 601)
                .multiProviderAggregatesByConsumerLayerID[603] == nil,
            "missingConsumerOrder": multiProviderCompositionPlan(omitRenderOrderID: 603)
                .multiProviderAggregatesByConsumerLayerID[603] == nil,
            "visibleEffectfulProvider": visibleGraph.multiProviderAggregatesByConsumerLayerID[603] != nil,
            "forwardSafeProvider": forward.multiProviderAggregatesByConsumerLayerID[603] != nil,
            "forwardUnsafeProvider": forwardUnsafe.multiProviderAggregatesByConsumerLayerID[603] == nil,
            "forwardVisibleEffectfulGeometryProvider": forwardGeometry.multiProviderAggregatesByConsumerLayerID[603] == nil,
        ]
        let coldCarriers: [String: Any] = [
            "declaredSubsetSlots": slots(declaredSubset),
            "declaredSubsetProviders": declaredSubset.requiredProviderLayerIDs.sorted(),
            "declaredSubsetRequiresProgram": declaredSubset
                .multiProviderAggregatesByConsumerLayerID[603]?.bindings
                .map(\.requiresResolvedMaterialProgram) ?? [],
            "visibleProviderSlots": slots(visible),
            "visibleProviderKinds": visible.multiProviderAggregatesByConsumerLayerID[603]?
                .bindings.map { String(describing: $0.kind) } ?? [],
            "visibleProviderRequiresProgram": visible
                .multiProviderAggregatesByConsumerLayerID[603]?.bindings
                .map(\.requiresResolvedMaterialProgram) ?? [],
        ]
        let geometryResult: [String: Any] = [
            "providers": geometry.multiProviderAggregatesByConsumerLayerID[603]?.bindings.map(\.providerLayerID) ?? [],
            "kinds": geometry.multiProviderAggregatesByConsumerLayerID[603]?.bindings.map { String(describing: $0.kind) } ?? [],
            "slots": slots(geometry),
        ]
        var nestedIssues: [String] = []
        for issue in nested.issues {
            let providerID: Int = issue.providerLayerID ?? -1
            nestedIssues.append("\(issue.layerID):\(issue.kind.rawValue):\(providerID)")
        }
        let nestedGeometry: [String: Any] = [
            "nestedBindingKind": nested.bindingsByConsumerLayerID[701].map { String(describing: $0.kind) } ?? "none",
            "nestedRequiresProgram": nested.bindingsByConsumerLayerID[701]?.requiresResolvedMaterialProgram == true,
            "aggregateProviders": nested.multiProviderAggregatesByConsumerLayerID[703]?.bindings.map(\.providerLayerID) ?? [],
            "aggregateKinds": nested.multiProviderAggregatesByConsumerLayerID[703]?.bindings.map { String(describing: $0.kind) } ?? [],
            "requiredProviders": nested.requiredProviderLayerIDs.sorted(),
            "graphProviders": nested.requiredGraphOutputProviderLayerIDs.sorted(),
            "issues": nestedIssues,
        ]
        let inactiveAggregate: [String: Any] = [
            "providers": inactive.requiredProviderLayerIDs.sorted(), "slots": slots(inactive),
        ]
        let inactiveSuperset: [String: Any] = [
            "candidate": inactive.multiProviderCandidateLayerIDs.contains(603),
            "references": inactiveReferences,
            "aggregate": inactiveAggregate,
            "requiredProviders": inactive.requiredProviderLayerIDs.sorted(),
            "declaredProviders": [601, 602, 604],
        ]
        return [
            "multiProviderCandidate": candidate,
            "multiProviderRejects": rejects,
            "multiProviderColdCarriers": coldCarriers,
            "multiProviderGeometry": geometryResult,
            "nestedGeometryAggregate": nestedGeometry,
            "multiProviderInactiveSuperset": inactiveSuperset,
            "preparedNamedInputs": preparedNamedInputResults(),
        ]
    }

    // This gate takes an already-prepared vector as typed input. Shader active
    // sampler proof and pixel contribution are tested by Program/GPU/App gates.
    static func preparedNamedInputResults() -> [String: Any] {
        typealias Slot = (effect: String, pass: Int, slot: Int, provider: Int)
        func inspect(
            _ kind: String, _ declared: [Slot], active: [Int]? = [0, 1],
            providers: [Int] = [901, 902], consumerID: Int = 903,
            resource: String = "owned", visible: Bool = true,
            providerFirst: Bool = true, variant: String = "a"
        ) -> [String: Any] {
            var effectIDs: [String] = []
            for slot in declared where !effectIDs.contains(slot.effect) { effectIDs.append(slot.effect) }
            let effects = effectIDs.map { effectID -> SceneRenderDescriptor.EffectDescriptor in
                let members = declared.filter { $0.effect == effectID }
                var passIDs: [Int] = []
                for slot in members where !passIDs.contains(slot.pass) { passIDs.append(slot.pass) }
                let passes = passIDs.map { passID -> SceneRenderDescriptor.EffectDescriptor.PassDescriptor in
                    let passMembers = members.filter { $0.pass == passID }
                    var paths = Array<String?>(repeating: nil, count: (passMembers.map { $0.slot }.max() ?? 0) + 1)
                    for slot in passMembers {
                        paths[slot.slot] = "_rt_imageLayerComposite_\(slot.provider)_\(variant)"
                    }
                    return .init(passIndex: passID, texturePaths: paths.compactMap { $0 },
                        textureSlots: paths, combos: ["\(resource)_VARIANT": 7],
                        constantShaderValues: ["\(resource)_weight": .init(components: [0.75])])
                }
                return .init(id: effectID, file: "effects/\(resource)/\(effectID).json", visible: true, passes: passes)
            }
            let consumer = SceneRenderDescriptor.Layer(id: consumerID, contentKind: kind,
                utilityLayer: nil, dependencyLayerIDs: Set(declared.map { $0.provider }).sorted(),
                childLayerIDs: [], visible: visible, effects: effects)
            let sources = providers.map { SceneRenderDescriptor.Layer(id: $0, contentKind: "image",
                utilityLayer: nil, dependencyLayerIDs: [], childLayerIDs: [], visible: false, effects: []) }
            let bindings = active?.map { index -> SceneDependencyRenderPlan.Binding in
                let slot = declared[index]
                return .init(consumerLayerID: consumerID, providerLayerID: slot.provider,
                    slot: .init(effectID: slot.effect, passIndex: slot.pass, slotIndex: slot.slot),
                    blendMode: 0, kind: .imageLayerBlend, requiresForwardCapture: !providerFirst,
                    requiresResolvedMaterialProgram: true)
            }
            let plan = SceneDependencyRenderPlan(descriptor: .init(layers: sources + [consumer],
                renderOrderLayerIDs: providerFirst ? providers + [consumerID] : [consumerID] + providers),
                visibleLayerIDs: visible ? [consumerID] : [],
                preparedNamedInputBindingsByConsumerLayerID: bindings.map { [consumerID: $0] } ?? [:])
            let vector = plan.multiProviderAggregatesByConsumerLayerID[consumerID]?.bindings
                ?? plan.bindingsByConsumerLayerID[consumerID].map { [$0] } ?? []
            return [
                "bindings": vector.map { "\($0.slot.effectID):\($0.slot.passIndex):\($0.slot.slotIndex)=\($0.providerLayerID)" },
                "single": plan.bindingsByConsumerLayerID[consumerID] != nil,
                "aggregate": plan.multiProviderAggregatesByConsumerLayerID[consumerID] != nil,
                "requiredProviders": plan.requiredProviderLayerIDs.sorted(),
                "requiresEffect": plan.requiredEffectConsumerLayerIDs.contains(consumerID),
                "referenceProviders": Set(plan.references.filter { $0.consumerLayerID == consumerID }.map(\.providerLayerID)).sorted(),
                "forward": vector.map(\.requiresForwardCapture),
                "requiresProgram": vector.allSatisfy(\.requiresResolvedMaterialProgram),
                "execution": plan.sourcePreparationPlan(
                    authoredLayerIDs: providerFirst ? providers + [consumerID] : [consumerID] + providers,
                    availableExecutionLayerIDs: [consumerID], visibleRootLayerIDs: visible ? [consumerID] : [],
                    activeStaticModelConsumerLayerIDs: [], sourceAfterLayerIDByLayerID: [:])?.preparationSchedule()
                    .preparationLayerIDs.sorted() ?? [-1],
                "issues": plan.issues.filter { $0.layerID == consumerID }.map(\.kind.rawValue).sorted(),
            ]
        }
        let same: [Slot] = [("z-first", 0, 2, 901), ("z-first", 0, 5, 902)]
        let across: [Slot] = [("z-first", 0, 2, 901), ("a-second", 1, 5, 902)]
        let dead: [Slot] = [("z-first", 0, 2, 901), ("z-first", 0, 5, 999)]
        var rows: [String: Any] = [:]
        for kind in ["solid", "image"] {
            rows["\(kind)SameEffect"] = inspect(kind, same)
            rows["\(kind)AcrossEffects"] = inspect(kind, across)
        }
        rows["sameProvider"] = inspect("solid", [("one", 1, 2, 901), ("one", 1, 5, 901)], providers: [901])
        rows["renamed"] = inspect("image", [("sun", 1, 2, 1701), ("moon", 0, 5, 1702)],
            providers: [1701, 1702], consumerID: 1703, resource: "renamed_resource")
        rows["emptyPrepared"] = inspect("solid", dead, active: [], providers: [901])
        rows["emptyPreparedSelf"] = inspect("image", [("self", 0, 1, 903)], active: [], providers: [])
        rows["oneActive"] = inspect("solid", dead, active: [0], providers: [901])
        rows["cold"] = inspect("solid", same, active: nil)
        rows["missingCold"] = inspect("solid", same, active: nil, providers: [901])
        rows["hidden"] = inspect("image", same, visible: false)
        rows["forward"] = inspect("image", same, providerFirst: false)
        rows["secondaryCold"] = inspect("solid", same, active: nil, variant: "b")
        return rows
    }

    static func multiProviderCompositionPlan(
        dependencies: [Int] = [601, 602],
        duplicateSlot: Bool = false,
        providerChildLayerIDs: [Int] = [],
        providerVisible: Bool? = false,
        providerEffectful: Bool = false,
        providerTexturePaths: [String] = [],
        providerFirst: Bool = true,
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
            let passes: [SceneRenderDescriptor.EffectDescriptor.PassDescriptor] = [.init(
                passIndex: 0, texturePaths: [path], textureSlots: [nil, path],
                combos: ["BLENDMODE": 0], constantShaderValues: [:])]
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
