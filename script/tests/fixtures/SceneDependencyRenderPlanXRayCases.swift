extension Harness {
    static func xRayResults() -> [String: Any] {
        let visibleNamedProvider = layer(100)
        let visibleUnboundConsumer = consumer(
            101,
            provider: 100,
            dependencies: [],
            effectPath: "effects/blend/effect.json"
        )
        let hiddenNamedProvider = layer(110)
        let hiddenNamedConsumer = consumer(
            111,
            provider: 110,
            visible: false,
            effectPath: "effects/blend/effect.json"
        )
        let selfReferenceConsumer = consumer(
            120,
            provider: 120,
            dependencies: [],
            effectPath: "effects/blend/effect.json"
        )
        let unreferencedProvider = layer(130)
        let explicitDependencyProvider = layer(140)
        let explicitDependencyConsumer = layer(141, dependencies: [140])
        let dependencySafetyLayers = [
            visibleNamedProvider,
            visibleUnboundConsumer,
            hiddenNamedProvider,
            hiddenNamedConsumer,
            selfReferenceConsumer,
            unreferencedProvider,
            explicitDependencyProvider,
            explicitDependencyConsumer,
        ]
        let dependencySafetyPlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: dependencySafetyLayers,
                renderOrderLayerIDs: dependencySafetyLayers.map(\.id)
            ),
            visibleLayerIDs: [100, 101, 110, 120, 130, 140, 141]
        )
        let xRayProviderLayer = layer(200)
        let xRayLayers: [SceneRenderDescriptor.Layer] = [
            xRayProviderLayer,
            xRayConsumer(201, provider: 200),
            xRayConsumer(202, provider: 200, dependencies: [200, 7]),
            xRayConsumer(203, provider: 200, combos: ["OPACITYMASK": 1]),
            xRayConsumer(204, provider: 200, combos: ["BLENDMODE": 5]),
            xRayConsumer(
                205,
                provider: 200,
                file: "effects/workshop/9/xray/effect.json"
            ),
            xRayConsumer(
                206,
                provider: 200,
                slots: [
                    nil,
                    "_rt_imageLayerComposite_200_a",
                    "_rt_imageLayerComposite_200_b",
                ]
            ),
            xRayConsumer(
                207,
                provider: 200,
                slots: [nil, "_rt_imageLayerComposite_999_a", "particle/halo_6"]
            ),
            xRayConsumer(208, provider: 200, extraEffect: true),
            xRayConsumer(209, provider: 200, passCount: 2),
            xRayConsumer(211, provider: 200),
            consumer(212, provider: 211),
        ]
        let xRayPlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: xRayLayers,
                renderOrderLayerIDs: xRayLayers.map(\.id)
            ),
            visibleLayerIDs: Set(xRayLayers.map(\.id)),
            verifiedXRayStageKeys: Set(
                [201, 202, 203, 204, 206, 207, 208, 209, 211].map {
                    xRayKey(layerID: $0)
                }
            )
        )
        let exactXRayLayers = [
            layer(220),
            xRayConsumer(221, provider: 220),
        ]
        let exactXRayPlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: exactXRayLayers,
                renderOrderLayerIDs: exactXRayLayers.map(\.id)
            ),
            visibleLayerIDs: Set(exactXRayLayers.map(\.id)),
            verifiedXRayStageKeys: [xRayKey(layerID: 221)]
        )
        let missingProviderXRay = xRayConsumer(231, provider: 230)
        let missingProviderXRayPlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: [missingProviderXRay],
                renderOrderLayerIDs: [missingProviderXRay.id]
            ),
            visibleLayerIDs: [missingProviderXRay.id],
            verifiedXRayStageKeys: [xRayKey(layerID: missingProviderXRay.id)]
        )
        let unverifiedStockPathLayers = [
            layer(240),
            xRayConsumer(241, provider: 240),
        ]
        let unverifiedStockPathPlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: unverifiedStockPathLayers,
                renderOrderLayerIDs: unverifiedStockPathLayers.map(\.id)
            ),
            visibleLayerIDs: Set(unverifiedStockPathLayers.map(\.id))
        )
        let multiEffectXRayLayers = [
            layer(250),
            xRayConsumer(
                251,
                provider: 250,
                localEffectsBefore: 1,
                localEffectsAfter: 1
            ),
        ]
        let multiEffectXRayPlan = SceneDependencyRenderPlan(
            descriptor: .init(
                layers: multiEffectXRayLayers,
                renderOrderLayerIDs: multiEffectXRayLayers.map(\.id)
            ),
            visibleLayerIDs: Set(multiEffectXRayLayers.map(\.id)),
            verifiedXRayStageKeys: [xRayKey(layerID: 251, effectIndex: 1)]
        )
        let hiddenVideoXRayLayers = [
            layer(260, visible: false),
            xRayConsumer(261, provider: 260),
        ]
        let hiddenVideoXRayDescriptor = SceneRenderDescriptor(
            layers: hiddenVideoXRayLayers,
            renderOrderLayerIDs: [261, 260]
        )
        let hiddenVideoXRayReferences = Set(
            SceneDependencyGraphAnalysis.references(
                in: hiddenVideoXRayDescriptor.layers
            )
        )
        let hiddenVideoXRayPlan = SceneDependencyRenderPlan(
            descriptor: hiddenVideoXRayDescriptor,
            visibleLayerIDs: [261],
            admittedResolvedMaterialReferences: hiddenVideoXRayReferences
        )
        let admittedHiddenVideoXRayPlan = SceneDependencyRenderPlan(
            descriptor: hiddenVideoXRayDescriptor,
            visibleLayerIDs: [261],
            admittedResolvedMaterialReferences: hiddenVideoXRayReferences
        )
        let rejectedHiddenVideoXRayPlan = SceneDependencyRenderPlan(
            descriptor: hiddenVideoXRayDescriptor,
            visibleLayerIDs: [261],
            admittedResolvedMaterialReferences: []
        )
        return [
            "staticPassthroughBlocks": [
                "namedProvider": dependencySafetyPlan.blocksStaticLayerSourcePassthrough(for: 100),
                "namedConsumer": dependencySafetyPlan.blocksStaticLayerSourcePassthrough(for: 101),
                "hiddenNamedProvider": dependencySafetyPlan.blocksStaticLayerSourcePassthrough(for: 110),
                "hiddenNamedConsumer": dependencySafetyPlan.blocksStaticLayerSourcePassthrough(for: 111),
                "selfReference": dependencySafetyPlan.blocksStaticLayerSourcePassthrough(for: 120),
                "unreferenced": dependencySafetyPlan.blocksStaticLayerSourcePassthrough(for: 130),
                "explicitProvider": dependencySafetyPlan.blocksStaticLayerSourcePassthrough(for: 140),
                "explicitConsumer": dependencySafetyPlan.blocksStaticLayerSourcePassthrough(for: 141),
                "requiredProvidersEmpty": dependencySafetyPlan.requiredProviderLayerIDs.isEmpty,
            ],
            "staticPassthroughXRayBlocks": [
                "exemptConsumer": xRayPlan.blocksStaticLayerSourcePassthrough(for: 201),
                "xRayProvider": xRayPlan.blocksStaticLayerSourcePassthrough(for: 200),
                "extraDependency": xRayPlan.blocksStaticLayerSourcePassthrough(for: 202),
                "opacityMaskCombo": xRayPlan.blocksStaticLayerSourcePassthrough(for: 203),
                "blendModeCombo": xRayPlan.blocksStaticLayerSourcePassthrough(for: 204),
                "nonStockDefinition": xRayPlan.blocksStaticLayerSourcePassthrough(for: 205),
                "secondNamedSlot": xRayPlan.blocksStaticLayerSourcePassthrough(for: 206),
                "mismatchedProvider": xRayPlan.blocksStaticLayerSourcePassthrough(for: 207),
                "secondNamedReference": xRayPlan.blocksStaticLayerSourcePassthrough(for: 208),
                "multiplePasses": xRayPlan.blocksStaticLayerSourcePassthrough(for: 209),
                "exemptThenProvider": xRayPlan.blocksStaticLayerSourcePassthrough(for: 211),
                "upperConsumer": xRayPlan.blocksStaticLayerSourcePassthrough(for: 212),
            ],
            "isolatedXRayPassthroughBlocks": [
                "exactProvider": exactXRayPlan.blocksStaticLayerSourcePassthrough(for: 220),
                "exactConsumer": exactXRayPlan.blocksStaticLayerSourcePassthrough(for: 221),
                "missingProviderConsumer": missingProviderXRayPlan
                    .blocksStaticLayerSourcePassthrough(for: 231),
                "unverifiedStockPathProvider": unverifiedStockPathPlan
                    .blocksStaticLayerSourcePassthrough(for: 240),
                "unverifiedStockPathConsumer": unverifiedStockPathPlan
                    .blocksStaticLayerSourcePassthrough(for: 241),
                "multiEffectProvider": multiEffectXRayPlan
                    .blocksStaticLayerSourcePassthrough(for: 250),
                "multiEffectConsumer": multiEffectXRayPlan
                    .blocksStaticLayerSourcePassthrough(for: 251),
            ],
            "hiddenVideoXRayProgramBinding": [
                "provisional": hiddenVideoXRayPlan.bindingsByConsumerLayerID[261]?
                    .kind == .imageLayerBlend,
                "provider": hiddenVideoXRayPlan.bindingsByConsumerLayerID[261]?
                    .providerLayerID ?? -1,
                "slot": hiddenVideoXRayPlan.bindingsByConsumerLayerID[261]?
                    .slot.slotIndex ?? -1,
                "requiresProgram": hiddenVideoXRayPlan
                    .bindingsByConsumerLayerID[261]?
                    .requiresResolvedMaterialProgram ?? false,
                "forward": hiddenVideoXRayPlan.bindingsByConsumerLayerID[261]?
                    .requiresForwardCapture ?? false,
                "runtimeAdmitted": admittedHiddenVideoXRayPlan
                    .bindingsByConsumerLayerID[261] != nil,
                "runtimeRejected": rejectedHiddenVideoXRayPlan
                    .bindingsByConsumerLayerID[261] == nil,
                "providerRequired": hiddenVideoXRayPlan.requiredProviderLayerIDs
                    .contains(260),
                "consumerRequiresEffect": hiddenVideoXRayPlan
                    .requiredEffectConsumerLayerIDs.contains(261),
                "activeExecution": admittedHiddenVideoXRayPlan
                    .sourcePreparationPlan(authoredLayerIDs: hiddenVideoXRayDescriptor.renderOrderLayerIDs,
                        availableExecutionLayerIDs: [261], visibleRootLayerIDs: [261],
                        activeStaticModelConsumerLayerIDs: [], sourceAfterLayerIDByLayerID: [:])?.preparationSchedule()
                    .preparationLayerIDs.sorted() ?? [-1],
                "inactiveExecution": admittedHiddenVideoXRayPlan
                    .sourcePreparationPlan(authoredLayerIDs: hiddenVideoXRayDescriptor.renderOrderLayerIDs,
                        availableExecutionLayerIDs: [261], visibleRootLayerIDs: [],
                        activeStaticModelConsumerLayerIDs: [], sourceAfterLayerIDByLayerID: [:])?.preparationSchedule()
                    .preparationLayerIDs.sorted() ?? [-1],
            ],
        ]
    }

    static func xRayEffect(
        id: String,
        provider: Int,
        combos: [String: Int] = [:],
        slots: [String?]? = nil,
        file: String = "effects/xray/effect.json",
        passCount: Int = 1
    ) -> SceneRenderDescriptor.EffectDescriptor {
        let authoredSlots = slots
            ?? [nil, "_rt_imageLayerComposite_\(provider)_a", "particle/halo_6"]
        let authoredPaths = authoredSlots.compactMap { $0 }
        let template = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: 0,
            texturePaths: authoredPaths,
            textureSlots: authoredSlots,
            userTextureInputs: [],
            combos: combos,
            constantShaderValues: [:]
        )
        return .init(
            id: id,
            file: file,
            visible: true,
            passes: (0 ..< passCount).map { index in
                .init(
                    passIndex: index,
                    texturePaths: template.texturePaths,
                    textureSlots: template.textureSlots,
                    userTextureInputs: template.userTextureInputs,
                    combos: template.combos,
                    constantShaderValues: template.constantShaderValues
                )
            }
        )
    }

    static func xRayConsumer(
        _ id: Int,
        provider: Int,
        dependencies: [Int]? = nil,
        combos: [String: Int] = [:],
        slots: [String?]? = nil,
        file: String = "effects/xray/effect.json",
        passCount: Int = 1,
        extraEffect: Bool = false,
        localEffectsBefore: Int = 0,
        localEffectsAfter: Int = 0
    ) -> SceneRenderDescriptor.Layer {
        let xRay = [
            xRayEffect(
                id: "xray-\(id)",
                provider: provider,
                combos: combos,
                slots: slots,
                file: file,
                passCount: passCount
            ),
        ]
        var effects = localEffects(
            layerID: id,
            count: localEffectsBefore,
            suffix: "before"
        ) + xRay + localEffects(
            layerID: id,
            count: localEffectsAfter,
            suffix: "after"
        )
        if extraEffect {
            effects.append(.init(
                id: "extra-\(id)",
                file: "effects/blend/effect.json",
                visible: true,
                passes: [.init(
                    passIndex: 0,
                    texturePaths: ["_rt_imageLayerComposite_\(provider)_a"],
                    textureSlots: [nil, "_rt_imageLayerComposite_\(provider)_a"],
                    userTextureInputs: [],
                    combos: [:],
                    constantShaderValues: [:]
                )]
            ))
        }
        return .init(
            id: id,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: dependencies ?? [provider],
            childLayerIDs: [],
            visible: true,
            effects: effects
        )
    }

    static func xRayKey(
        layerID: Int,
        effectIndex: Int = 0
    ) -> SceneAuthoredEffectRenderPlan.EffectKey {
        .init(
            layerID: layerID,
            effectIndex: effectIndex,
            descriptorID: "xray-\(layerID)"
        )
    }
}
